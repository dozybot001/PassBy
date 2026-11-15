package cn.tenonai.apps.passby.system

import cn.tenonai.apps.passby.BuildConfig
import cn.tenonai.apps.passby.core.AiGrouping
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.net.SocketTimeoutException
import java.net.URL
import javax.net.ssl.HttpsURLConnection

/**
 * The only place in the app that opens a network connection (a test checks that no other file can).
 *
 * It sends one request, to the address the person entered, when the person has just pressed Send on
 * the page that showed them the request. It keeps nothing: no log, no cookie, no retry.
 */
object AiClient {
    enum class Problem { OFF, ADDRESS, NO_KEY, NETWORK, TIMEOUT, REDIRECT, STATUS, TOO_LARGE }

    /** [status] is the HTTP status for [Problem.STATUS] and [Problem.REDIRECT]. The response body is never kept. */
    class Failure(val problem: Problem, val status: Int? = null) : Exception()

    /** A request body exactly as it was shown to the person, who then chose to send it. */
    class Approved(val body: String)

    private const val CONNECT_TIMEOUT_MS = 20_000
    private const val READ_TIMEOUT_MS = 60_000
    private const val MAX_RESPONSE_BYTES = 1024 * 1024

    /** Returns the provider's response. Throws [Failure] and sends nothing when a condition is not met. */
    @Throws(Failure::class)
    fun send(settings: AiSettings, approved: Approved): String {
        val config = settings.load() ?: throw Failure(Problem.OFF)
        val endpoint = AiGrouping.endpoint(config.endpoint) ?: throw Failure(Problem.ADDRESS)
        // Read for this host and port only; a key saved for another is not returned.
        val key = settings.key(endpoint.authority)?.let { AiGrouping.apiKey(it) } ?: throw Failure(Problem.NO_KEY)
        return guarded { post(endpoint, key, approved.body) }
    }

    /**
     * Runs [block] so that nothing but a [Failure] comes out of it. An unexpected error carries no
     * message onward: the text of such an error can hold a request header, and with it the API key.
     */
    internal inline fun <T> guarded(block: () -> T): T = try {
        block()
    } catch (e: Failure) {
        throw e
    } catch (e: SocketTimeoutException) {
        throw Failure(Problem.TIMEOUT)
    } catch (e: IOException) {
        throw Failure(Problem.NETWORK)
    } catch (e: RuntimeException) {
        throw Failure(Problem.NETWORK)
    }

    private fun post(endpoint: AiGrouping.Endpoint, key: String, text: String): String {
        var connection: HttpsURLConnection? = null
        try {
            val url = URL(endpoint.url)
            // The address was checked with another parser; the two have to agree on where it leads.
            val port = if (url.port == -1) 443 else url.port
            if (!url.protocol.equals("https", ignoreCase = true) || url.host.lowercase() != endpoint.host || port != endpoint.port) {
                throw Failure(Problem.ADDRESS)
            }
            // An https address always yields an HTTPS connection; anything else stops here.
            connection = url.openConnection() as? HttpsURLConnection ?: throw Failure(Problem.ADDRESS)
            connection.requestMethod = "POST"
            connection.instanceFollowRedirects = false
            connection.useCaches = false
            connection.doOutput = true
            connection.connectTimeout = CONNECT_TIMEOUT_MS
            connection.readTimeout = READ_TIMEOUT_MS
            connection.setRequestProperty("Content-Type", "application/json")
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("Authorization", "Bearer $key")
            // The default would name the phone's model and Android version.
            connection.setRequestProperty("User-Agent", "PassBy-Android/${BuildConfig.VERSION_NAME}")
            val body = text.toByteArray(Charsets.UTF_8)
            connection.setFixedLengthStreamingMode(body.size)
            connection.outputStream.use { it.write(body) }

            val status = connection.responseCode
            if (status in 300..399) throw Failure(Problem.REDIRECT, status)
            // An error body can repeat part of the key or the request, so it is not read.
            if (status !in 200..299) throw Failure(Problem.STATUS, status)
            val out = ByteArrayOutputStream()
            connection.inputStream.use { input ->
                val buffer = ByteArray(16 * 1024)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) break
                    out.write(buffer, 0, count)
                    if (out.size() > MAX_RESPONSE_BYTES) throw Failure(Problem.TOO_LARGE)
                }
            }
            return String(out.toByteArray(), Charsets.UTF_8)
        } finally {
            connection?.disconnect()
        }
    }
}
