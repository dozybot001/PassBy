package cn.tenonai.apps.passby.data

import cn.tenonai.apps.passby.core.Notebook
import cn.tenonai.apps.passby.core.NotebookStore
import java.io.IOException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

sealed interface NotebookState {
    data object Loading : NotebookState
    data class Ready(val notebook: Notebook) : NotebookState

    /** The files are there but cannot be read. They are left as they are. */
    data class Unreadable(val newerVersion: Boolean) : NotebookState
}

/**
 * The one place the notebook is held in memory and written from. A change shows in [state] only
 * after it is on disk, so the screen never shows something that was not saved.
 */
class NotebookRepository(
    private val store: NotebookStore,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val mutex = Mutex()
    private val mutableState = MutableStateFlow<NotebookState>(NotebookState.Loading)
    val state: StateFlow<NotebookState> = mutableState

    /** Set when the current file could not be read and the previous version was used instead. */
    val restoredFromPrevious = MutableStateFlow(false)

    suspend fun load() = mutex.withLock {
        if (mutableState.value != NotebookState.Loading) return@withLock
        mutableState.value = withContext(Dispatchers.IO) {
            when (val opened = store.open()) {
                is NotebookStore.Opened.Unreadable -> NotebookState.Unreadable(opened.newerVersion)
                is NotebookStore.Opened.Ready -> {
                    if (opened.restored) restoredFromPrevious.value = true
                    // Entries the person deleted more than 30 days ago leave Recently Deleted here.
                    val current = opened.notebook.withoutExpired(clock())
                    if (current !== opened.notebook) {
                        try {
                            store.saveWithoutEarlierVersion(current)
                        } catch (e: IOException) {
                            // Nothing is lost; they are dropped again next time.
                        }
                    }
                    NotebookState.Ready(current)
                }
            }
        }
    }

    /**
     * Applies [change] to the notebook and writes the result. Returns false and leaves the notebook
     * as it was when it cannot be written or is not open.
     */
    suspend fun update(change: (notebook: Notebook, now: Long) -> Notebook): Boolean =
        commit { notebook, now -> change(notebook, now).marked(notebook, now) }

    /**
     * Writes the outcome of a sync. [change] returns the notebook with the merged state taken in
     * ([Notebook.synced]), or null to leave everything as it is; the result is not stamped as a change
     * made on this phone.
     */
    suspend fun sync(change: (notebook: Notebook, now: Long) -> Notebook?): Boolean =
        commit { notebook, now -> change(notebook, now) ?: notebook }

    private suspend fun commit(change: (notebook: Notebook, now: Long) -> Notebook): Boolean = mutex.withLock {
        val current = (mutableState.value as? NotebookState.Ready)?.notebook ?: return@withLock false
        val next = change(current, clock())
        if (next == current) return@withLock true
        try {
            // Entries removed from Recently Deleted for good are not left in the earlier version either.
            val removed = current.deleted.any { old -> next.deleted.none { it.entry.id == old.entry.id } && next.entries.none { it.id == old.entry.id } }
            withContext(Dispatchers.IO) { if (removed) store.saveWithoutEarlierVersion(next) else store.save(next) }
        } catch (e: IOException) {
            return@withLock false
        }
        mutableState.value = NotebookState.Ready(next)
        true
    }

    /**
     * Starts an empty notebook when the files cannot be read. The unreadable files are renamed and
     * kept. Only called when the person chooses it.
     */
    suspend fun startOver(): Boolean = mutex.withLock {
        if (mutableState.value !is NotebookState.Unreadable) return@withLock false
        try {
            withContext(Dispatchers.IO) { store.setUnreadableAside() }
        } catch (e: IOException) {
            return@withLock false
        }
        mutableState.value = NotebookState.Ready(Notebook())
        true
    }
}
