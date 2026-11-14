package cn.tenonai.apps.passby.core

/**
 * Draws the QR code shown beside the export code (docs/export-format.md §2.4).
 *
 * The app only ever encodes the 23 characters of a grouped export code, so this covers exactly that:
 * alphanumeric mode, version 2 (25 by 25 modules), error correction level M. It follows ISO/IEC 18004.
 * The app does not read QR codes; the unit tests check this output with a separate decoder.
 */
object Qr {
    const val SIZE = 25
    private const val ALPHANUMERIC = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"
    private const val DATA_CODEWORDS = 28
    private const val ERROR_CODEWORDS = 16

    /** Version 2-M holds up to 38 alphanumeric characters. */
    const val MAX_LENGTH = 38

    /** The modules, row by row; true is dark. The caller adds the quiet zone of four light modules. */
    fun encode(text: String): Array<BooleanArray> {
        require(text.length <= MAX_LENGTH && text.all { it in ALPHANUMERIC }) { "not alphanumeric or too long" }
        val codewords = codewords(text)
        val all = codewords + remainder(codewords, divisor(ERROR_CODEWORDS))

        val function = Array(SIZE) { BooleanArray(SIZE) }
        val base = Array(SIZE) { BooleanArray(SIZE) }
        drawFunctionPatterns(base, function)
        drawCodewords(base, function, all)

        var best: Array<BooleanArray>? = null
        var bestPenalty = Int.MAX_VALUE
        for (mask in 0 until 8) {
            val candidate = Array(SIZE) { base[it].copyOf() }
            applyMask(candidate, function, mask)
            drawFormatBits(candidate, function, mask)
            val penalty = penalty(candidate)
            if (penalty < bestPenalty) {
                best = candidate
                bestPenalty = penalty
            }
        }
        return best!!
    }

    // ---- Data ----

    private fun codewords(text: String): IntArray {
        val bits = ArrayList<Boolean>(DATA_CODEWORDS * 8)
        fun append(value: Int, length: Int) {
            for (i in length - 1 downTo 0) bits.add((value ushr i) and 1 == 1)
        }
        append(0b0010, 4) // alphanumeric mode
        append(text.length, 9) // character count, 9 bits for versions 1 to 9
        var i = 0
        while (i + 1 < text.length) {
            append(ALPHANUMERIC.indexOf(text[i]) * 45 + ALPHANUMERIC.indexOf(text[i + 1]), 11)
            i += 2
        }
        if (i < text.length) append(ALPHANUMERIC.indexOf(text[i]), 6)
        val capacity = DATA_CODEWORDS * 8
        append(0, minOf(4, capacity - bits.size)) // terminator
        append(0, (8 - bits.size % 8) % 8) // up to a whole byte
        var pad = 0xEC
        while (bits.size < capacity) {
            append(pad, 8)
            pad = pad xor 0xEC xor 0x11
        }
        return IntArray(DATA_CODEWORDS) { index ->
            var value = 0
            for (bit in 0 until 8) value = (value shl 1) or (if (bits[index * 8 + bit]) 1 else 0)
            value
        }
    }

    // ---- Reed-Solomon over GF(2^8) with the polynomial x^8 + x^4 + x^3 + x^2 + 1 ----

    private fun multiply(x: Int, y: Int): Int {
        var z = 0
        for (i in 7 downTo 0) {
            z = (z shl 1) xor ((z ushr 7) * 0x11D)
            z = z xor (((y ushr i) and 1) * x)
        }
        return z
    }

    private fun divisor(degree: Int): IntArray {
        val result = IntArray(degree)
        result[degree - 1] = 1
        var root = 1
        repeat(degree) {
            for (j in 0 until degree) {
                result[j] = multiply(result[j], root)
                if (j + 1 < degree) result[j] = result[j] xor result[j + 1]
            }
            root = multiply(root, 2)
        }
        return result
    }

    private fun remainder(data: IntArray, divisor: IntArray): IntArray {
        val result = IntArray(divisor.size)
        for (value in data) {
            val factor = value xor result[0]
            for (i in 0 until result.size - 1) result[i] = result[i + 1]
            result[result.size - 1] = 0
            for (i in result.indices) result[i] = result[i] xor multiply(divisor[i], factor)
        }
        return result
    }

    // ---- Modules. Coordinates are (x, y) with the origin at the top left; arrays are indexed [y][x]. ----

    private fun set(modules: Array<BooleanArray>, function: Array<BooleanArray>, x: Int, y: Int, dark: Boolean) {
        modules[y][x] = dark
        function[y][x] = true
    }

    private fun drawFunctionPatterns(modules: Array<BooleanArray>, function: Array<BooleanArray>) {
        // Timing patterns.
        for (i in 0 until SIZE) {
            set(modules, function, 6, i, i % 2 == 0)
            set(modules, function, i, 6, i % 2 == 0)
        }
        // Finder patterns with their separators, in three corners.
        for ((cx, cy) in listOf(3 to 3, SIZE - 4 to 3, 3 to SIZE - 4)) {
            for (dy in -4..4) {
                for (dx in -4..4) {
                    val x = cx + dx
                    val y = cy + dy
                    if (x !in 0 until SIZE || y !in 0 until SIZE) continue
                    val distance = maxOf(kotlin.math.abs(dx), kotlin.math.abs(dy))
                    set(modules, function, x, y, distance != 2 && distance != 4)
                }
            }
        }
        // Version 2 has one alignment pattern, centred on (18, 18).
        for (dy in -2..2) {
            for (dx in -2..2) {
                set(modules, function, 18 + dx, 18 + dy, maxOf(kotlin.math.abs(dx), kotlin.math.abs(dy)) != 1)
            }
        }
        // Reserve the format areas; the real bits are drawn per mask.
        drawFormatBits(modules, function, 0)
    }

    private fun drawFormatBits(modules: Array<BooleanArray>, function: Array<BooleanArray>, mask: Int) {
        // Level M is 00 in the two format bits, so the data is the mask number alone.
        val data = mask
        var rem = data
        repeat(10) { rem = (rem shl 1) xor ((rem ushr 9) * 0x537) }
        val bits = ((data shl 10) or rem) xor 0x5412
        fun bit(i: Int) = (bits ushr i) and 1 == 1

        for (i in 0..5) set(modules, function, 8, i, bit(i))
        set(modules, function, 8, 7, bit(6))
        set(modules, function, 8, 8, bit(7))
        set(modules, function, 7, 8, bit(8))
        for (i in 9 until 15) set(modules, function, 14 - i, 8, bit(i))

        for (i in 0 until 8) set(modules, function, SIZE - 1 - i, 8, bit(i))
        for (i in 8 until 15) set(modules, function, 8, SIZE - 15 + i, bit(i))
        set(modules, function, 8, SIZE - 8, true) // always dark
    }

    private fun drawCodewords(modules: Array<BooleanArray>, function: Array<BooleanArray>, data: IntArray) {
        var i = 0
        var right = SIZE - 1
        while (right >= 1) {
            if (right == 6) right = 5 // the vertical timing pattern takes column 6
            for (vertical in 0 until SIZE) {
                for (j in 0..1) {
                    val x = right - j
                    val upward = ((right + 1) and 2) == 0
                    val y = if (upward) SIZE - 1 - vertical else vertical
                    if (!function[y][x] && i < data.size * 8) {
                        modules[y][x] = (data[i ushr 3] ushr (7 - (i and 7))) and 1 == 1
                        i++
                    }
                    // The seven modules left over after the last codeword stay light.
                }
            }
            right -= 2
        }
        check(i == data.size * 8)
    }

    private fun applyMask(modules: Array<BooleanArray>, function: Array<BooleanArray>, mask: Int) {
        for (y in 0 until SIZE) {
            for (x in 0 until SIZE) {
                if (function[y][x]) continue
                val invert = when (mask) {
                    0 -> (x + y) % 2 == 0
                    1 -> y % 2 == 0
                    2 -> x % 3 == 0
                    3 -> (x + y) % 3 == 0
                    4 -> (x / 3 + y / 2) % 2 == 0
                    5 -> x * y % 2 + x * y % 3 == 0
                    6 -> (x * y % 2 + x * y % 3) % 2 == 0
                    else -> ((x + y) % 2 + x * y % 3) % 2 == 0
                }
                if (invert) modules[y][x] = !modules[y][x]
            }
        }
    }

    // ---- The standard's four penalty rules, used to pick the mask that scans best ----

    private fun penalty(modules: Array<BooleanArray>): Int {
        var result = 0
        val lines = ArrayList<BooleanArray>(SIZE * 2)
        for (y in 0 until SIZE) lines.add(modules[y])
        for (x in 0 until SIZE) lines.add(BooleanArray(SIZE) { y -> modules[y][x] })

        for (line in lines) {
            // Rule 1: five or more of the same colour in a row.
            var run = 1
            for (i in 1 until SIZE) {
                if (line[i] == line[i - 1]) {
                    run++
                    if (run == 5) result += 3 else if (run > 5) result++
                } else {
                    run = 1
                }
            }
            // Rule 3: the finder's 1:1:3:1:1 pattern with four light modules on either side.
            for (i in 0..SIZE - 11) {
                if (matches(line, i, FINDER_LIKE_A) || matches(line, i, FINDER_LIKE_B)) result += 40
            }
        }
        // Rule 2: two-by-two blocks of one colour.
        for (y in 0 until SIZE - 1) {
            for (x in 0 until SIZE - 1) {
                val colour = modules[y][x]
                if (colour == modules[y][x + 1] && colour == modules[y + 1][x] && colour == modules[y + 1][x + 1]) result += 3
            }
        }
        // Rule 4: how far the share of dark modules is from one half.
        val dark = modules.sumOf { row -> row.count { it } }
        val total = SIZE * SIZE
        val steps = (kotlin.math.abs(dark * 20 - total * 10) + total - 1) / total - 1
        result += maxOf(steps, 0) * 10
        return result
    }

    private val FINDER_LIKE_A = booleanArrayOf(true, false, true, true, true, false, true, false, false, false, false)
    private val FINDER_LIKE_B = booleanArrayOf(false, false, false, false, true, false, true, true, true, false, true)

    private fun matches(line: BooleanArray, start: Int, pattern: BooleanArray): Boolean {
        for (i in pattern.indices) if (line[start + i] != pattern[i]) return false
        return true
    }
}
