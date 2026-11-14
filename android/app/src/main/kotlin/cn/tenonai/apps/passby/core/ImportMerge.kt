package cn.tenonai.apps.passby.core

import java.text.Normalizer

/**
 * Bringing an export file into the notebook on this phone, by the rules iPhone follows too
 * (docs/export-format.md §7).
 *
 * Nothing here removes an entry for good: merging only adds, and replacing moves what was here to
 * Recently Deleted, where it stays for 30 days.
 */
object ImportMerge {
    class Result(
        val notebook: Notebook,
        /** Entries from the file added as they are. */
        val added: Int,
        /** Entries from the file that were already here with the same contents. */
        val skipped: Int,
        /** Entries from the file that differed from the one here and were added beside it with the mark. */
        val marked: Int,
        /** Entries that were here and went to Recently Deleted. Only replacing does this. */
        val movedToDeleted: Int,
    )

    private fun nfc(text: String) = Normalizer.normalize(text, Normalizer.Form.NFC)

    /**
     * Merge, the default.
     *
     * Folders: the folder here with the same identifier is the same folder and keeps its name; failing
     * that, a folder here with the same name (after NFC) takes the file's entries; otherwise the folder
     * is added.
     *
     * Entries, compared only with the entries here and not with Recently Deleted:
     * - same identifier and the same title, account, password, notes and folder: skipped;
     * - same identifier, something differs: the one here is untouched, the one from the file gets a
     *   new identifier and [importedMark] after its title;
     * - not here: added as it is, with a new identifier if Recently Deleted already uses its own.
     *
     * Recently Deleted and the draft are left alone.
     */
    fun merge(local: Notebook, incoming: ExportedNotebook, importedMark: String, now: Long, freshId: () -> String = ::newId): Result {
        val folders = local.folders.toMutableList()
        val folderFor = HashMap<String, String>()
        for (folder in incoming.folders) {
            val match = local.folders.firstOrNull { it.id == folder.id }
                ?: local.folders.firstOrNull { nfc(it.name) == nfc(folder.name) }
            if (match != null) {
                folderFor[folder.id] = match.id
            } else {
                folders.add(folder)
                folderFor[folder.id] = folder.id
            }
        }

        val entries = local.entries.toMutableList()
        val here = local.entries.associateBy { it.id }
        val deletedIds = local.deleted.mapTo(HashSet()) { it.entry.id }
        var added = 0
        var skipped = 0
        var marked = 0
        for (item in incoming.entries) {
            val entry = item.copy(folderId = item.folderId?.let { folderFor[it] })
            val existing = here[entry.id]
            when {
                existing == null -> {
                    entries.add(if (entry.id in deletedIds) entry.copy(id = freshId()) else entry)
                    added++
                }
                existing.sameContent(entry) -> skipped++
                else -> {
                    entries.add(entry.copy(id = freshId(), title = entry.title + importedMark))
                    marked++
                }
            }
        }
        val changed = added + marked > 0 || folders.size != local.folders.size
        val notebook = if (changed) local.copy(folders = folders, entries = entries, changedAt = now) else local
        return Result(notebook, added, skipped, marked, 0)
    }

    /**
     * Replace: folders and entries become the file's. Every entry that was here goes to Recently
     * Deleted without its folder.
     */
    fun replace(local: Notebook, incoming: ExportedNotebook, now: Long, freshId: () -> String = ::newId): Result {
        val deleted = local.deleted.toMutableList()
        for (entry in local.entries) deleted.add(Notebook.deletedCopy(entry.copy(folderId = null), now, deleted, freshId))
        val notebook = local.copy(
            folders = incoming.folders,
            entries = incoming.entries,
            deleted = deleted,
            // The draft is kept; it only loses a folder that no longer exists.
            draft = local.draft?.let { draft -> if (incoming.folders.none { it.id == draft.folderId }) draft.copy(folderId = null) else draft },
            changedAt = now,
        )
        return Result(notebook, incoming.entries.size, 0, 0, local.entries.size)
    }
}
