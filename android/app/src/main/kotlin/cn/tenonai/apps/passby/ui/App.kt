package cn.tenonai.apps.passby.ui

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.Settings
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SnackbarDuration
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SnackbarResult
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import androidx.fragment.app.FragmentActivity
import cn.tenonai.apps.passby.BuildConfig
import cn.tenonai.apps.passby.R
import cn.tenonai.apps.passby.core.Notebook
import cn.tenonai.apps.passby.data.NotebookState
import kotlinx.coroutines.flow.collectLatest

const val PRIVACY_URL = "https://passby.tenonai.cn/privacy/"
const val TERMS_URL = "https://passby.tenonai.cn/terms/"
const val WEBSITE_URL = "https://tenonai.cn/"
const val SUPPORT_EMAIL = "support@tenonai.cn"

/** Hands a web address to the system browser. The app itself has no network access. */
fun openLink(context: Context, url: String): Boolean = start(context, Intent(Intent.ACTION_VIEW, url.toUri()))

/** Opens the person's mail app with the version and platform filled in, and nothing else. */
fun writeToSupport(context: Context): Boolean {
    val subject = "PassBy Android ${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})"
    val intent = Intent(Intent.ACTION_SENDTO, "mailto:$SUPPORT_EMAIL?subject=${Uri.encode(subject)}".toUri())
    return start(context, intent)
}

fun openSecuritySettings(context: Context): Boolean = start(context, Intent(Settings.ACTION_SECURITY_SETTINGS))

private fun start(context: Context, intent: Intent): Boolean = try {
    context.startActivity(intent)
    true
} catch (e: ActivityNotFoundException) {
    false
}

@Composable
fun App(model: AppViewModel, activity: FragmentActivity) {
    val state by model.state.collectAsState()
    val snackbar = remember { SnackbarHostState() }
    LaunchedEffect(Unit) {
        // A newer notice replaces the one on screen.
        model.notices.collectLatest { notice ->
            // A notice that offers something to do stays long enough to be read and tapped.
            val duration = if (notice.actionLabel != null) SnackbarDuration.Long else SnackbarDuration.Short
            val result = snackbar.showSnackbar(notice.text, notice.actionLabel, duration = duration)
            if (result == SnackbarResult.ActionPerformed) notice.action?.invoke()
        }
    }
    Surface(Modifier.fillMaxSize(), color = palette.paper, contentColor = palette.ink) {
        Box(Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing)) {
            when (val current = state) {
                NotebookState.Loading -> Unit
                is NotebookState.Unreadable -> UnreadableScreen(current.newerVersion, model)
                is NotebookState.Ready -> {
                    val doorApplies = current.notebook.gateEnabled && model.deviceHasLock
                    if (doorApplies && model.locked) {
                        LockScreen(onUnlock = { model.unlock(activity) })
                    } else {
                        LaunchedEffect(Unit) { model.enteredWithoutDoor() }
                        Pages(model, current.notebook, activity)
                    }
                }
            }
            SnackbarHost(snackbar, Modifier.align(Alignment.BottomCenter).padding(bottom = 72.dp))
        }
    }
}

/** The page on top of the stack, plus the notices that can appear over any page. */
@Composable
private fun Pages(model: AppViewModel, notebook: Notebook, activity: FragmentActivity) {
    BackHandler(enabled = model.stack.size > 1) { model.back() }
    when (val screen = model.stack.last()) {
        Screen.Library -> LibraryScreen(model, notebook)
        is Screen.Detail -> EntryDetailScreen(model, notebook, screen.id)
        Screen.Editor -> EntryEditorScreen(model, notebook)
        is Screen.Generator -> GeneratorScreen(model, screen.forEditor)
        Screen.Folders -> FoldersScreen(model, notebook)
        Screen.Deleted -> DeletedScreen(model, notebook)
        Screen.Settings -> SettingsScreen(model, notebook, activity)
        Screen.About -> AboutScreen(model)
        Screen.Licenses -> LicensesScreen(model)
        Screen.Export -> ExportScreen(model, notebook)
        Screen.Import -> ImportScreen(model, notebook)
        Screen.Ai -> AiScreen(model, notebook)
        Screen.AiPreview -> AiPreviewScreen(model)
        Screen.AiResult -> AiResultScreen(model, notebook)
        Screen.Sync -> SyncScreen(model)
    }

    val context = LocalContext.current
    val restored by model.restoredFromPrevious.collectAsState()
    if (restored) {
        AlertDialog(
            onDismissRequest = model::restoredNoticeSeen,
            title = { Text(stringResource(R.string.restored_title)) },
            text = { Text(stringResource(R.string.restored_text)) },
            confirmButton = { TextButton(onClick = model::restoredNoticeSeen) { Text(stringResource(R.string.ok)) } },
        )
    } else if (!model.deviceHasLock && !notebook.noLockNoticeShown) {
        // Shown once. Without a screen lock there is nothing for the door to verify against.
        AlertDialog(
            onDismissRequest = model::noLockNoticeShown,
            title = { Text(stringResource(R.string.gate_no_lock)) },
            text = { Text(stringResource(R.string.no_lock_notice_text)) },
            confirmButton = {
                TextButton(onClick = {
                    model.noLockNoticeShown()
                    openSecuritySettings(context)
                }) { Text(stringResource(R.string.open_security_settings)) }
            },
            dismissButton = { TextButton(onClick = model::noLockNoticeShown) { Text(stringResource(R.string.not_now)) } },
        )
    }
}

/** Shown instead of the notebook until the person is verified. Asks straight away, and again on request. */
@Composable
private fun LockScreen(onUnlock: () -> Unit) {
    LaunchedEffect(Unit) { onUnlock() }
    Box(Modifier.fillMaxSize().padding(PagePadding), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
            BrandMark(size = 64.dp)
            Text(stringResource(R.string.lock_title), style = MaterialTheme.typography.titleMedium)
            PrimaryButton(stringResource(R.string.lock_unlock), onClick = onUnlock, icon = Icons.Lock)
        }
    }
}

/** The notebook files exist but cannot be read. They are not touched unless the person chooses to start over. */
@Composable
private fun UnreadableScreen(newerVersion: Boolean, model: AppViewModel) {
    val context = LocalContext.current
    var confirm by remember { mutableStateOf(false) }
    Box(Modifier.fillMaxSize().padding(PagePadding), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(16.dp)) {
            BrandMark(size = 64.dp)
            Text(stringResource(R.string.unreadable_title), style = MaterialTheme.typography.titleLarge)
            Text(
                stringResource(if (newerVersion) R.string.unreadable_newer else R.string.unreadable_damaged),
                style = MaterialTheme.typography.bodyLarge,
                color = palette.secondary,
            )
            SecondaryButton(stringResource(R.string.contact_support), onClick = { writeToSupport(context) }, icon = Icons.Mail)
            if (!newerVersion) {
                LinkButton(stringResource(R.string.unreadable_start_over), Icons.Refresh, onClick = { confirm = true })
            }
        }
    }
    if (confirm) {
        ConfirmDialog(
            title = stringResource(R.string.unreadable_start_over_title),
            text = stringResource(R.string.unreadable_start_over_text),
            confirm = stringResource(R.string.unreadable_start_over),
            onConfirm = {
                confirm = false
                model.startOver()
            },
            onDismiss = { confirm = false },
        )
    }
}
