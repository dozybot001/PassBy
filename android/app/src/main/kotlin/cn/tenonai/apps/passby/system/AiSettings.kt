package cn.tenonai.apps.passby.system

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import cn.tenonai.apps.passby.core.AiGrouping
import cn.tenonai.apps.passby.core.Json
import cn.tenonai.apps.passby.core.JsonException
import cn.tenonai.apps.passby.core.JsonObject
import cn.tenonai.apps.passby.core.JsonString
import cn.tenonai.apps.passby.core.get
import cn.tenonai.apps.passby.core.string
import java.io.File
import java.io.IOException
import java.security.GeneralSecurityException
import java.security.KeyStore
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Whether AI grouping is on, where it sends requests, and the person's API key.
 *
 * These live in their own directory, apart from the notebook: the backup rules name only the
 * notebook's files, and an export holds only entries and folders, so neither carries any of this.
 *
 * The API key is encrypted with a key that the Android Keystore holds and does not give out. It is
 * tied to the host it was saved for: a key saved for one provider is never read back for another.
 * Turning the feature off removes all of it.
 */
class AiSettings(private val directory: File) {
    data class Config(val endpoint: String, val model: String)

    private val settingsFile = File(directory, "settings.json")
    private val keyFile = File(directory, "key.bin")

    /** Null while the feature is off, which is how it starts. */
    @Synchronized
    fun load(): Config? {
        if (!settingsFile.exists()) return null
        return try {
            val root = Json.parse(settingsFile.readText())
            Config(root["endpoint"].string ?: return null, root["model"].string ?: return null)
        } catch (e: JsonException) {
            null
        } catch (e: IOException) {
            null
        }
    }

    /** Turns the feature on, or changes where it sends. A key saved for a different host is removed. */
    @Synchronized
    @Throws(IOException::class)
    fun save(config: Config) {
        val host = AiGrouping.endpoint(config.endpoint)?.host
        if (host == null || savedHost() != host) removeKey()
        if (!directory.isDirectory && !directory.mkdirs()) throw IOException("cannot create the settings directory")
        val root = JsonObject(linkedMapOf("endpoint" to JsonString(config.endpoint), "model" to JsonString(config.model)))
        settingsFile.writeText(Json.write(root))
    }

    /** Turns the feature off: the settings, the API key and the key that encrypted it all go. */
    @Synchronized
    fun turnOff() {
        removeKey()
        settingsFile.delete()
        directory.delete()
    }

    val hasKey: Boolean
        @Synchronized get() = keyFile.exists()

    private fun savedHost(): String? = try {
        if (keyFile.exists()) Json.parse(keyFile.readText())["host"].string else null
    } catch (e: JsonException) {
        null
    } catch (e: IOException) {
        null
    }

    @Synchronized
    @Throws(IOException::class, GeneralSecurityException::class)
    fun saveKey(apiKey: String, host: String) {
        if (!directory.isDirectory && !directory.mkdirs()) throw IOException("cannot create the settings directory")
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, wrappingKey(create = true))
        // The host is authenticated with the key, so the file cannot be pointed at another host.
        cipher.updateAAD(host.toByteArray(Charsets.UTF_8))
        val sealed = cipher.doFinal(apiKey.toByteArray(Charsets.UTF_8))
        val encoder = Base64.getEncoder()
        val root = JsonObject(
            linkedMapOf(
                "host" to JsonString(host),
                "iv" to JsonString(encoder.encodeToString(cipher.iv)),
                "data" to JsonString(encoder.encodeToString(sealed)),
            ),
        )
        keyFile.writeText(Json.write(root))
    }

    /**
     * The API key, if one is saved for exactly [host]. A key that cannot be read back, as after the
     * phone was restored from a backup or replaced, counts as not saved and is removed.
     */
    @Synchronized
    fun key(host: String): String? {
        if (!keyFile.exists()) return null
        return try {
            val root = Json.parse(keyFile.readText())
            if (root["host"].string != host) return null
            val decoder = Base64.getDecoder()
            val cipher = Cipher.getInstance(TRANSFORMATION)
            val wrapping = wrappingKey(create = false) ?: throw GeneralSecurityException("no wrapping key")
            cipher.init(Cipher.DECRYPT_MODE, wrapping, GCMParameterSpec(128, decoder.decode(root["iv"].string)))
            cipher.updateAAD(host.toByteArray(Charsets.UTF_8))
            String(cipher.doFinal(decoder.decode(root["data"].string)), Charsets.UTF_8)
        } catch (e: Exception) {
            // Unreadable for any reason: the person is asked to enter it again.
            removeKey()
            null
        }
    }

    @Synchronized
    fun removeKey() {
        keyFile.delete()
        try {
            KeyStore.getInstance(KEYSTORE).apply { load(null) }.deleteEntry(ALIAS)
        } catch (e: GeneralSecurityException) {
            // Without the file the Keystore key protects nothing.
        } catch (e: IOException) {
            // The same.
        }
    }

    private fun wrappingKey(create: Boolean): SecretKey? {
        val store = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        if (!create) return null
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private companion object {
        const val KEYSTORE = "AndroidKeyStore"
        const val ALIAS = "passby-ai-key"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
    }
}
