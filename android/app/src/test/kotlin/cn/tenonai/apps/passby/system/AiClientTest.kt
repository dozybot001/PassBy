package cn.tenonai.apps.passby.system

import java.io.IOException
import java.net.SocketTimeoutException
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.fail
import org.junit.Test

class AiClientTest {
    private fun problemOf(block: () -> Unit): AiClient.Failure {
        try {
            AiClient.guarded(block)
        } catch (e: AiClient.Failure) {
            return e
        }
        throw AssertionError("nothing was thrown")
    }

    /** The platform's own error for a bad header value quotes the value, which would be the API key. */
    @Test
    fun anUnexpectedErrorBecomesAFailureThatCarriesNothing() {
        val failure = problemOf { throw IllegalArgumentException("Unexpected char 0x0a in header value: Bearer sk-SECRET") }
        assertEquals(AiClient.Problem.NETWORK, failure.problem)
        assertNull(failure.message)
        assertNull(failure.cause)
        assertNull(failure.status)
    }

    @Test
    fun knownErrorsKeepTheirKind() {
        assertEquals(AiClient.Problem.TIMEOUT, problemOf { throw SocketTimeoutException("x") }.problem)
        assertEquals(AiClient.Problem.NETWORK, problemOf { throw IOException("x") }.problem)
        val status = problemOf { throw AiClient.Failure(AiClient.Problem.STATUS, 500) }
        assertEquals(AiClient.Problem.STATUS, status.problem)
        assertEquals(500, status.status)
    }

    @Test
    fun aResultPassesThrough() {
        assertEquals("ok", AiClient.guarded { "ok" })
        try {
            AiClient.guarded { throw OutOfMemoryError() }
            fail()
        } catch (e: OutOfMemoryError) {
            // Not something to turn into a network problem.
        }
    }
}
