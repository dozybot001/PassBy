package cn.tenonai.apps.passby.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color

/**
 * Black, white and gray (AGENTS.md), the colours the web version uses. There is no
 * accent colour: what stands out does so by being ink on paper.
 */
data class Palette(
    val paper: Color,
    val ink: Color,
    val secondary: Color,
    val rule: Color,
    /** The fill of the filled button and the chosen chip, and what is written on it. */
    val button: Color,
    val onButton: Color,
    /** Between paper and rule, for raised surfaces such as dialogs and menus. */
    val raised: Color,
) {
    /** The fill of chips, round icon buttons and the circle behind a row's initial: rule at 40% over paper, as on iPhone. */
    val wash: Color get() = rule.copy(alpha = 0.4f)
}

private val Light = Palette(
    paper = Color(0xFFFAFAFA),
    ink = Color(0xFF141414),
    secondary = Color(0xFF6B6B6B),
    rule = Color(0xFFDDDDDD),
    button = Color(0xFF171717),
    onButton = Color(0xFFFFFFFF),
    raised = Color(0xFFEFEFEF),
)

private val Dark = Palette(
    paper = Color(0xFF080808),
    ink = Color(0xFFF6F6F6),
    secondary = Color(0xFF9A9A9A),
    rule = Color(0xFF333333),
    button = Color(0xFFF6F6F6),
    onButton = Color(0xFF111111),
    raised = Color(0xFF171717),
)

private val LocalPalette = staticCompositionLocalOf { Light }

val palette: Palette
    @Composable @ReadOnlyComposable get() = LocalPalette.current

/** Follows the system's light or dark appearance. Material's dynamic colours are not used. */
@Composable
fun PassByTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val p = if (dark) Dark else Light
    val other = if (dark) Light else Dark
    val scheme = if (dark) {
        darkColorScheme(
            primary = p.ink, onPrimary = p.paper, primaryContainer = p.rule, onPrimaryContainer = p.ink,
            inversePrimary = other.ink,
            secondary = p.ink, onSecondary = p.paper, secondaryContainer = p.rule, onSecondaryContainer = p.ink,
            tertiary = p.ink, onTertiary = p.paper, tertiaryContainer = p.rule, onTertiaryContainer = p.ink,
            background = p.paper, onBackground = p.ink, surface = p.paper, onSurface = p.ink,
            surfaceVariant = p.rule, onSurfaceVariant = p.secondary, surfaceTint = p.ink,
            inverseSurface = p.ink, inverseOnSurface = p.paper,
            error = p.ink, onError = p.paper, errorContainer = p.rule, onErrorContainer = p.ink,
            outline = p.secondary, outlineVariant = p.rule, scrim = Color.Black,
            surfaceBright = p.raised, surfaceDim = p.paper,
            surfaceContainerLowest = p.paper, surfaceContainerLow = p.paper, surfaceContainer = p.raised,
            surfaceContainerHigh = p.raised, surfaceContainerHighest = p.rule,
        )
    } else {
        lightColorScheme(
            primary = p.ink, onPrimary = p.paper, primaryContainer = p.rule, onPrimaryContainer = p.ink,
            inversePrimary = other.ink,
            secondary = p.ink, onSecondary = p.paper, secondaryContainer = p.rule, onSecondaryContainer = p.ink,
            tertiary = p.ink, onTertiary = p.paper, tertiaryContainer = p.rule, onTertiaryContainer = p.ink,
            background = p.paper, onBackground = p.ink, surface = p.paper, onSurface = p.ink,
            surfaceVariant = p.rule, onSurfaceVariant = p.secondary, surfaceTint = p.ink,
            inverseSurface = p.ink, inverseOnSurface = p.paper,
            error = p.ink, onError = p.paper, errorContainer = p.rule, onErrorContainer = p.ink,
            outline = p.secondary, outlineVariant = p.rule, scrim = Color.Black,
            surfaceBright = p.paper, surfaceDim = p.raised,
            surfaceContainerLowest = p.paper, surfaceContainerLow = p.paper, surfaceContainer = p.raised,
            surfaceContainerHigh = p.raised, surfaceContainerHighest = p.rule,
        )
    }
    CompositionLocalProvider(LocalPalette provides p) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
