package cn.tenonai.apps.passby.ui

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.FileProvider
import cn.tenonai.apps.passby.PassByApp
import cn.tenonai.apps.passby.R
import cn.tenonai.apps.passby.core.ExportException
import cn.tenonai.apps.passby.core.ExportFile
import cn.tenonai.apps.passby.core.ExportSecret
import cn.tenonai.apps.passby.core.ExportedNotebook
import cn.tenonai.apps.passby.core.Notebook
import cn.tenonai.apps.passby.core.Qr
import cn.tenonai.apps.passby.system.ExportCache
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.text.Normalizer
import java.time.LocalDate
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// ---- Export ----

/**
 * Makes the encrypted backup file. The secret is an export code the app generates, or a passphrase
 * the person sets; neither is stored. The file goes where the person saves or shares it and nowhere else.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ExportScreen(model: AppViewModel, notebook: Notebook) {
    val context = LocalContext.current
    val resources = LocalResources.current
    val scope = rememberCoroutineScope()
    var useCode by remember { mutableStateOf(true) }
    var code by remember { mutableStateOf(ExportSecret.newCode()) }
    var noted by remember { mutableStateOf(false) }
    var passphrase by remember { mutableStateOf("") }
    var again by remember { mutableStateOf("") }
    var revealed by remember { mutableStateOf(false) }
    var working by remember { mutableStateOf(false) }

    val problem = ExportSecret.passphraseProblem(passphrase)
    val secretReady = if (useCode) noted else problem == null && passphrase == again
    val ready = notebook.entries.isNotEmpty() && secretReady && !working
    val count = notebook.entries.size
    val fileName = remember { "PassBy-${LocalDate.now()}.passby" }

    fun secret(): ByteArray = ExportSecret.secretBytes(if (useCode) ExportSecret.grouped(code) else passphrase).bytes
    fun notice(id: Int, vararg arguments: Any) = model.notices.tryEmit(Notice(resources.getString(id, *arguments)))

    val save = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/octet-stream")) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        working = true
        scope.launch {
            val written = try {
                val bytes = model.buildExport(secret())
                bytes != null && withContext(Dispatchers.IO) {
                    val stream = context.contentResolver.openOutputStream(uri, "w") ?: throw IOException("no stream")
                    stream.use { it.write(bytes) }
                    true
                }
            } catch (e: IOException) {
                false
            } catch (e: SecurityException) {
                false
            }
            working = false
            if (written) {
                model.exported()
                notice(R.string.export_done, count)
                model.back()
            } else {
                // The picker created an empty file before anything was written; remove that leftover.
                try {
                    DocumentsContract.deleteDocument(context.contentResolver, uri)
                } catch (e: Exception) {
                    // Some providers do not allow it. The empty file stays.
                }
                notice(R.string.export_failed)
            }
        }
    }

    fun share() {
        working = true
        scope.launch {
            val file = try {
                val bytes = model.buildExport(secret())
                if (bytes == null) null else withContext(Dispatchers.IO) { ExportCache.write(context, fileName, bytes) }
            } catch (e: IOException) {
                null
            }
            working = false
            if (file == null) {
                notice(R.string.export_failed)
                return@launch
            }
            val uri = FileProvider.getUriForFile(context, "${context.packageName}.exports", file)
            val send = Intent(Intent.ACTION_SEND)
                .setType("application/octet-stream")
                .putExtra(Intent.EXTRA_STREAM, uri)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            send.clipData = ClipData.newRawUri(null, uri)
            // The system tells this receiver when an app is picked in the share sheet. Only then is the
            // export recorded; closing the sheet records nothing.
            val mutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) PendingIntent.FLAG_MUTABLE else 0
            val chosen = PendingIntent.getBroadcast(
                context, 0, Intent(context, ExportSharedReceiver::class.java), PendingIntent.FLAG_UPDATE_CURRENT or mutable,
            )
            context.startActivity(Intent.createChooser(send, null, chosen.intentSender))
        }
    }

    Page(title = stringResource(R.string.export), onBack = { model.back() }) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = PagePadding, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Text(stringResource(R.string.export_intro), style = MaterialTheme.typography.bodyMedium, color = palette.secondary)
            if (notebook.entries.isEmpty()) {
                Text(stringResource(R.string.export_empty), style = MaterialTheme.typography.bodyLarge)
            }
            Column {
                Choice(stringResource(R.string.export_use_code), null, useCode) { useCode = true }
                Choice(stringResource(R.string.export_use_passphrase), null, !useCode) { useCode = false }
            }

            if (useCode) {
                val grouped = ExportSecret.grouped(code)
                val spoken = code.toList().joinToString(" ")
                SectionLabel(stringResource(R.string.export_code))
                // The four groups wrap as whole groups when the line is too narrow, never in the middle of one.
                FlowRow(
                    Modifier.fillMaxWidth().clearAndSetSemantics { contentDescription = spoken },
                    horizontalArrangement = Arrangement.Center,
                ) {
                    val groups = grouped.split("-")
                    groups.forEachIndexed { index, group ->
                        Text(
                            if (index < groups.lastIndex) "$group-" else group,
                            fontFamily = FontFamily.Monospace,
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 20.sp,
                            maxLines = 1,
                        )
                    }
                }
                QrCode(grouped, stringResource(R.string.export_qr), Modifier.align(Alignment.CenterHorizontally).size(208.dp))
                Text(stringResource(R.string.export_code_note), style = MaterialTheme.typography.bodyMedium)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    LinkButton(stringResource(R.string.export_code_copy), Icons.Copy, onClick = { model.copyExportCode(grouped) })
                    LinkButton(stringResource(R.string.export_code_new), Icons.Refresh, onClick = {
                        code = ExportSecret.newCode()
                        noted = false
                    })
                }
                Row(
                    Modifier.fillMaxWidth().heightIn(min = 48.dp).toggleable(value = noted, role = Role.Checkbox, onValueChange = { noted = it }),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Checkbox(checked = noted, onCheckedChange = null)
                    Text(stringResource(R.string.export_code_confirm), style = MaterialTheme.typography.bodyLarge)
                }
            } else {
                SecretField(passphrase, { passphrase = it }, stringResource(R.string.export_passphrase), revealed) { revealed = !revealed }
                SecretField(again, { again = it }, stringResource(R.string.export_passphrase_again), revealed) { revealed = !revealed }
                val message = when {
                    passphrase.isEmpty() -> null
                    problem == ExportSecret.PassphraseProblem.SURROUNDING_SPACE -> R.string.export_problem_space
                    problem == ExportSecret.PassphraseProblem.LOOKS_LIKE_CODE -> R.string.export_problem_code
                    problem == ExportSecret.PassphraseProblem.TOO_SHORT -> R.string.export_problem_short
                    again.isNotEmpty() && again != passphrase -> R.string.export_problem_mismatch
                    else -> null
                }
                if (message != null) {
                    Text(stringResource(message), style = MaterialTheme.typography.bodyMedium, color = palette.ink)
                } else if (passphrase.isNotEmpty()) {
                    Text(stringResource(strength(passphrase)), style = MaterialTheme.typography.bodyMedium)
                }
                Text(stringResource(R.string.export_passphrase_note), style = MaterialTheme.typography.bodyMedium, color = palette.secondary)
            }
        }
        if (working) {
            Working(stringResource(R.string.export_working))
        } else {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = PagePadding, vertical = 12.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                PrimaryButton(stringResource(R.string.export_save), onClick = { save.launch(fileName) }, modifier = Modifier.weight(1f), enabled = ready, icon = Icons.File)
                SecondaryButton(stringResource(R.string.export_share), onClick = { share() }, enabled = ready, icon = Icons.Share)
            }
        }
    }
}

/** A rough reading of how hard a passphrase is to guess, from its length and the kinds of character in it. */
private fun strength(passphrase: String): Int {
    val text = Normalizer.normalize(passphrase, Normalizer.Form.NFC)
    val length = text.codePointCount(0, text.length)
    val kinds = listOf(
        text.any { it.isLowerCase() },
        text.any { it.isUpperCase() },
        text.any { it.isDigit() },
        text.any { !it.isLetterOrDigit() || it.code > 0x7F },
    ).count { it }
    return when {
        length >= 20 && kinds >= 2 -> R.string.strength_strong
        length >= 16 || kinds >= 3 -> R.string.strength_fair
        else -> R.string.strength_weak
    }
}

/** Records an export once the person has picked an app in the share sheet. */
class ExportSharedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val repository = (context.applicationContext as PassByApp).repository
        val pending = goAsync()
        CoroutineScope(Dispatchers.Default).launch {
            try {
                repository.load()
                repository.update { notebook, now -> notebook.exported(now) }
            } finally {
                pending.finish()
            }
        }
    }
}

/** The export code as a QR code: always dark on white with a quiet zone, so a camera reads it in either appearance. */
@Composable
private fun QrCode(text: String, description: String, modifier: Modifier = Modifier) {
    val modules = remember(text) { Qr.encode(text) }
    Canvas(modifier.background(Color.White).semantics { contentDescription = description }) {
        val quiet = 4
        val cell = size.minDimension / (Qr.SIZE + 2 * quiet)
        for (y in 0 until Qr.SIZE) {
            for (x in 0 until Qr.SIZE) {
                if (modules[y][x]) {
                    // Half a pixel of overlap keeps hairlines from showing between neighbouring modules.
                    drawRect(Color.Black, Offset((x + quiet) * cell, (y + quiet) * cell), Size(cell + 0.5f, cell + 0.5f))
                }
            }
        }
    }
}

// ---- Import ----

/** Larger than any notebook could be. A file over this is not read further and is reported as not an export. */
private const val MAX_IMPORT_BYTES = 16 * 1024 * 1024

private fun readFile(context: Context, uri: Uri): ByteArray? = try {
    context.contentResolver.openInputStream(uri)?.use { input ->
        val out = ByteArrayOutputStream()
        val buffer = ByteArray(64 * 1024)
        var tooLarge = false
        while (!tooLarge) {
            val count = input.read(buffer)
            if (count < 0) break
            out.write(buffer, 0, count)
            tooLarge = out.size() > MAX_IMPORT_BYTES
        }
        if (tooLarge) ByteArray(0) else out.toByteArray()
    }
} catch (e: IOException) {
    null
} catch (e: SecurityException) {
    null
}

private fun message(kind: ExportException.Kind): Int = when (kind) {
    ExportException.Kind.NOT_EXPORT -> R.string.error_not_export
    ExportException.Kind.UPDATE -> R.string.error_update
    ExportException.Kind.DAMAGED -> R.string.error_damaged
    ExportException.Kind.WRONG_CODE -> R.string.error_wrong_code
}

/**
 * Brings an export file into the notebook: choose the file, enter the code or passphrase, see how
 * much is in it, then merge or replace by the shared rules (docs/export-format.md §7).
 */
@Composable
fun ImportScreen(model: AppViewModel, notebook: Notebook) {
    val context = LocalContext.current
    val resources = LocalResources.current
    val scope = rememberCoroutineScope()
    var file by remember { mutableStateOf<ByteArray?>(null) }
    var typed by remember { mutableStateOf("") }
    var revealed by remember { mutableStateOf(true) }
    var working by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<Int?>(null) }
    var opened by remember { mutableStateOf<ExportedNotebook?>(null) }
    var replace by remember { mutableStateOf(false) }
    var done by remember { mutableStateOf<String?>(null) }
    var confirmReplace by remember { mutableStateOf(false) }
    val localIsEmpty = notebook.entries.isEmpty() && notebook.folders.isEmpty()

    val pick = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri == null) return@rememberLauncherForActivityResult
        scope.launch {
            error = null
            opened = null
            file = null
            typed = ""
            val bytes = withContext(Dispatchers.IO) { readFile(context, uri) }
            if (bytes == null) {
                error = R.string.error_read
            } else {
                try {
                    // Refuses a file that is not an export before asking for its code.
                    ExportFile.checkHeader(bytes)
                    file = bytes
                } catch (e: ExportException) {
                    error = message(e.kind)
                }
            }
        }
    }

    val finished = done
    val incoming = opened
    val bytes = file

    fun openFile(bytes: ByteArray) {
        working = true
        error = null
        scope.launch {
            try {
                opened = model.openImport(bytes, typed)
                typed = ""
            } catch (e: ExportException) {
                error = message(e.kind)
            }
            working = false
        }
    }

    fun apply(incoming: ExportedNotebook) {
        working = true
        scope.launch {
            val replacing = replace && !localIsEmpty
            val result = model.applyImport(incoming, replacing)
            working = false
            if (result == null) {
                model.notices.tryEmit(Notice(resources.getString(R.string.save_failed)))
            } else {
                // The decrypted file is not kept once it is in the notebook.
                opened = null
                file = null
                done = if (replacing) {
                    resources.getString(R.string.import_done_replace, result.added, result.movedToDeleted)
                } else {
                    resources.getString(R.string.import_done_merge, result.added, result.skipped, result.marked)
                }
            }
        }
    }

    Page(title = stringResource(R.string.import_), onBack = { model.back() }) {
        // What to read sits at the top; what to press sits at the bottom, within reach of a thumb.
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = PagePadding, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            when {
                finished != null -> Text(finished, style = MaterialTheme.typography.bodyLarge)
                incoming != null -> {
                    Text(
                        stringResource(R.string.import_found, incoming.entries.size, incoming.folders.size, formatDate(incoming.exportedAt.toEpochMilli())),
                        style = MaterialTheme.typography.bodyLarge,
                    )
                    if (!localIsEmpty) {
                        Column {
                            Choice(stringResource(R.string.import_merge), stringResource(R.string.import_merge_text), !replace) { replace = false }
                            Choice(
                                stringResource(R.string.import_replace),
                                stringResource(R.string.import_replace_text, notebook.entries.size),
                                replace,
                            ) { replace = true }
                        }
                    }
                }
                bytes != null -> {
                    SecretField(typed, { typed = it }, stringResource(R.string.import_secret), revealed) { revealed = !revealed }
                    error?.let { Text(stringResource(it), style = MaterialTheme.typography.bodyMedium, color = palette.ink) }
                }
                else -> {
                    Text(stringResource(R.string.import_intro), style = MaterialTheme.typography.bodyMedium, color = palette.secondary)
                    error?.let { Text(stringResource(it), style = MaterialTheme.typography.bodyMedium, color = palette.ink) }
                }
            }
        }
        if (working) Working(stringResource(R.string.import_working))
        Column(
            Modifier.fillMaxWidth().padding(horizontal = PagePadding, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            when {
                finished != null -> PrimaryButton(stringResource(R.string.done), onClick = { model.back() }, modifier = Modifier.fillMaxWidth(), icon = Icons.Check)
                incoming != null -> PrimaryButton(
                    stringResource(R.string.import_confirm),
                    // Replacing moves everything on this phone to Recently Deleted, so it asks once more.
                    onClick = { if (replace && !localIsEmpty) confirmReplace = true else apply(incoming) },
                    modifier = Modifier.fillMaxWidth(),
                    enabled = !working,
                    icon = Icons.Download,
                )
                bytes != null -> {
                    LinkButton(stringResource(R.string.import_choose_other), Icons.File, onClick = { pick.launch(arrayOf("*/*")) }, enabled = !working)
                    PrimaryButton(
                        stringResource(R.string.import_open),
                        onClick = { openFile(bytes) },
                        modifier = Modifier.fillMaxWidth(),
                        enabled = typed.isNotBlank() && !working,
                        icon = Icons.Key,
                    )
                }
                else -> PrimaryButton(stringResource(R.string.import_choose), onClick = { pick.launch(arrayOf("*/*")) }, modifier = Modifier.fillMaxWidth(), icon = Icons.File)
            }
        }
    }

    if (confirmReplace && incoming != null) {
        ConfirmDialog(
            title = stringResource(R.string.import_replace_title),
            text = stringResource(R.string.import_replace_confirm_text, notebook.entries.size),
            confirm = stringResource(R.string.import_replace),
            onConfirm = {
                confirmReplace = false
                apply(incoming)
            },
            onDismiss = { confirmReplace = false },
        )
    }
}

// ---- Shared pieces ----

@Composable
fun Working(text: String) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = PagePadding, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
        Text(text, style = MaterialTheme.typography.bodyLarge)
    }
}

/** One of a pair of options. The row is the radio button. */
@Composable
private fun Choice(title: String, text: String?, selected: Boolean, onSelect: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).selectable(selected = selected, role = Role.RadioButton, onClick = onSelect).padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        RadioButton(selected = selected, onClick = null)
        Column {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            if (text != null) Text(text, style = MaterialTheme.typography.bodyMedium, color = palette.secondary)
        }
    }
}

/**
 * A field for an export code or passphrase. Hidden, it uses the password keyboard, which keeps the
 * text out of the keyboard's learned words. Shown, it uses the ordinary keyboard so that a
 * passphrase in Chinese can be typed.
 */
@Composable
fun SecretField(value: String, onChange: (String) -> Unit, label: String, revealed: Boolean, onToggle: () -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        modifier = Modifier.fillMaxWidth(),
        label = { Text(label) },
        singleLine = true,
        visualTransformation = if (revealed) VisualTransformation.None else PasswordVisualTransformation(),
        keyboardOptions = KeyboardOptions(
            capitalization = KeyboardCapitalization.None,
            autoCorrectEnabled = false,
            keyboardType = if (revealed) KeyboardType.Text else KeyboardType.Password,
        ),
        trailingIcon = {
            IconButton(onClick = onToggle) {
                Icon(
                    if (revealed) Icons.EyeOff else Icons.Eye,
                    contentDescription = stringResource(if (revealed) R.string.hide_password else R.string.show_password),
                )
            }
        },
    )
}
