package cn.tenonai.apps.passby.core

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.nio.channels.FileChannel
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption

/** The notebook as the JSON kept on this phone. This layout is the app's own and is not the export format. */
object NotebookCodec {
    const val SCHEMA = 1

    /** The file was written by a later version of the app. */
    class NewerSchema : Exception()

    /** The file is JSON but not a notebook. */
    class Invalid : Exception()

    fun encode(notebook: Notebook): ByteArray {
        val root = linkedMapOf<String, JsonValue>(
            "schema" to JsonNumber(SCHEMA.toString()),
            "folders" to JsonArray(notebook.folders.map { JsonObject(linkedMapOf<String, JsonValue>("id" to JsonString(it.id), "name" to JsonString(it.name))) }),
            "entries" to JsonArray(notebook.entries.map { JsonObject(entryMembers(it)) }),
            "deleted" to JsonArray(
                notebook.deleted.map { item ->
                    JsonObject(entryMembers(item.entry).also { it["deletedAt"] = JsonNumber(item.deletedAt.toString()) })
                },
            ),
            "gate" to JsonBool(notebook.gateEnabled),
            "noLockNoticeShown" to JsonBool(notebook.noLockNoticeShown),
        )
        notebook.draft?.let { root["draft"] = JsonObject(entryMembers(it)) }
        notebook.lastExportAt?.let { root["lastExportAt"] = JsonNumber(it.toString()) }
        notebook.changedAt?.let { root["changedAt"] = JsonNumber(it.toString()) }
        notebook.reminderDismissedAt?.let { root["reminderDismissedAt"] = JsonNumber(it.toString()) }
        return Json.write(JsonObject(root)).toByteArray(Charsets.UTF_8)
    }

    fun decode(bytes: ByteArray): Notebook {
        val root = try {
            Json.parse(String(bytes, Charsets.UTF_8)) as? JsonObject ?: throw Invalid()
        } catch (e: JsonException) {
            throw Invalid()
        }
        val schema = root["schema"].long ?: throw Invalid()
        if (schema > SCHEMA) throw NewerSchema()
        if (schema != SCHEMA.toLong()) throw Invalid()
        val folders = (root["folders"].items ?: throw Invalid()).map {
            Folder(it["id"].string ?: throw Invalid(), it["name"].string ?: throw Invalid())
        }
        val folderIds = folders.mapTo(HashSet()) { it.id }
        // A folder reference that points nowhere is read as Unfiled instead of refusing the whole file.
        fun entry(value: JsonValue?): Entry = Entry(
            id = value["id"].string ?: throw Invalid(),
            title = value["title"].string ?: throw Invalid(),
            account = value["account"].string ?: throw Invalid(),
            password = value["password"].string ?: throw Invalid(),
            notes = value["notes"].string ?: throw Invalid(),
            folderId = value["folderID"].string,
        )
        val entries = (root["entries"].items ?: throw Invalid()).map { entry(it) }
            .map { if (it.folderId != null && it.folderId !in folderIds) it.copy(folderId = null) else it }
        val deleted = (root["deleted"].items ?: throw Invalid()).map {
            DeletedEntry(entry(it), it["deletedAt"].long ?: throw Invalid())
        }
        if (folderIds.size != folders.size) throw Invalid()
        if (entries.mapTo(HashSet()) { it.id }.size != entries.size) throw Invalid()
        if (deleted.mapTo(HashSet()) { it.entry.id }.size != deleted.size) throw Invalid()
        return Notebook(
            folders = folders,
            entries = entries,
            deleted = deleted,
            draft = root["draft"]?.let { entry(it) },
            lastExportAt = root["lastExportAt"].long,
            changedAt = root["changedAt"].long,
            reminderDismissedAt = root["reminderDismissedAt"].long,
            gateEnabled = root["gate"].bool ?: true,
            noLockNoticeShown = root["noLockNoticeShown"].bool ?: false,
        )
    }

    private fun entryMembers(entry: Entry): LinkedHashMap<String, JsonValue> {
        val members = linkedMapOf<String, JsonValue>(
            "id" to JsonString(entry.id),
            "title" to JsonString(entry.title),
            "account" to JsonString(entry.account),
            "password" to JsonString(entry.password),
            "notes" to JsonString(entry.notes),
        )
        entry.folderId?.let { members["folderID"] = JsonString(it) }
        return members
    }
}

/**
 * Reads and writes the notebook file in the app's private directory.
 *
 * A save writes the new contents to a separate file, checks them, keeps a copy of the file being
 * replaced as `.previous`, then renames the new file into place. The current file is therefore whole
 * at every moment, and one earlier version is always at hand. Nothing here deletes a notebook: a file
 * that cannot be read is renamed and kept.
 */
class NotebookStore(private val directory: File) {
    private val current = File(directory, FILE)
    private val previous = File(directory, "$FILE.previous")

    sealed interface Opened {
        /** [restored] is true when the current file was unreadable and the previous version was used. */
        class Ready(val notebook: Notebook, val restored: Boolean) : Opened

        /** Neither file can be read. Both are left as they are. */
        class Unreadable(val newerVersion: Boolean) : Opened
    }

    @Synchronized
    fun open(): Opened {
        if (!current.exists() && !previous.exists()) return Opened.Ready(Notebook(), restored = false)
        var newer = false
        if (current.exists()) {
            try {
                return Opened.Ready(NotebookCodec.decode(current.readBytes()), restored = false)
            } catch (e: NotebookCodec.NewerSchema) {
                // Falling back to an older copy here would split the notebook in two.
                return Opened.Unreadable(newerVersion = true)
            } catch (e: NotebookCodec.Invalid) {
                newer = false
            } catch (e: IOException) {
                newer = false
            }
        }
        if (previous.exists()) {
            try {
                val notebook = NotebookCodec.decode(previous.readBytes())
                setAside(current)
                write(notebook, keepPrevious = false)
                return Opened.Ready(notebook, restored = true)
            } catch (e: NotebookCodec.NewerSchema) {
                newer = true
            } catch (e: NotebookCodec.Invalid) {
                // Fall through.
            } catch (e: IOException) {
                // Fall through.
            }
        }
        return Opened.Unreadable(newer)
    }

    /** Writes the notebook. Throws IOException and leaves the current file untouched if it cannot. */
    @Synchronized
    fun save(notebook: Notebook) = write(notebook, keepPrevious = true)

    /**
     * Renames unreadable files out of the way so a new notebook can be started or imported.
     * They stay in the directory. Only called when the person chooses to start over.
     */
    @Synchronized
    fun setUnreadableAside() {
        setAside(current)
        setAside(previous)
    }

    private fun write(notebook: Notebook, keepPrevious: Boolean) {
        if (!directory.isDirectory && !directory.mkdirs()) throw IOException("cannot create the notebook directory")
        val bytes = NotebookCodec.encode(notebook)
        val incoming = File(directory, "$FILE.new")
        writeAndSync(incoming, bytes)
        if (!incoming.readBytes().contentEquals(bytes)) throw IOException("the notebook was not written correctly")
        if (keepPrevious && current.exists()) {
            val copy = File(directory, "$FILE.previous.new")
            Files.copy(current.toPath(), copy.toPath(), StandardCopyOption.REPLACE_EXISTING)
            sync(copy)
            Files.move(copy.toPath(), previous.toPath(), StandardCopyOption.ATOMIC_MOVE)
        }
        Files.move(incoming.toPath(), current.toPath(), StandardCopyOption.ATOMIC_MOVE)
        sync(directory)
    }

    private fun writeAndSync(file: File, bytes: ByteArray) {
        FileOutputStream(file).use { out ->
            out.write(bytes)
            out.flush()
            out.fd.sync()
        }
    }

    private fun sync(file: File) {
        try {
            FileChannel.open(file.toPath(), StandardOpenOption.READ).use { it.force(true) }
        } catch (e: IOException) {
            // Syncing a directory is not possible on every file system; the rename itself has happened.
        }
    }

    private fun setAside(file: File) {
        if (!file.exists()) return
        var target = File(directory, "${file.name}.unreadable")
        var number = 1
        while (target.exists()) target = File(directory, "${file.name}.unreadable.${number++}")
        Files.move(file.toPath(), target.toPath(), StandardCopyOption.ATOMIC_MOVE)
    }

    companion object {
        const val FILE = "notebook.json"
    }
}
