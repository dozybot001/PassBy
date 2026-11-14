package cn.tenonai.apps.passby.core

/**
 * Bringing an export file into the notebook on this phone (docs/local-notebook.md §6).
 *
 * Nothing here removes an entry for good: merging only adds, and replacing moves what it
 * replaces to Recently Deleted, where it stays for 30 days.
 */
object ImportMerge {
    class Result(
        val notebook: Notebook,
        /** Entries from the file that are now in the notebook. */
        val added: Int,
        /** Entries from the file that were already here with the same contents. */
        val unchanged: Int,
        /** Entries from the file that differed from the one here and were added beside it, marked as imported. */
        val keptBoth: Int,
        /** Entries that were here and went to Recently Deleted. Only replacing does this. */
        val movedToDeleted: Int,
    )

    /**
     * Merge, the default. An entry is the same entry when its identifier matches.
     * - Same entry, same contents: skipped.
     * - Same entry, different contents: both stay. The one here is untouched; the one from the file
     *   gets a new identifier and [importedSuffix] after its title.
     * - Not here yet: added.
     * A folder from the file is the folder here with the same identifier, else the one with the same
     * name, else it is added.
     */
    fun merge(local: Notebook, incoming: ExportedNotebook, importedSuffix: String, now: Long, freshId: () -> String = ::newId): Result {
        val folders = local.folders.toMutableList()
        val folderFor = HashMap<String, String>()
        for (folder in incoming.folders) {
            val match = folders.firstOrNull { it.id == folder.id } ?: folders.firstOrNull { it.name == folder.name }
            if (match != null) {
                folderFor[folder.id] = match.id
            } else {
                folders.add(folder)
                folderFor[folder.id] = folder.id
            }
        }

        val entries = local.entries.toMutableList()
        val existing = local.entries.associateBy { it.id }
        var added = 0
        var unchanged = 0
        var keptBoth = 0
        for (item in incoming.entries) {
            val entry = item.copy(folderId = item.folderId?.let { folderFor[it] })
            val here = existing[entry.id]
            when {
                here == null -> {
                    entries.add(entry)
                    added++
                }
                here.sameContent(entry) -> unchanged++
                else -> {
                    entries.add(entry.copy(id = freshId(), title = entry.title + importedSuffix))
                    keptBoth++
                }
            }
        }
        val changed = added + keptBoth > 0 || folders.size != local.folders.size
        val notebook = if (changed) local.copy(folders = folders, entries = entries, changedAt = now) else local
        return Result(notebook, added + keptBoth, unchanged, keptBoth, 0)
    }

    /**
     * Replace: the notebook becomes what the file holds. Every entry that was here and is not in the
     * file with the same identifier and contents goes to Recently Deleted.
     */
    fun replace(local: Notebook, incoming: ExportedNotebook, now: Long, freshId: () -> String = ::newId): Result {
        val arriving = incoming.entries.associateBy { it.id }
        val deleted = local.deleted.toMutableList()
        var moved = 0
        var unchanged = 0
        for (entry in local.entries) {
            val same = arriving[entry.id]?.let { it.sameContent(entry) } ?: false
            if (same) {
                unchanged++
            } else {
                deleted.add(Notebook.deletedCopy(entry, now, deleted, freshId))
                moved++
            }
        }
        val notebook = local.copy(
            folders = incoming.folders,
            entries = incoming.entries,
            deleted = deleted,
            draft = local.draft?.let { draft -> if (incoming.folders.none { it.id == draft.folderId }) draft.copy(folderId = null) else draft },
            changedAt = now,
        )
        return Result(notebook, incoming.entries.size - unchanged, unchanged, 0, moved)
    }
}
