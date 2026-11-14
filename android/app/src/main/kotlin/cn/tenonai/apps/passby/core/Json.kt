package cn.tenonai.apps.passby.core

/**
 * A strict RFC 8259 reader and writer.
 *
 * The app carries no JSON library: the platform's org.json accepts input that is not JSON
 * (comments, bare words, single quotes), and import has to reject the same files on every
 * Android version that iPhone and the web app reject.
 */
sealed interface JsonValue

data class JsonObject(val members: Map<String, JsonValue>) : JsonValue
data class JsonArray(val items: List<JsonValue>) : JsonValue
data class JsonString(val value: String) : JsonValue

/** The number as written, so a caller decides how to read it. */
data class JsonNumber(val text: String) : JsonValue
data class JsonBool(val value: Boolean) : JsonValue
data object JsonNull : JsonValue

class JsonException(message: String) : Exception(message)

operator fun JsonValue?.get(name: String): JsonValue? = (this as? JsonObject)?.members?.get(name)
val JsonValue?.string: String? get() = (this as? JsonString)?.value
val JsonValue?.items: List<JsonValue>? get() = (this as? JsonArray)?.items
val JsonValue?.long: Long? get() = (this as? JsonNumber)?.text?.toLongOrNull()
val JsonValue?.bool: Boolean? get() = (this as? JsonBool)?.value

object Json {
    /** Deeper nesting than this is refused rather than risking the stack. */
    private const val MAX_DEPTH = 64

    fun parse(text: String): JsonValue = Reader(text).document()

    fun write(value: JsonValue): String = StringBuilder().also { write(value, it) }.toString()

    private fun write(value: JsonValue, out: StringBuilder) {
        when (value) {
            is JsonObject -> {
                out.append('{')
                var first = true
                for ((name, member) in value.members) {
                    if (!first) out.append(',')
                    first = false
                    quote(name, out)
                    out.append(':')
                    write(member, out)
                }
                out.append('}')
            }
            is JsonArray -> {
                out.append('[')
                value.items.forEachIndexed { index, item ->
                    if (index > 0) out.append(',')
                    write(item, out)
                }
                out.append(']')
            }
            is JsonString -> quote(value.value, out)
            is JsonNumber -> out.append(value.text)
            is JsonBool -> out.append(if (value.value) "true" else "false")
            JsonNull -> out.append("null")
        }
    }

    // Escapes what JSON.stringify escapes, so the bytes match the other platforms for the same text.
    private fun quote(text: String, out: StringBuilder) {
        out.append('"')
        var i = 0
        while (i < text.length) {
            val c = text[i]
            when {
                c == '"' -> out.append("\\\"")
                c == '\\' -> out.append("\\\\")
                c == '\n' -> out.append("\\n")
                c == '\r' -> out.append("\\r")
                c == '\t' -> out.append("\\t")
                c == '\b' -> out.append("\\b")
                c == '\u000C' -> out.append("\\f")
                c < ' ' -> escape(c, out)
                Character.isHighSurrogate(c) && i + 1 < text.length && Character.isLowSurrogate(text[i + 1]) -> {
                    out.append(c).append(text[i + 1])
                    i++
                }
                // A surrogate on its own cannot be written as UTF-8, so it stays an escape.
                Character.isSurrogate(c) -> escape(c, out)
                else -> out.append(c)
            }
            i++
        }
        out.append('"')
    }

    private fun escape(c: Char, out: StringBuilder) {
        out.append("\\u")
        val hex = "0123456789abcdef"
        for (shift in intArrayOf(12, 8, 4, 0)) out.append(hex[(c.code shr shift) and 0xF])
    }

    private class Reader(private val s: String) {
        private var i = 0

        fun document(): JsonValue {
            val value = value(0)
            skipSpace()
            if (i != s.length) fail("trailing characters")
            return value
        }

        private fun fail(what: String): Nothing = throw JsonException("$what at $i")

        private fun skipSpace() {
            while (i < s.length) {
                val c = s[i]
                if (c == ' ' || c == '\n' || c == '\r' || c == '\t') i++ else break
            }
        }

        private fun value(depth: Int): JsonValue {
            if (depth > MAX_DEPTH) fail("nested too deeply")
            skipSpace()
            if (i >= s.length) fail("unexpected end")
            val c = s[i]
            return when {
                c == '{' -> obj(depth)
                c == '[' -> arr(depth)
                c == '"' -> JsonString(string())
                c == 't' -> literal("true", JsonBool(true))
                c == 'f' -> literal("false", JsonBool(false))
                c == 'n' -> literal("null", JsonNull)
                c == '-' || c in '0'..'9' -> number()
                else -> fail("unexpected character")
            }
        }

        private fun literal(word: String, value: JsonValue): JsonValue {
            if (!s.startsWith(word, i)) fail("unexpected literal")
            i += word.length
            return value
        }

        private fun obj(depth: Int): JsonValue {
            i++
            val members = LinkedHashMap<String, JsonValue>()
            skipSpace()
            if (i < s.length && s[i] == '}') {
                i++
                return JsonObject(members)
            }
            while (true) {
                skipSpace()
                if (i >= s.length || s[i] != '"') fail("expected a member name")
                val name = string()
                skipSpace()
                if (i >= s.length || s[i] != ':') fail("expected ':'")
                i++
                // A repeated name keeps its last value, as JSON.parse does.
                members[name] = value(depth + 1)
                skipSpace()
                if (i >= s.length) fail("unexpected end")
                val next = s[i]
                if (next == ',') {
                    i++
                } else if (next == '}') {
                    i++
                    return JsonObject(members)
                } else {
                    fail("expected ',' or '}'")
                }
            }
        }

        private fun arr(depth: Int): JsonValue {
            i++
            val items = ArrayList<JsonValue>()
            skipSpace()
            if (i < s.length && s[i] == ']') {
                i++
                return JsonArray(items)
            }
            while (true) {
                items.add(value(depth + 1))
                skipSpace()
                if (i >= s.length) fail("unexpected end")
                val next = s[i]
                if (next == ',') {
                    i++
                } else if (next == ']') {
                    i++
                    return JsonArray(items)
                } else {
                    fail("expected ',' or ']'")
                }
            }
        }

        private fun string(): String {
            i++
            val out = StringBuilder()
            while (true) {
                if (i >= s.length) fail("unterminated string")
                val c = s[i++]
                when {
                    c == '"' -> return out.toString()
                    c == '\\' -> {
                        if (i >= s.length) fail("unterminated escape")
                        when (val e = s[i++]) {
                            '"', '\\', '/' -> out.append(e)
                            'b' -> out.append('\b')
                            'f' -> out.append('\u000C')
                            'n' -> out.append('\n')
                            'r' -> out.append('\r')
                            't' -> out.append('\t')
                            'u' -> {
                                if (i + 4 > s.length) fail("short unicode escape")
                                var code = 0
                                repeat(4) {
                                    val digit = hexDigit(s[i++])
                                    if (digit < 0) fail("bad unicode escape")
                                    code = code * 16 + digit
                                }
                                out.append(code.toChar())
                            }
                            else -> fail("bad escape")
                        }
                    }
                    c < ' ' -> fail("control character in string")
                    else -> out.append(c)
                }
            }
        }

        // Character.digit also accepts full-width and other Unicode digits, which JSON does not.
        private fun hexDigit(c: Char): Int = when (c) {
            in '0'..'9' -> c - '0'
            in 'a'..'f' -> c - 'a' + 10
            in 'A'..'F' -> c - 'A' + 10
            else -> -1
        }

        private fun digits(): Int {
            val start = i
            while (i < s.length && s[i] in '0'..'9') i++
            return i - start
        }

        private fun number(): JsonValue {
            val start = i
            if (s[i] == '-') i++
            if (i >= s.length) fail("bad number")
            if (s[i] == '0') {
                i++
            } else if (digits() == 0) {
                fail("bad number")
            }
            if (i < s.length && s[i] == '.') {
                i++
                if (digits() == 0) fail("bad number")
            }
            if (i < s.length && (s[i] == 'e' || s[i] == 'E')) {
                i++
                if (i < s.length && (s[i] == '+' || s[i] == '-')) i++
                if (digits() == 0) fail("bad number")
            }
            return JsonNumber(s.substring(start, i))
        }
    }
}
