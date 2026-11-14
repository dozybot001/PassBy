package cn.tenonai.apps.passby.core

import java.io.File
import java.util.Base64
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.fail
import org.junit.Test

/**
 * Every vector in docs/export-vectors.json. iPhone and the web app pass the same file, which is what
 * makes an export from one open on the others. The file is read where it is, not copied.
 */
class ExportVectorsTest {
    private val vectors: JsonValue = Json.parse(vectorsFile().readText(Charsets.UTF_8))

    // Gradle passes the path; the fallback is the test working directory, android/app.
    private fun vectorsFile() = File(System.getProperty("passby.vectors") ?: "../../docs/export-vectors.json")

    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }
    private fun unhex(text: String) = ByteArray(text.length / 2) { text.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
    private fun base64(text: String): ByteArray = Base64.getDecoder().decode(text)
    private fun JsonValue.text(name: String): String = this[name].string!!
    private fun JsonValue.iterations(): Int = this["iterations"].long!!.toInt()
    private fun JsonValue.inputs(): List<String> = listOf(text("typed")) + this["equivalentInputs"].items!!.map { it.string!! }

    private fun name(kind: ExportException.Kind) = when (kind) {
        ExportException.Kind.NOT_EXPORT -> "notExport"
        ExportException.Kind.UPDATE -> "update"
        ExportException.Kind.DAMAGED -> "damaged"
        ExportException.Kind.WRONG_CODE -> "wrongCode"
    }

    private fun name(problem: ExportSecret.PassphraseProblem?) = when (problem) {
        ExportSecret.PassphraseProblem.SURROUNDING_SPACE -> "surroundingSpace"
        ExportSecret.PassphraseProblem.LOOKS_LIKE_CODE -> "looksLikeCode"
        ExportSecret.PassphraseProblem.TOO_SHORT -> "tooShort"
        null -> null
    }

    @Test
    fun theFileHasTheExpectedVectors() {
        assertEquals(5, vectors["valid"].items!!.size)
        assertEquals(10, vectors["invalid"].items!!.size)
        assertEquals(4, vectors["passphraseRules"].items!!.size)
    }

    @Test
    fun everyWayOfTypingGivesTheSameSecretBytes() {
        for (v in vectors["valid"].items!!) {
            for (input in v.inputs()) {
                val secret = ExportSecret.secretBytes(input)
                assertEquals("${v.text("name")}: $input", v.text("secretHex"), hex(secret.bytes))
                assertEquals(v.text("kind"), if (secret.kind == ExportSecret.Kind.CODE) "code" else "passphrase")
            }
        }
    }

    @Test
    fun derivedKeysMatch() {
        for (v in vectors["valid"].items!!) {
            val keys = ExportFile.deriveKeys(unhex(v.text("secretHex")), unhex(v.text("saltHex")), v.iterations())
            assertEquals(v.text("name"), v.text("masterKeyHex"), hex(keys.master))
            assertEquals(v.text("name"), v.text("encryptKeyHex"), hex(keys.encrypt))
            assertEquals(v.text("name"), v.text("checkKeyHex"), hex(keys.checkKey))
            assertEquals(v.text("name"), v.text("checkHex"), hex(keys.check))
        }
    }

    @Test
    fun validFilesOpenToThePlaintext() {
        for (v in vectors["valid"].items!!) {
            val file = base64(v.text("fileBase64"))
            for (input in v.inputs()) {
                val plaintext = ExportFile.open(file, input)
                assertEquals("${v.text("name")}: $input", v.text("plaintext"), String(plaintext, Charsets.UTF_8))
                // Reading the notebook and writing it again gives the same JSON, byte for byte.
                val notebook = ExportPlaintext.parse(plaintext)
                assertArrayEquals(plaintext, ExportPlaintext.serialize(notebook.folders, notebook.entries, notebook.exportedAt))
            }
        }
    }

    @Test
    fun encodingWithTheGivenSaltAndNonceGivesTheSameFile() {
        for (v in vectors["valid"].items!!) {
            val file = ExportFile.encode(
                secret = unhex(v.text("secretHex")),
                salt = unhex(v.text("saltHex")),
                nonce = unhex(v.text("nonceHex")),
                iterations = v.iterations(),
                plaintext = v.text("plaintext").toByteArray(Charsets.UTF_8),
            )
            assertArrayEquals(v.text("name"), base64(v.text("fileBase64")), file)
        }
    }

    @Test
    fun invalidFilesReportTheListedError() {
        for (v in vectors["invalid"].items!!) {
            try {
                ExportPlaintext.parse(ExportFile.open(base64(v.text("fileBase64")), v.text("typed")))
                fail("${v.text("name")}: expected ${v.text("error")}")
            } catch (e: ExportException) {
                assertEquals(v.text("name"), v.text("error"), name(e.kind))
            }
        }
    }

    @Test
    fun passphraseRulesMatch() {
        for (rule in vectors["passphraseRules"].items!!) {
            assertEquals(rule.text("typed"), rule["problem"].string, name(ExportSecret.passphraseProblem(rule.text("typed"))))
        }
    }
}
