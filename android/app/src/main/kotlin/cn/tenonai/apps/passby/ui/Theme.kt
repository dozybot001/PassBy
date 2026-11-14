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

/** Scheme A, "kraft paper with a vermilion margin" (docs/local-notebook.md §7). The same five colours as iPhone. */
data class Palette(
    val paper: Color,
    val ink: Color,
    val secondary: Color,
    val rule: Color,
    val accent: Color,
    /** Between paper and rule, for raised surfaces such as dialogs and menus. */
    val raised: Color,
) {
    /** The fill of chips and round icon buttons. */
    val wash: Color get() = rule.copy(alpha = 0.55f)
}

private val Light = Palette(
    paper = Color(0xFFF4ECDB),
    ink = Color(0xFF2A241C),
    secondary = Color(0xFF6B6152),
    rule = Color(0xFFE2D5BC),
    accent = Color(0xFFA63F28),
    raised = Color(0xFFEDE3CE),
)

private val Dark = Palette(
    paper = Color(0xFF1C1915),
    ink = Color(0xFFEFE7D6),
    secondary = Color(0xFFA89D8B),
    rule = Color(0xFF3A332A),
    accent = Color(0xFFE58A6E),
    raised = Color(0xFF29241E),
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
            primary = p.accent, onPrimary = p.paper, primaryContainer = p.rule, onPrimaryContainer = p.ink,
            inversePrimary = other.accent,
            secondary = p.ink, onSecondary = p.paper, secondaryContainer = p.rule, onSecondaryContainer = p.ink,
            tertiary = p.accent, onTertiary = p.paper, tertiaryContainer = p.rule, onTertiaryContainer = p.ink,
            background = p.paper, onBackground = p.ink, surface = p.paper, onSurface = p.ink,
            surfaceVariant = p.rule, onSurfaceVariant = p.secondary, surfaceTint = p.ink,
            inverseSurface = p.ink, inverseOnSurface = p.paper,
            error = p.accent, onError = p.paper, errorContainer = p.rule, onErrorContainer = p.ink,
            outline = p.secondary, outlineVariant = p.rule, scrim = Color.Black,
            surfaceBright = p.raised, surfaceDim = p.paper,
            surfaceContainerLowest = p.paper, surfaceContainerLow = p.paper, surfaceContainer = p.raised,
            surfaceContainerHigh = p.raised, surfaceContainerHighest = p.rule,
        )
    } else {
        lightColorScheme(
            primary = p.accent, onPrimary = p.paper, primaryContainer = p.rule, onPrimaryContainer = p.ink,
            inversePrimary = other.accent,
            secondary = p.ink, onSecondary = p.paper, secondaryContainer = p.rule, onSecondaryContainer = p.ink,
            tertiary = p.accent, onTertiary = p.paper, tertiaryContainer = p.rule, onTertiaryContainer = p.ink,
            background = p.paper, onBackground = p.ink, surface = p.paper, onSurface = p.ink,
            surfaceVariant = p.rule, onSurfaceVariant = p.secondary, surfaceTint = p.ink,
            inverseSurface = p.ink, inverseOnSurface = p.paper,
            error = p.accent, onError = p.paper, errorContainer = p.rule, onErrorContainer = p.ink,
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
