package cn.tenonai.apps.passby.core

import java.security.SecureRandom

/** The same choices and character sets as the iPhone app. */
data class PasswordOptions(
    val length: Int = 16,
    val lowercase: Boolean = true,
    val uppercase: Boolean = true,
    val digits: Boolean = true,
    val symbols: Boolean = true,
) {
    val alphabets: List<String>
        get() = buildList {
            if (lowercase) add("abcdefghijklmnopqrstuvwxyz")
            if (uppercase) add("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
            if (digits) add("0123456789")
            if (symbols) add("!@#\$%^&*()-_=+[]{}:,.?")
        }

    val isValid: Boolean get() = length in LENGTHS && alphabets.isNotEmpty()

    companion object {
        /** What can be typed. */
        val LENGTHS = 8..4096

        /** What the slider covers. */
        val COMMON_LENGTHS = 8..24
    }
}

object PasswordGenerator {
    /**
     * One character from every chosen set, the rest from all of them, then shuffled.
     * SecureRandom.nextInt(bound) rejects and redraws, so no character is favoured.
     */
    fun generate(options: PasswordOptions, random: SecureRandom = SecureRandom()): String {
        require(options.isValid)
        val alphabets = options.alphabets
        val pool = alphabets.joinToString("")
        val chars = CharArray(options.length)
        alphabets.forEachIndexed { index, alphabet -> chars[index] = alphabet[random.nextInt(alphabet.length)] }
        for (index in alphabets.size until chars.size) chars[index] = pool[random.nextInt(pool.length)]
        for (index in chars.lastIndex downTo 1) {
            val other = random.nextInt(index + 1)
            val held = chars[index]
            chars[index] = chars[other]
            chars[other] = held
        }
        return String(chars)
    }
}
