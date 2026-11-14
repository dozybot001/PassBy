package cn.tenonai.apps.passby

import android.app.Application
import cn.tenonai.apps.passby.core.NotebookStore
import cn.tenonai.apps.passby.data.NotebookRepository
import cn.tenonai.apps.passby.system.SecretClipboard
import java.io.File

class PassByApp : Application() {
    /** The notebook lives in the app's private files directory; the backup rules name this path. */
    val repository: NotebookRepository by lazy { NotebookRepository(NotebookStore(File(filesDir, "notebook"))) }

    val clipboard: SecretClipboard by lazy { SecretClipboard(this) }
}
