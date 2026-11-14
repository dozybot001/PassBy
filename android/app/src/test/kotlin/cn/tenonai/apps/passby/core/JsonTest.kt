package cn.tenonai.apps.passby.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class JsonTest {
    private fun rejects(text: String) {
        try {
            Json.parse(text)
            fail("expected a JsonException for: $text")
        } catch (e: JsonException) {
            // Expected.
        }
    }

    @Test
    fun readsEveryKindOfValue() {
        val value = Json.parse(""" { "a" : [1, -2.5e+3, true, false, null, "x"], "b" : { } , "c":[] } """)
        assertEquals(
            JsonObject(
                linkedMapOf(
                    "a" to JsonArray(listOf(JsonNumber("1"), JsonNumber("-2.5e+3"), JsonBool(true), JsonBool(false), JsonNull, JsonString("x"))),
                    "b" to JsonObject(emptyMap()),
                    "c" to JsonArray(emptyList()),
                ),
            ),
            value,
        )
    }

    @Test
    fun readsEscapes() {
        assertEquals(JsonString("\"\\/\b\u000C\n\r\t"), Json.parse(""""\"\\\/\b\f\n\r\t""""))
        assertEquals(JsonString("é🔑"), Json.parse(""""\u00e9\ud83d\udd11""""))
        assertEquals(JsonString("é🔑 我"), Json.parse("\"é🔑 我\""))
    }

    @Test
    fun aRepeatedNameKeepsItsLastValue() {
        assertEquals(JsonNumber("2"), Json.parse("""{"a":1,"a":2}""")["a"])
    }

    @Test
    fun rejectsWhatIsNotJson() {
        for (text in listOf(
            "", " ", "{", "[", "{\"a\"}", "{\"a\":}", "{\"a\":1,}", "[1,]", "[1 2]", "{a:1}", "{'a':1}",
            "// c\n1", "1 2", "{} x", "01", "1.", ".5", "1e", "+1", "-", "tru", "nul", "NaN", "Infinity",
            "\"abc", "\"a\nb\"", "\"\\x\"", "\"\\u12\"", "\"\\u１234\"", "\uFEFF{}",
        )) rejects(text)
    }

    @Test
    fun refusesVeryDeepNesting() {
        rejects("[".repeat(200) + "]".repeat(200))
        assertTrue(Json.parse("[".repeat(60) + "]".repeat(60)) is JsonArray)
    }

    @Test
    fun writesWhatJsonStringifyWrites() {
        val value = JsonObject(
            linkedMapOf<String, JsonValue>(
                "t" to JsonString("第一行\nsecond \"line\" \\ \t \u0001 🔑"),
                "n" to JsonNumber("1"),
                "l" to JsonArray(listOf(JsonBool(true), JsonNull)),
            ),
        )
        assertEquals("""{"t":"第一行\nsecond \"line\" \\ \t \u0001 🔑","n":1,"l":[true,null]}""", Json.write(value))
    }

    @Test
    fun aSurrogateWithoutAPartnerIsWrittenAsAnEscapeAndReadBack() {
        val text = "a\uD83Db"
        val written = Json.write(JsonString(text))
        assertEquals("\"a\\ud83db\"", written)
        assertEquals(JsonString(text), Json.parse(written))
    }

    @Test
    fun whatIsWrittenReadsBackTheSame() {
        val value = JsonObject(linkedMapOf<String, JsonValue>("k\"ey" to JsonArray(listOf(JsonString("\u0000\u001F/\u2028"), JsonNumber("-0.5E-7")))))
        assertEquals(value, Json.parse(Json.write(value)))
    }
}
