package cn.tenonai.apps.passby

import android.app.Application
import cn.tenonai.apps.passby.core.NotebookStore
import cn.tenonai.apps.passby.data.NotebookRepository
import cn.tenonai.apps.passby.system.AiSettings
import cn.tenonai.apps.passby.system.SecretClipboard
import cn.tenonai.apps.passby.system.SyncSettings
import java.io.File

class PassByApp : Application() {
    /** The notebook lives in the app's private files directory; the backup rules name this path. */
    val repository: NotebookRepository by lazy { NotebookRepository(NotebookStore(File(filesDir, "notebook"))) }

    val clipboard: SecretClipboard by lazy { SecretClipboard(this) }

    /** AI grouping's settings and API key, kept apart from the notebook and out of backups and exports. */
    val aiSettings: AiSettings by lazy { AiSettings(File(filesDir, "ai")) }

    val syncSettings: SyncSettings by lazy { SyncSettings(this) }
}
