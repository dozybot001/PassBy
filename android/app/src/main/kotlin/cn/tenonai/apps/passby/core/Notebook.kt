package cn.tenonai.apps.passby.core

import java.util.Locale
import java.util.UUID

/** Identifiers are UUIDs kept in upper case, the form the export file writes. */
fun newId(): String = UUID.randomUUID().toString().uppercase(Locale.ROOT)

data class Folder(val id: String, val name: String)

data class Entry(
    val id: String,
    val title: String = "",
    val account: String = "",
    val password: String = "",
    val notes: String = "",
    val folderId: String? = null,
) {
    /** True when everything except the identifier is the same. */
    fun sameContent(other: Entry): Boolean =
        title == other.title && account == other.account && password == other.password &&
            notes == other.notes && folderId == other.folderId

    // The generated toString would print the password; keep it out of logs and crash traces.
    override fun toString(): String = "Entry($id)"
}

data class DeletedEntry(val entry: Entry, val deletedAt: Long)

/**
 * Everything the app keeps: one value, written to one file. Times are milliseconds since 1970 UTC.
 *
 * Entry identifiers are unique among [entries] and, separately, among [deleted]; the same identifier
 * may appear once in each.
 */
data class Notebook(
    val folders: List<Folder> = emptyList(),
    val entries: List<Entry> = emptyList(),
    val deleted: List<DeletedEntry> = emptyList(),
    /** An entry being written that has not been saved yet, so leaving the app does not lose it. */
    val draft: Entry? = null,
    val lastExportAt: Long? = null,
    /** When folders or entries last changed. */
    val changedAt: Long? = null,
    val reminderDismissedAt: Long? = null,
    /** Ask for a fingerprint, face or the screen lock when opening. On by default. */
    val gateEnabled: Boolean = true,
    /** The one-time notice that this phone has no screen lock has been shown. */
    val noLockNoticeShown: Boolean = false,
    /** Kept for LAN sync (docs/sync.md §4). Set by [marked] and [synced], not by the changes themselves. */
    val marks: SyncMarks = SyncMarks(),
) {
    fun folder(id: String?): Folder? = folders.firstOrNull { it.id == id }

    /** Adds the entry or replaces the one with the same identifier. A folder that no longer exists is dropped. */
    fun save(entry: Entry, now: Long): Notebook {
        val value = if (entry.folderId != null && folder(entry.folderId) == null) entry.copy(folderId = null) else entry
        val index = entries.indexOfFirst { it.id == value.id }
        val updated = if (index >= 0) entries.toMutableList().also { it[index] = value } else entries + value
        return copy(entries = updated, draft = if (draft?.id == value.id) null else draft, changedAt = now)
    }

    /** Moves the entry to Recently Deleted. */
    fun delete(id: String, now: Long, freshId: () -> String = ::newId): Notebook {
        val entry = entries.firstOrNull { it.id == id } ?: return this
        return copy(entries = entries - entry, deleted = deleted + deletedCopy(entry, now, deleted, freshId), changedAt = now)
    }

    /** Puts an entry from Recently Deleted back. It lands in Unfiled if its folder is gone. */
    fun restore(id: String, now: Long, freshId: () -> String = ::newId): Notebook {
        val item = deleted.firstOrNull { it.entry.id == id } ?: return this
        var entry = item.entry
        if (entries.any { it.id == entry.id }) entry = entry.copy(id = freshId())
        if (entry.folderId != null && folder(entry.folderId) == null) entry = entry.copy(folderId = null)
        return copy(entries = entries + entry, deleted = deleted - item, changedAt = now)
    }

    /** Removes one entry from Recently Deleted for good. Only called when the person asks for it. */
    fun removeDeleted(id: String): Notebook = copy(deleted = deleted.filterNot { it.entry.id == id })

    /** Drops entries that have been in Recently Deleted for 30 days. */
    fun withoutExpired(now: Long): Notebook {
        val kept = deleted.filter { now - it.deletedAt < DELETED_RETENTION_MS }
        return if (kept.size == deleted.size) this else copy(deleted = kept)
    }

    fun addFolder(folder: Folder, now: Long): Notebook = copy(folders = folders + folder, changedAt = now)

    fun renameFolder(id: String, name: String, now: Long): Notebook =
        copy(folders = folders.map { if (it.id == id) it.copy(name = name) else it }, changedAt = now)

    /** Removes the folder; its entries stay and become Unfiled. */
    fun removeFolder(id: String, now: Long): Notebook = copy(
        folders = folders.filterNot { it.id == id },
        entries = entries.map { if (it.folderId == id) it.copy(folderId = null) else it },
        draft = draft?.takeIf { it.folderId == id }?.copy(folderId = null) ?: draft,
        changedAt = now,
    )

    /**
     * Records what changed between [previous] and this notebook: changed and new entries and folders
     * are stamped [now] and marked as changed, and those that are gone leave a tombstone. Moving an
     * entry to Recently Deleted counts as deleting it; putting it back counts as a change.
     */
    fun marked(previous: Notebook, now: Long): Notebook {
        if (folders == previous.folders && entries == previous.entries && marks == previous.marks &&
            marks.entries.size == entries.size && marks.folders.size == folders.size
        ) {
            return this
        }
        val oldEntries = previous.entries.associateBy { it.id }
        val oldFolders = previous.folders.associateBy { it.id }
        val entryStamps = entries.associate {
            it.id to if (oldEntries[it.id] == it) marks.entries[it.id] ?: Stamp.UNKNOWN else Stamp(now, true)
        }
        val folderStamps = folders.associate {
            it.id to if (oldFolders[it.id] == it) marks.folders[it.id] ?: Stamp.UNKNOWN else Stamp(now, true)
        }
        fun live(kind: Tombstone.Kind) = if (kind == Tombstone.Kind.ENTRY) entryStamps else folderStamps
        val kept = marks.tombstones.filter { it.id !in live(it.kind) && now - it.deletedAt < SyncMarks.TOMBSTONE_RETENTION_MS }
        val gone = oldEntries.keys.filter { it !in entryStamps }.map { Tombstone(it, Tombstone.Kind.ENTRY, now, true) } +
            oldFolders.keys.filter { it !in folderStamps }.map { Tombstone(it, Tombstone.Kind.FOLDER, now, true) }
        val tombstones = kept + gone.filter { new -> kept.none { it.kind == new.kind && it.id == new.id } }
        return copy(marks = SyncMarks(entryStamps, folderStamps, tombstones))
    }

    /** This notebook as it is sent to the other device. */
    fun syncState(): SyncState = SyncState(
        entries.map { SyncEntry(it, marks.entries[it.id] ?: Stamp.UNKNOWN) },
        folders.map { SyncFolder(it, marks.folders[it.id] ?: Stamp.UNKNOWN) },
        marks.tombstones,
    )

    /**
     * Takes the merged [state] of a sync. Entries and folders keep their place in the list and new ones
     * go to the end. An entry the other device deleted moves to Recently Deleted here instead of
     * vanishing, so it can still be put back for 30 days.
     */
    fun synced(state: SyncState, now: Long, freshId: () -> String = ::newId): Notebook {
        val incomingFolders = state.folders.associateBy { it.folder.id }
        val incomingEntries = state.entries.associateBy { it.entry.id }
        val nextFolders = folders.mapNotNull { incomingFolders[it.id]?.folder } +
            state.folders.map { it.folder }.filter { new -> folders.none { it.id == new.id } }
        val nextEntries = entries.mapNotNull { incomingEntries[it.id]?.entry } +
            state.entries.map { it.entry }.filter { new -> entries.none { it.id == new.id } }
        var nextDeleted = deleted
        for (entry in entries) if (entry.id !in incomingEntries) nextDeleted = nextDeleted + deletedCopy(entry, now, nextDeleted, freshId)
        val changed = nextFolders != folders || nextEntries != entries
        return copy(
            folders = nextFolders,
            entries = nextEntries,
            deleted = nextDeleted,
            draft = draft?.let { if (it.folderId != null && it.folderId !in incomingFolders) it.copy(folderId = null) else it },
            changedAt = if (changed) now else changedAt,
            marks = SyncMarks(
                state.entries.associate { it.entry.id to it.stamp.copy(dirty = false) },
                state.folders.associate { it.folder.id to it.stamp.copy(dirty = false) },
                state.tombstones.map { it.copy(dirty = false) },
            ),
        )
    }

    fun exported(now: Long): Notebook = copy(lastExportAt = now, reminderDismissedAt = null)

    /**
     * Whether to show the export reminder: there is something to lose and it was never exported, or the
     * last export is over 30 days old and the notebook changed since. Dismissing it keeps it away for 30 days.
     */
    fun shouldRemindToExport(now: Long): Boolean {
        if (entries.isEmpty()) return false
        reminderDismissedAt?.let { if (now - it < EXPORT_REMINDER_MS) return false }
        val last = lastExportAt ?: return true
        return now - last > EXPORT_REMINDER_MS && (changedAt ?: 0) > last
    }

    companion object {
        private const val DAY_MS = 24L * 60 * 60 * 1000
        const val DELETED_RETENTION_MS = 30 * DAY_MS
        const val EXPORT_REMINDER_MS = 30 * DAY_MS

        /** A copy for Recently Deleted, given a fresh identifier if one there already uses the same. */
        internal fun deletedCopy(entry: Entry, now: Long, deleted: List<DeletedEntry>, freshId: () -> String): DeletedEntry {
            val unique = if (deleted.any { it.entry.id == entry.id }) entry.copy(id = freshId()) else entry
            return DeletedEntry(unique, now)
        }
    }
}
