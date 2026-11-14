package cn.tenonai.apps.passby.system

import android.content.Context
import java.io.File
import java.io.IOException

/**
 * Sharing an export needs the encrypted file to exist somewhere the receiving app can read it
 * through the FileProvider. That copy lives in the app's cache, in the one directory the provider
 * exposes, and does not stay there: an earlier copy is removed before a new one is written, and any
 * copy older than fifteen minutes is removed whenever the app comes to the front.
 */
object ExportCache {
    /** Matches the path in res/xml/export_paths.xml. */
    private const val DIRECTORY = "exports"
    private const val KEEP_MS = 15 * 60 * 1000L

    private fun directory(context: Context) = File(context.cacheDir, DIRECTORY)

    fun write(context: Context, name: String, bytes: ByteArray): File {
        val directory = directory(context)
        if (!directory.isDirectory && !directory.mkdirs()) throw IOException("cannot create the exports directory")
        directory.listFiles()?.forEach { it.delete() }
        return File(directory, name).also { it.writeBytes(bytes) }
    }

    fun removeOld(context: Context, now: Long = System.currentTimeMillis()) {
        directory(context).listFiles()?.forEach { if (now - it.lastModified() > KEEP_MS) it.delete() }
    }
}
