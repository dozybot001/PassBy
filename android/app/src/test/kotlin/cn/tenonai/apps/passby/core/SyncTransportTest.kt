package cn.tenonai.apps.passby.core

import java.io.ByteArrayInputStream
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** A host and a guest talking over the loopback interface, and the host turning away what it should. */
class SyncTransportTest {
    private val loopback = InetAddress.getLoopbackAddress()
    private val code = "AB3D9KXMP2QW"
    private val iterations = 1000
    private val a = "00000000-0000-4000-8000-00000000000A"
    private val b = "00000000-0000-4000-8000-00000000000B"

    private var hostNotebook = Notebook().save(Entry(a, "host", password = "h"), 100).let { it.marked(Notebook(), 100) }
    private var now = 1_000_000L
    private var stop: SyncHost.Stop? = null
    private val stoppedLatch = CountDownLatch(1)
    private var host: SyncHost? = null

    private fun startHost(port: Int = 0): SyncHost {
        val started = SyncHost(
            code, loopback, port,
            exchange = { guest ->
                val merged = SyncMerge.merge(hostNotebook.syncState(), guest, " (Conflict copy)")
                hostNotebook = hostNotebook.synced(merged.state, now)
                SyncHost.Reply(merged.state, SyncMerge.summary(guest, merged.state, merged.conflicts))
            },
            onStopped = { stop = it; stoppedLatch.countDown() },
            iterations = iterations,
            clock = { now },
        )
        started.start()
        host = started
        return started
    }

    @After
    fun tearDown() {
        host?.stop()
    }

    private fun guest(port: Int, with: String = code) = SyncGuest(loopback, port, with, iterations)

    private fun failsWith(kind: SyncGuestException.Kind, block: () -> Unit) {
        try {
            block()
            fail("expected $kind")
        } catch (e: SyncGuestException) {
            assertEquals(kind, e.kind)
        }
    }

    private fun raw(port: Int, request: String): String = Socket().use {
        it.connect(InetSocketAddress(loopback, port), 2000)
        it.soTimeout = 5000
        it.getOutputStream().write(request.toByteArray(Charsets.ISO_8859_1))
        it.getOutputStream().flush()
        try {
            String(it.getInputStream().readBytes(), Charsets.ISO_8859_1)
        } catch (e: IOException) {
            "" // The host hung up without answering.
        }
    }

    @Test
    fun twoPhonesEndUpWithTheSameNotebook() {
        val h = startHost()
        var phone = Notebook().save(Entry(b, "guest", password = "g"), 200).let { it.marked(Notebook(), 200) }
        val g = guest(h.port)
        val (state, summary) = g.exchange(phone.syncState())
        phone = phone.synced(state, 300)

        assertEquals(SyncSummary(1, 0, 0, 0), summary)
        assertEquals(setOf(a, b), phone.entries.map { it.id }.toSet())
        assertEquals(hostNotebook.entries.toSet(), phone.entries.toSet())
        assertEquals(hostNotebook.marks, phone.marks)

        // The same session carries a later change, as the web page does on every save.
        phone = phone.save(Entry(b, "guest", password = "g2"), 400).let { it.marked(phone, 400) }
        val (again, second) = g.exchange(phone.syncState())
        assertEquals(SyncSummary(0, 0, 0, 0), second)
        assertEquals("g2", hostNotebook.entries.first { it.id == b }.password)
        assertEquals(hostNotebook.syncState().entries.toSet(), again.entries.toSet())
        g.close()
    }

    @Test
    fun aWrongCodeIsRefusedAndFiveOfThemStopTheHost() {
        val h = startHost()
        val before = hostNotebook
        repeat(SyncHost.MAX_FAILURES) {
            failsWith(SyncGuestException.Kind.WRONG_CODE) { guest(h.port, "AB3D9KXMP2QX").exchange(SyncState()) }
        }
        assertTrue(stoppedLatch.await(5, TimeUnit.SECONDS))
        assertEquals(SyncHost.Stop.WRONG_CODE, stop)
        assertEquals(before, hostNotebook)
        failsWith(SyncGuestException.Kind.UNREACHABLE) { guest(h.port).exchange(SyncState()) }
    }

    @Test
    fun aRecordedRequestCannotBeSentAgain() {
        val h = startHost()
        val nonce = post(h.port, SyncHttp.BEGIN, ByteArray(0)).second
        val guestNonce = ByteArray(16) { 7 }
        val keys = SyncCrypto.deriveKeys(code, nonce, guestNonce, iterations)
        val body = SyncCrypto.requestBody(nonce, guestNonce, 0, SyncCrypto.seal(keys.guestToHost, nonce, guestNonce, 0, 0, SyncCodec.request(SyncState())))
        assertEquals("200", post(h.port, SyncHttp.EXCHANGE, body).first)
        assertEquals("403", post(h.port, SyncHttp.EXCHANGE, body).first)
        // The host nonce is used up: a new session cannot be started on it either.
        val other = ByteArray(16) { 8 }
        val otherKeys = SyncCrypto.deriveKeys(code, nonce, other, iterations)
        val second = SyncCrypto.requestBody(nonce, other, 0, SyncCrypto.seal(otherKeys.guestToHost, nonce, other, 0, 0, SyncCodec.request(SyncState())))
        assertEquals("403", post(h.port, SyncHttp.EXCHANGE, second).first)
    }

    @Test
    fun aHostNonceExpiresAfterAMinute() {
        val h = startHost()
        val nonce = post(h.port, SyncHttp.BEGIN, ByteArray(0)).second
        now += SyncHost.NONCE_MS
        val guestNonce = ByteArray(16) { 7 }
        val keys = SyncCrypto.deriveKeys(code, nonce, guestNonce, iterations)
        val body = SyncCrypto.requestBody(nonce, guestNonce, 0, SyncCrypto.seal(keys.guestToHost, nonce, guestNonce, 0, 0, SyncCodec.request(SyncState())))
        assertEquals("403", post(h.port, SyncHttp.EXCHANGE, body).first)
    }

    @Test
    fun anInvalidStateChangesNothing() {
        val h = startHost()
        val before = hostNotebook
        val nonce = post(h.port, SyncHttp.BEGIN, ByteArray(0)).second
        val guestNonce = ByteArray(16) { 7 }
        val keys = SyncCrypto.deriveKeys(code, nonce, guestNonce, iterations)
        val plain = """{"v":2,"entries":[],"folders":[],"tombstones":[]}""".toByteArray()
        val body = SyncCrypto.requestBody(nonce, guestNonce, 0, SyncCrypto.seal(keys.guestToHost, nonce, guestNonce, 0, 0, plain))
        assertEquals("400", post(h.port, SyncHttp.EXCHANGE, body).first)
        assertEquals(before, hostNotebook)
    }

    @Test
    fun theBrowserGetsItsHeadersAndNothingElseIsServed() {
        val h = startHost()
        val preflight = raw(h.port, "OPTIONS /passby-sync/v1/exchange HTTP/1.1\r\nOrigin: https://passby.tenonai.cn\r\n\r\n")
        assertTrue(preflight, preflight.startsWith("HTTP/1.1 204"))
        assertTrue(preflight.contains("Access-Control-Allow-Origin: https://passby.tenonai.cn\r\n"))
        assertTrue(preflight.contains("Cache-Control: no-store\r\n"))
        assertTrue(raw(h.port, "GET / HTTP/1.1\r\n\r\n").startsWith("HTTP/1.1 400"))
        assertTrue(raw(h.port, "POST /passby-sync/v1/begin HTTP/1.1\r\nContent-Length: 1\r\n\r\nx").startsWith("HTTP/1.1 400"))
        // Malformed or oversized requests get no answer at all.
        assertEquals("", raw(h.port, "POST /passby-sync/v1/exchange HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n"))
        assertEquals("", raw(h.port, "POST /passby-sync/v1/exchange HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"))
        assertEquals("", raw(h.port, "nonsense\r\n\r\n"))
        assertEquals("", raw(h.port, "GET / HTTP/1.1\r\n" + "X: ${"y".repeat(9000)}\r\n\r\n"))
        // None of that counts against the code, and the host still works.
        assertEquals(SyncSummary(1, 0, 0, 0), guest(h.port).exchange(SyncState()).second)
    }

    @Test
    fun theHostStopsWhenIdleAndWhenClosed() {
        val h = startHost()
        now += SyncHost.IDLE_MS
        assertTrue(stoppedLatch.await(5, TimeUnit.SECONDS))
        assertEquals(SyncHost.Stop.IDLE, stop)
        failsWith(SyncGuestException.Kind.UNREACHABLE) { guest(h.port).exchange(SyncState()) }
    }

    @Test
    fun aTakenPortFallsBackToAnother() {
        val first = startHost()
        val second = SyncHost(code, loopback, first.port, { null }, {}, iterations)
        second.start()
        try {
            assertNotEquals(first.port, second.port)
        } finally {
            second.stop()
        }
    }

    @Test
    fun addressesMustBePrivateAndWrittenOut() {
        assertEquals(SyncAddress("10.91.92.79", 52814), SyncAddress.parse(" 10.91.92.79:52814 "))
        assertEquals(SyncAddress("172.16.0.1", 1), SyncAddress.parse("172.16.0.1:1"))
        assertEquals(SyncAddress("192.168.1.20", 65535), SyncAddress.parse("192.168.1.20:65535"))
        for (bad in listOf("8.8.8.8:80", "172.32.0.1:80", "127.0.0.1:80", "192.168.1.20", "192.168.1.20:0", "192.168.1.20:65536", "192.168.1.256:80", "phone.local:80", "http://10.0.0.1:80", "10.0.0.1:80/x")) {
            assertNull(bad, SyncAddress.parse(bad))
        }
        assertArrayEquals(byteArrayOf(10, 91, 92, 79), SyncAddress.parse("10.91.92.79:1")!!.inet().address)
    }

    @Test
    fun messagesAreReadStrictly() {
        fun read(text: String) = SyncHttp.read(ByteArrayInputStream(text.toByteArray(Charsets.ISO_8859_1)))
        val message = read("POST /x HTTP/1.1\r\nContent-Length: 3\r\nX-Other:  v \r\n\r\nabcdef")
        assertEquals("abc", String(message.body))
        assertEquals("v", message.headers["x-other"])
        for (bad in listOf("POST /x HTTP/1.1\r\nContent-Length: 3\r\n\r\nab", "POST /x HTTP/1.1\r\nContent-Length: -1\r\n\r\n", "POST /x HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 1\r\n\r\na", "POST /x HTTP/1.1\r\nno colon\r\n\r\n", "POST /x HTTP/1.1\r\n")) {
            try {
                read(bad)
                fail(bad)
            } catch (e: IOException) {
                // Expected.
            }
        }
        var ticks = 0L
        try {
            SyncHttp.read(ByteArrayInputStream("POST /x HTTP/1.1\r\n\r\n".toByteArray())) { ticks += 1_000_000_000L; ticks }
            fail("a slow sender is cut off")
        } catch (e: IOException) {
            // Expected.
        }
    }

    private fun post(port: Int, path: String, body: ByteArray): Pair<String, ByteArray> = Socket().use {
        it.connect(InetSocketAddress(loopback, port), 2000)
        it.soTimeout = 5000
        SyncHttp.write(it.getOutputStream(), "POST $path HTTP/1.1", listOf("Host" to "x"), body)
        val response = SyncHttp.read(it.getInputStream())
        response.start.split(' ')[1] to response.body
    }
}
