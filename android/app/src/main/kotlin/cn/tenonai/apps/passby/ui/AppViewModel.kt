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
import cn.tenonai.apps.passby.core.AiGrouping
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
import cn.tenonai.apps.passby.system.AiClient
import cn.tenonai.apps.passby.system.AiSettings
import cn.tenonai.apps.passby.system.ExportCache
import cn.tenonai.apps.passby.system.Gate
import java.io.IOException
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
    data object Licenses : Screen
    data object Export : Screen
    data object Import : Screen

    /** Turning AI grouping on and off, and where it sends. */
    data object Ai : Screen

    /** What is about to be sent, shown before anything is sent. */
    data object AiPreview : Screen

    /** The model's suggestions, to tick and apply. */
    data object AiResult : Screen
}

/** One request as shown on the preview page: the body, and which entry each numbered title belongs to. */
class AiDraft(val body: String, val titles: List<String>, val folders: List<String>, val entryIds: List<String>, val blankIds: List<String>, val leftOut: Int)

/** One entry the model has a suggestion for. [title] and [folder] are null where nothing would change. */
class AiRow(val entryId: String, val oldTitle: String, val title: String?, val oldFolder: String?, val folder: String?, val unclear: Boolean)

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

    /** Null while AI grouping is off. */
    var aiConfig by mutableStateOf(app.aiSettings.load())
        private set
    var aiHasKey by mutableStateOf(app.aiSettings.hasKey)
        private set
    var aiDraft by mutableStateOf<AiDraft?>(null)
        private set
    var aiRows by mutableStateOf<List<AiRow>>(emptyList())
        private set
    var aiWorking by mutableStateOf(false)
        private set
    var aiError by mutableStateOf<String?>(null)
        private set

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
        viewModelScope.launch(Dispatchers.IO) { ExportCache.removeOld(app) }
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

    fun copyExportCode(code: String) {
        app.clipboard.copy(code)
        notices.tryEmit(Notice(string(R.string.copied_export_code)))
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

    // ---- AI grouping ----

    /** Turns AI grouping on with the given address and model, or changes them. A key for another host is removed. */
    fun aiSave(config: AiSettings.Config): Boolean = try {
        app.aiSettings.save(config)
        aiConfig = config
        aiHasKey = app.aiSettings.hasKey
        true
    } catch (e: IOException) {
        notices.tryEmit(Notice(string(R.string.save_failed)))
        false
    }

    /** Turns AI grouping off and removes the API key and settings from this phone. */
    fun aiTurnOff() {
        app.aiSettings.turnOff()
        aiConfig = null
        aiHasKey = false
        aiDraft = null
        aiRows = emptyList()
        aiError = null
    }

    fun aiSaveKey(apiKey: String): Boolean {
        val host = aiConfig?.let { AiGrouping.endpoint(it.endpoint) }?.host ?: return false
        return try {
            app.aiSettings.saveKey(apiKey.trim(), host)
            aiHasKey = true
            true
        } catch (e: Exception) {
            notices.tryEmit(Notice(string(R.string.save_failed)))
            false
        }
    }

    fun aiRemoveKey() {
        app.aiSettings.removeKey()
        aiHasKey = false
    }

    /**
     * Builds the request from titles and folder names and opens the page that shows it. Nothing is
     * sent here. Entries without a title are not sent; they go to the folder for unclear titles.
     */
    fun aiPrepare() {
        val notebook = notebook() ?: return
        val config = aiConfig ?: return
        val titled = notebook.entries.filter { it.title.isNotBlank() }
        val sent = titled.take(AiGrouping.MAX_TITLES)
        val titles = sent.map { it.title }
        val folders = notebook.folders.map { it.name }
        aiDraft = AiDraft(
            body = AiGrouping.request(titles, folders, config.model),
            titles = titles,
            folders = folders,
            entryIds = sent.map { it.id },
            blankIds = notebook.entries.filter { it.title.isBlank() }.map { it.id },
            leftOut = titled.size - sent.size,
        )
        aiError = null
        open(Screen.AiPreview)
    }

    /** Sends the request the preview page is showing, as it is shown, and opens the suggestions. */
    fun aiSend() {
        val draft = aiDraft ?: return
        if (aiWorking) return
        aiWorking = true
        aiError = null
        viewModelScope.launch {
            try {
                val response = withContext(Dispatchers.IO) { AiClient.send(app.aiSettings, AiClient.Approved(draft.body)) }
                val suggestions = withContext(Dispatchers.Default) { AiGrouping.parse(response, draft.titles.size) }
                aiRows = rows(draft, suggestions)
                close(Screen.AiPreview)
                open(Screen.AiResult)
            } catch (e: AiClient.Failure) {
                aiHasKey = app.aiSettings.hasKey
                aiError = when (e.problem) {
                    AiClient.Problem.OFF, AiClient.Problem.ADDRESS -> string(R.string.ai_error_address)
                    AiClient.Problem.NO_KEY -> string(R.string.ai_error_no_key)
                    AiClient.Problem.NETWORK -> string(R.string.ai_error_network)
                    AiClient.Problem.TIMEOUT -> string(R.string.ai_error_timeout)
                    AiClient.Problem.REDIRECT -> string(R.string.ai_error_redirect, e.status ?: 0)
                    AiClient.Problem.STATUS -> string(if (e.status == 401 || e.status == 403) R.string.ai_error_key_refused else R.string.ai_error_status, e.status ?: 0)
                    AiClient.Problem.TOO_LARGE -> string(R.string.ai_error_answer)
                }
            } catch (e: AiGrouping.UnusableAnswer) {
                aiError = string(R.string.ai_error_answer)
            }
            aiWorking = false
        }
    }

    private fun rows(draft: AiDraft, suggestions: List<AiGrouping.Suggestion>): List<AiRow> {
        val notebook = notebook() ?: return emptyList()
        val byId = notebook.entries.associateBy { it.id }
        val unclearName = string(R.string.ai_unclear_folder)
        val out = ArrayList<AiRow>()
        for (suggestion in suggestions) {
            val entry = byId[draft.entryIds[suggestion.index - 1]] ?: continue
            val oldFolder = notebook.folder(entry.folderId)?.name
            val folder = (if (suggestion.unclear) unclearName else suggestion.folder)?.takeIf { it != oldFolder }
            val title = (if (suggestion.unclear) null else suggestion.title)?.takeIf { it != entry.title }
            if (folder != null || title != null) out.add(AiRow(entry.id, entry.title, title, oldFolder, folder, suggestion.unclear))
        }
        for (id in draft.blankIds) {
            val entry = byId[id] ?: continue
            val oldFolder = notebook.folder(entry.folderId)?.name
            if (oldFolder != unclearName) out.add(AiRow(entry.id, entry.title, null, oldFolder, unclearName, unclear = true))
        }
        return out
    }

    /** Applies the ticked suggestions in one save. Entries are renamed and moved; none is removed. */
    fun aiApply(picked: Set<String>) {
        val changes = aiRows.filter { it.entryId in picked }.map { AiGrouping.Change(it.entryId, it.title, it.folder) }
        var applied: AiGrouping.Applied? = null
        change(then = {
            aiRows = emptyList()
            aiDraft = null
            close(Screen.AiResult)
            val done = applied
            if (done != null && done.before.isNotEmpty()) {
                notices.tryEmit(
                    Notice(string(R.string.ai_applied, done.before.size), string(R.string.undo)) {
                        change { notebook, now -> AiGrouping.undo(notebook, done, now) }
                    },
                )
            }
        }) { notebook, now -> AiGrouping.apply(notebook, changes, now).also { applied = it }.notebook }
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
