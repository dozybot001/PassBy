package cn.tenonai.apps.passby.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import cn.tenonai.apps.passby.R
import cn.tenonai.apps.passby.core.Folder
import cn.tenonai.apps.passby.core.Notebook
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** Adding, renaming and deleting folders. Deleting a folder keeps its passwords; they become Unfiled. */
@Composable
fun FoldersScreen(model: AppViewModel, notebook: Notebook) {
    var adding by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf<Folder?>(null) }
    var deleting by remember { mutableStateOf<Folder?>(null) }

    Page(
        title = stringResource(R.string.folders),
        onBack = { model.back() },
        actions = {
            IconButton(onClick = { adding = true }) { Icon(Icons.Plus, contentDescription = stringResource(R.string.new_folder)) }
        },
    ) {
        if (notebook.folders.isEmpty()) {
            EmptyState(stringResource(R.string.no_folders), stringResource(R.string.no_folders_text), Modifier.weight(1f))
        } else {
            LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(vertical = 8.dp)) {
                items(notebook.folders, key = { it.id }) { folder ->
                    var menu by remember { mutableStateOf(false) }
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(start = PagePadding, end = PagePadding - 12.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Folder, contentDescription = null, tint = palette.secondary)
                        Spacer(Modifier.width(14.dp))
                        Text(folder.name, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(
                            stringResource(R.string.folder_count, notebook.entries.count { it.folderId == folder.id }),
                            style = MaterialTheme.typography.bodyMedium,
                            color = palette.secondary,
                        )
                        Box {
                            IconButton(onClick = { menu = true }) { Icon(Icons.More, contentDescription = stringResource(R.string.more)) }
                            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.rename_folder)) },
                                    onClick = {
                                        menu = false
                                        renaming = folder
                                    },
                                )
                                DropdownMenuItem(
                                    text = { Text(stringResource(R.string.delete_folder)) },
                                    onClick = {
                                        menu = false
                                        deleting = folder
                                    },
                                )
                            }
                        }
                    }
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = PagePadding, vertical = 12.dp)) {
            PrimaryButton(stringResource(R.string.new_folder), onClick = { adding = true }, modifier = Modifier.weight(1f), icon = Icons.Plus)
        }
    }

    if (adding) {
        TextPromptDialog(
            title = stringResource(R.string.new_folder),
            label = stringResource(R.string.folder_name),
            initial = "",
            onSave = { name ->
                adding = false
                model.addFolder(name)
            },
            onDismiss = { adding = false },
        )
    }
    renaming?.let { folder ->
        TextPromptDialog(
            title = stringResource(R.string.rename_folder),
            label = stringResource(R.string.folder_name),
            initial = folder.name,
            onSave = { name ->
                renaming = null
                model.renameFolder(folder.id, name)
            },
            onDismiss = { renaming = null },
        )
    }
    deleting?.let { folder ->
        ConfirmDialog(
            title = stringResource(R.string.delete_folder_title),
            text = stringResource(R.string.delete_folder_text),
            confirm = stringResource(R.string.delete_folder),
            onConfirm = {
                deleting = null
                model.removeFolder(folder.id)
            },
            onDismiss = { deleting = null },
        )
    }
}

/** Passwords the person deleted in the last 30 days. Each can be put back, or deleted for good after a confirmation. */
@Composable
fun DeletedScreen(model: AppViewModel, notebook: Notebook) {
    var removing by remember { mutableStateOf<String?>(null) }
    val time = remember { DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm").withZone(ZoneId.systemDefault()) }

    Page(title = stringResource(R.string.recently_deleted), onBack = { model.back() }) {
        Text(
            stringResource(R.string.deleted_note),
            Modifier.padding(horizontal = PagePadding, vertical = 8.dp),
            style = MaterialTheme.typography.bodyMedium,
            color = palette.secondary,
        )
        if (notebook.deleted.isEmpty()) {
            EmptyState(stringResource(R.string.deleted_empty), "", Modifier.weight(1f))
        } else {
            LazyColumn(Modifier.weight(1f).fillMaxSize(), contentPadding = PaddingValues(vertical = 8.dp)) {
                // Most recently deleted first.
                items(notebook.deleted.sortedByDescending { it.deletedAt }, key = { it.entry.id }) { item ->
                    Row(
                        Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(start = PagePadding, end = PagePadding - 12.dp, top = 6.dp, bottom = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(Modifier.weight(1f)) {
                            Text(item.entry.title, style = MaterialTheme.typography.bodyLarge, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (item.entry.account.isNotEmpty()) {
                                Text(item.entry.account, style = MaterialTheme.typography.bodyMedium, color = palette.secondary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            }
                            Text(
                                stringResource(R.string.deleted_on, time.format(Instant.ofEpochMilli(item.deletedAt))),
                                style = MaterialTheme.typography.bodySmall,
                                color = palette.secondary,
                            )
                        }
                        IconButton(onClick = { model.restoreDeleted(item.entry.id) }) {
                            Icon(Icons.Restore, contentDescription = stringResource(R.string.restore_password))
                        }
                        IconButton(onClick = { removing = item.entry.id }) {
                            Icon(Icons.Trash, contentDescription = stringResource(R.string.delete_now))
                        }
                    }
                }
            }
        }
    }

    removing?.let { id ->
        ConfirmDialog(
            title = stringResource(R.string.delete_now_title),
            text = stringResource(R.string.delete_now_text),
            confirm = stringResource(R.string.delete_now),
            onConfirm = {
                removing = null
                model.removeDeleted(id)
            },
            onDismiss = { removing = null },
        )
    }
}
