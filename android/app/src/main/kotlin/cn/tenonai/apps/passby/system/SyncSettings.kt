package cn.tenonai.apps.passby.system

import android.content.Context
import java.security.SecureRandom

/**
 * The two things sync remembers on this phone: the port it listens on, so its address stays the
 * same from one time to the next, and the address last connected to. Neither is in any backup.
 */
class SyncSettings(context: Context) {
    private val preferences = context.getSharedPreferences("sync", Context.MODE_PRIVATE)

    /** Chosen at random the first time and kept. */
    fun port(): Int {
        val saved = preferences.getInt(PORT, 0)
        if (saved in FIRST_PORT..LAST_PORT) return saved
        val port = FIRST_PORT + SecureRandom().nextInt(LAST_PORT - FIRST_PORT + 1)
        preferences.edit().putInt(PORT, port).apply()
        return port
    }

    var lastAddress: String
        get() = preferences.getString(LAST_ADDRESS, "") ?: ""
        set(value) = preferences.edit().putString(LAST_ADDRESS, value).apply()

    private companion object {
        const val PORT = "port"
        const val LAST_ADDRESS = "lastAddress"
        const val FIRST_PORT = 49152
        const val LAST_PORT = 65535
    }
}
