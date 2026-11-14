package cn.tenonai.apps.passby.ui

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.fragment.app.FragmentActivity
import cn.tenonai.apps.passby.BuildConfig
import cn.tenonai.apps.passby.R
import cn.tenonai.apps.passby.core.Notebook
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** A date the way the product standard writes it: "2026 年 11 月 14 日" or "Nov 14, 2026". */
@Composable
fun formatDate(millis: Long): String {
    val locale = LocalConfiguration.current.locales[0]
    val formatter = DateTimeFormatter.ofPattern(stringResource(R.string.date_pattern), locale).withZone(ZoneId.systemDefault())
    return formatter.format(Instant.ofEpochMilli(millis))
}

@Composable
fun SettingsScreen(model: AppViewModel, notebook: Notebook, activity: FragmentActivity) {
    val context = LocalContext.current
    val resources = LocalResources.current
    val gateTitle = stringResource(R.string.gate_title)
    Page(title = stringResource(R.string.settings), onBack = { model.back() }) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            SettingRow(
                title = gateTitle,
                text = stringResource(if (model.deviceHasLock) R.string.gate_text else R.string.gate_no_lock),
                icon = Icons.Lock,
                trailing = {
                    Switch(
                        checked = notebook.gateEnabled && model.deviceHasLock,
                        onCheckedChange = { model.setGate(it, activity) },
                        enabled = model.deviceHasLock,
                        modifier = Modifier.semantics { contentDescription = gateTitle },
                    )
                },
            )
            HorizontalDivider(Modifier.padding(horizontal = PagePadding), color = palette.rule)

            SectionLabel(stringResource(R.string.backup), Modifier.padding(start = PagePadding, end = PagePadding, top = 20.dp, bottom = 4.dp))
            val lastExport = notebook.lastExportAt
            SettingRow(
                title = stringResource(R.string.export),
                text = if (lastExport == null) stringResource(R.string.never_exported) else stringResource(R.string.last_export, formatDate(lastExport)),
                icon = Icons.Upload,
                onClick = { model.open(Screen.Export) },
            )
            SettingRow(title = stringResource(R.string.import_), icon = Icons.Download, onClick = { model.open(Screen.Import) })
            SettingRow(
                title = stringResource(R.string.recently_deleted),
                text = stringResource(R.string.folder_count, notebook.deleted.size),
                icon = Icons.Trash,
                onClick = { model.open(Screen.Deleted) },
            )
            HorizontalDivider(Modifier.padding(horizontal = PagePadding), color = palette.rule)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                // Android 13 and later keep a language per app in system settings.
                SettingRow(
                    title = stringResource(R.string.language),
                    text = stringResource(R.string.language_system),
                    icon = Icons.Globe,
                    onClick = {
                        val intent = Intent(Settings.ACTION_APP_LOCALE_SETTINGS, Uri.fromParts("package", context.packageName, null))
                        try {
                            context.startActivity(intent)
                        } catch (e: android.content.ActivityNotFoundException) {
                            model.notices.tryEmit(Notice(resources.getString(R.string.no_app_for_link)))
                        }
                    },
                )
            } else {
                SettingRow(title = stringResource(R.string.language), text = stringResource(R.string.language_follow), icon = Icons.Globe)
            }
            SettingRow(title = stringResource(R.string.about), icon = Icons.Info, onClick = { model.open(Screen.About) })
        }
    }
}

/** What the product standard asks of an About page (§2.2), in its order. */
@Composable
fun AboutScreen(model: AppViewModel) {
    val context = LocalContext.current
    val resources = LocalResources.current
    fun open(action: () -> Boolean) {
        if (!action()) model.notices.tryEmit(Notice(resources.getString(R.string.no_app_for_link)))
    }
    Page(title = stringResource(R.string.about), onBack = { model.back() }) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState())) {
            Column(
                Modifier.padding(horizontal = PagePadding, vertical = 16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                BrandLockup(wordmarkSize = 34)
                Text(
                    stringResource(R.string.version) + " " +
                        stringResource(R.string.version_value, BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE),
                    style = MaterialTheme.typography.bodyMedium,
                    color = palette.secondary,
                )
                Text(stringResource(R.string.about_what), style = MaterialTheme.typography.bodyLarge)
                Text(stringResource(R.string.about_how), style = MaterialTheme.typography.bodyLarge)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Image(painterResource(R.drawable.tenon_mark), contentDescription = null, Modifier.size(28.dp))
                    Column {
                        Text(stringResource(R.string.publisher), style = MaterialTheme.typography.labelMedium, color = palette.secondary)
                        Text(stringResource(R.string.publisher_name), style = MaterialTheme.typography.bodyLarge)
                    }
                }
            }
            HorizontalDivider(Modifier.padding(horizontal = PagePadding), color = palette.rule)
            SettingRow(title = stringResource(R.string.website), text = WEBSITE_URL, icon = Icons.External, onClick = { open { openLink(context, WEBSITE_URL) } })
            SettingRow(title = stringResource(R.string.privacy_policy), icon = Icons.Shield, onClick = { open { openLink(context, PRIVACY_URL) } })
            SettingRow(title = stringResource(R.string.terms), icon = Icons.File, onClick = { open { openLink(context, TERMS_URL) } })
            SettingRow(title = stringResource(R.string.feedback), text = SUPPORT_EMAIL, icon = Icons.Mail, onClick = { open { writeToSupport(context) } })
            SettingRow(title = stringResource(R.string.licenses), icon = Icons.List, onClick = { model.open(Screen.Licenses) })
        }
    }
}

/** The third-party software in the app and the licence it comes under, with the licence text in full. */
@Composable
fun LicensesScreen(model: AppViewModel) {
    val resources = LocalResources.current
    val license = remember { resources.openRawResource(R.raw.apache_license_2_0).bufferedReader().use { it.readText() } }
    Page(title = stringResource(R.string.licenses), onBack = { model.back() }) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = PagePadding, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(stringResource(R.string.licenses_intro), style = MaterialTheme.typography.bodyLarge)
            Text(stringResource(R.string.licenses_components), style = MaterialTheme.typography.bodyMedium)
            HorizontalDivider(color = palette.rule)
            Text(license, style = MaterialTheme.typography.bodySmall, color = palette.secondary)
        }
    }
}
