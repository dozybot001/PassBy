package cn.tenonai.apps.passby.core

import java.time.Instant
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class NotebookTest {
    private val day = 24L * 60 * 60 * 1000
    private val work = Folder("F1", "工作")
    private val mail = Entry("E1", "邮箱", "alex@example.com", "p1", "", "F1")
    private val bank = Entry("E2", "银行", "alex", "p2", "note")
    private var counter = 0
    private val freshId: () -> String = { "NEW${++counter}" }

    @Test
    fun savingAddsThenReplacesAndDropsAMissingFolder() {
        var notebook = Notebook(folders = listOf(work)).save(mail, 10)
        assertEquals(listOf(mail), notebook.entries)
        assertEquals(10L, notebook.changedAt)
        notebook = notebook.save(mail.copy(password = "p9", folderId = "GONE"), 20)
        assertEquals(listOf(mail.copy(password = "p9", folderId = null)), notebook.entries)
    }

    @Test
    fun savingTheDraftClearsIt() {
        val notebook = Notebook(draft = bank).save(bank, 1)
        assertNull(notebook.draft)
        assertEquals(mail, Notebook(draft = mail).save(bank, 1).draft)
    }

    @Test
    fun deletingKeepsTheEntryInRecentlyDeletedAndRestoringBringsItBack() {
        val start = Notebook(folders = listOf(work), entries = listOf(mail, bank))
        val deleted = start.delete("E1", 100, freshId)
        assertEquals(listOf(bank), deleted.entries)
        assertEquals(listOf(DeletedEntry(mail, 100)), deleted.deleted)
        val restored = deleted.restore("E1", 200, freshId)
        assertEquals(listOf(bank, mail), restored.entries)
        assertTrue(restored.deleted.isEmpty())
        assertSame(start, start.delete("NOPE", 1, freshId))
    }

    @Test
    fun restoringIntoAMissingFolderOrOverATakenIdentifierStillKeepsTheEntry() {
        val notebook = Notebook(entries = listOf(mail.copy(title = "新的", folderId = null)), deleted = listOf(DeletedEntry(mail, 1)))
        val restored = notebook.restore("E1", 2, freshId)
        assertEquals(2, restored.entries.size)
        assertEquals(mail.copy(id = "NEW1", folderId = null), restored.entries.last())
    }

    @Test
    fun deletingTheSameIdentifierTwiceKeepsBothCopies() {
        val notebook = Notebook(entries = listOf(mail), deleted = listOf(DeletedEntry(mail.copy(password = "old"), 1)))
        val deleted = notebook.delete("E1", 2, freshId).deleted
        assertEquals(listOf("E1", "NEW1"), deleted.map { it.entry.id })
        assertEquals(listOf("old", "p1"), deleted.map { it.entry.password })
    }

    @Test
    fun recentlyDeletedExpiresAfterThirtyDaysAndNotBefore() {
        val notebook = Notebook(deleted = listOf(DeletedEntry(mail, 0), DeletedEntry(bank, 5 * day)))
        assertSame(notebook, notebook.withoutExpired(30 * day - 1))
        assertEquals(listOf(bank), notebook.withoutExpired(30 * day).deleted.map { it.entry })
        // A clock set back does not remove anything.
        assertSame(notebook, notebook.withoutExpired(-day))
    }

    @Test
    fun removingAFolderLeavesItsEntriesUnfiled() {
        val notebook = Notebook(folders = listOf(work), entries = listOf(mail, bank), draft = mail.copy(id = "D")).removeFolder("F1", 5)
        assertTrue(notebook.folders.isEmpty())
        assertEquals(listOf(null, null), notebook.entries.map { it.folderId })
        assertEquals(2, notebook.entries.size)
        assertNull(notebook.draft!!.folderId)
    }

    @Test
    fun exportReminder() {
        val empty = Notebook()
        assertFalse(empty.shouldRemindToExport(0))
        val never = empty.save(mail.copy(folderId = null), 0)
        assertTrue(never.shouldRemindToExport(1))
        // Dismissed: quiet for 30 days, then back.
        val dismissed = never.copy(reminderDismissedAt = 10)
        assertFalse(dismissed.shouldRemindToExport(10 + 30 * day - 1))
        assertTrue(dismissed.shouldRemindToExport(10 + 30 * day))
        // Exported and unchanged: never reminded, however long ago.
        val exported = never.exported(100)
        assertFalse(exported.shouldRemindToExport(100 + 400 * day))
        // Changed after the export: reminded once 30 days have passed since the export.
        val changed = exported.save(bank, 200)
        assertFalse(changed.shouldRemindToExport(100 + 30 * day))
        assertTrue(changed.shouldRemindToExport(100 + 30 * day + 1))
    }

    @Test
    fun entriesDoNotPrintTheirPassword() {
        assertFalse(mail.toString().contains("p1"))
        assertFalse(DeletedEntry(mail, 1).toString().contains("p1"))
        assertFalse(Notebook(entries = listOf(mail)).toString().contains("p1"))
    }

    // ---- Import (docs/export-format.md §7) ----

    private fun file(folders: List<Folder> = emptyList(), vararg entries: Entry) = ExportedNotebook(Instant.EPOCH, folders, entries.toList())

    @Test
    fun mergingIntoAnEmptyNotebookTakesEverything() {
        val result = ImportMerge.merge(Notebook(), file(listOf(work), mail, bank), "（导入）", 7, freshId)
        assertEquals(listOf(work), result.notebook.folders)
        assertEquals(listOf(mail, bank), result.notebook.entries)
        assertEquals(2, result.added)
        assertEquals(0, result.skipped)
        assertEquals(7L, result.notebook.changedAt)
    }

    @Test
    fun mergingTheSameFileAgainChangesNothing() {
        val local = Notebook(folders = listOf(work), entries = listOf(mail, bank), changedAt = 3)
        val result = ImportMerge.merge(local, file(listOf(work), mail, bank), "（导入）", 7, freshId)
        assertSame(local, result.notebook)
        assertEquals(0, result.added)
        assertEquals(2, result.skipped)
    }

    @Test
    fun mergingKeepsBothWhenTheSameEntryDiffers() {
        val local = Notebook(folders = listOf(work), entries = listOf(mail))
        val result = ImportMerge.merge(local, file(listOf(work), mail.copy(password = "older")), " (Imported)", 7, freshId)
        assertEquals(listOf(mail, mail.copy(id = "NEW1", title = "邮箱 (Imported)", password = "older")), result.notebook.entries)
        assertEquals(1, result.marked)
        assertEquals(0, result.added)
        assertEquals(0, result.skipped)
    }

    @Test
    fun mergingMatchesFoldersByIdentifierThenByName() {
        val local = Notebook(folders = listOf(work), entries = listOf(mail))
        val sameIdOtherName = Folder("F1", "Work")
        val sameNameOtherId = Folder("F9", "工作")
        val brandNew = Folder("F3", "家")
        val result = ImportMerge.merge(
            local,
            file(listOf(sameIdOtherName, sameNameOtherId, brandNew), mail.copy(folderId = "F9"), bank.copy(folderId = "F3")),
            "（导入）", 7, freshId,
        )
        // The local name wins; the folder with the same name is not added twice.
        assertEquals(listOf(work, brandNew), result.notebook.folders)
        // The entry that pointed at F9 points at the local folder, so it is the same as the one here.
        assertEquals(listOf(mail, bank.copy(folderId = "F3")), result.notebook.entries)
        assertEquals(1, result.skipped)
        assertEquals(1, result.added)
    }

    @Test
    fun folderNamesAreComparedAfterNfc() {
        val local = Notebook(folders = listOf(Folder("F1", "Caf\u00E9")))
        val result = ImportMerge.merge(local, file(listOf(Folder("F2", "Cafe\u0301")), bank.copy(folderId = "F2")), "（导入）", 7, freshId)
        assertEquals(local.folders, result.notebook.folders)
        assertEquals("F1", result.notebook.entries.single().folderId)
    }

    @Test
    fun twoFoldersInTheFileWithTheSameNameAreBothAdded() {
        val result = ImportMerge.merge(Notebook(), file(listOf(Folder("F2", "家"), Folder("F3", "家"))), "（导入）", 7, freshId)
        assertEquals(listOf("F2", "F3"), result.notebook.folders.map { it.id })
    }

    @Test
    fun anIdentifierUsedInRecentlyDeletedIsChangedWithoutAMark() {
        val local = Notebook(deleted = listOf(DeletedEntry(mail.copy(folderId = null), 1)))
        val result = ImportMerge.merge(local, file(emptyList(), mail.copy(folderId = null, password = "from file")), "（导入）", 7, freshId)
        assertEquals(listOf(mail.copy(id = "NEW1", folderId = null, password = "from file")), result.notebook.entries)
        assertEquals(local.deleted, result.notebook.deleted)
        assertEquals(1, result.added)
        assertEquals(0, result.marked)
    }

    @Test
    fun mergingNeverRemovesOrAltersWhatIsHere() {
        val local = Notebook(folders = listOf(work), entries = listOf(mail, bank), deleted = listOf(DeletedEntry(bank, 1)), draft = mail.copy(id = "D"))
        val result = ImportMerge.merge(local, file(emptyList(), Entry("E3", "新")), "（导入）", 7, freshId)
        assertEquals(local.entries, result.notebook.entries.take(2))
        assertEquals(local.folders, result.notebook.folders)
        assertEquals(local.deleted, result.notebook.deleted)
        assertEquals(local.draft, result.notebook.draft)
    }

    @Test
    fun replacingMovesEverythingThatWasHereToRecentlyDeletedWithoutItsFolder() {
        val local = Notebook(folders = listOf(work), entries = listOf(mail, bank), deleted = listOf(DeletedEntry(bank.copy(password = "x"), 1)))
        val incoming = file(listOf(Folder("F3", "家")), mail.copy(folderId = null), Entry("E3", "新", folderId = "F3"))
        val result = ImportMerge.replace(local, incoming, 50, freshId)
        assertEquals(incoming.folders, result.notebook.folders)
        assertEquals(incoming.entries, result.notebook.entries)
        // Both local entries are kept for 30 days, even the one the file also holds unchanged.
        assertEquals(2, result.movedToDeleted)
        assertEquals(2, result.added)
        assertEquals(
            // The one the file also holds gets a new identifier; so does the one Recently Deleted already holds.
            listOf(DeletedEntry(bank.copy(password = "x"), 1), DeletedEntry(mail.copy(id = "NEW1", folderId = null), 50), DeletedEntry(bank.copy(id = "NEW2"), 50)),
            result.notebook.deleted,
        )
        // Restoring it does not collide with the entry the file brought in.
        val restored = result.notebook.restore("NEW1", 60, freshId)
        assertEquals(listOf("E1", "E3", "NEW1"), restored.entries.map { it.id })
    }

    @Test
    fun replacingKeepsTheDraft() {
        val local = Notebook(folders = listOf(work), entries = listOf(mail), draft = bank.copy(id = "D", folderId = "F1"))
        val result = ImportMerge.replace(local, file(emptyList()), 50, freshId)
        assertEquals(bank.copy(id = "D", folderId = null), result.notebook.draft)
        assertTrue(result.notebook.entries.isEmpty())
        assertEquals(1, result.notebook.deleted.size)
    }
}
