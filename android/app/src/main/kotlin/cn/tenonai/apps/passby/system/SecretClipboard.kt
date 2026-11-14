package cn.tenonai.apps.passby.system

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PersistableBundle
import android.os.SystemClock
import cn.tenonai.apps.passby.PassByApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Copies a password or account so that the system treats it as sensitive, and clears it 60 seconds later.
 *
 * Clearing has two triggers. A timer in the app runs while the process is alive. An alarm is the
 * fallback when the system has stopped the process; it needs no permission because it is inexact.
 */
class SecretClipboard(private val context: Context) {
    private val manager = context.getSystemService(ClipboardManager::class.java)
    private val alarms = context.getSystemService(AlarmManager::class.java)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private var timer: Job? = null

    /** When the clip this app last put on the clipboard was set, as the clipboard reports it. */
    private var ownTimestamp: Long? = null

    fun copy(text: String) {
        val clip = ClipData.newPlainText(LABEL, text)
        // Android 13 and later hide a sensitive clip in the system's copy preview. Older versions ignore the flag.
        clip.description.extras = PersistableBundle().apply { putBoolean(EXTRA_IS_SENSITIVE, true) }
        manager.setPrimaryClip(clip)
        ownTimestamp = manager.primaryClipDescription?.timestamp

        timer?.cancel()
        timer = scope.launch {
            delay(CLEAR_AFTER_MS)
            clear(force = false)
        }
        alarms.set(AlarmManager.ELAPSED_REALTIME, SystemClock.elapsedRealtime() + CLEAR_AFTER_MS, alarmIntent())
    }

    /**
     * Clears the clipboard. With [force] false it is left alone when the app can see that something
     * else has been copied since. The app can only see that while it is on screen; in the background
     * the clipboard cannot be inspected, so it is cleared.
     */
    fun clear(force: Boolean) {
        timer?.cancel()
        timer = null
        alarms.cancel(alarmIntent())
        val own = ownTimestamp
        ownTimestamp = null
        if (!force && own != null) {
            // Reading the description does not read the contents and does not show the system's paste notice.
            val description = manager.primaryClipDescription
            if (description != null && description.timestamp != own) return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            manager.clearPrimaryClip()
        } else {
            manager.setPrimaryClip(ClipData.newPlainText("", ""))
        }
    }

    /** True while a copy made here is still waiting to be cleared. */
    val isPending: Boolean get() = ownTimestamp != null

    private fun alarmIntent(): PendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        Intent(context, ClipboardClearReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

    companion object {
        const val CLEAR_AFTER_MS = 60_000L
        private const val LABEL = "PassBy"

        // ClipDescription.EXTRA_IS_SENSITIVE, which only has a constant from API 33.
        private const val EXTRA_IS_SENSITIVE = "android.content.extra.IS_SENSITIVE"
    }
}

/**
 * Runs when the alarm fires. If the app's own timer already cleared the clipboard, the alarm was
 * cancelled and this does not run. If the process was restarted for this, nothing is known about the
 * clipboard any more, so it is cleared.
 */
class ClipboardClearReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val clipboard = (context.applicationContext as PassByApp).clipboard
        clipboard.clear(force = !clipboard.isPending)
    }
}
