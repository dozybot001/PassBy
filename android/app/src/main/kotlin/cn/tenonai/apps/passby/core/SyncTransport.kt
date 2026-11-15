package cn.tenonai.apps.passby.core

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.net.ServerSocket
import java.net.Socket
import java.net.SocketTimeoutException
import java.security.SecureRandom

/**
 * The little HTTP/1.1 that carries sync frames (docs/sync.md §6.1). It is an envelope only: every
 * body is sealed by [SyncCrypto], and nothing here is trusted before it opens. One message per
 * connection, a fixed length, and anything out of the ordinary ends the connection.
 */
internal object SyncHttp {
    const val MAX_BODY = 8 * 1024 * 1024
    const val MAX_HEAD = 8192
    const val TIMEOUT_MS = 15_000
    const val BEGIN = "/passby-sync/v1/begin"
    const val EXCHANGE = "/passby-sync/v1/exchange"
    const val ORIGIN = "https://passby.tenonai.cn"

    class Message(val start: String, val headers: Map<String, String>, val body: ByteArray)

    /** Reads one message, giving up when it is malformed, too large or takes longer than [TIMEOUT_MS] in all. */
    fun read(input: InputStream, now: () -> Long = System::nanoTime): Message {
        val deadline = now() + TIMEOUT_MS * 1_000_000L
        fun late() = now() - deadline > 0
        val head = ByteArrayOutputStream()
        var matched = 0
        while (matched < 4) {
            val byte = input.read()
            if (byte < 0 || late()) throw IOException("incomplete head")
            head.write(byte)
            if (head.size() > MAX_HEAD) throw IOException("head too large")
            matched = if (byte == "\r\n\r\n"[matched].code) matched + 1 else if (byte == '\r'.code) 1 else 0
        }
        val lines = String(head.toByteArray(), Charsets.ISO_8859_1).dropLast(4).split("\r\n")
        val headers = HashMap<String, String>()
        for (line in lines.drop(1)) {
            val colon = line.indexOf(':')
            if (colon <= 0) throw IOException("bad header")
            val name = line.substring(0, colon).lowercase()
            if (headers.put(name, line.substring(colon + 1).trim()) != null && name == "content-length") throw IOException("two lengths")
        }
        if ("transfer-encoding" in headers) throw IOException("unsupported encoding")
        val text = headers["content-length"] ?: "0"
        if (text.isEmpty() || text.length > 8 || !text.all { it in '0'..'9' }) throw IOException("bad length")
        val length = text.toInt()
        if (length > MAX_BODY) throw IOException("body too large")
        val body = ByteArray(length)
        var filled = 0
        while (filled < length) {
            val count = input.read(body, filled, length - filled)
            if (count < 0 || late()) throw IOException("incomplete body")
            filled += count
        }
        return Message(lines[0], headers, body)
    }

    fun write(out: OutputStream, start: String, headers: List<Pair<String, String>>, body: ByteArray) {
        val head = StringBuilder(start).append("\r\n")
        for ((name, value) in headers) head.append(name).append(": ").append(value).append("\r\n")
        head.append("Content-Length: ").append(body.size).append("\r\nConnection: close\r\n\r\n")
        out.write(head.toString().toByteArray(Charsets.ISO_8859_1))
        out.write(body)
        out.flush()
    }
}

/** An address the other device is reached at: a private IPv4 address written out, and a port. */
data class SyncAddress(val host: String, val port: Int) {
    override fun toString() = "$host:$port"

    fun inet(): InetAddress = InetAddress.getByAddress(host.split('.').map { it.toInt().toByte() }.toByteArray())

    companion object {
        /**
         * This phone's address on the Wi-Fi or local network it is on, or null when it is on none.
         * Mobile data and VPN interfaces are left out; Wi-Fi comes before anything else.
         */
        fun local(port: Int): SyncAddress? = try {
            NetworkInterface.getNetworkInterfaces().toList()
                .filter { it.isUp && !it.isLoopback && !it.isPointToPoint && LEFT_OUT.none { prefix -> it.name.startsWith(prefix) } }
                .sortedBy { if (it.name.startsWith("wlan")) 0 else 1 }
                .flatMap { it.inetAddresses.toList() }
                .firstNotNullOfOrNull { parse("${it.hostAddress}:$port") }
        } catch (e: IOException) {
            null
        }

        private val LEFT_OUT = listOf("rmnet", "ccmni", "pdp", "tun", "ppp", "dummy")

        /** Reads `10.1.2.3:52814`. Names are not looked up, and only 10/8, 172.16/12 and 192.168/16 are accepted. */
        fun parse(text: String): SyncAddress? {
            val match = Regex("^(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3}):(\\d{1,5})$").find(text.trim()) ?: return null
            val parts = match.groupValues.drop(1).map { it.toInt() }
            val (a, b, c, d) = parts
            val port = parts[4]
            if (listOf(a, b, c, d).any { it > 255 } || port !in 1..65535) return null
            val private = a == 10 || (a == 172 && b in 16..31) || (a == 192 && b == 168)
            return if (private) SyncAddress("$a.$b.$c.$d", port) else null
        }
    }
}

/**
 * The listening side (docs/sync.md §6). It serves one connection at a time on its own thread, and
 * stops for good when [stop] is called, after [MAX_FAILURES] frames that did not open, or after
 * [IDLE_MS] without a request.
 *
 * [exchange] is given the guest's state once a frame has opened and been read; it merges, writes the
 * notebook and returns what to answer, or null when the notebook could not be written.
 */
class SyncHost(
    code: String,
    private val bind: InetAddress,
    private val preferredPort: Int,
    private val exchange: (SyncState) -> Reply?,
    private val onStopped: (Stop) -> Unit,
    private val iterations: Int = SyncCrypto.ITERATIONS,
    private val random: SecureRandom = SecureRandom(),
    private val clock: () -> Long = System::currentTimeMillis,
) {
    class Reply(val state: SyncState, val summary: SyncSummary)

    enum class Stop { CLOSED, IDLE, WRONG_CODE, FAILED }

    private class Session(val hostNonce: ByteArray, val guestNonce: ByteArray, val keys: SyncCrypto.Keys, var counter: Long)

    private val code = code.toByteArray(Charsets.US_ASCII)
    private val pending = LinkedHashMap<String, Long>()
    private val sessions = ArrayList<Session>()
    private var failures = 0
    private var lastRequest = 0L
    private var server: ServerSocket? = null

    @Volatile private var stopped = false

    /** The port being listened on; differs from the preferred one when that was taken. */
    var port = 0
        private set

    /** Starts listening. Throws IOException when no port can be opened on the address. */
    fun start() {
        val socket = try {
            open(preferredPort)
        } catch (e: IOException) {
            open(0)
        }
        server = socket
        port = socket.localPort
        lastRequest = clock()
        Thread({ serve(socket) }, "passby-sync-host").apply { isDaemon = true }.start()
    }

    private fun open(port: Int) = ServerSocket().apply {
        reuseAddress = true
        soTimeout = 1000
        bind(InetSocketAddress(bind, port), 4)
    }

    /** Stops listening and forgets the code and the keys. */
    fun stop() = stop(Stop.CLOSED)

    private fun stop(reason: Stop) {
        synchronized(this) {
            if (stopped) return
            stopped = true
            code.fill(0)
            sessions.forEach { it.keys.wipe() }
            sessions.clear()
            pending.clear()
        }
        try {
            server?.close()
        } catch (e: IOException) {
            // Already closed.
        }
        onStopped(reason)
    }

    private fun serve(socket: ServerSocket) {
        while (!stopped) {
            val connection = try {
                socket.accept()
            } catch (e: SocketTimeoutException) {
                if (clock() - lastRequest >= IDLE_MS) stop(Stop.IDLE)
                continue
            } catch (e: IOException) {
                if (!stopped) stop(Stop.FAILED)
                return
            }
            try {
                connection.use {
                    it.soTimeout = SyncHttp.TIMEOUT_MS
                    handle(it)
                }
            } catch (e: IOException) {
                // A connection that breaks or misbehaves is dropped; the next one is served.
            }
            if (failures >= MAX_FAILURES) stop(Stop.WRONG_CODE)
        }
    }

    private fun handle(connection: Socket) {
        val request = SyncHttp.read(connection.getInputStream())
        val parts = request.start.split(' ')
        if (parts.size != 3 || !parts[2].startsWith("HTTP/1.")) throw IOException("bad request line")
        lastRequest = clock()
        val out = connection.getOutputStream()
        fun answer(status: String, body: ByteArray = ByteArray(0)) = SyncHttp.write(
            out,
            "HTTP/1.1 $status",
            listOf(
                "Access-Control-Allow-Origin" to SyncHttp.ORIGIN,
                "Access-Control-Allow-Methods" to "POST",
                "Access-Control-Allow-Headers" to "content-type",
                "Cache-Control" to "no-store",
                "Content-Type" to "application/octet-stream",
            ),
            body,
        )
        val (method, path) = parts
        when {
            stopped -> answer("410 Gone")
            method == "OPTIONS" -> answer("204 No Content")
            method == "POST" && path == SyncHttp.BEGIN && request.body.isEmpty() -> answer("200 OK", begin())
            method == "POST" && path == SyncHttp.EXCHANGE -> {
                val body = try {
                    answerTo(request.body)
                } catch (e: SyncException) {
                    if (e.kind == SyncException.Kind.REFUSED) {
                        failures += 1
                        return answer("403 Forbidden")
                    }
                    null
                }
                if (body == null) answer("400 Bad Request") else answer("200 OK", body)
            }
            else -> answer("400 Bad Request")
        }
    }

    private fun key(nonce: ByteArray) = nonce.joinToString("") { "%02x".format(it) }

    private fun begin(): ByteArray {
        val now = clock()
        pending.values.removeAll { now - it >= NONCE_MS }
        // Someone asking for nonces without using them pushes out the oldest, not the newest.
        while (pending.size >= MAX_PENDING) pending.remove(pending.keys.first())
        val nonce = ByteArray(SyncCrypto.NONCE_LENGTH).also { random.nextBytes(it) }
        pending[key(nonce)] = now
        return nonce
    }

    /** The sealed answer, or null when the request opened but cannot be answered. Throws REFUSED when it does not open. */
    private fun answerTo(body: ByteArray): ByteArray? {
        fun refused(): Nothing = throw SyncException(SyncException.Kind.REFUSED)
        val request = SyncCrypto.readRequest(body)
        if (request.counter < 0) refused()
        var session = sessions.firstOrNull { it.hostNonce.contentEquals(request.hostNonce) && it.guestNonce.contentEquals(request.guestNonce) }
        val plain: ByteArray
        if (session == null) {
            // A host nonce starts one session, within a minute of being handed out.
            val issued = pending.remove(key(request.hostNonce)) ?: refused()
            if (clock() - issued >= NONCE_MS) refused()
            val keys = SyncCrypto.deriveKeys(String(code, Charsets.US_ASCII), request.hostNonce, request.guestNonce, iterations) {
                if (stopped) throw IOException("stopped")
            }
            plain = try {
                SyncCrypto.open(keys.guestToHost, request.hostNonce, request.guestNonce, SyncCrypto.GUEST_TO_HOST, request.counter, request.sealed)
            } catch (e: SyncException) {
                keys.wipe()
                throw e
            }
            session = Session(request.hostNonce, request.guestNonce, keys, request.counter)
            synchronized(this) {
                if (stopped) {
                    keys.wipe()
                    return null
                }
                if (sessions.size >= MAX_SESSIONS) sessions.removeAt(0).keys.wipe()
                sessions += session
            }
        } else {
            if (request.counter <= session.counter) refused()
            plain = SyncCrypto.open(session.keys.guestToHost, request.hostNonce, request.guestNonce, SyncCrypto.GUEST_TO_HOST, request.counter, request.sealed)
            session.counter = request.counter
        }
        val reply = try {
            exchange(SyncCodec.readRequest(plain))
        } catch (e: SyncException) {
            null
        } ?: return null
        return SyncCrypto.responseBody(
            request.counter,
            SyncCrypto.seal(session.keys.hostToGuest, request.hostNonce, request.guestNonce, SyncCrypto.HOST_TO_GUEST, request.counter, SyncCodec.response(reply.state, reply.summary)),
        )
    }

    companion object {
        const val MAX_FAILURES = 5
        const val IDLE_MS = 10 * 60 * 1000L
        const val NONCE_MS = 60 * 1000L
        private const val MAX_PENDING = 8
        private const val MAX_SESSIONS = 4
    }
}

class SyncGuestException(val kind: Kind) : Exception(kind.name) {
    enum class Kind {
        /** Nothing answered at the address. */
        UNREACHABLE,

        /** The host refused the frame: the code is wrong. */
        WRONG_CODE,

        /** The host has stopped listening. */
        STOPPED,

        /** The answer did not come from a device holding the code, or is not a valid state. */
        UNTRUSTED,

        /** The host could not take the request. */
        FAILED,
    }
}

/** The connecting side when it is a phone. One instance is one session; [exchange] may be called again. */
class SyncGuest(
    private val address: InetAddress,
    private val port: Int,
    code: String,
    private val iterations: Int = SyncCrypto.ITERATIONS,
    private val random: SecureRandom = SecureRandom(),
) {
    private val code = code.toByteArray(Charsets.US_ASCII)
    private var hostNonce: ByteArray? = null
    private val guestNonce = ByteArray(SyncCrypto.NONCE_LENGTH).also { random.nextBytes(it) }
    private var keys: SyncCrypto.Keys? = null
    private var counter = 0L

    /** Sends this device's state and returns the merged state with what changed here. [check] may cancel by throwing. */
    fun exchange(state: SyncState, check: (() -> Unit)? = null): Pair<SyncState, SyncSummary> {
        val nonce = hostNonce ?: post(SyncHttp.BEGIN, ByteArray(0)).also {
            if (it.size != SyncCrypto.NONCE_LENGTH) throw SyncGuestException(SyncGuestException.Kind.UNTRUSTED)
            hostNonce = it
        }
        val keys = keys ?: SyncCrypto.deriveKeys(String(code, Charsets.US_ASCII), nonce, guestNonce, iterations, check).also { keys = it }
        val sent = counter++
        val body = SyncCrypto.requestBody(
            nonce, guestNonce, sent,
            SyncCrypto.seal(keys.guestToHost, nonce, guestNonce, SyncCrypto.GUEST_TO_HOST, sent, SyncCodec.request(state)),
        )
        val answer = post(SyncHttp.EXCHANGE, body)
        try {
            val (answered, sealed) = SyncCrypto.readResponse(answer)
            if (answered != sent) throw SyncGuestException(SyncGuestException.Kind.UNTRUSTED)
            return SyncCodec.readResponse(SyncCrypto.open(keys.hostToGuest, nonce, guestNonce, SyncCrypto.HOST_TO_GUEST, sent, sealed))
        } catch (e: SyncException) {
            throw SyncGuestException(SyncGuestException.Kind.UNTRUSTED)
        }
    }

    /** Forgets the code and the keys. */
    fun close() {
        code.fill(0)
        keys?.wipe()
        keys = null
    }

    private fun post(path: String, body: ByteArray): ByteArray {
        val response = try {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(address, port), CONNECT_TIMEOUT_MS)
                socket.soTimeout = SyncHttp.TIMEOUT_MS
                SyncHttp.write(
                    socket.getOutputStream(),
                    "POST $path HTTP/1.1",
                    listOf("Host" to "${address.hostAddress}:$port", "Content-Type" to "application/octet-stream"),
                    body,
                )
                SyncHttp.read(socket.getInputStream())
            }
        } catch (e: IOException) {
            throw SyncGuestException(SyncGuestException.Kind.UNREACHABLE)
        }
        val status = response.start.split(' ').getOrNull(1)
        throw SyncGuestException(
            when (status) {
                "200" -> return response.body
                "403" -> SyncGuestException.Kind.WRONG_CODE
                "410" -> SyncGuestException.Kind.STOPPED
                else -> SyncGuestException.Kind.FAILED
            },
        )
    }

    companion object {
        const val CONNECT_TIMEOUT_MS = 5000
    }
}
