package cn.tenonai.apps.passby.core

import java.io.ByteArrayOutputStream
import java.security.SecureRandom
import java.text.Normalizer

/** Turns what the person typed into the bytes fed to PBKDF2 (docs/export-format.md §2). */
object ExportSecret {
    /** Crockford Base32: no I, L, O or U. */
    const val CODE_ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    const val CODE_LENGTH = 20
    const val MIN_PASSPHRASE_LENGTH = 12

    // The format lists these code points itself. Kotlin's trim() and Char.isWhitespace() use another set.
    private val SPACE = setOf(
        0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x2000, 0x2001, 0x2002, 0x2003,
        0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF,
    )
    private val DASH = setOf(0x2D, 0x2010, 0x2011, 0x2012, 0x2013, 0x2014, 0x2015)

    enum class Kind { CODE, PASSPHRASE }

    class Secret(val kind: Kind, val bytes: ByteArray)

    enum class PassphraseProblem { SURROUNDING_SPACE, LOOKS_LIKE_CODE, TOO_SHORT }

    /** The export code in its canonical 20 characters, or null when the input is not an export code. */
    fun canonicalCode(input: String): String? {
        val out = StringBuilder(CODE_LENGTH)
        var i = 0
        while (i < input.length) {
            val cp = input.codePointAt(i)
            i += Character.charCount(cp)
            if (cp in SPACE || cp in DASH) continue
            var c = if (cp in 0x61..0x7A) cp - 32 else cp
            if (c == 'I'.code || c == 'L'.code) c = '1'.code else if (c == 'O'.code) c = '0'.code
            if (c > 0x7F || CODE_ALPHABET.indexOf(c.toChar()) < 0) return null
            if (out.length == CODE_LENGTH) return null
            out.append(c.toChar())
        }
        return if (out.length == CODE_LENGTH) out.toString() else null
    }

    /** Removes the format's white space from both ends and keeps it in the middle. */
    fun trimSpace(input: String): String {
        var start = 0
        var end = input.length
        while (start < end) {
            val cp = input.codePointAt(start)
            if (cp !in SPACE) break
            start += Character.charCount(cp)
        }
        while (end > start) {
            val cp = input.codePointBefore(end)
            if (cp !in SPACE) break
            end -= Character.charCount(cp)
        }
        return input.substring(start, end)
    }

    /** The bytes for an import: an export code if the input reads as one, otherwise a passphrase. */
    fun secretBytes(input: String): Secret {
        canonicalCode(input)?.let { return Secret(Kind.CODE, it.toByteArray(Charsets.US_ASCII)) }
        return Secret(Kind.PASSPHRASE, utf8(Normalizer.normalize(trimSpace(input), Normalizer.Form.NFC)))
    }

    /** Why a passphrase cannot be set when exporting, or null when it can (§2.3). */
    fun passphraseProblem(input: String): PassphraseProblem? {
        if (trimSpace(input) != input) return PassphraseProblem.SURROUNDING_SPACE
        if (canonicalCode(input) != null) return PassphraseProblem.LOOKS_LIKE_CODE
        val normalized = Normalizer.normalize(input, Normalizer.Form.NFC)
        if (normalized.codePointCount(0, normalized.length) < MIN_PASSPHRASE_LENGTH) return PassphraseProblem.TOO_SHORT
        return null
    }

    /** A new export code: 20 characters, each chosen evenly from 32, so 100 bits. */
    fun newCode(random: SecureRandom = SecureRandom()): String =
        buildString(CODE_LENGTH) { repeat(CODE_LENGTH) { append(CODE_ALPHABET[random.nextInt(CODE_ALPHABET.length)]) } }

    /** Four groups of five with hyphens, the form shown on screen and put in the QR code (§2.4). */
    fun grouped(code: String): String = code.chunked(5).joinToString("-")

    /**
     * UTF-8 with a surrogate that has no partner written as U+FFFD, which is what the reference
     * implementation and browsers do. String.toByteArray writes '?' instead.
     */
    fun utf8(text: String): ByteArray {
        val out = ByteArrayOutputStream(text.length + 16)
        var i = 0
        while (i < text.length) {
            var cp = text.codePointAt(i)
            i += Character.charCount(cp)
            if (cp in 0xD800..0xDFFF) cp = 0xFFFD
            when {
                cp < 0x80 -> out.write(cp)
                cp < 0x800 -> {
                    out.write(0xC0 or (cp shr 6))
                    out.write(0x80 or (cp and 0x3F))
                }
                cp < 0x10000 -> {
                    out.write(0xE0 or (cp shr 12))
                    out.write(0x80 or ((cp shr 6) and 0x3F))
                    out.write(0x80 or (cp and 0x3F))
                }
                else -> {
                    out.write(0xF0 or (cp shr 18))
                    out.write(0x80 or ((cp shr 12) and 0x3F))
                    out.write(0x80 or ((cp shr 6) and 0x3F))
                    out.write(0x80 or (cp and 0x3F))
                }
            }
        }
        return out.toByteArray()
    }
}
