package cn.tenonai.apps.passby.core

import java.security.SecureRandom
import java.time.Instant
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/** Cases the shared vectors do not cover. */
class ExportFormatTest {
    private val folderId = "6F1C2A4E-8B3D-4C5E-9F60-1A2B3C4D5E6F"
    private val entryId = "0E8F6A2B-1C3D-4E5F-8A9B-0C1D2E3F4A5B"

    private fun kindOf(json: String): ExportException.Kind? = try {
        ExportPlaintext.parse(json.toByteArray(Charsets.UTF_8))
        null
    } catch (e: ExportException) {
        e.kind
    }

    private fun notebook(format: String = "1", folders: String = "[]", entries: String = "[]") =
        """{"format":$format,"exportedAt":"2026-11-14T12:00:00Z","folders":$folders,"entries":$entries}"""

    private fun entry(id: String = entryId, extra: String = "") =
        """{"id":"$id","title":"t","account":"a","password":"p","notes":"n"$extra}"""

    @Test
    fun pbkdf2MatchesAPublishedVector() {
        // PBKDF2-HMAC-SHA256, "password" / "salt", 4096 rounds, 32 bytes: a widely published value.
        val key = ExportFile.pbkdf2("password".toByteArray(), "salt".toByteArray(), 4096, 32)
        assertEquals("c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a", key.joinToString("") { "%02x".format(it) })
    }

    @Test
    fun pbkdf2SpansMoreThanOneBlock() {
        // Same inputs, 40 bytes: the first 32 must equal the 32-byte result and the rest come from block 2.
        val long = ExportFile.pbkdf2("password".toByteArray(), "salt".toByteArray(), 2, 40)
        val short = ExportFile.pbkdf2("password".toByteArray(), "salt".toByteArray(), 2, 32)
        assertArrayEquals(short, long.copyOf(32))
        assertEquals(40, long.size)
    }

    @Test
    fun hkdfMatchesRfc5869Case1() {
        fun unhex(text: String) = ByteArray(text.length / 2) { text.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
        val okm = ExportFile.hkdf(
            ikm = unhex("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"),
            salt = unhex("000102030405060708090a0b0c"),
            info = unhex("f0f1f2f3f4f5f6f7f8f9"),
            length = 42,
        )
        assertEquals(
            "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865",
            okm.joinToString("") { "%02x".format(it) },
        )
    }

    @Test
    fun anEmptySecretIsAWrongCodeNotACrash() {
        val file = ExportFile.encode("correct horse".toByteArray(), ByteArray(16), ByteArray(12), ExportFile.MIN_ITERATIONS, "{}".toByteArray())
        try {
            ExportFile.open(file, "   ")
            fail("expected wrongCode")
        } catch (e: ExportException) {
            assertEquals(ExportException.Kind.WRONG_CODE, e.kind)
        }
    }

    @Test
    fun sealUsesFreshSaltAndNonceAndOpensAgain() {
        val code = ExportSecret.newCode()
        val plaintext = ExportPlaintext.serialize(emptyList(), listOf(Entry(entryId, "标题", "a", "p", "")), Instant.parse("2026-11-14T12:00:00.900Z"))
        val secret = ExportSecret.secretBytes(code).bytes
        val first = ExportFile.seal(secret, plaintext, SecureRandom())
        val second = ExportFile.seal(secret, plaintext, SecureRandom())
        assertFalse(first.copyOfRange(14, 42).contentEquals(second.copyOfRange(14, 42)))
        assertEquals(ExportFile.DEFAULT_ITERATIONS, ((first[10].toInt() and 0xFF) shl 24) or ((first[11].toInt() and 0xFF) shl 16) or ((first[12].toInt() and 0xFF) shl 8) or (first[13].toInt() and 0xFF))
        val opened = ExportPlaintext.parse(ExportFile.open(first, ExportSecret.grouped(code).lowercase()))
        assertEquals("标题", opened.entries.single().title)
        // Seconds only, as the format says.
        assertEquals(Instant.parse("2026-11-14T12:00:00Z"), opened.exportedAt)
    }

    @Test
    fun aCancelledDerivationStops() {
        var calls = 0
        try {
            ExportFile.pbkdf2(ByteArray(1), ByteArray(16), 1_000_000, 32) {
                calls++
                throw InterruptedException()
            }
            fail("expected the check to stop the derivation")
        } catch (e: InterruptedException) {
            assertEquals(1, calls)
        }
    }

    @Test
    fun formatMustBeAWholeNumber() {
        assertNull(kindOf(notebook()))
        assertNull(kindOf(notebook(format = "1.0")))
        assertNull(kindOf(notebook(format = "1e0")))
        assertEquals(ExportException.Kind.DAMAGED, kindOf(notebook(format = "1.5")))
        assertEquals(ExportException.Kind.DAMAGED, kindOf(notebook(format = "\"1\"")))
        assertEquals(ExportException.Kind.DAMAGED, kindOf(notebook(format = "null")))
        assertEquals(ExportException.Kind.UPDATE, kindOf(notebook(format = "2")))
        assertEquals(ExportException.Kind.UPDATE, kindOf(notebook(format = "0")))
        assertEquals(ExportException.Kind.DAMAGED, kindOf("""{"exportedAt":"2026-11-14T12:00:00Z","folders":[],"entries":[]}"""))
        assertEquals(ExportException.Kind.DAMAGED, kindOf("[]"))
        assertEquals(ExportException.Kind.DAMAGED, kindOf(""))
    }

    @Test
    fun aNewerFormatIsReportedBeforeItsFieldsAreChecked() {
        assertEquals(ExportException.Kind.UPDATE, kindOf("""{"format":2,"somethingNew":true}"""))
    }

    @Test
    fun fieldsAreChecked() {
        val folder = """[{"id":"$folderId","name":"工作"}]"""
        assertNull(kindOf(notebook(folders = folder, entries = "[${entry(extra = ""","folderID":"$folderId"""")}]")))
        assertNull(kindOf(notebook(entries = "[${entry(extra = ""","unknown":{"deep":[1,2,3]}""")}]")))
        // Missing or mistyped fields.
        assertEquals(ExportException.Kind.DAMAGED, kindOf(notebook(entries = """[{"id":"$entryId","title":"t","account":"a","password":"p"}]""")))
        assertEquals(ExportException.Kind.DAMAGED, kindOf(notebook(entries = """[{"id":"$entryId","title":1,"account":"a","password":"p","notes":""}]""")))
        assertEquals(ExportException.Kind.DAMAGED, kindOf(notebook(entries = "[${entry(id = "not-a-uuid")}]")))
        assertEquals(ExportException.Kind.DAMAGED, kindOf(notebook(entries = "[${entry(extra = ""","folderID":null""")}]")))
        // A folder that is not in the file, and repeated identifiers in either case.
        assertEquals(ExportException.Kind.DAMAGED, kindOf(notebook(entries = "[${entry(extra = ""","folderID":"$folderId"""")}]")))
        assertEquals(ExportException.Kind.DAMAGED, kindOf(notebook(entries = "[${entry()},${entry(id = entryId.lowercase())}]")))
        assertEquals(ExportException.Kind.DAMAGED, kindOf(notebook(folders = """[{"id":"$folderId","name":"a"},{"id":"$folderId","name":"b"}]""")))
        assertEquals(ExportException.Kind.DAMAGED, kindOf("""{"format":1,"exportedAt":"yesterday","folders":[],"entries":[]}"""))
        // Other ISO 8601 spellings of the time, which the reference also reads.
        for (time in listOf("2026-11-14T12:00:00.000Z", "2026-11-14T20:00:00+08:00", "2026-11-14T12:00:00", "2026-11-14")) {
            assertNull(time, kindOf("""{"format":1,"exportedAt":"$time","folders":[],"entries":[]}"""))
        }
        // Bytes that are not UTF-8.
        assertEquals(
            ExportException.Kind.DAMAGED,
            try {
                ExportPlaintext.parse(byteArrayOf(0x7B, 0xFF.toByte(), 0x7D))
                null
            } catch (e: ExportException) {
                e.kind
            },
        )
    }

    @Test
    fun identifiersAreReadInEitherCaseAndKeptInUpperCase() {
        val lower = folderId.lowercase()
        val parsed = ExportPlaintext.parse(
            notebook(folders = """[{"id":"$lower","name":"x"}]""", entries = "[${entry(id = entryId.lowercase(), extra = ""","folderID":"$folderId"""")}]")
                .toByteArray(Charsets.UTF_8),
        )
        assertEquals(folderId, parsed.folders.single().id)
        assertEquals(entryId, parsed.entries.single().id)
        assertEquals(folderId, parsed.entries.single().folderId)
    }

    @Test
    fun exportLeavesOutAFolderThatDoesNotExist() {
        val bytes = ExportPlaintext.serialize(emptyList(), listOf(Entry(entryId, "t", folderId = folderId)), Instant.EPOCH)
        assertNull(ExportPlaintext.parse(bytes).entries.single().folderId)
    }

    @Test
    fun newCodesUseTheAlphabetAndGroupInFives() {
        repeat(50) {
            val code = ExportSecret.newCode()
            assertEquals(20, code.length)
            assertTrue(code.all { it in ExportSecret.CODE_ALPHABET })
            assertEquals(code, ExportSecret.canonicalCode(ExportSecret.grouped(code)))
            assertEquals(ExportSecret.PassphraseProblem.LOOKS_LIKE_CODE, ExportSecret.passphraseProblem(ExportSecret.grouped(code)))
        }
        assertEquals("7K3M9-Q2XHB-R8T4V-W6YZ0", ExportSecret.grouped("7K3M9Q2XHBR8T4VW6YZ0"))
    }

    @Test
    fun codesWithOtherCharactersOrLengthsAreNotCodes() {
        assertNull(ExportSecret.canonicalCode("7K3M9-Q2XHB-R8T4V-W6YZ"))
        assertNull(ExportSecret.canonicalCode("7K3M9-Q2XHB-R8T4V-W6YZ00"))
        assertNull(ExportSecret.canonicalCode("7K3M9-Q2XHB-R8T4V-W6YZU"))
        assertNull(ExportSecret.canonicalCode("７K3M9-Q2XHB-R8T4V-W6YZ0"))
        assertNull(ExportSecret.canonicalCode(""))
    }

    @Test
    fun trimmingUsesTheListedCodePointsOnly() {
        assertEquals("a b", ExportSecret.trimSpace("　﻿ a b  "))
        // U+001F and U+200B are white space or invisible to some libraries but are not in the format's list.
        assertEquals("\u001Fa​", ExportSecret.trimSpace("\u001Fa​"))
        assertEquals("", ExportSecret.trimSpace(" \t\n"))
    }

    @Test
    fun aSurrogateWithoutAPartnerBecomesTheReplacementCharacter() {
        assertArrayEquals(byteArrayOf(0x61, 0xEF.toByte(), 0xBF.toByte(), 0xBD.toByte(), 0x62), ExportSecret.utf8("a\uD83Db"))
        assertArrayEquals("a🔐é我".toByteArray(Charsets.UTF_8), ExportSecret.utf8("a🔐é我"))
    }
}
