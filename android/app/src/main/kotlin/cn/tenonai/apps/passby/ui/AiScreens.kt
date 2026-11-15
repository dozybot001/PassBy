package cn.tenonai.apps.passby.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
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
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import cn.tenonai.apps.passby.R
import cn.tenonai.apps.passby.core.AiGrouping
import cn.tenonai.apps.passby.core.Notebook
import cn.tenonai.apps.passby.system.AiSettings

/** The sentence people need most: what the model gets and what it never gets. */
@Composable
private fun OnlyTitles(modifier: Modifier = Modifier) {
    Column(
        modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(palette.wash).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(stringResource(R.string.ai_only_titles), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
        Text(stringResource(R.string.ai_never_sent), style = MaterialTheme.typography.bodyMedium)
    }
}

/**
 * AI grouping's own page: what it does, the switch, and where it sends. It is off until the person
 * turns it on here and confirms; turning it off removes the API key and the settings.
 */
@Composable
fun AiScreen(model: AppViewModel, notebook: Notebook) {
    val config = model.aiConfig
    var confirmOn by remember { mutableStateOf(false) }
    var confirmOff by remember { mutableStateOf(false) }
    var endpoint by remember(config) { mutableStateOf(config?.endpoint ?: AiGrouping.DEEPSEEK_ENDPOINT) }
    var modelName by remember(config) { mutableStateOf(config?.model ?: AiGrouping.DEEPSEEK_MODEL) }
    var key by remember { mutableStateOf("") }
    var revealed by remember { mutableStateOf(false) }
    val switchLabel = stringResource(R.string.ai_switch)

    val parsed = AiGrouping.endpoint(endpoint)
    val changed = config != null && (endpoint.trim() != config.endpoint || modelName.trim() != config.model)
    val valid = parsed != null && modelName.isNotBlank()
    val hostChanges = config != null && parsed != null && parsed.authority != AiGrouping.endpoint(config.endpoint)?.authority

    Page(title = stringResource(R.string.ai_grouping), onBack = { model.back() }) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = PagePadding, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(stringResource(R.string.ai_intro), style = MaterialTheme.typography.bodyLarge)
            OnlyTitles()
            // The whole row is the switch.
            Row(
                Modifier
                    .fillMaxWidth()
                    .toggleable(value = config != null, role = Role.Switch, onValueChange = { if (it) confirmOn = true else confirmOff = true })
                    .heightIn(min = 56.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Column(Modifier.weight(1f)) {
                    Text(switchLabel, style = MaterialTheme.typography.bodyLarge)
                    Text(stringResource(R.string.ai_switch_text), style = MaterialTheme.typography.bodyMedium, color = palette.secondary)
                }
                Switch(checked = config != null, onCheckedChange = null)
            }

            if (config != null) {
                HorizontalDivider(color = palette.rule)
                SectionLabel(stringResource(R.string.ai_provider))
                OutlinedTextField(
                    value = endpoint,
                    onValueChange = { endpoint = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.ai_endpoint)) },
                    singleLine = true,
                    isError = parsed == null,
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, keyboardType = KeyboardType.Uri),
                )
                OutlinedTextField(
                    value = modelName,
                    onValueChange = { modelName = it },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.ai_model)) },
                    singleLine = true,
                    isError = modelName.isBlank(),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false),
                )
                Text(
                    stringResource(
                        when {
                            parsed == null -> R.string.ai_endpoint_error
                            hostChanges && model.aiHasKey -> R.string.ai_host_changes
                            else -> R.string.ai_provider_note
                        },
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = if (parsed == null || (hostChanges && model.aiHasKey)) palette.ink else palette.secondary,
                )
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    if (changed) {
                        SecondaryButton(
                            stringResource(R.string.ai_save_provider),
                            onClick = { model.aiSave(AiSettings.Config(endpoint.trim(), modelName.trim())) },
                            enabled = valid,
                            icon = Icons.Check,
                        )
                    }
                    if (endpoint.trim() != AiGrouping.DEEPSEEK_ENDPOINT || modelName.trim() != AiGrouping.DEEPSEEK_MODEL) {
                        LinkButton(stringResource(R.string.ai_use_deepseek), Icons.Restore, onClick = {
                            endpoint = AiGrouping.DEEPSEEK_ENDPOINT
                            modelName = AiGrouping.DEEPSEEK_MODEL
                        })
                    }
                }

                SectionLabel(stringResource(R.string.ai_key))
                if (model.aiHasKey) {
                    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Key, contentDescription = null, tint = palette.secondary)
                        Text(stringResource(R.string.ai_key_saved), Modifier.weight(1f).padding(horizontal = 12.dp), style = MaterialTheme.typography.bodyLarge)
                        LinkButton(stringResource(R.string.delete), Icons.Trash, onClick = { model.aiRemoveKey() })
                    }
                } else {
                    SecretField(key, { key = it }, stringResource(R.string.ai_key), revealed) { revealed = !revealed }
                    if (key.isNotBlank() && AiGrouping.apiKey(key) == null) {
                        Text(stringResource(R.string.ai_key_invalid), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                    }
                    SecondaryButton(
                        stringResource(R.string.ai_key_save),
                        onClick = {
                            if (model.aiSaveKey(key)) key = ""
                        },
                        enabled = AiGrouping.apiKey(key) != null && !changed,
                        icon = Icons.Check,
                    )
                }
                Text(stringResource(R.string.ai_key_note), style = MaterialTheme.typography.bodySmall, color = palette.secondary)
            }
        }
        if (config != null) {
            Column(Modifier.fillMaxWidth().padding(horizontal = PagePadding, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                PrimaryButton(
                    stringResource(R.string.ai_start),
                    onClick = { model.aiPrepare() },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = model.aiHasKey && !changed && notebook.entries.isNotEmpty(),
                    icon = Icons.Sparkle,
                )
                Text(stringResource(R.string.ai_start_note), style = MaterialTheme.typography.bodySmall, color = palette.secondary)
            }
        }
    }

    if (confirmOn) {
        AlertDialog(
            onDismissRequest = { confirmOn = false },
            icon = { Icon(Icons.Sparkle, contentDescription = null) },
            title = { Text(stringResource(R.string.ai_turn_on_title)) },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    Text(stringResource(R.string.ai_turn_on_network))
                    Text(stringResource(R.string.ai_turn_on_sent), fontWeight = FontWeight.SemiBold)
                    Text(stringResource(R.string.ai_turn_on_provider))
                    Text(stringResource(R.string.ai_turn_on_key))
                }
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmOn = false
                    model.aiSave(AiSettings.Config(AiGrouping.DEEPSEEK_ENDPOINT, AiGrouping.DEEPSEEK_MODEL))
                }) { Text(stringResource(R.string.ai_turn_on)) }
            },
            dismissButton = { TextButton(onClick = { confirmOn = false }) { Text(stringResource(R.string.cancel)) } },
        )
    }
    if (confirmOff) {
        ConfirmDialog(
            title = stringResource(R.string.ai_turn_off_title),
            text = stringResource(R.string.ai_turn_off_text),
            confirm = stringResource(R.string.ai_turn_off),
            onConfirm = {
                confirmOff = false
                model.aiTurnOff()
            },
            onDismiss = { confirmOff = false },
        )
    }
}

/** Everything that is about to leave the phone, before it does. Send sends exactly what is shown here. */
@Composable
fun AiPreviewScreen(model: AppViewModel) {
    val draft = model.aiDraft
    val host = model.aiConfig?.let { AiGrouping.endpoint(it.endpoint) }?.host.orEmpty()
    var showBody by remember { mutableStateOf(false) }

    Page(title = stringResource(R.string.ai_preview_title), onBack = { model.back() }) {
        if (draft == null) {
            EmptyState(stringResource(R.string.ai_nothing_to_send), "", Modifier.weight(1f))
            return@Page
        }
        LazyColumn(
            Modifier.weight(1f),
            contentPadding = PaddingValues(horizontal = PagePadding, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            item {
                Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    Text(stringResource(R.string.ai_preview_to, host), style = MaterialTheme.typography.bodyLarge)
                    OnlyTitles()
                    if (draft.leftOut > 0) {
                        Text(stringResource(R.string.ai_preview_left_out, draft.titles.size, draft.leftOut), style = MaterialTheme.typography.bodyMedium)
                    }
                    if (draft.blankIds.isNotEmpty()) {
                        Text(stringResource(R.string.ai_preview_blank, draft.blankIds.size), style = MaterialTheme.typography.bodyMedium, color = palette.secondary)
                    }
                    SectionLabel(stringResource(R.string.ai_preview_titles, draft.titles.size))
                }
            }
            items(draft.titles.size) { index -> Text(draft.titles[index], Modifier.padding(vertical = 4.dp), style = MaterialTheme.typography.bodyLarge) }
            item {
                Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    SectionLabel(stringResource(R.string.ai_preview_folders, draft.folders.size))
                    if (draft.folders.isEmpty()) Text(stringResource(R.string.ai_preview_no_folders), style = MaterialTheme.typography.bodyMedium, color = palette.secondary)
                }
            }
            items(draft.folders.size) { index -> Text(draft.folders[index], Modifier.padding(vertical = 4.dp), style = MaterialTheme.typography.bodyLarge) }
            item {
                Column(Modifier.padding(top = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    LinkButton(
                        stringResource(if (showBody) R.string.ai_preview_hide_request else R.string.ai_preview_show_request),
                        Icons.File,
                        onClick = { showBody = !showBody },
                    )
                    if (showBody) {
                        Text(stringResource(R.string.ai_preview_request_note), style = MaterialTheme.typography.bodySmall, color = palette.secondary)
                        Text(
                            draft.body,
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(palette.wash).padding(12.dp),
                            style = MaterialTheme.typography.bodySmall,
                            fontFamily = FontFamily.Monospace,
                        )
                    }
                }
            }
        }
        if (model.aiWorking) Working(stringResource(R.string.ai_working))
        Column(Modifier.fillMaxWidth().padding(horizontal = PagePadding, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            model.aiError?.let { Text(it, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold) }
            PrimaryButton(
                stringResource(R.string.ai_send),
                onClick = { model.aiSend() },
                modifier = Modifier.fillMaxWidth(),
                enabled = !model.aiWorking && draft.titles.isNotEmpty(),
                icon = Icons.Upload,
            )
        }
    }
}

/** The model's suggestions, one entry a row. Nothing changes until the ticked ones are applied. */
@Composable
fun AiResultScreen(model: AppViewModel, notebook: Notebook) {
    val rows = model.aiRows
    var picked by remember(rows) { mutableStateOf(rows.map { it.entryId }.toSet()) }
    val unfiled = stringResource(R.string.filter_unfiled)

    Page(title = stringResource(R.string.ai_result_title), onBack = { model.back() }) {
        if (rows.isEmpty()) {
            EmptyState(stringResource(R.string.ai_result_empty), stringResource(R.string.ai_result_empty_text), Modifier.weight(1f))
            return@Page
        }
        val clear = rows.filterNot { it.unclear }
        val unclear = rows.filter { it.unclear }
        LazyColumn(Modifier.weight(1f), contentPadding = PaddingValues(vertical = 8.dp)) {
            item {
                Column(Modifier.padding(horizontal = PagePadding), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    Text(stringResource(R.string.ai_result_intro), style = MaterialTheme.typography.bodyMedium, color = palette.secondary)
                    Row {
                        LinkButton(stringResource(R.string.ai_select_all), Icons.Check, onClick = { picked = rows.map { it.entryId }.toSet() })
                        LinkButton(stringResource(R.string.ai_select_none), Icons.Close, onClick = { picked = emptySet() })
                    }
                }
            }
            if (clear.isNotEmpty()) {
                item { SectionLabel(stringResource(R.string.ai_result_suggestions, clear.size), Modifier.padding(horizontal = PagePadding, vertical = 8.dp)) }
                items(clear, key = { it.entryId }) { row ->
                    SuggestionRow(row, unfiled, row.entryId in picked, onToggle = { picked = if (it) picked + row.entryId else picked - row.entryId })
                }
            }
            if (unclear.isNotEmpty()) {
                item {
                    Column(Modifier.padding(horizontal = PagePadding, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        SectionLabel(stringResource(R.string.ai_result_unclear, unclear.size))
                        Text(stringResource(R.string.ai_result_unclear_text), style = MaterialTheme.typography.bodyMedium, color = palette.secondary)
                    }
                }
                items(unclear, key = { it.entryId }) { row ->
                    SuggestionRow(
                        row, unfiled, row.entryId in picked,
                        onToggle = { picked = if (it) picked + row.entryId else picked - row.entryId },
                        onEdit = { notebook.entries.firstOrNull { it.id == row.entryId }?.let { model.editEntry(it) } },
                    )
                }
            }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = PagePadding, vertical = 12.dp)) {
            PrimaryButton(
                stringResource(R.string.ai_apply, picked.size),
                onClick = { model.aiApply(picked) },
                modifier = Modifier.weight(1f),
                enabled = picked.isNotEmpty(),
                icon = Icons.Check,
            )
        }
    }
}

@Composable
private fun SuggestionRow(row: AiRow, unfiled: String, checked: Boolean, onToggle: (Boolean) -> Unit, onEdit: (() -> Unit)? = null) {
    Row(
        Modifier
            .fillMaxWidth()
            .toggleable(value = checked, role = Role.Checkbox, onValueChange = onToggle)
            .heightIn(min = 64.dp)
            .padding(start = PagePadding, end = if (onEdit != null) PagePadding - 12.dp else PagePadding, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Checkbox(checked = checked, onCheckedChange = null)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            val shown = row.oldTitle.ifBlank { stringResource(R.string.ai_no_title) }
            if (row.title != null) {
                Text(stringResource(R.string.ai_change, shown, row.title), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
            } else {
                Text(shown, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
            }
            if (row.folder != null) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Icon(Icons.Folder, contentDescription = stringResource(R.string.folder), Modifier.size(16.dp), tint = palette.secondary)
                    Text(
                        stringResource(R.string.ai_change, row.oldFolder ?: unfiled, row.folder),
                        style = MaterialTheme.typography.bodyMedium,
                        color = palette.secondary,
                    )
                }
            }
        }
        if (onEdit != null) {
            IconButton(onClick = onEdit) {
                Icon(Icons.Pencil, contentDescription = stringResource(R.string.ai_edit_title))
            }
        }
    }
}
