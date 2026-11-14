package cn.tenonai.apps.passby.core

import java.math.BigDecimal
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.time.temporal.ChronoUnit
import java.util.Locale

/** What an export file holds once decrypted (docs/export-format.md §4). Recently Deleted is never in it. */
class ExportedNotebook(val exportedAt: Instant, val folders: List<Folder>, val entries: List<Entry>)

object ExportPlaintext {
    private val UUID_PATTERN = Regex("^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$")

    private fun damaged() = ExportException(ExportException.Kind.DAMAGED)

    /** Checks 6 to 8 of §5. */
    fun parse(plaintext: ByteArray): ExportedNotebook {
        val root = try {
            Json.parse(decodeUtf8(plaintext))
        } catch (e: JsonException) {
            throw damaged()
        } catch (e: CharacterCodingException) {
            throw damaged()
        }
        // `format` has to be a whole number before its value is looked at: 1.0 counts, 1.5 and "1" do not.
        val format = try {
            BigDecimal((root["format"] as? JsonNumber ?: throw damaged()).text)
        } catch (e: NumberFormatException) {
            throw damaged()
        }
        if (format.signum() != 0 && format.stripTrailingZeros().scale() > 0) throw damaged()
        if (format.compareTo(BigDecimal.ONE) != 0) throw ExportException(ExportException.Kind.UPDATE)

        val exportedAt = parseInstant(root["exportedAt"].string ?: throw damaged()) ?: throw damaged()
        val folders = (root["folders"].items ?: throw damaged()).map { item ->
            Folder(id = uuid(item["id"]), name = item["name"].string ?: throw damaged())
        }
        val entries = (root["entries"].items ?: throw damaged()).map { item ->
            if (item !is JsonObject) throw damaged()
            Entry(
                id = uuid(item["id"]),
                title = item["title"].string ?: throw damaged(),
                account = item["account"].string ?: throw damaged(),
                password = item["password"].string ?: throw damaged(),
                notes = item["notes"].string ?: throw damaged(),
                // Leaving folderID out means Unfiled. Anything else has to be a UUID, as in the reference.
                folderId = if (item.members.containsKey("folderID")) uuid(item["folderID"]) else null,
            )
        }
        val folderIds = folders.mapTo(HashSet()) { it.id }
        val entryIds = entries.mapTo(HashSet()) { it.id }
        if (folderIds.size != folders.size || entryIds.size != entries.size) throw damaged()
        if (entries.any { it.folderId != null && it.folderId !in folderIds }) throw damaged()
        return ExportedNotebook(exportedAt, folders, entries)
    }

    /** The JSON for a new export. Member order follows the reference so the same notebook gives the same bytes. */
    fun serialize(folders: List<Folder>, entries: List<Entry>, exportedAt: Instant): ByteArray {
        val folderIds = folders.mapTo(HashSet()) { it.id }
        val root = JsonObject(
            linkedMapOf<String, JsonValue>(
                "format" to JsonNumber("1"),
                "exportedAt" to JsonString(DateTimeFormatter.ISO_INSTANT.format(exportedAt.truncatedTo(ChronoUnit.SECONDS))),
                "folders" to JsonArray(
                    folders.map { JsonObject(linkedMapOf<String, JsonValue>("id" to JsonString(it.id), "name" to JsonString(it.name))) },
                ),
                "entries" to JsonArray(
                    entries.map { entry ->
                        val members = linkedMapOf<String, JsonValue>(
                            "id" to JsonString(entry.id),
                            "title" to JsonString(entry.title),
                            "account" to JsonString(entry.account),
                            "password" to JsonString(entry.password),
                            "notes" to JsonString(entry.notes),
                        )
                        if (entry.folderId != null && entry.folderId in folderIds) members["folderID"] = JsonString(entry.folderId)
                        JsonObject(members)
                    },
                ),
            ),
        )
        return Json.write(root).toByteArray(Charsets.UTF_8)
    }

    private fun uuid(value: JsonValue?): String {
        val text = value.string ?: throw damaged()
        if (!UUID_PATTERN.matches(text)) throw damaged()
        return text.uppercase(Locale.ROOT)
    }

    // The format writes "2026-11-14T12:00:00Z". Other ISO 8601 spellings the reference also reads are
    // accepted: fractional seconds, a numeric offset, no offset (taken as UTC) and a date on its own.
    private fun parseInstant(text: String): Instant? {
        try {
            return OffsetDateTime.parse(text).toInstant()
        } catch (e: DateTimeParseException) {
            // Try the next spelling.
        }
        try {
            return LocalDateTime.parse(text).toInstant(ZoneOffset.UTC)
        } catch (e: DateTimeParseException) {
            // Try the next spelling.
        }
        return try {
            LocalDate.parse(text).atStartOfDay().toInstant(ZoneOffset.UTC)
        } catch (e: DateTimeParseException) {
            null
        }
    }

    private fun decodeUtf8(bytes: ByteArray): String =
        Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(bytes))
            .toString()
}
