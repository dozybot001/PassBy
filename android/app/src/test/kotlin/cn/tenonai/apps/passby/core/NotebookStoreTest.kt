package cn.tenonai.apps.passby.core

import java.io.File
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class NotebookStoreTest {
    @get:Rule
    val temporary = TemporaryFolder()

    private val full = Notebook(
        folders = listOf(Folder("F1", "工作 \"Work\"")),
        entries = listOf(Entry("E1", "邮箱", "alex@example.com", "p@ss 密码 🔑\n\\", "第一行\nsecond", "F1"), Entry("E2", "空")),
        deleted = listOf(DeletedEntry(Entry("E3", "旧", password = "old"), 1_700_000_000_000)),
        draft = Entry("E4", "草稿"),
        lastExportAt = 1_700_000_000_001,
        changedAt = 1_700_000_000_002,
        reminderDismissedAt = 1_700_000_000_003,
        gateEnabled = false,
    )

    private fun directory() = File(temporary.root, "notebook")
    private fun ready(store: NotebookStore) = store.open() as NotebookStore.Opened.Ready

    @Test
    fun theFileKeepsEveryField() {
        assertEquals(full, NotebookCodec.decode(NotebookCodec.encode(full)))
        assertEquals(Notebook(), NotebookCodec.decode(NotebookCodec.encode(Notebook())))
    }

    @Test
    fun aFreshInstallOpensAnEmptyNotebookAndWritesNothing() {
        val opened = ready(NotebookStore(directory()))
        assertEquals(Notebook(), opened.notebook)
        assertFalse(opened.restored)
        assertFalse(directory().exists())
    }

    @Test
    fun savingKeepsThePreviousVersionBesideTheCurrentOne() {
        val store = NotebookStore(directory())
        val first = Notebook(entries = listOf(Entry("E1", "一")))
        store.save(first)
        store.save(full)
        assertEquals(full, ready(NotebookStore(directory())).notebook)
        assertEquals(first, NotebookCodec.decode(File(directory(), "notebook.json.previous").readBytes()))
        assertEquals(setOf("notebook.json", "notebook.json.previous"), directory().list()!!.toSet())
    }

    @Test
    fun aDamagedCurrentFileFallsBackToThePreviousVersionAndIsKept() {
        val store = NotebookStore(directory())
        val first = Notebook(entries = listOf(Entry("E1", "一")))
        store.save(first)
        store.save(full)
        val current = File(directory(), "notebook.json")
        current.writeBytes(byteArrayOf(1, 2, 3))

        val opened = ready(NotebookStore(directory()))
        assertEquals(first, opened.notebook)
        assertTrue(opened.restored)
        // The damaged bytes are still on disk under another name, and the notebook is readable again.
        assertArrayEquals(byteArrayOf(1, 2, 3), File(directory(), "notebook.json.unreadable").readBytes())
        assertEquals(first, ready(NotebookStore(directory())).notebook)
        assertFalse(ready(NotebookStore(directory())).restored)
    }

    @Test
    fun whenNothingCanBeReadTheFilesAreLeftAlone() {
        directory().mkdirs()
        File(directory(), "notebook.json").writeText("not json")
        File(directory(), "notebook.json.previous").writeText("{}")
        val opened = NotebookStore(directory()).open()
        assertTrue(opened is NotebookStore.Opened.Unreadable)
        assertFalse((opened as NotebookStore.Opened.Unreadable).newerVersion)
        assertEquals("not json", File(directory(), "notebook.json").readText())
        assertEquals("{}", File(directory(), "notebook.json.previous").readText())
    }

    @Test
    fun aFileFromANewerVersionIsNotOpenedOrReplaced() {
        val store = NotebookStore(directory())
        store.save(full)
        store.save(full)
        val current = File(directory(), "notebook.json")
        val newer = """{"schema":2,"folders":[],"entries":[],"deleted":[],"somethingNew":1}"""
        current.writeText(newer)
        val opened = NotebookStore(directory()).open()
        assertTrue((opened as NotebookStore.Opened.Unreadable).newerVersion)
        assertEquals(newer, current.readText())
    }

    @Test
    fun startingOverKeepsTheUnreadableFiles() {
        directory().mkdirs()
        File(directory(), "notebook.json").writeText("not json")
        File(directory(), "notebook.json.previous").writeText("also not json")
        val store = NotebookStore(directory())
        store.setUnreadableAside()
        assertEquals(Notebook(), ready(store).notebook)
        store.save(full)
        assertEquals("not json", File(directory(), "notebook.json.unreadable").readText())
        assertEquals("also not json", File(directory(), "notebook.json.previous.unreadable").readText())
        assertEquals(full, ready(NotebookStore(directory())).notebook)
    }

    @Test
    fun aFolderReferenceThatPointsNowhereIsReadAsUnfiled() {
        val json = """{"schema":1,"folders":[],"entries":[{"id":"E1","title":"t","account":"","password":"","notes":"","folderID":"GONE"}],"deleted":[]}"""
        val notebook = NotebookCodec.decode(json.toByteArray())
        assertEquals(listOf(Entry("E1", "t")), notebook.entries)
        assertTrue(notebook.gateEnabled)
    }

    @Test
    fun passwordGeneratorUsesEveryChosenSetAndOnlyThose() {
        repeat(200) {
            val all = PasswordGenerator.generate(PasswordOptions(length = 8))
            assertEquals(8, all.length)
            assertTrue(all.any { it in 'a'..'z' } && all.any { it in 'A'..'Z' } && all.any { it in '0'..'9' } && all.any { !it.isLetterOrDigit() })
            val digits = PasswordGenerator.generate(PasswordOptions(length = 24, lowercase = false, uppercase = false, symbols = false))
            assertTrue(digits.all { it in '0'..'9' })
        }
        assertEquals(4096, PasswordGenerator.generate(PasswordOptions(length = 4096)).length)
        assertFalse(PasswordOptions(length = 7).isValid)
        assertFalse(PasswordOptions(length = 4097).isValid)
        assertFalse(PasswordOptions(lowercase = false, uppercase = false, digits = false, symbols = false).isValid)
        assertEquals("!@#\$%^&*()-_=+[]{}:,.?", PasswordOptions(lowercase = false, uppercase = false, digits = false).alphabets.single())
    }
}
