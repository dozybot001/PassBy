package cn.tenonai.apps.passby.core

import java.nio.ByteBuffer
import java.security.GeneralSecurityException
import java.security.SecureRandom
import java.util.Locale
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** When an entry or folder last changed, and whether it changed since this phone last synced. */
data class Stamp(val updatedAt: Long, val dirty: Boolean) {
    companion object {
        /** For items written before the app kept stamps: no known time, and treated as changed. */
        val UNKNOWN = Stamp(0, true)
    }
}

/** A record that an entry or folder was deleted, so the deletion can reach the other device. */
data class Tombstone(val id: String, val kind: Kind, val deletedAt: Long, val dirty: Boolean) {
    enum class Kind(val word: String) { ENTRY("entry"), FOLDER("folder") }
}

/** What the notebook keeps for sync next to its entries and folders. */
data class SyncMarks(
    val entries: Map<String, Stamp> = emptyMap(),
    val folders: Map<String, Stamp> = emptyMap(),
    val tombstones: List<Tombstone> = emptyList(),
) {
    companion object {
        const val TOMBSTONE_RETENTION_MS = 400L * 24 * 60 * 60 * 1000
    }
}

data class SyncEntry(val entry: Entry, val stamp: Stamp)
data class SyncFolder(val folder: Folder, val stamp: Stamp)

/** One device's notebook as it is exchanged (docs/sync.md §6.4). */
data class SyncState(
    val entries: List<SyncEntry> = emptyList(),
    val folders: List<SyncFolder> = emptyList(),
    val tombstones: List<Tombstone> = emptyList(),
)

/** What a sync changed for one device. */
data class SyncSummary(val added: Int, val updated: Int, val removed: Int, val conflicts: Int)

class SyncException(val kind: Kind) : Exception(kind.name) {
    enum class Kind {
        /** The other side sent something that is not a valid state. */
        INVALID,

        /** A frame did not open: wrong code, wrong direction or counter, or tampering. */
        REFUSED,
    }
}

/** The merge both devices arrive at (docs/sync.md §5). scripts/sync-format.mjs is the reference. */
object SyncMerge {
    private const val MAX_TIME = 9_007_199_254_740_991L
    private val UUID = Regex("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")

    class Result(val state: SyncState, val conflicts: Int)

    private fun invalid(): Nothing = throw SyncException(SyncException.Kind.INVALID)
    private fun up(id: String) = id.uppercase(Locale.ROOT)
    private fun time(value: Long) = value in 0..MAX_TIME

    /** Checks a state and returns it with identifiers in upper case. */
    fun validate(state: SyncState): SyncState {
        val folders = state.folders.map {
            if (!UUID.matches(it.folder.id) || !time(it.stamp.updatedAt)) invalid()
            it.copy(folder = it.folder.copy(id = up(it.folder.id)))
        }
        val folderIds = folders.mapTo(HashSet()) { it.folder.id }
        val entries = state.entries.map {
            if (!UUID.matches(it.entry.id) || !time(it.stamp.updatedAt)) invalid()
            val folderId = it.entry.folderId?.let { id -> if (!UUID.matches(id) || up(id) !in folderIds) invalid() else up(id) }
            it.copy(entry = it.entry.copy(id = up(it.entry.id), folderId = folderId))
        }
        val tombstones = state.tombstones.map {
            if (!UUID.matches(it.id) || !time(it.deletedAt)) invalid()
            it.copy(id = up(it.id))
        }
        for (kind in Tombstone.Kind.entries) {
            val dead = tombstones.filter { it.kind == kind }.map { it.id }
            val live = if (kind == Tombstone.Kind.ENTRY) entries.map { it.entry.id } else folders.map { it.folder.id }
            if (dead.toSet().size != dead.size || live.toSet().size != live.size || live.any { it in dead }) invalid()
        }
        return SyncState(entries, folders, tombstones)
    }

    /** One side's view of an identifier: a live item or a tombstone. */
    private class Side(val entry: SyncEntry? = null, val folder: SyncFolder? = null, val dead: Tombstone? = null) {
        val live get() = dead == null
        val dirty get() = entry?.stamp?.dirty ?: folder?.stamp?.dirty ?: dead!!.dirty
        val time get() = entry?.stamp?.updatedAt ?: folder?.stamp?.updatedAt ?: dead!!.deletedAt
    }

    private fun sides(state: SyncState, kind: Tombstone.Kind): Map<String, Side> {
        val map = HashMap<String, Side>()
        if (kind == Tombstone.Kind.ENTRY) state.entries.forEach { map[it.entry.id] = Side(entry = it) }
        else state.folders.forEach { map[it.folder.id] = Side(folder = it) }
        state.tombstones.forEach { if (it.kind == kind) map[it.id] = Side(dead = it) }
        return map
    }

    /**
     * Merges the host's and the guest's states. [marker] is appended to the title of a conflict copy;
     * [freshId] supplies the identifier of each copy, in ascending order of the entry's identifier.
     * The result has nothing dirty and is sorted by identifier.
     */
    fun merge(hostState: SyncState, guestState: SyncState, marker: String, freshId: () -> String = ::newId): Result {
        val host = validate(hostState)
        val guest = validate(guestState)
        val entries = ArrayList<SyncEntry>()
        val folders = ArrayList<SyncFolder>()
        val tombstones = ArrayList<Tombstone>()
        var conflicts = 0
        fun keep(side: Side, updatedAt: Long? = null) {
            side.entry?.let { entries += it.copy(stamp = Stamp(updatedAt ?: it.stamp.updatedAt, false)) }
            side.folder?.let { folders += it.copy(stamp = Stamp(updatedAt ?: it.stamp.updatedAt, false)) }
            side.dead?.let { tombstones += it.copy(dirty = false) }
        }
        for (kind in listOf(Tombstone.Kind.FOLDER, Tombstone.Kind.ENTRY)) {
            val h = sides(host, kind)
            val g = sides(guest, kind)
            for (id in (h.keys + g.keys).sorted()) {
                val a = h[id]
                val b = g[id]
                if (a == null || b == null) {
                    keep(a ?: b!!)
                    continue
                }
                val same = when {
                    a.entry != null && b.entry != null -> a.entry.entry.sameContent(b.entry.entry)
                    a.folder != null && b.folder != null -> a.folder.folder.name == b.folder.folder.name
                    else -> !a.live && !b.live
                }
                // The later one; the host's when they are equally late.
                val later = if (b.time > a.time) b else a
                when {
                    same -> if (a.live) keep(a, maxOf(a.time, b.time)) else keep(later)
                    a.dirty != b.dirty -> keep(if (a.dirty) a else b)
                    !a.dirty -> keep(later)
                    // Both changed since they last agreed.
                    a.live && b.live -> {
                        keep(later)
                        if (kind == Tombstone.Kind.ENTRY) {
                            val loser = (if (later === a) b else a).entry!!
                            entries += SyncEntry(
                                loser.entry.copy(id = up(freshId()), title = loser.entry.title + marker),
                                Stamp(loser.stamp.updatedAt, false),
                            )
                            conflicts += 1
                        }
                    }
                    a.live || b.live -> keep(if (a.live) a else b) // an edit outlives a deletion
                    else -> keep(later)
                }
            }
        }
        val folderIds = folders.mapTo(HashSet()) { it.folder.id }
        return Result(
            SyncState(
                entries.map { if (it.entry.folderId != null && it.entry.folderId !in folderIds) it.copy(entry = it.entry.copy(folderId = null)) else it }
                    .sortedBy { it.entry.id },
                folders.sortedBy { it.folder.id },
                tombstones.sortedBy { it.kind.word + it.id },
            ),
            conflicts,
        )
    }

    /** What changed for the side that had [before]: entries gained, entries whose content changed, entries lost. */
    fun summary(before: SyncState, after: SyncState, conflicts: Int): SyncSummary {
        val old = validate(before).entries.associate { it.entry.id to it.entry }
        val now = after.entries.associate { it.entry.id to it.entry }
        val added = now.keys.count { it !in old }
        val updated = now.count { (id, entry) -> old[id]?.let { !it.sameContent(entry) } ?: false }
        val removed = old.keys.count { it !in now }
        return SyncSummary(added - conflicts, updated, removed, conflicts)
    }
}

/** The JSON inside the frames (docs/sync.md §6.4). */
object SyncCodec {
    const val VERSION = 1

    private fun invalid(): Nothing = throw SyncException(SyncException.Kind.INVALID)
    private fun number(value: Long) = JsonNumber(value.toString())

    fun json(state: SyncState): LinkedHashMap<String, JsonValue> = linkedMapOf(
        "entries" to JsonArray(
            state.entries.map {
                val members = linkedMapOf<String, JsonValue>(
                    "id" to JsonString(it.entry.id),
                    "title" to JsonString(it.entry.title),
                    "account" to JsonString(it.entry.account),
                    "password" to JsonString(it.entry.password),
                    "notes" to JsonString(it.entry.notes),
                    "updatedAt" to number(it.stamp.updatedAt),
                    "dirty" to JsonBool(it.stamp.dirty),
                )
                it.entry.folderId?.let { id -> members["folderID"] = JsonString(id) }
                JsonObject(members)
            },
        ),
        "folders" to JsonArray(
            state.folders.map {
                JsonObject(
                    linkedMapOf<String, JsonValue>(
                        "id" to JsonString(it.folder.id),
                        "name" to JsonString(it.folder.name),
                        "updatedAt" to number(it.stamp.updatedAt),
                        "dirty" to JsonBool(it.stamp.dirty),
                    ),
                )
            },
        ),
        "tombstones" to JsonArray(
            state.tombstones.map {
                JsonObject(
                    linkedMapOf<String, JsonValue>(
                        "id" to JsonString(it.id),
                        "kind" to JsonString(it.kind.word),
                        "deletedAt" to number(it.deletedAt),
                        "dirty" to JsonBool(it.dirty),
                    ),
                )
            },
        ),
    )

    /** Reads and validates a state. Throws [SyncException] INVALID. */
    fun state(value: JsonValue?): SyncState {
        fun text(item: JsonValue, name: String) = item[name].string ?: invalid()
        fun stamp(item: JsonValue) = Stamp(item["updatedAt"].long ?: invalid(), item["dirty"].bool ?: invalid())
        val entries = (value["entries"].items ?: invalid()).map {
            val folder = (it as? JsonObject ?: invalid()).members["folderID"]
            if (folder != null && folder !is JsonString) invalid()
            SyncEntry(
                Entry(text(it, "id"), text(it, "title"), text(it, "account"), text(it, "password"), text(it, "notes"), folder.string),
                stamp(it),
            )
        }
        val folders = (value["folders"].items ?: invalid()).map { SyncFolder(Folder(text(it, "id"), text(it, "name")), stamp(it)) }
        val tombstones = (value["tombstones"].items ?: invalid()).map {
            val kind = Tombstone.Kind.entries.firstOrNull { k -> k.word == text(it, "kind") } ?: invalid()
            Tombstone(text(it, "id"), kind, it["deletedAt"].long ?: invalid(), it["dirty"].bool ?: invalid())
        }
        return SyncMerge.validate(SyncState(entries, folders, tombstones))
    }

    /** What the guest sends. */
    fun request(state: SyncState): ByteArray {
        val root = linkedMapOf<String, JsonValue>("v" to number(VERSION.toLong()))
        root.putAll(json(state))
        return Json.write(JsonObject(root)).toByteArray(Charsets.UTF_8)
    }

    fun readRequest(bytes: ByteArray): SyncState {
        val root = parse(bytes)
        if (root["v"].long != VERSION.toLong()) invalid()
        return state(root)
    }

    /** What the host answers: the merged state and what changed for the guest. */
    fun response(state: SyncState, summary: SyncSummary): ByteArray = Json.write(
        JsonObject(
            linkedMapOf(
                "v" to number(VERSION.toLong()),
                "state" to JsonObject(json(state)),
                "summary" to JsonObject(
                    linkedMapOf<String, JsonValue>(
                        "added" to number(summary.added.toLong()),
                        "updated" to number(summary.updated.toLong()),
                        "removed" to number(summary.removed.toLong()),
                        "conflicts" to number(summary.conflicts.toLong()),
                    ),
                ),
            ),
        ),
    ).toByteArray(Charsets.UTF_8)

    fun readResponse(bytes: ByteArray): Pair<SyncState, SyncSummary> {
        val root = parse(bytes)
        if (root["v"].long != VERSION.toLong()) invalid()
        val s = root["summary"]
        fun count(name: String) = s[name].long?.takeIf { it in 0..Int.MAX_VALUE }?.toInt() ?: invalid()
        return state(root["state"]) to SyncSummary(count("added"), count("updated"), count("removed"), count("conflicts"))
    }

    private fun parse(bytes: ByteArray): JsonValue = try {
        Json.parse(String(bytes, Charsets.UTF_8))
    } catch (e: JsonException) {
        invalid()
    }
}

/** The pairing code, the keys and the frames (docs/sync.md §6.3). Only the platform's HMAC-SHA256 and AES-GCM. */
object SyncCrypto {
    const val ITERATIONS = 600_000
    const val NONCE_LENGTH = 16
    const val CODE_LENGTH = 12
    const val TAG_LENGTH = 16
    const val GUEST_TO_HOST = 0
    const val HOST_TO_GUEST = 1

    /** Bytes before the sealed part of a request: both nonces and the counter. */
    const val REQUEST_HEADER = NONCE_LENGTH * 2 + 8

    private const val ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
    private val PREFIX = "PassBy sync v1".toByteArray(Charsets.US_ASCII)

    class Keys(val guestToHost: ByteArray, val hostToGuest: ByteArray) {
        fun wipe() {
            guestToHost.fill(0)
            hostToGuest.fill(0)
        }
    }

    class Request(val hostNonce: ByteArray, val guestNonce: ByteArray, val counter: Long, val sealed: ByteArray)

    private fun refused(): Nothing = throw SyncException(SyncException.Kind.REFUSED)

    /** A fresh pairing code: 12 characters, 60 bits. */
    fun newCode(random: SecureRandom = SecureRandom()): String =
        String(CharArray(CODE_LENGTH) { ALPHABET[random.nextInt(ALPHABET.length)] })

    /** The code as shown, in groups of four. */
    fun display(code: String): String = code.chunked(4).joinToString("-")

    /** The 12-character code, or null. Spaces and dashes are ignored; I, L and O read as 1, 1 and 0. */
    fun canonicalCode(input: String): String? {
        val out = StringBuilder()
        for (ch in input) {
            if (ch.isWhitespace() || ch == ' ' || ch == '﻿' || ch == '-' || ch in '‐'..'―') continue
            val c = when (val upper = ch.uppercaseChar()) {
                'I', 'L' -> '1'
                'O' -> '0'
                else -> upper
            }
            if (c !in ALPHABET) return null
            out.append(c)
        }
        return if (out.length == CODE_LENGTH) out.toString() else null
    }

    fun deriveKeys(code: String, hostNonce: ByteArray, guestNonce: ByteArray, iterations: Int = ITERATIONS, check: (() -> Unit)? = null): Keys {
        val master = ExportFile.pbkdf2(code.toByteArray(Charsets.US_ASCII), PREFIX + hostNonce + guestNonce, iterations, 32, check)
        try {
            fun key(info: String) = ExportFile.hkdf(master, ByteArray(0), info.toByteArray(Charsets.US_ASCII), 32)
            return Keys(key("PassBy sync v1 guest to host"), key("PassBy sync v1 host to guest"))
        } finally {
            master.fill(0)
        }
    }

    private fun counterBytes(counter: Long): ByteArray = ByteBuffer.allocate(8).putLong(counter).array()

    private fun cipher(mode: Int, key: ByteArray, hostNonce: ByteArray, guestNonce: ByteArray, direction: Int, counter: Long): Cipher {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(mode, SecretKeySpec(key, "AES"), GCMParameterSpec(TAG_LENGTH * 8, ByteArray(4) + counterBytes(counter)))
        cipher.updateAAD(PREFIX + hostNonce + guestNonce + byteArrayOf(direction.toByte()) + counterBytes(counter))
        return cipher
    }

    /**
     * Ciphertext followed by the tag. A key must never seal two frames with the same counter; the
     * caller counts up from zero within one session, whose keys are bound to fresh nonces.
     */
    fun seal(key: ByteArray, hostNonce: ByteArray, guestNonce: ByteArray, direction: Int, counter: Long, plaintext: ByteArray): ByteArray =
        cipher(Cipher.ENCRYPT_MODE, key, hostNonce, guestNonce, direction, counter).doFinal(plaintext)

    fun open(key: ByteArray, hostNonce: ByteArray, guestNonce: ByteArray, direction: Int, counter: Long, sealed: ByteArray): ByteArray {
        if (sealed.size < TAG_LENGTH) refused()
        return try {
            cipher(Cipher.DECRYPT_MODE, key, hostNonce, guestNonce, direction, counter).doFinal(sealed)
        } catch (e: GeneralSecurityException) {
            refused()
        }
    }

    fun requestBody(hostNonce: ByteArray, guestNonce: ByteArray, counter: Long, sealed: ByteArray): ByteArray =
        hostNonce + guestNonce + counterBytes(counter) + sealed

    fun responseBody(counter: Long, sealed: ByteArray): ByteArray = counterBytes(counter) + sealed

    fun readRequest(body: ByteArray): Request {
        if (body.size < REQUEST_HEADER + TAG_LENGTH) refused()
        return Request(
            body.copyOfRange(0, NONCE_LENGTH),
            body.copyOfRange(NONCE_LENGTH, NONCE_LENGTH * 2),
            ByteBuffer.wrap(body, NONCE_LENGTH * 2, 8).long,
            body.copyOfRange(REQUEST_HEADER, body.size),
        )
    }

    /** The counter and the sealed part of a response. */
    fun readResponse(body: ByteArray): Pair<Long, ByteArray> {
        if (body.size < 8 + TAG_LENGTH) refused()
        return ByteBuffer.wrap(body, 0, 8).long to body.copyOfRange(8, body.size)
    }
}
