package cn.tenonai.apps.passby.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import cn.tenonai.apps.passby.R

/** Side padding of every page. */
val PagePadding = 24.dp

/** The PassBy mark: a margin line and three lines of writing, the shapes of the launcher icon. */
@Composable
fun BrandMark(size: Dp, modifier: Modifier = Modifier, color: Color = palette.accent) {
    Canvas(modifier.size(size)) {
        // The bars sit in a 56-unit square whose origin is (22, 22) on the icon's 100-unit canvas.
        val unit = this.size.minDimension / 56f
        fun bar(x: Float, y: Float, w: Float, h: Float, alpha: Float = 1f) {
            drawRoundRect(
                color = color.copy(alpha = color.alpha * alpha),
                topLeft = Offset((x - 22f) * unit, (y - 22f) * unit),
                size = Size(w * unit, h * unit),
                cornerRadius = CornerRadius(3.25f * unit),
            )
        }
        bar(28.25f, 27f, 6.5f, 46f)
        bar(43.75f, 33.25f, 28f, 6.5f)
        bar(43.75f, 46.75f, 22f, 6.5f)
        bar(43.75f, 60.25f, 15f, 6.5f, alpha = 0.4f)
    }
}

/**
 * The full logo: mark, wordmark, and the Tenon mark at the upper right of the wordmark, with the
 * proportions the product standard gives (§1.2 to §1.5). Read out as one name.
 */
@Composable
fun BrandLockup(wordmarkSize: Int, modifier: Modifier = Modifier) {
    val s = wordmarkSize
    val description = stringResource(R.string.brand_description)
    Row(
        modifier.clearAndSetSemantics {
            contentDescription = description
            heading()
        },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        BrandMark(size = s.dp)
        Spacer(Modifier.width((s * 0.3f).dp))
        Row(verticalAlignment = Alignment.Top) {
            Text(
                stringResource(R.string.app_name),
                fontSize = s.sp,
                fontWeight = FontWeight.SemiBold,
                letterSpacing = (-0.02f).em,
                color = palette.ink,
                maxLines = 1,
            )
            Spacer(Modifier.width(maxOf(4f, s * 0.18f).dp))
            Image(
                painterResource(R.drawable.tenon_mark),
                contentDescription = null,
                modifier = Modifier.offset(y = (-s * 0.04f).dp).size(maxOf(14f, s * 0.58f).dp),
            )
        }
    }
}

/** A page under the list: a bar with a back button, a title and optional actions, then the content. */
@Composable
fun Page(
    title: String,
    onBack: () -> Unit,
    backIcon: ImageVector = Icons.Back,
    backLabel: String = stringResource(R.string.back),
    actions: @Composable RowScope.() -> Unit = {},
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) { Icon(backIcon, contentDescription = backLabel) }
            Text(
                title,
                Modifier.weight(1f).padding(horizontal = 8.dp).semantics { heading() },
                style = MaterialTheme.typography.titleLarge,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            actions()
        }
        content()
    }
}

/** A round button holding one icon, as on iPhone. The touch target is at least 48 dp. */
@Composable
fun RoundIconButton(icon: ImageVector, label: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    IconButton(
        onClick = onClick,
        modifier = modifier,
        enabled = enabled,
        colors = IconButtonDefaults.iconButtonColors(containerColor = palette.wash, contentColor = palette.ink),
    ) {
        Icon(icon, contentDescription = label)
    }
}

/** The one filled button on a page. */
@Composable
fun PrimaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, icon: ImageVector? = null) {
    Button(
        onClick = onClick,
        modifier = modifier.heightIn(min = 48.dp),
        enabled = enabled,
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(containerColor = palette.ink, contentColor = palette.paper),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 8.dp),
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, Modifier.size(20.dp))
            Spacer(Modifier.width(8.dp))
        }
        Text(text, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
fun SecondaryButton(text: String, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true, icon: ImageVector? = null) {
    Button(
        onClick = onClick,
        modifier = modifier.heightIn(min = 48.dp),
        enabled = enabled,
        shape = CircleShape,
        colors = ButtonDefaults.buttonColors(containerColor = palette.wash, contentColor = palette.ink),
        contentPadding = PaddingValues(horizontal = 20.dp, vertical = 8.dp),
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, Modifier.size(20.dp))
            Spacer(Modifier.width(8.dp))
        }
        Text(text, fontWeight = FontWeight.Medium)
    }
}

/** A lesser action shown as an icon and words without a filled shape. */
@Composable
fun LinkButton(text: String, icon: ImageVector, onClick: () -> Unit, modifier: Modifier = Modifier, enabled: Boolean = true) {
    TextButton(onClick = onClick, modifier = modifier.heightIn(min = 48.dp), enabled = enabled) {
        Icon(icon, contentDescription = null, Modifier.size(20.dp))
        Spacer(Modifier.width(8.dp))
        Text(text)
    }
}

/** A filter chip: a name and how many passwords it holds. The chosen one is filled with ink. */
@Composable
fun CountChip(name: String, count: Int, selected: Boolean, onClick: () -> Unit) {
    val content = if (selected) palette.paper else palette.ink
    Row(
        Modifier
            .heightIn(min = 48.dp)
            .padding(vertical = 4.dp)
            .clip(CircleShape)
            .background(if (selected) palette.ink else palette.wash)
            .selectable(selected = selected, role = Role.Tab, onClick = onClick)
            .padding(horizontal = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        Text(name, color = content, style = MaterialTheme.typography.labelLarge, maxLines = 1)
        Text(count.toString(), color = content.copy(alpha = 0.75f), style = MaterialTheme.typography.labelMedium)
    }
}

/** The small heading above a group of fields or rows. */
@Composable
fun SectionLabel(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        modifier.semantics { heading() },
        style = MaterialTheme.typography.labelLarge,
        color = palette.secondary,
    )
}

/** A row in a settings list. With [onClick] the whole row is one button. */
@Composable
fun SettingRow(
    title: String,
    modifier: Modifier = Modifier,
    text: String? = null,
    icon: ImageVector? = null,
    onClick: (() -> Unit)? = null,
    trailing: @Composable (() -> Unit)? = null,
) {
    Row(
        modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier)
            .heightIn(min = 56.dp)
            .padding(horizontal = PagePadding, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = palette.secondary)
            Spacer(Modifier.width(16.dp))
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            if (text != null) {
                Text(text, style = MaterialTheme.typography.bodyMedium, color = palette.secondary)
            }
        }
        if (trailing != null) {
            Spacer(Modifier.width(12.dp))
            trailing()
        } else if (onClick != null) {
            Icon(Icons.Chevron, contentDescription = null, tint = palette.secondary)
        }
    }
}

/** A notice in the middle of an otherwise empty page: what is the case, and what to do next. */
@Composable
fun EmptyState(title: String, text: String, modifier: Modifier = Modifier) {
    Box(modifier.fillMaxSize().padding(PagePadding), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(title, style = MaterialTheme.typography.titleMedium, textAlign = TextAlign.Center)
            if (text.isNotEmpty()) {
                Text(text, style = MaterialTheme.typography.bodyMedium, color = palette.secondary, textAlign = TextAlign.Center)
            }
        }
    }
}

@Composable
fun ConfirmDialog(
    title: String,
    text: String,
    confirm: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
    dismiss: String = stringResource(R.string.cancel),
    icon: ImageVector? = null,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        icon = icon?.let { { Icon(it, contentDescription = null) } },
        title = { Text(title) },
        text = { Text(text) },
        confirmButton = { TextButton(onClick = onConfirm) { Text(confirm) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(dismiss) } },
    )
}

/** Asks for one line of text, such as a folder name. Save is off while the text is blank. */
@Composable
fun TextPromptDialog(title: String, label: String, initial: String, onSave: (String) -> Unit, onDismiss: () -> Unit) {
    var value by remember { mutableStateOf(initial) }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = {
            OutlinedTextField(
                value = value,
                onValueChange = { value = it },
                modifier = Modifier.focusRequester(focus),
                label = { Text(label) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            )
        },
        confirmButton = {
            TextButton(onClick = { onSave(value.trim()) }, enabled = value.isNotBlank()) { Text(stringResource(R.string.save)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}
