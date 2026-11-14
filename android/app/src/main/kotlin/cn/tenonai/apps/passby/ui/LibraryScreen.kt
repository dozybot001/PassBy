package cn.tenonai.apps.passby.ui

import android.icu.text.Collator
import android.icu.text.RuleBasedCollator
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
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
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.DpOffset
import androidx.compose.ui.unit.dp
import cn.tenonai.apps.passby.R
import cn.tenonai.apps.passby.core.Entry
import cn.tenonai.apps.passby.core.Notebook

/** The first page: every password, filtered by folder or search. Tapping a row copies its password. */
@Composable
fun LibraryScreen(model: AppViewModel, notebook: Notebook) {
    // A folder that was the filter and has since been deleted falls back to everything.
    LaunchedEffect(notebook.folders, model.filter) {
        val filter = model.filter
        if (filter != "" && filter != AppViewModel.UNFILED && notebook.folder(filter) == null) model.filter = ""
    }
    val collator = remember {
        // Titles sort the way the person's language sorts them, with numbers in numeric order.
        val base = Collator.getInstance()
        if (base is RuleBasedCollator) {
            base.numericCollation = true
        }
        base.strength = Collator.SECONDARY
        base
    }
    val keyboard = LocalSoftwareKeyboardController.current
    val query = if (model.searching) model.query.trim() else ""
    val entries = remember(notebook.entries, model.filter, query) {
        notebook.entries
            .filter { entry ->
                when (model.filter) {
                    "" -> true
                    AppViewModel.UNFILED -> entry.folderId == null
                    else -> entry.folderId == model.filter
                }
            }
            .filter { query.isEmpty() || it.title.contains(query, ignoreCase = true) || it.account.contains(query, ignoreCase = true) }
            .sortedWith { a, b -> collator.compare(a.title, b.title) }
    }

    Column(Modifier.fillMaxSize()) {
        Row(
            Modifier.fillMaxWidth().padding(start = PagePadding, end = PagePadding - 8.dp, top = 20.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            BrandLockup(wordmarkSize = 26, modifier = Modifier.weight(1f))
            RoundIconButton(Icons.Search, stringResource(if (model.searching) R.string.search_close else R.string.search_open), onClick = {
                model.searching = !model.searching
                if (!model.searching) {
                    model.query = ""
                    // Older Android versions leave the keyboard up when the field it was typing into goes away.
                    keyboard?.hide()
                }
            })
            Spacer(Modifier.width(4.dp))
            RoundIconButton(Icons.Dice, stringResource(R.string.generator_open), onClick = { model.open(Screen.Generator(forEditor = false)) })
            Spacer(Modifier.width(4.dp))
            RoundIconButton(Icons.Sliders, stringResource(R.string.settings), onClick = { model.open(Screen.Settings) })
        }

        val now = remember(notebook) { System.currentTimeMillis() }
        if (notebook.shouldRemindToExport(now)) ExportReminder(model, neverExported = notebook.lastExportAt == null)

        if (model.searching) {
            SearchField(model)
        } else {
            LazyRow(
                contentPadding = PaddingValues(horizontal = PagePadding),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                item {
                    CountChip(stringResource(R.string.filter_all), notebook.entries.size, model.filter == "") { model.filter = "" }
                }
                item {
                    CountChip(
                        stringResource(R.string.filter_unfiled),
                        notebook.entries.count { it.folderId == null },
                        model.filter == AppViewModel.UNFILED,
                    ) { model.filter = AppViewModel.UNFILED }
                }
                items(notebook.folders, key = { it.id }) { folder ->
                    CountChip(folder.name, notebook.entries.count { it.folderId == folder.id }, model.filter == folder.id) { model.filter = folder.id }
                }
            }
        }

        Box(Modifier.weight(1f).fillMaxWidth()) {
            if (entries.isEmpty()) {
                if (query.isEmpty()) {
                    EmptyState(stringResource(R.string.empty_title), stringResource(R.string.empty_text))
                } else {
                    EmptyState(stringResource(R.string.no_match_title), stringResource(R.string.no_match_text))
                }
            } else {
                LazyColumn(Modifier.fillMaxSize(), contentPadding = PaddingValues(vertical = 8.dp)) {
                    items(entries, key = { it.id }) { entry -> EntryRow(model, entry) }
                }
            }
        }

        Row(
            Modifier.fillMaxWidth().padding(horizontal = PagePadding, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            RoundIconButton(Icons.Folder, stringResource(R.string.manage_folders), onClick = { model.open(Screen.Folders) })
            PrimaryButton(
                stringResource(R.string.new_password),
                onClick = {
                    val filter = model.filter
                    model.newEntry(if (filter == "" || filter == AppViewModel.UNFILED) null else filter)
                },
                modifier = Modifier.weight(1f),
                icon = Icons.Plus,
            )
        }
    }
}

/**
 * One password in the list. A tap copies the password; the button at the end copies the account; a
 * long press opens the menu with both and View. Screen readers get the same three as custom actions.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun EntryRow(model: AppViewModel, entry: Entry) {
    var menu by remember { mutableStateOf(false) }
    val copyAccount = stringResource(R.string.copy_account)
    val copyPassword = stringResource(R.string.copy_password)
    val view = stringResource(R.string.view)
    Box {
        Row(
            Modifier
                .fillMaxWidth()
                .combinedClickable(
                    onClickLabel = copyPassword,
                    onLongClickLabel = stringResource(R.string.more),
                    onClick = { model.copyPassword(entry, offerView = true) },
                    onLongClick = { menu = true },
                )
                .semantics {
                    customActions = listOf(
                        CustomAccessibilityAction(view) {
                            model.open(Screen.Detail(entry.id))
                            true
                        },
                        CustomAccessibilityAction(copyAccount) {
                            model.copyAccount(entry)
                            true
                        },
                    )
                }
                .padding(start = PagePadding, end = PagePadding - 12.dp, top = 8.dp, bottom = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.size(44.dp).clip(CircleShape).background(palette.wash), contentAlignment = Alignment.Center) {
                Text(
                    entry.title.trim().take(1).uppercase(),
                    color = palette.ink,
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Medium,
                )
            }
            Spacer(Modifier.width(14.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(
                    entry.title,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                Text(
                    entry.account.ifEmpty { stringResource(R.string.no_account) },
                    style = MaterialTheme.typography.bodyLarge,
                    color = if (entry.account.isEmpty()) palette.secondary else palette.ink.copy(alpha = 0.78f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            IconButton(onClick = { model.copyAccount(entry) }, enabled = entry.account.isNotEmpty()) {
                Icon(Icons.Copy, contentDescription = copyAccount)
            }
        }
        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }, offset = DpOffset(PagePadding, 0.dp)) {
            DropdownMenuItem(
                text = { Text(copyAccount) },
                leadingIcon = { Icon(Icons.Copy, contentDescription = null) },
                enabled = entry.account.isNotEmpty(),
                onClick = {
                    menu = false
                    model.copyAccount(entry)
                },
            )
            DropdownMenuItem(
                text = { Text(copyPassword) },
                leadingIcon = { Icon(Icons.Key, contentDescription = null) },
                enabled = entry.password.isNotEmpty(),
                onClick = {
                    menu = false
                    model.copyPassword(entry)
                },
            )
            DropdownMenuItem(
                text = { Text(view) },
                leadingIcon = { Icon(Icons.Eye, contentDescription = null) },
                onClick = {
                    menu = false
                    model.open(Screen.Detail(entry.id))
                },
            )
        }
    }
}

@Composable
private fun SearchField(model: AppViewModel) {
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { focus.requestFocus() }
    OutlinedTextField(
        value = model.query,
        onValueChange = { model.query = it },
        modifier = Modifier.fillMaxWidth().padding(horizontal = PagePadding).focusRequester(focus),
        placeholder = { Text(stringResource(R.string.search_hint)) },
        leadingIcon = { Icon(Icons.Search, contentDescription = null) },
        trailingIcon = {
            if (model.query.isNotEmpty()) {
                IconButton(onClick = { model.query = "" }) { Icon(Icons.Close, contentDescription = stringResource(R.string.search_clear)) }
            }
        },
        singleLine = true,
        shape = CircleShape,
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, imeAction = ImeAction.Search),
    )
}

/** Shown above the list when a backup is due. It can be dismissed and then stays away for 30 days. */
@Composable
private fun ExportReminder(model: AppViewModel, neverExported: Boolean) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = PagePadding, vertical = 6.dp)
            .clip(RoundedCornerShape(16.dp))
            .background(palette.wash)
            .heightIn(min = 56.dp)
            .padding(start = 16.dp, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            stringResource(if (neverExported) R.string.export_reminder_never else R.string.export_reminder_stale),
            Modifier.weight(1f),
            style = MaterialTheme.typography.bodyMedium,
        )
        LinkButton(stringResource(R.string.export_reminder_action), Icons.Upload, onClick = { model.open(Screen.Export) })
        IconButton(onClick = model::dismissExportReminder) { Icon(Icons.Close, contentDescription = stringResource(R.string.dismiss)) }
    }
}
