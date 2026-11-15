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
        it.shutdownOutput()
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

    /** A guest driven by hand, so that single frames can be replayed, reordered and forged. */
    private inner class Manual(val port: Int, with: String = code) {
        val nonce = post(port, SyncHttp.BEGIN, ByteArray(0)).second
        val guestNonce = ByteArray(16) { 7 }
        val keys = SyncCrypto.deriveKeys(with, nonce, guestNonce, iterations)
        fun frame(counter: Long, plain: ByteArray, direction: Int = SyncCrypto.GUEST_TO_HOST, key: ByteArray = keys.guestToHost) =
            SyncCrypto.requestBody(nonce, guestNonce, counter, SyncCrypto.seal(key, nonce, guestNonce, direction, counter, plain))
        fun send(body: ByteArray) = post(port, SyncHttp.EXCHANGE, body).first
        val hello get() = frame(0, SyncCodec.HELLO)
        fun state(counter: Long) = frame(counter, SyncCodec.request(SyncState()))
    }

    @Test
    fun nothingOfTheNotebookIsSentBeforeTheHostHasAnsweredTheGreeting() {
        // A host that does not hold the code: it hands out a nonce and answers every exchange with noise.
        val seen = ArrayList<ByteArray>()
        val fake = java.net.ServerSocket(0, 4, loopback)
        val thread = Thread {
            try {
                while (true) fake.accept().use {
                    val request = SyncHttp.read(it.getInputStream())
                    seen += request.body
                    SyncHttp.write(it.getOutputStream(), "HTTP/1.1 200 OK", emptyList(), ByteArray(if (request.body.isEmpty()) 16 else 60) { 1 })
                }
            } catch (e: IOException) {
                // Closed.
            }
        }.apply { isDaemon = true; start() }
        val phone = Notebook().save(Entry(b, "guest", password = "a-long-secret-that-would-show-in-the-size"), 200).let { it.marked(Notebook(), 200) }
        failsWith(SyncGuestException.Kind.UNTRUSTED) { guest(fake.localPort).exchange(phone.syncState()) }
        fake.close()
        thread.join(2000)
        // The fake host got the empty begin and the greeting, and nothing else.
        assertEquals(2, seen.size)
        assertEquals(SyncCrypto.REQUEST_HEADER + SyncCodec.HELLO.size + SyncCrypto.TAG_LENGTH, seen[1].size)
    }

    @Test
    fun aRecordedFrameCannotBeSentAgainAndCountersOnlyGoUp() {
        val h = startHost()
        val g = Manual(h.port)
        assertEquals("200", g.send(g.hello))
        assertEquals("a replayed greeting", "403", g.send(g.hello))
        val third = g.state(3)
        assertEquals("200", g.send(third))
        assertEquals("a replayed state", "403", g.send(third))
        assertEquals("a counter that goes back", "403", g.send(g.state(2)))
        assertEquals("200", g.send(g.state(4)))
    }

    @Test
    fun aFrameSealedForTheOtherDirectionOrWithTheOtherKeyIsRefused() {
        val h = startHost()
        val g = Manual(h.port)
        assertEquals("200", g.send(g.hello))
        assertEquals("403", g.send(g.frame(1, SyncCodec.request(SyncState()), SyncCrypto.HOST_TO_GUEST)))
        assertEquals("403", g.send(g.frame(2, SyncCodec.request(SyncState()), key = g.keys.hostToGuest)))
        assertEquals("200", g.send(g.state(3)))
    }

    @Test
    fun aStateInPlaceOfTheGreetingAndAGreetingInPlaceOfAStateAreNotTaken() {
        val h = startHost()
        val before = hostNotebook
        val early = Manual(h.port)
        assertEquals("400", early.send(early.state(0)))
        assertEquals("its nonce is used up", "403", early.send(early.hello))
        val g = Manual(h.port)
        assertEquals("200", g.send(g.hello))
        assertEquals("400", g.send(g.frame(1, SyncCodec.HELLO)))
        assertEquals("400", g.send(g.frame(2, """{"v":2,"entries":[],"folders":[],"tombstones":[]}""".toByteArray())))
        assertEquals("400", g.send(g.frame(3, "not json".toByteArray())))
        assertEquals(before, hostNotebook)
    }

    @Test
    fun theCodeIsGoodForOneSession() {
        val h = startHost()
        val first = Manual(h.port)
        val waiting = Manual(h.port)
        assertEquals("200", first.send(first.hello))
        // Someone who read the code off the screen cannot follow: no new nonce, and the one handed out earlier is void.
        assertEquals("403", post(h.port, SyncHttp.BEGIN, ByteArray(0)).first)
        assertEquals("403", waiting.send(waiting.hello))
        failsWith(SyncGuestException.Kind.WRONG_CODE) { guest(h.port).exchange(SyncState()) }
        assertEquals("the session itself carries on", "200", first.send(first.state(1)))
        // With the code used up, frames that do not open are refused without counting: another device
        // on the network cannot stop the sync by sending a handful of them.
        repeat(SyncHost.MAX_FAILURES + 2) {
            assertEquals("403", waiting.send(waiting.state(1)))
            assertEquals("403", first.send(first.frame(9, SyncCodec.request(SyncState()), key = first.keys.hostToGuest)))
        }
        assertEquals("200", first.send(first.state(20)))
        assertEquals(null, stop)
    }

    @Test
    fun connectionsThatAreNeverAnsweredDoNotKeepAnIdleHostOpen() {
        val h = startHost()
        now += SyncHost.IDLE_MS
        // Something keeps knocking under the wrong name; the host still notices it has been idle.
        repeat(3) {
            try {
                raw(h.port, "POST /passby-sync/v1/begin HTTP/1.1\r\nHost: other:1\r\nContent-Length: 0\r\n\r\n")
            } catch (e: IOException) {
                // Already closed.
            }
        }
        assertTrue(stoppedLatch.await(5, TimeUnit.SECONDS))
        assertEquals(SyncHost.Stop.IDLE, stop)
    }

    @Test
    fun refusedRequestsDoNotKeepAnIdleHostOpen() {
        val h = startHost()
        val host = "Host: 127.0.0.1:${h.port}\r\n"
        now += SyncHost.IDLE_MS - 1
        // Another website's page is answered, with a refusal. That is not use.
        assertTrue(raw(h.port, "POST /passby-sync/v1/begin HTTP/1.1\r\n${host}Origin: https://example.com\r\nContent-Length: 0\r\n\r\n").startsWith("HTTP/1.1 403"))
        assertEquals(null, stop)
        now += 1
        assertTrue(stoppedLatch.await(5, TimeUnit.SECONDS))
        assertEquals(SyncHost.Stop.IDLE, stop)
    }

    @Test
    fun onlyAFewUnusedNoncesAreKeptAndEachExpiresAfterAMinute() {
        val h = startHost()
        val old = Manual(h.port)
        repeat(SyncHost.MAX_PENDING - 1) { assertEquals("200", post(h.port, SyncHttp.BEGIN, ByteArray(0)).first) }
        assertEquals("403", post(h.port, SyncHttp.BEGIN, ByteArray(0)).first)
        now += SyncHost.NONCE_MS
        assertEquals("an expired nonce", "403", old.send(old.hello))
        assertEquals("room again", "200", post(h.port, SyncHttp.BEGIN, ByteArray(0)).first)
        // Asking for nonces never counts against the code.
        assertEquals(SyncSummary(1, 0, 0, 0), guest(h.port).exchange(SyncState()).second)
    }

    @Test
    fun theBrowserGetsItsHeadersAndNothingElseIsServed() {
        val h = startHost()
        val host = "Host: 127.0.0.1:${h.port}\r\n"
        val preflight = raw(h.port, "OPTIONS /passby-sync/v1/exchange HTTP/1.1\r\n${host}Origin: https://passby.tenonai.cn\r\n\r\n")
        assertTrue(preflight, preflight.startsWith("HTTP/1.1 204"))
        assertTrue(preflight.contains("Access-Control-Allow-Origin: https://passby.tenonai.cn\r\n"))
        assertTrue(preflight.contains("Cache-Control: no-store\r\n"))
        assertTrue(preflight.contains("Connection: close\r\n"))
        assertTrue(raw(h.port, "GET / HTTP/1.1\r\n$host\r\n").startsWith("HTTP/1.1 400"))
        assertTrue(raw(h.port, "PUT /passby-sync/v1/begin HTTP/1.1\r\n${host}Content-Length: 0\r\n\r\n").startsWith("HTTP/1.1 400"))
        assertTrue(raw(h.port, "POST /passby-sync/v1/other HTTP/1.1\r\n${host}Content-Length: 0\r\n\r\n").startsWith("HTTP/1.1 400"))
        assertTrue(raw(h.port, "POST /passby-sync/v1/begin HTTP/1.1\r\n${host}Content-Length: 1\r\n\r\nx").startsWith("HTTP/1.1 400"))
        // Another website's page is turned away, whatever it asks for.
        for (origin in listOf("https://evil.example", "http://passby.tenonai.cn", "null")) {
            assertTrue(raw(h.port, "POST /passby-sync/v1/begin HTTP/1.1\r\n${host}Origin: $origin\r\nContent-Length: 0\r\n\r\n").startsWith("HTTP/1.1 403"))
            assertTrue(raw(h.port, "OPTIONS /passby-sync/v1/begin HTTP/1.1\r\n${host}Origin: $origin\r\n\r\n").startsWith("HTTP/1.1 403"))
        }
        // A request under another name, or malformed, oversized or half sent, gets no answer at all.
        val dropped = listOf(
            "POST /passby-sync/v1/begin HTTP/1.1\r\nContent-Length: 0\r\n\r\n",
            "POST /passby-sync/v1/begin HTTP/1.1\r\nHost: phone.evil.example:${h.port}\r\nContent-Length: 0\r\n\r\n",
            "POST /passby-sync/v1/begin HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Length: 0\r\n\r\n",
            "POST /passby-sync/v1/begin HTTP/1.1\r\n$host\r\n",
            "POST /passby-sync/v1/exchange HTTP/1.1\r\n${host}Content-Length: 99999999\r\n\r\n",
            "POST /passby-sync/v1/exchange HTTP/1.1\r\n${host}Content-Length: -5\r\n\r\n",
            "POST /passby-sync/v1/exchange HTTP/1.1\r\n${host}Content-Length: 12abc\r\n\r\n",
            "POST /passby-sync/v1/exchange HTTP/1.1\r\n${host}Transfer-Encoding: chunked\r\n\r\n",
            "POST /passby-sync/v1/exchange HTTP/1.1\r\n${host}Content-Length: 4\r\nExpect: 100-continue\r\n\r\nabcd",
            "POST /passby-sync/v1/exchange HTTP/1.1\r\n${host}Content-Length: 40\r\n\r\nhalf",
            "POST /passby-sync/v1/exchange HTTP/1.0 extra\r\n$host\r\n",
            "nonsense\r\n\r\n",
            "no line end at all",
            "GET / HTTP/1.1\r\n${host}X: ${"y".repeat(9000)}\r\n\r\n",
            "GET /${"p".repeat(9000)} HTTP/1.1\r\n$host\r\n",
            "GET / HTTP/1.1\r\n$host" + (1..40).joinToString("") { "X-$it: v\r\n" } + "\r\n",
            "\u0000\u0001\u0002\r\n\r\n",
        )
        for (request in dropped) assertEquals(request.take(60), "", raw(h.port, request))
        // None of that counts against the code or stops the host.
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
        for (bad in listOf("POST /x HTTP/1.1\r\nContent-Length: 3\r\n\r\nab", "POST /x HTTP/1.1\r\nContent-Length: -1\r\n\r\n", "POST /x HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 1\r\n\r\na", "POST /x HTTP/1.1\r\nno colon\r\n\r\n", "POST /x HTTP/1.1\r\n", "POST /x HTTP/1.1\r\nExpect: 100-continue\r\n\r\n", "POST /x HTTP/1.1\r\nContent-Length: 123456789\r\n\r\n", "POST /x HTTP/1.1\r\n" + "A: b\r\n".repeat(33) + "\r\n")) {
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
        SyncHttp.write(it.getOutputStream(), "POST $path HTTP/1.1", listOf("Host" to "127.0.0.1:$port"), body)
        val response = SyncHttp.read(it.getInputStream())
        response.start.split(' ')[1] to response.body
    }
}
