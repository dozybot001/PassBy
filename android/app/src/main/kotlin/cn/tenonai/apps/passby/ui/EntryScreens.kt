package cn.tenonai.apps.passby.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import cn.tenonai.apps.passby.R
import cn.tenonai.apps.passby.core.Entry
import cn.tenonai.apps.passby.core.Notebook

/** One password in full. The password is hidden until the eye is tapped, and hidden again on leaving. */
@Composable
fun EntryDetailScreen(model: AppViewModel, notebook: Notebook, id: String) {
    val entry = notebook.entries.firstOrNull { it.id == id }
    var revealed by remember(id) { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }

    Page(title = "", onBack = { model.back() }) {
        if (entry == null) {
            EmptyState(stringResource(R.string.password_removed), "")
            return@Page
        }
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = PagePadding, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(24.dp),
        ) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(entry.title, style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.SemiBold)
                notebook.folder(entry.folderId)?.let { folder ->
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Icon(Icons.Folder, contentDescription = stringResource(R.string.folder), Modifier.size(18.dp), tint = palette.secondary)
                        Text(folder.name, style = MaterialTheme.typography.bodyMedium, color = palette.secondary)
                    }
                }
            }
            Credential(
                label = stringResource(R.string.account),
                value = entry.account,
                copyLabel = stringResource(R.string.copy_account),
                onCopy = { model.copyAccount(entry) },
            )
            Credential(
                label = stringResource(R.string.password),
                value = entry.password,
                copyLabel = stringResource(R.string.copy_password),
                onCopy = { model.copyPassword(entry) },
                secret = true,
                revealed = revealed,
                onReveal = { revealed = !revealed },
            )
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SectionLabel(stringResource(R.string.notes))
                Text(
                    entry.notes.ifEmpty { stringResource(R.string.no_notes) },
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (entry.notes.isEmpty()) palette.secondary else palette.ink,
                )
            }
        }
        Row(
            Modifier.fillMaxWidth().padding(horizontal = PagePadding, vertical = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            SecondaryButton(stringResource(R.string.delete), onClick = { confirmDelete = true }, icon = Icons.Trash)
            PrimaryButton(stringResource(R.string.edit), onClick = { model.editEntry(entry) }, modifier = Modifier.weight(1f), icon = Icons.Pencil)
        }
    }

    if (confirmDelete && entry != null) {
        ConfirmDialog(
            title = stringResource(R.string.delete_password_title),
            text = stringResource(R.string.delete_password_text),
            confirm = stringResource(R.string.delete_password),
            onConfirm = {
                confirmDelete = false
                model.deleteEntry(entry.id)
            },
            onDismiss = { confirmDelete = false },
            icon = Icons.Trash,
        )
    }
}

@Composable
private fun Credential(
    label: String,
    value: String,
    copyLabel: String,
    onCopy: () -> Unit,
    secret: Boolean = false,
    revealed: Boolean = true,
    onReveal: () -> Unit = {},
) {
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        SectionLabel(label)
        Row(verticalAlignment = Alignment.CenterVertically) {
            val hidden = secret && !revealed && value.isNotEmpty()
            val hiddenLabel = stringResource(R.string.password_hidden)
            Text(
                when {
                    value.isEmpty() -> stringResource(R.string.not_added)
                    hidden -> "••••••••••••"
                    else -> value
                },
                Modifier.weight(1f).then(if (hidden) Modifier.semantics { contentDescription = hiddenLabel } else Modifier),
                style = MaterialTheme.typography.bodyLarge,
                fontFamily = if (secret) FontFamily.Monospace else null,
                color = if (value.isEmpty()) palette.secondary else palette.ink,
            )
            if (secret) {
                IconButton(onClick = onReveal, enabled = value.isNotEmpty()) {
                    Icon(
                        if (revealed) Icons.EyeOff else Icons.Eye,
                        contentDescription = stringResource(if (revealed) R.string.hide_password else R.string.show_password),
                    )
                }
            }
            IconButton(onClick = onCopy, enabled = value.isNotEmpty()) { Icon(Icons.Copy, contentDescription = copyLabel) }
        }
        HorizontalDivider(color = palette.rule)
    }
}

/**
 * Writing or changing one password. The close button discards what was typed, after asking when
 * there is something to lose. Leaving any other way, including switching apps, keeps it as a draft
 * that New password opens again.
 */
@Composable
fun EntryEditorScreen(model: AppViewModel, notebook: Notebook) {
    val entry = model.editing ?: return
    var revealed by remember { mutableStateOf(false) }
    var folderMenu by remember { mutableStateOf(false) }
    var newFolder by remember { mutableStateOf(false) }
    var confirmDiscard by remember { mutableStateOf(false) }
    val saved = notebook.entries.firstOrNull { it.id == entry.id }
    val changed = if (saved != null) !entry.sameContent(saved) else !entry.sameContent(Entry(entry.id, folderId = entry.folderId))

    Page(
        title = stringResource(if (model.editingIsNew) R.string.new_password else R.string.edit_password),
        onBack = { if (changed) confirmDiscard = true else model.cancelEditing() },
        backIcon = Icons.Close,
        backLabel = stringResource(R.string.cancel),
    ) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = PagePadding, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            OutlinedTextField(
                value = entry.title,
                onValueChange = { model.updateEditing(entry.copy(title = it)) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.title)) },
                placeholder = { Text(stringResource(R.string.title_hint)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            )
            OutlinedTextField(
                value = entry.account,
                onValueChange = { model.updateEditing(entry.copy(account = it)) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.account)) },
                placeholder = { Text(stringResource(R.string.account_hint)) },
                singleLine = true,
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    autoCorrectEnabled = false,
                    keyboardType = KeyboardType.Email,
                ),
            )
            OutlinedTextField(
                value = entry.password,
                onValueChange = { model.updateEditing(entry.copy(password = it)) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.password)) },
                singleLine = true,
                textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                visualTransformation = if (revealed) VisualTransformation.None else PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    autoCorrectEnabled = false,
                    keyboardType = KeyboardType.Password,
                ),
                trailingIcon = {
                    Row {
                        IconButton(onClick = { model.open(Screen.Generator(forEditor = true)) }) {
                            Icon(Icons.Dice, contentDescription = stringResource(R.string.generator_open))
                        }
                        IconButton(onClick = { revealed = !revealed }) {
                            Icon(
                                if (revealed) Icons.EyeOff else Icons.Eye,
                                contentDescription = stringResource(if (revealed) R.string.hide_password else R.string.show_password),
                            )
                        }
                    }
                },
            )
            OutlinedTextField(
                value = entry.notes,
                onValueChange = { model.updateEditing(entry.copy(notes = it)) },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.notes)) },
                minLines = 4,
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Sentences),
            )

            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                SectionLabel(stringResource(R.string.folder))
                Box {
                    Row(
                        Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .clickable(role = Role.DropdownList) { folderMenu = true }
                            .heightIn(min = 56.dp)
                            .padding(horizontal = 16.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Folder, contentDescription = null, tint = palette.secondary)
                        Spacer(Modifier.size(12.dp))
                        Text(
                            notebook.folder(entry.folderId)?.name ?: stringResource(R.string.filter_unfiled),
                            Modifier.weight(1f),
                            style = MaterialTheme.typography.bodyLarge,
                        )
                        Icon(Icons.Chevron, contentDescription = null, tint = palette.secondary)
                    }
                    DropdownMenu(expanded = folderMenu, onDismissRequest = { folderMenu = false }) {
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.filter_unfiled)) },
                            trailingIcon = { if (entry.folderId == null) Icon(Icons.Check, contentDescription = null) },
                            onClick = {
                                folderMenu = false
                                model.updateEditing(entry.copy(folderId = null))
                            },
                        )
                        for (folder in notebook.folders) {
                            DropdownMenuItem(
                                text = { Text(folder.name) },
                                leadingIcon = { Icon(Icons.Folder, contentDescription = null) },
                                trailingIcon = { if (entry.folderId == folder.id) Icon(Icons.Check, contentDescription = null) },
                                onClick = {
                                    folderMenu = false
                                    model.updateEditing(entry.copy(folderId = folder.id))
                                },
                            )
                        }
                        HorizontalDivider(color = palette.rule)
                        DropdownMenuItem(
                            text = { Text(stringResource(R.string.new_folder)) },
                            leadingIcon = { Icon(Icons.Plus, contentDescription = null) },
                            onClick = {
                                folderMenu = false
                                newFolder = true
                            },
                        )
                    }
                }
                HorizontalDivider(color = palette.rule)
            }

            Text(stringResource(R.string.draft_note), style = MaterialTheme.typography.bodySmall, color = palette.secondary)
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = PagePadding, vertical = 12.dp)) {
            PrimaryButton(
                stringResource(R.string.save),
                onClick = model::saveEditing,
                modifier = Modifier.weight(1f),
                enabled = entry.title.isNotBlank(),
                icon = Icons.Check,
            )
        }
    }

    if (confirmDiscard) {
        ConfirmDialog(
            title = stringResource(R.string.discard_title),
            text = stringResource(if (saved != null) R.string.discard_text_changes else R.string.discard_text_new),
            confirm = stringResource(R.string.discard),
            onConfirm = {
                confirmDiscard = false
                model.cancelEditing()
            },
            onDismiss = { confirmDiscard = false },
            dismiss = stringResource(R.string.keep_editing),
        )
    }

    if (newFolder) {
        TextPromptDialog(
            title = stringResource(R.string.new_folder),
            label = stringResource(R.string.folder_name),
            initial = "",
            onSave = { name ->
                newFolder = false
                // The folder is chosen for this entry once it has been saved.
                model.addFolder(name) { id -> model.editing?.let { model.updateEditing(it.copy(folderId = id)) } }
            },
            onDismiss = { newFolder = false },
        )
    }
}
