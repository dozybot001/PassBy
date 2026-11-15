package cn.tenonai.apps.passby.core

import java.io.File
import java.util.Base64
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

/**
 * Every vector in docs/sync-vectors.json, which each platform passes so that two devices arrive at
 * the same notebook, and how the notebook keeps the marks a sync needs.
 */
class SyncTest {
    private val vectors: JsonValue = Json.parse(
        File(System.getProperty("passby.syncVectors") ?: "../../docs/sync-vectors.json").readText(Charsets.UTF_8),
    )

    private fun hex(bytes: ByteArray) = bytes.joinToString("") { "%02x".format(it) }
    private fun unhex(text: String) = ByteArray(text.length / 2) { text.substring(it * 2, it * 2 + 2).toInt(16).toByte() }
    private fun base64(text: String): ByteArray = Base64.getDecoder().decode(text)

    private fun summary(value: JsonValue?) = SyncSummary(
        value["added"].long!!.toInt(), value["updated"].long!!.toInt(), value["removed"].long!!.toInt(), value["conflicts"].long!!.toInt(),
    )

    private fun refused(block: () -> Unit) {
        try {
            block()
            fail("expected the frame to be refused")
        } catch (e: SyncException) {
            assertEquals(SyncException.Kind.REFUSED, e.kind)
        }
    }

    @Test
    fun theFileHasTheExpectedVectors() {
        assertEquals(5, vectors["codes"].items!!.size)
        assertEquals(3, vectors["crypto"]["exchanges"].items!!.size)
        assertEquals(11, vectors["merges"].items!!.size)
        assertEquals(6, vectors["invalid"].items!!.size)
    }

    @Test
    fun codesAreReadTheSameWay() {
        for (c in vectors["codes"].items!!) assertEquals(c["typed"].string, c["code"].string, SyncCrypto.canonicalCode(c["typed"].string!!))
        repeat(50) {
            val code = SyncCrypto.newCode()
            assertEquals(code, SyncCrypto.canonicalCode(SyncCrypto.display(code).lowercase()))
        }
    }

    @Test
    fun keysAndFramesMatch() {
        val c = vectors["crypto"]
        val hostNonce = unhex(c["hostNonceHex"].string!!)
        val guestNonce = unhex(c["guestNonceHex"].string!!)
        val keys = SyncCrypto.deriveKeys(SyncCrypto.canonicalCode(c["typed"].string!!)!!, hostNonce, guestNonce, c["iterations"].long!!.toInt())
        assertEquals(c["guestToHostKeyHex"].string, hex(keys.guestToHost))
        assertEquals(c["hostToGuestKeyHex"].string, hex(keys.hostToGuest))
        for (x in c["exchanges"].items!!) {
            val counter = x["counter"].long!!
            val body = base64(x["requestBodyBase64"].string!!)
            val request = SyncCrypto.readRequest(body)
            assertArrayEquals(hostNonce, request.hostNonce)
            assertArrayEquals(guestNonce, request.guestNonce)
            assertEquals(counter, request.counter)
            val plain = SyncCrypto.open(keys.guestToHost, hostNonce, guestNonce, SyncCrypto.GUEST_TO_HOST, counter, request.sealed)
            assertEquals(x["requestPlaintext"].string, String(plain, Charsets.UTF_8))
            assertArrayEquals(
                body,
                SyncCrypto.requestBody(hostNonce, guestNonce, counter, SyncCrypto.seal(keys.guestToHost, hostNonce, guestNonce, SyncCrypto.GUEST_TO_HOST, counter, plain)),
            )
            val (responseCounter, sealed) = SyncCrypto.readResponse(base64(x["responseBodyBase64"].string!!))
            assertEquals(counter, responseCounter)
            val answer = SyncCrypto.open(keys.hostToGuest, hostNonce, guestNonce, SyncCrypto.HOST_TO_GUEST, counter, sealed)
            assertEquals(x["responsePlaintext"].string, String(answer, Charsets.UTF_8))
            if (x["hello"].bool == true) {
                // Counter 0 is the greeting, and this side writes it byte for byte the same.
                assertEquals(0L, counter)
                assertTrue(SyncCodec.isHello(plain) && SyncCodec.isHello(answer))
                assertArrayEquals(plain, SyncCodec.HELLO)
                assertFalse(SyncCodec.isHello(SyncCodec.request(SyncState())))
            } else {
                // The JSON inside reads as a state and a summary.
                assertEquals(1, SyncCodec.readRequest(plain).entries.size)
                assertEquals(SyncSummary(0, 0, 0, 0), SyncCodec.readResponse(answer).second)
                assertFalse(SyncCodec.isHello(plain))
            }
            // A frame must not open under the other direction, another counter or the other key.
            refused { SyncCrypto.open(keys.guestToHost, hostNonce, guestNonce, SyncCrypto.HOST_TO_GUEST, counter, request.sealed) }
            refused { SyncCrypto.open(keys.guestToHost, hostNonce, guestNonce, SyncCrypto.GUEST_TO_HOST, counter + 1, request.sealed) }
            refused { SyncCrypto.open(keys.hostToGuest, hostNonce, guestNonce, SyncCrypto.GUEST_TO_HOST, counter, request.sealed) }
            refused { SyncCrypto.open(keys.guestToHost, hostNonce, guestNonce, SyncCrypto.GUEST_TO_HOST, counter, ByteArray(3)) }
        }
    }

    @Test
    fun mergesMatch() {
        for (m in vectors["merges"].items!!) {
            val name = m["name"].string!!
            val host = SyncCodec.state(m["host"])
            val guest = SyncCodec.state(m["guest"])
            val ids = m["copyIds"].items!!.map { it.string!! }.toMutableList()
            val result = SyncMerge.merge(host, guest, m["marker"].string!!) { ids.removeAt(0) }
            val expected = SyncCodec.state(m["result"])
            assertEquals(name, expected, result.state)
            assertEquals(name, m["conflicts"].long!!.toInt(), result.conflicts)
            assertEquals(name, summary(m["guestSummary"]), SyncMerge.summary(guest, result.state, result.conflicts))
            assertEquals(name, summary(m["hostSummary"]), SyncMerge.summary(host, result.state, result.conflicts))
            // Merging the result with itself changes nothing, and it survives being written and read.
            assertEquals(name, expected, SyncMerge.merge(result.state, result.state, "") { error("no copy expected") }.state)
            assertEquals(name, expected, SyncCodec.readRequest(SyncCodec.request(result.state)))
        }
    }

    @Test
    fun invalidStatesAreRefused() {
        for (i in vectors["invalid"].items!!) {
            try {
                SyncCodec.state(i["state"])
                fail(i["name"].string)
            } catch (e: SyncException) {
                assertEquals(SyncException.Kind.INVALID, e.kind)
            }
        }
    }

    // ---- The notebook's marks ----

    private val a = "00000000-0000-4000-8000-00000000000A"
    private val b = "00000000-0000-4000-8000-00000000000B"
    private val f = "F0000000-0000-4000-8000-000000000001"

    /** Applies a change the way the repository does. */
    private fun Notebook.change(now: Long, change: (Notebook) -> Notebook): Notebook = change(this).marked(this, now)

    @Test
    fun changesAreStampedAndDeletionsLeaveTombstones() {
        var n = Notebook().change(100) { it.addFolder(Folder(f, "Work"), 100).save(Entry(a, "A", folderId = f), 100).save(Entry(b, "B"), 100) }
        assertEquals(Stamp(100, true), n.marks.entries[a])
        assertEquals(Stamp(100, true), n.marks.folders[f])

        n = n.change(200) { it.save(Entry(a, "A2", folderId = f), 200) }
        assertEquals(Stamp(200, true), n.marks.entries[a])
        assertEquals("an untouched entry keeps its stamp", Stamp(100, true), n.marks.entries[b])

        n = n.change(300) { it.delete(b, 300) }
        assertNull(n.marks.entries[b])
        assertEquals(listOf(Tombstone(b, Tombstone.Kind.ENTRY, 300, true)), n.marks.tombstones)

        n = n.change(400) { it.restore(b, 400) }
        assertEquals(Stamp(400, true), n.marks.entries[b])
        assertTrue("putting it back removes the tombstone", n.marks.tombstones.isEmpty())

        n = n.change(500) { it.removeFolder(f, 500) }
        assertEquals("leaving a deleted folder is a change to the entry", Stamp(500, true), n.marks.entries[a])
        assertEquals(listOf(Tombstone(f, Tombstone.Kind.FOLDER, 500, true)), n.marks.tombstones)

        val later = 500 + SyncMarks.TOMBSTONE_RETENTION_MS
        n = n.change(later) { it.save(Entry(a, "A3"), later) }
        assertTrue("tombstones are dropped after 400 days", n.marks.tombstones.isEmpty())
    }

    @Test
    fun aChangeThatTouchesNoEntryLeavesTheMarksAlone() {
        val n = Notebook().change(100) { it.save(Entry(a, "A"), 100) }
        assertEquals(n.marks, n.change(900) { it.copy(draft = Entry(b, "draft"), gateEnabled = false) }.marks)
    }

    @Test
    fun aNotebookFromBeforeSyncCountsAsChangedAtAnUnknownTime() {
        val old = NotebookCodec.decode(
            """{"schema":1,"folders":[],"entries":[{"id":"$a","title":"A","account":"","password":"p","notes":""}],"deleted":[]}""".toByteArray(),
        )
        assertEquals(SyncMarks(), old.marks)
        assertEquals(Stamp.UNKNOWN, old.syncState().entries.single().stamp)
        assertEquals(Stamp.UNKNOWN, old.change(50) { it.copy(gateEnabled = false) }.marks.entries[a])
    }

    @Test
    fun marksSurviveTheFile() {
        val n = Notebook().change(100) { it.addFolder(Folder(f, "Work"), 100).save(Entry(a, "A"), 100).save(Entry(b, "B"), 100) }
            .change(200) { it.delete(b, 200) }
        assertEquals(n, NotebookCodec.decode(NotebookCodec.encode(n)))
    }

    @Test
    fun takingASyncedStateKeepsWhatTheOtherDeviceDeletedInRecentlyDeleted() {
        val phone = Notebook().change(100) { it.save(Entry(a, "A"), 100).save(Entry(b, "B"), 100) }
        // The other device had both, deleted A and added a folder with a new entry.
        val c = "00000000-0000-4000-8000-00000000000C"
        val other = SyncState(
            entries = listOf(SyncEntry(Entry(b, "B"), Stamp(100, false)), SyncEntry(Entry(c, "C", folderId = f), Stamp(150, true))),
            folders = listOf(SyncFolder(Folder(f, "Work"), Stamp(150, true))),
            tombstones = listOf(Tombstone(a, Tombstone.Kind.ENTRY, 160, true)),
        )
        val clean = phone.copy(marks = phone.marks.copy(entries = phone.marks.entries.mapValues { it.value.copy(dirty = false) }))
        val merged = SyncMerge.merge(clean.syncState(), other, " (Conflict copy)")
        val after = clean.synced(merged.state, 900)

        assertEquals(listOf(b, c), after.entries.map { it.id })
        assertEquals(listOf(f), after.folders.map { it.id })
        assertEquals("the deleted entry can still be put back", listOf(a), after.deleted.map { it.entry.id })
        assertEquals(900L, after.deleted.single().deletedAt)
        assertFalse(after.marks.entries.values.any { it.dirty } || after.marks.folders.values.any { it.dirty } || after.marks.tombstones.any { it.dirty })
        assertEquals(SyncSummary(1, 0, 1, 0), SyncMerge.summary(clean.syncState(), merged.state, merged.conflicts))
        // A second sync straight away changes nothing on either side.
        assertEquals(after, after.synced(SyncMerge.merge(after.syncState(), merged.state, "").state, 950))
        // Putting the entry back is a change the next sync carries to the other device.
        val restored = after.restore(a, 1000).marked(after, 1000)
        assertEquals(Stamp(1000, true), restored.marks.entries[a])
        assertTrue(restored.marks.tombstones.isEmpty())
    }
}
