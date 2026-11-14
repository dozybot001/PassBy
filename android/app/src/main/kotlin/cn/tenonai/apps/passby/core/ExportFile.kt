package cn.tenonai.apps.passby.core

import java.security.GeneralSecurityException
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.Mac
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** Why an export file could not be opened (docs/export-format.md §5). */
class ExportException(val kind: Kind) : Exception(kind.name) {
    enum class Kind { NOT_EXPORT, UPDATE, DAMAGED, WRONG_CODE }
}

/**
 * The binary export file (docs/export-format.md §1 and §3). Only the platform's own
 * HMAC-SHA256 and AES-GCM are used; PBKDF2 and HKDF are written out on top of HMAC.
 */
object ExportFile {
    const val HEADER_LENGTH = 58
    const val TAG_LENGTH = 16
    const val SALT_LENGTH = 16
    const val NONCE_LENGTH = 12
    const val DEFAULT_ITERATIONS = 600_000
    const val MIN_ITERATIONS = 100_000
    const val MAX_ITERATIONS = 10_000_000

    private const val HMAC = "HmacSHA256"
    private const val HASH_LENGTH = 32
    private val MAGIC = ascii("PASSBYEX")

    /** How many PBKDF2 rounds run between two calls of the caller's check, which may cancel by throwing. */
    private const val CHECK_EVERY = 4096

    class Keys(val master: ByteArray, val encrypt: ByteArray, val checkKey: ByteArray, val check: ByteArray) {
        fun wipe() {
            master.fill(0)
            encrypt.fill(0)
            checkKey.fill(0)
        }
    }

    private fun ascii(text: String) = text.toByteArray(Charsets.US_ASCII)

    private fun hmac(key: ByteArray): Mac {
        // HMAC pads a short key with zero bytes, so an empty key and a single zero byte are the same key.
        // SecretKeySpec refuses an empty array.
        val mac = Mac.getInstance(HMAC)
        mac.init(SecretKeySpec(if (key.isEmpty()) ByteArray(1) else key, HMAC))
        return mac
    }

    /**
     * PBKDF2-HMAC-SHA256 as in RFC 8018 §5.2. PBEKeySpec is not used: it takes chars, and how those
     * become bytes depends on the provider.
     */
    fun pbkdf2(password: ByteArray, salt: ByteArray, iterations: Int, length: Int, check: (() -> Unit)? = null): ByteArray {
        require(iterations > 0 && length > 0)
        val mac = hmac(password)
        val out = ByteArray(length)
        val u = ByteArray(HASH_LENGTH)
        val t = ByteArray(HASH_LENGTH)
        var block = 1
        var offset = 0
        while (offset < length) {
            mac.update(salt)
            mac.update(byteArrayOf((block ushr 24).toByte(), (block ushr 16).toByte(), (block ushr 8).toByte(), block.toByte()))
            mac.doFinal(u, 0)
            u.copyInto(t)
            for (round in 2..iterations) {
                mac.update(u)
                mac.doFinal(u, 0)
                for (j in 0 until HASH_LENGTH) t[j] = (t[j].toInt() xor u[j].toInt()).toByte()
                if (check != null && round % CHECK_EVERY == 0) check()
            }
            val count = minOf(HASH_LENGTH, length - offset)
            t.copyInto(out, offset, 0, count)
            offset += count
            block++
        }
        u.fill(0)
        t.fill(0)
        return out
    }

    /** HKDF-SHA256 as in RFC 5869. An empty salt stands for a hash length of zero bytes. */
    fun hkdf(ikm: ByteArray, salt: ByteArray, info: ByteArray, length: Int): ByteArray {
        require(length in 1..255 * HASH_LENGTH)
        val prk = hmac(if (salt.isEmpty()) ByteArray(HASH_LENGTH) else salt).doFinal(ikm)
        val expand = hmac(prk)
        val out = ByteArray(length)
        var previous = ByteArray(0)
        var offset = 0
        var counter = 1
        while (offset < length) {
            expand.update(previous)
            expand.update(info)
            expand.update(counter.toByte())
            previous = expand.doFinal()
            val count = minOf(HASH_LENGTH, length - offset)
            previous.copyInto(out, offset, 0, count)
            offset += count
            counter++
        }
        prk.fill(0)
        previous.fill(0)
        return out
    }

    fun deriveKeys(secret: ByteArray, salt: ByteArray, iterations: Int, check: (() -> Unit)? = null): Keys {
        val master = pbkdf2(secret, salt, iterations, 32, check)
        val encrypt = hkdf(master, ByteArray(0), ascii("PassBy export v1 encrypt"), 32)
        val checkKey = hkdf(master, ByteArray(0), ascii("PassBy export v1 check"), 32)
        val checkValue = hmac(checkKey).doFinal(ascii("PassBy export key check")).copyOf(16)
        return Keys(master, encrypt, checkKey, checkValue)
    }

    /** Builds the file for a fixed salt and nonce. Exports go through [seal], which draws both at random. */
    fun encode(
        secret: ByteArray,
        salt: ByteArray,
        nonce: ByteArray,
        iterations: Int,
        plaintext: ByteArray,
        check: (() -> Unit)? = null,
    ): ByteArray {
        require(salt.size == SALT_LENGTH && nonce.size == NONCE_LENGTH)
        require(iterations in MIN_ITERATIONS..MAX_ITERATIONS)
        val keys = deriveKeys(secret, salt, iterations, check)
        try {
            val header = ByteArray(HEADER_LENGTH)
            MAGIC.copyInto(header, 0)
            header[8] = 1
            header[9] = 1
            header[10] = (iterations ushr 24).toByte()
            header[11] = (iterations ushr 16).toByte()
            header[12] = (iterations ushr 8).toByte()
            header[13] = iterations.toByte()
            salt.copyInto(header, 14)
            nonce.copyInto(header, 30)
            keys.check.copyInto(header, 42)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(keys.encrypt, "AES"), GCMParameterSpec(TAG_LENGTH * 8, nonce))
            cipher.updateAAD(header)
            // The cipher returns the ciphertext followed by the 16-byte tag, which is the file's layout.
            return header + cipher.doFinal(plaintext)
        } finally {
            keys.wipe()
        }
    }

    /** A new export file: fresh random salt and nonce, 600,000 iterations. */
    fun seal(secret: ByteArray, plaintext: ByteArray, random: SecureRandom = SecureRandom(), check: (() -> Unit)? = null): ByteArray {
        val salt = ByteArray(SALT_LENGTH).also(random::nextBytes)
        val nonce = ByteArray(NONCE_LENGTH).also(random::nextBytes)
        return encode(secret, salt, nonce, DEFAULT_ITERATIONS, plaintext, check)
    }

    /**
     * Checks 1 to 3 of §5, which need no secret, and returns the iteration count. Import runs this as
     * soon as a file is chosen, so a file that is not an export is refused before a code is asked for.
     */
    fun checkHeader(file: ByteArray): Int {
        if (file.size < HEADER_LENGTH + TAG_LENGTH) throw ExportException(ExportException.Kind.NOT_EXPORT)
        for (i in MAGIC.indices) if (file[i] != MAGIC[i]) throw ExportException(ExportException.Kind.NOT_EXPORT)
        if (file[8].toInt() != 1 || file[9].toInt() != 1) throw ExportException(ExportException.Kind.UPDATE)
        val iterations = ((file[10].toLong() and 0xFF) shl 24) or ((file[11].toLong() and 0xFF) shl 16) or
            ((file[12].toLong() and 0xFF) shl 8) or (file[13].toLong() and 0xFF)
        if (iterations < MIN_ITERATIONS || iterations > MAX_ITERATIONS) throw ExportException(ExportException.Kind.DAMAGED)
        return iterations.toInt()
    }

    /**
     * Checks 1 to 5 of §5, in that order, and returns the decrypted bytes. The iteration count is
     * checked before any derivation so a hostile file cannot keep the phone busy.
     */
    fun open(file: ByteArray, typed: String, check: (() -> Unit)? = null): ByteArray {
        val iterations = checkHeader(file)
        val secret = ExportSecret.secretBytes(typed).bytes
        val keys = deriveKeys(secret, file.copyOfRange(14, 30), iterations, check)
        secret.fill(0)
        try {
            // MessageDigest.isEqual takes the same time whatever the bytes are.
            if (!MessageDigest.isEqual(keys.check, file.copyOfRange(42, 58))) throw ExportException(ExportException.Kind.WRONG_CODE)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(keys.encrypt, "AES"), GCMParameterSpec(TAG_LENGTH * 8, file, 30, NONCE_LENGTH))
            cipher.updateAAD(file, 0, HEADER_LENGTH)
            return cipher.doFinal(file, HEADER_LENGTH, file.size - HEADER_LENGTH)
        } catch (e: GeneralSecurityException) {
            throw ExportException(ExportException.Kind.DAMAGED)
        } finally {
            keys.wipe()
        }
    }
}
