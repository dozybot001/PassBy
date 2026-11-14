package cn.tenonai.apps.passby.ui

import android.app.Application
import android.os.SystemClock
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.fragment.app.FragmentActivity
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import cn.tenonai.apps.passby.PassByApp
import cn.tenonai.apps.passby.R
import cn.tenonai.apps.passby.core.Entry
import cn.tenonai.apps.passby.core.ExportException
import cn.tenonai.apps.passby.core.ExportFile
import cn.tenonai.apps.passby.core.ExportPlaintext
import cn.tenonai.apps.passby.core.ExportedNotebook
import cn.tenonai.apps.passby.core.Folder
import cn.tenonai.apps.passby.core.ImportMerge
import cn.tenonai.apps.passby.core.Notebook
import cn.tenonai.apps.passby.core.newId
import cn.tenonai.apps.passby.data.NotebookState
import cn.tenonai.apps.passby.system.Gate
import java.time.Instant
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

sealed interface Screen {
    data object Library : Screen
    data class Detail(val id: String) : Screen
    data object Editor : Screen

    /** [forEditor] true: the chosen password goes into the entry being edited. False: it is only copied. */
    data class Generator(val forEditor: Boolean) : Screen
    data object Folders : Screen
    data object Deleted : Screen
    data object Settings : Screen
    data object About : Screen
    data object Export : Screen
    data object Import : Screen
}

/** A short notice at the bottom of the screen, with at most one action. */
class Notice(val text: String, val actionLabel: String? = null, val action: (() -> Unit)? = null)

/**
 * What is on screen and what the person is doing, kept outside the composition so that it survives
 * rotation and the lock screen. While locked, none of the notebook is composed.
 */
class AppViewModel(application: Application) : AndroidViewModel(application) {
    private val app = application as PassByApp
    private val repository = app.repository

    val state: StateFlow<NotebookState> = repository.state
    val restoredFromPrevious = repository.restoredFromPrevious
    val notices = MutableSharedFlow<Notice>(extraBufferCapacity = 8)

    /** The pages opened on top of the list, oldest first. The list itself is always underneath. */
    val stack = mutableStateListOf<Screen>(Screen.Library)

    /** True from a cold start, and again after five minutes away, until the person is verified. */
    var locked by mutableStateOf(true)
        private set
    var deviceHasLock by mutableStateOf(true)
        private set
    private var leftAt: Long? = null
    private var verifying = false

    /** What the list shows: "" for everything, [UNFILED] for entries without a folder, or a folder's identifier. */
    var filter by mutableStateOf("")
    var searching by mutableStateOf(false)
    var query by mutableStateOf("")

    /** The entry in the editor, and whether it is not in the notebook yet. */
    var editing by mutableStateOf<Entry?>(null)
        private set
    var editingIsNew by mutableStateOf(false)
        private set
    private var draftJob: Job? = null

    init {
        viewModelScope.launch { repository.load() }
    }

    private fun string(id: Int, vararg arguments: Any): String = app.getString(id, *arguments)

    private fun notebook(): Notebook? = (state.value as? NotebookState.Ready)?.notebook

    private fun change(onFailure: Int = R.string.save_failed, then: () -> Unit = {}, change: (Notebook, Long) -> Notebook) {
        viewModelScope.launch {
            if (repository.update(change)) then() else notices.tryEmit(Notice(string(onFailure)))
        }
    }

    // ---- The door ----

    fun onForeground(deviceHasLock: Boolean) {
        this.deviceHasLock = deviceHasLock
        val away = leftAt?.let { SystemClock.elapsedRealtime() - it }
        leftAt = null
        if (away != null && away >= Gate.AWAY_LIMIT_MS) locked = true
    }

    fun onBackground() {
        leftAt = SystemClock.elapsedRealtime()
        flushDraft()
    }

    /** Asks the system to verify the person. Does nothing if a prompt is already showing. */
    fun unlock(activity: FragmentActivity) {
        if (verifying) return
        verifying = true
        Gate.authenticate(activity, string(R.string.lock_prompt_title), string(R.string.lock_prompt_subtitle)) { verified ->
            verifying = false
            if (verified) locked = false
        }
    }

    /** Called when the notebook is shown without the door: it is switched off, or the phone has no lock. */
    fun enteredWithoutDoor() {
        locked = false
    }

    /** Turning the door off takes a verification first. Turning it on does not. */
    fun setGate(enabled: Boolean, activity: FragmentActivity) {
        if (enabled) {
            change { notebook, _ -> notebook.copy(gateEnabled = true) }
            return
        }
        if (verifying) return
        verifying = true
        Gate.authenticate(activity, string(R.string.lock_confirm_off_title), null) { verified ->
            verifying = false
            if (verified) change { notebook, _ -> notebook.copy(gateEnabled = false) }
        }
    }

    fun noLockNoticeShown() = change { notebook, _ -> notebook.copy(noLockNoticeShown = true) }

    // ---- Moving between pages ----

    fun open(screen: Screen) {
        stack.add(screen)
    }

    /**
     * Returns false when only the list is left, so the system can close the app. Leaving the editor
     * this way keeps what was typed as the draft; only its Cancel button discards it.
     */
    fun back(): Boolean {
        if (stack.size <= 1) return false
        if (stack.last() == Screen.Editor) {
            flushDraft()
            editing = null
        }
        stack.removeAt(stack.lastIndex)
        return true
    }

    private fun close(screen: Screen) {
        val index = stack.lastIndexOf(screen)
        if (index > 0) stack.removeAt(index)
    }

    // ---- Copying ----

    fun copyPassword(entry: Entry, offerView: Boolean = false) {
        if (entry.password.isEmpty()) {
            open(Screen.Detail(entry.id))
            return
        }
        app.clipboard.copy(entry.password)
        val notice = if (offerView) {
            Notice(string(R.string.copied_password), string(R.string.view)) { open(Screen.Detail(entry.id)) }
        } else {
            Notice(string(R.string.copied_password))
        }
        notices.tryEmit(notice)
    }

    fun copyAccount(entry: Entry) {
        if (entry.account.isEmpty()) return
        app.clipboard.copy(entry.account)
        notices.tryEmit(Notice(string(R.string.copied_account)))
    }

    fun copyGenerated(password: String) {
        app.clipboard.copy(password)
        notices.tryEmit(Notice(string(R.string.copied_password)))
    }

    /** Puts a generated password into the entry being edited and copies it, as iPhone does. */
    fun useGenerated(password: String) {
        editing?.let { updateEditing(it.copy(password = password)) }
        copyGenerated(password)
    }

    // ---- Entries ----

    /** Opens the editor on a new entry, or on what was being written when the app was last left. */
    fun newEntry(folderId: String?) {
        val notebook = notebook() ?: return
        val draft = notebook.draft
        editing = draft ?: Entry(id = newId(), folderId = folderId)
        editingIsNew = draft == null || notebook.entries.none { it.id == draft.id }
        open(Screen.Editor)
    }

    fun editEntry(entry: Entry) {
        val draft = notebook()?.draft
        editing = if (draft?.id == entry.id) draft else entry
        editingIsNew = false
        open(Screen.Editor)
    }

    /** Every change in the editor is kept as a draft shortly after, so switching apps does not lose it. */
    fun updateEditing(entry: Entry) {
        editing = entry
        draftJob?.cancel()
        draftJob = viewModelScope.launch {
            delay(DRAFT_DELAY_MS)
            repository.update { notebook, _ -> notebook.copy(draft = entry) }
        }
    }

    private fun flushDraft() {
        val entry = editing ?: return
        if (draftJob?.isActive != true) return
        draftJob?.cancel()
        viewModelScope.launch { repository.update { notebook, _ -> notebook.copy(draft = entry) } }
    }

    fun saveEditing() {
        val entry = editing ?: return
        if (entry.title.isBlank()) return
        draftJob?.cancel()
        change(then = {
            editing = null
            close(Screen.Editor)
        }) { notebook, now -> notebook.save(entry, now).copy(draft = null) }
    }

    fun cancelEditing() {
        draftJob?.cancel()
        editing = null
        close(Screen.Editor)
        change { notebook, _ -> notebook.copy(draft = null) }
    }

    fun deleteEntry(id: String) {
        change(then = {
            close(Screen.Detail(id))
            notices.tryEmit(Notice(string(R.string.password_removed)))
        }) { notebook, now -> notebook.delete(id, now) }
    }

    fun restoreDeleted(id: String) = change { notebook, now -> notebook.restore(id, now) }

    /** Removes one entry from Recently Deleted for good. The page asks the person to confirm first. */
    fun removeDeleted(id: String) = change { notebook, _ -> notebook.removeDeleted(id) }

    // ---- Folders ----

    /** Adds a folder and hands back its identifier once it is saved. */
    fun addFolder(name: String, then: (String) -> Unit = {}) {
        val folder = Folder(newId(), name)
        change(then = { then(folder.id) }) { notebook, now -> notebook.addFolder(folder, now) }
    }

    fun renameFolder(id: String, name: String) = change { notebook, now -> notebook.renameFolder(id, name, now) }

    fun removeFolder(id: String) = change { notebook, now -> notebook.removeFolder(id, now) }

    // ---- Export and import ----

    fun dismissExportReminder() = change { notebook, now -> notebook.copy(reminderDismissedAt = now) }

    /**
     * Encrypts everything except Recently Deleted and the draft. Slow on purpose: the key derivation
     * runs 600,000 rounds. Returns null when there is nothing open to export.
     */
    suspend fun buildExport(secret: ByteArray): ByteArray? {
        val notebook = notebook() ?: return null
        return withContext(Dispatchers.Default) {
            val plaintext = ExportPlaintext.serialize(notebook.folders, notebook.entries, Instant.now())
            ExportFile.seal(secret, plaintext, check = { coroutineContext.ensureActive() })
        }
    }

    /** Records the export once the file has left the app. */
    fun exported() = change { notebook, now -> notebook.exported(now) }

    /** Opens an export file. Throws ExportException with the reason when it cannot. */
    @Throws(ExportException::class)
    suspend fun openImport(file: ByteArray, typed: String): ExportedNotebook = withContext(Dispatchers.Default) {
        ExportPlaintext.parse(ExportFile.open(file, typed, check = { coroutineContext.ensureActive() }))
    }

    /** Merges the file in, or replaces the notebook with it. Returns what happened, or null if it could not be saved. */
    suspend fun applyImport(incoming: ExportedNotebook, replace: Boolean): ImportMerge.Result? {
        var result: ImportMerge.Result? = null
        val mark = string(R.string.imported_mark)
        val saved = repository.update { notebook, now ->
            val outcome = if (replace) ImportMerge.replace(notebook, incoming, now) else ImportMerge.merge(notebook, incoming, mark, now)
            result = outcome
            outcome.notebook
        }
        return if (saved) result else null
    }

    fun startOver() {
        viewModelScope.launch {
            if (!repository.startOver()) notices.tryEmit(Notice(string(R.string.save_failed)))
        }
    }

    fun restoredNoticeSeen() {
        restoredFromPrevious.value = false
    }

    companion object {
        const val UNFILED = "unfiled"
        private const val DRAFT_DELAY_MS = 400L
    }
}
