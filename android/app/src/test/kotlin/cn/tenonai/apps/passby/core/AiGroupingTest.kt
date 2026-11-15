package cn.tenonai.apps.passby.core

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class AiGroupingTest {
    private var counter = 0
    private val freshId: () -> String = { "NEW${++counter}" }

    private val work = Folder("F1", "工作")
    private val mail = Entry("ID-MAIL-0001", "gmail", "ACCOUNT-alex@example.com", "PASSWORD-s3cret", "NOTES-recovery codes", "F1")
    private val bank = Entry("ID-BANK-0002", "招行", "ACCOUNT-6222", "PASSWORD-123456", "NOTES-card pin")
    private val odd = Entry("ID-ODD-0003", "x", "ACCOUNT-odd", "PASSWORD-odd", "NOTES-odd")
    private val notebook = Notebook(folders = listOf(work), entries = listOf(mail, bank, odd))

    /** The one way the app builds a request: titles and folder names, nothing else. */
    private fun requestFor(notebook: Notebook) =
        AiGrouping.request(notebook.entries.map { it.title }, notebook.folders.map { it.name }, "model-x")

    @Test
    fun theRequestHoldsTitlesAndFolderNamesAndNothingElseFromTheNotebook() {
        val body = requestFor(notebook)
        for (entry in notebook.entries) {
            assertTrue(body.contains(entry.title))
            assertFalse(body.contains(entry.account))
            assertFalse(body.contains(entry.password))
            assertFalse(body.contains(entry.notes))
            assertFalse(body.contains(entry.id))
        }
        assertFalse(body.contains("ACCOUNT-"))
        assertFalse(body.contains("PASSWORD-"))
        assertFalse(body.contains("NOTES-"))
        assertFalse(body.contains(work.id))
        assertTrue(body.contains("工作"))
    }

    @Test
    fun theRequestIsWhatTheDocumentSays() {
        val root = Json.parse(AiGrouping.request(listOf("a \"b\"", "c"), listOf("F"), "m"))
        assertEquals(setOf("model", "messages", "temperature", "stream"), (root as JsonObject).members.keys)
        assertEquals("m", root["model"].string)
        assertEquals(false, root["stream"].bool)
        val messages = root["messages"].items!!
        assertEquals(2, messages.size)
        assertEquals("system", messages[0]["role"].string)
        assertEquals(AiGrouping.SYSTEM_PROMPT, messages[0]["content"].string)
        assertEquals("user", messages[1]["role"].string)
        val input = Json.parse(messages[1]["content"].string!!)
        assertEquals(setOf("folders", "titles"), (input as JsonObject).members.keys)
        assertEquals(listOf("F"), input["folders"].items!!.map { it.string })
        assertEquals(listOf(1L to "a \"b\"", 2L to "c"), input["titles"].items!!.map { it["n"].long to it["title"].string })
    }

    private fun response(content: String) = Json.write(
        JsonObject(
            mapOf(
                "choices" to JsonArray(listOf(JsonObject(mapOf("message" to JsonObject(mapOf("content" to JsonString(content))))))),
            ),
        ),
    )

    @Test
    fun anAnswerIsReadByNumber() {
        val answer = """{"items":[{"n":2,"folder":"银行","title":"招商银行","unclear":false},{"n":1,"folder":"工作","title":"Gmail","unclear":false},{"n":3,"folder":"","title":"x","unclear":true}]}"""
        assertEquals(
            listOf(
                AiGrouping.Suggestion(1, "工作", "Gmail", false),
                AiGrouping.Suggestion(2, "银行", "招商银行", false),
                AiGrouping.Suggestion(3, null, "x", true),
            ),
            AiGrouping.parse(response(answer), 3),
        )
        // A code fence around the JSON is tolerated.
        assertEquals(3, AiGrouping.parse(response("```json\n$answer\n```"), 3).size)
    }

    @Test
    fun whatWasNotAskedForIsIgnored() {
        val long = "长".repeat(AiGrouping.MAX_FOLDER_NAME + 1)
        val answer = """{"items":[
            {"n":0,"folder":"a","title":"a"},
            {"n":4,"folder":"a","title":"a"},
            {"n":"1","folder":"a","title":"a"},
            {"n":1,"folder":"$long","title":"ok","extra":{"run":"rm -rf"}},
            {"n":1,"folder":"second","title":"second"},
            {"n":2,"folder":"  a\u0000\n b‮ ","title":"\t"}
        ],"also":"ignored"}"""
        assertEquals(
            listOf(AiGrouping.Suggestion(1, null, "ok", false), AiGrouping.Suggestion(2, "a b", null, false)),
            AiGrouping.parse(response(answer), 3),
        )
    }

    @Test
    fun anAnswerInAnotherFormIsRefused() {
        for (bad in listOf("", "not json", "{}", """{"choices":[]}""", """{"choices":[{"message":{"content":"sorry"}}]}""", response("""{"items":"none"}"""))) {
            assertThrows(AiGrouping.UnusableAnswer::class.java) { AiGrouping.parse(bad, 3) }
        }
    }

    @Test
    fun cleaningRemovesWhatShouldNotBeShown() {
        assertEquals("a b", AiGrouping.clean(" a \r\n\t b ", 10))
        assertEquals("ab", AiGrouping.clean("a\u0007b", 10))
        assertEquals("ab", AiGrouping.clean("a‮b⁦", 10))
        assertNull(AiGrouping.clean(" \n ", 10))
        assertNull(AiGrouping.clean("abcdef", 5))
        assertEquals("🔑钥匙", AiGrouping.clean("🔑钥匙", 3))
        assertNull(AiGrouping.clean(null, 3))
    }

    @Test
    fun applyingRenamesAndMovesAndKeepsEveryEntry() {
        val changes = listOf(
            AiGrouping.Change(mail.id, "Gmail", "工作"),
            AiGrouping.Change(bank.id, "招商银行", "银行"),
            AiGrouping.Change(odd.id, null, "待明确"),
            AiGrouping.Change("GONE", "x", "别处"),
        )
        val applied = AiGrouping.apply(notebook, changes, 9, freshId)
        val after = applied.notebook
        assertEquals(notebook.entries.size, after.entries.size)
        assertEquals(notebook.entries.map { it.id }, after.entries.map { it.id })
        // Nothing but the title and the folder changes.
        for ((old, new) in notebook.entries.zip(after.entries)) {
            assertEquals(old.account, new.account)
            assertEquals(old.password, new.password)
            assertEquals(old.notes, new.notes)
        }
        assertEquals(listOf("Gmail", "招商银行", "x"), after.entries.map { it.title })
        assertEquals(listOf(work, Folder("NEW1", "银行"), Folder("NEW2", "待明确")), after.folders)
        assertEquals(listOf("F1", "NEW1", "NEW2"), after.entries.map { it.folderId })
        assertEquals(listOf("NEW1", "NEW2"), applied.createdFolders)
        assertEquals(9L, after.changedAt)

        assertEquals(notebook.copy(changedAt = 10), AiGrouping.undo(after, applied, 10))
    }

    @Test
    fun applyingNothingChangesNothing() {
        assertTrue(AiGrouping.apply(notebook, emptyList(), 9, freshId).notebook === notebook)
        // The same title and the folder it is already in.
        val same = AiGrouping.apply(notebook, listOf(AiGrouping.Change(mail.id, "gmail", "工作")), 9, freshId)
        assertTrue(same.notebook === notebook)
    }

    @Test
    fun undoingLeavesLaterChangesAlone() {
        val applied = AiGrouping.apply(notebook, listOf(AiGrouping.Change(bank.id, "招商银行", "银行")), 9, freshId)
        // Since then another entry was put in the new folder and the changed one was deleted.
        val later = applied.notebook.save(odd.copy(folderId = "NEW1"), 10).delete(bank.id, 11)
        val undone = AiGrouping.undo(later, applied, 12)
        assertEquals(listOf(work, Folder("NEW1", "银行")), undone.folders)
        assertEquals(later.entries, undone.entries)
        assertEquals(later.deleted, undone.deleted)
    }

    @Test
    fun onlyAnHttpsAddressIsAccepted() {
        assertEquals(AiGrouping.Endpoint("https://api.deepseek.com/chat/completions", "api.deepseek.com"), AiGrouping.endpoint(" https://API.deepseek.com/chat/completions ".replace("API", "api")))
        assertEquals("api.example.com", AiGrouping.endpoint("https://API.Example.com:8443/v1/chat/completions")?.host)
        for (bad in listOf("", "api.deepseek.com", "http://api.deepseek.com/chat", "ftp://a.b/c", "https://", "https://user:pw@a.b/c", "https://a.b/c#x", "https://a b/c", "file:///etc/hosts")) {
            assertNull(bad, AiGrouping.endpoint(bad))
        }
        assertEquals(AiGrouping.DEEPSEEK_ENDPOINT, AiGrouping.endpoint(AiGrouping.DEEPSEEK_ENDPOINT)?.url)
    }

    /**
     * The app may open a network connection in one place only. Every other source file is checked for
     * the classes that could open one.
     */
    @Test
    fun onlyOneFileCanOpenAConnection() {
        val sources = File(System.getProperty("passby.sources")!!)
        val connecting = Regex("""\b(URLConnection|HttpURLConnection|HttpsURLConnection|Socket|SocketChannel|DatagramSocket|ServerSocket|SSLSocket|openConnection|openStream|InetAddress|WebView|DownloadManager|ConnectivityManager)\b|\bURL\(""")
        val offenders = sources.walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .filter { connecting.containsMatchIn(it.readText()) }
            .map { it.name }
            .toList()
        assertEquals(listOf("AiClient.kt"), offenders)
    }
}
