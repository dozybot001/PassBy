package cn.tenonai.apps.passby.ui

import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import cn.tenonai.apps.passby.R
import cn.tenonai.apps.passby.core.SyncCrypto
import cn.tenonai.apps.passby.core.SyncHost
import cn.tenonai.apps.passby.core.SyncSummary

private const val WEB_APP = "https://passby.tenonai.cn/app/"

/** A value to read off this screen and type on the other device. */
@Composable
private fun ReadOut(label: String, value: String) {
    Column {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = palette.secondary)
        SelectionContainer {
            Text(value, style = MaterialTheme.typography.headlineSmall, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.SemiBold)
        }
    }
}

@Composable
private fun Result(summary: SyncSummary) {
    Column(
        Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(palette.wash).padding(16.dp)
            .semantics { liveRegion = LiveRegionMode.Polite },
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text(stringResource(R.string.sync_done), style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
        val nothing = summary.added == 0 && summary.updated == 0 && summary.removed == 0 && summary.conflicts == 0
        Text(
            if (nothing) stringResource(R.string.sync_result_same) else stringResource(R.string.sync_result, summary.added, summary.updated, summary.removed),
            style = MaterialTheme.typography.bodyMedium,
        )
        if (summary.conflicts > 0) Text(stringResource(R.string.sync_conflict_note, summary.conflicts), style = MaterialTheme.typography.bodyMedium)
        if (summary.removed > 0) Text(stringResource(R.string.sync_removed_note), style = MaterialTheme.typography.bodyMedium)
    }
}

/**
 * Sync with another device on the same local network (docs/sync.md). This phone either listens,
 * showing an address and a pairing code, or connects to a phone that is listening. Listening ends
 * when the page is left.
 */
@Composable
fun SyncScreen(model: AppViewModel) {
    val context = LocalContext.current
    val hosting = model.syncHosting
    var address by rememberSaveable(model.syncLastAddress) { mutableStateOf(model.syncLastAddress) }
    var code by rememberSaveable { mutableStateOf("") }
    LaunchedEffect(Unit) { model.syncRefresh() }

    Page(title = stringResource(R.string.sync), onBack = { model.back() }) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = PagePadding, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Text(stringResource(R.string.sync_intro), style = MaterialTheme.typography.bodyLarge)
            model.syncSummary?.let { Result(it) }
            model.syncError?.let {
                Text(stringResource(it), Modifier.semantics { liveRegion = LiveRegionMode.Polite }, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
            }
            model.syncStopped?.let {
                Text(
                    stringResource(
                        when (it) {
                            SyncHost.Stop.IDLE -> R.string.sync_stopped_idle
                            SyncHost.Stop.WRONG_CODE -> R.string.sync_stopped_wrong_code
                            else -> R.string.sync_stopped_failed
                        },
                    ),
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                )
            }

            HorizontalDivider(color = palette.rule)
            SectionLabel(stringResource(R.string.sync_this_phone))
            if (hosting != null) {
                ReadOut(stringResource(R.string.sync_address), hosting.address.toString())
                ReadOut(stringResource(R.string.sync_code), SyncCrypto.display(hosting.code))
                Text(stringResource(R.string.sync_host_waiting), style = MaterialTheme.typography.bodyMedium, color = palette.secondary)
                SecondaryButton(stringResource(R.string.sync_host_stop), onClick = model::syncHostStop, icon = Icons.Close)
            } else {
                PrimaryButton(stringResource(R.string.sync_host_start), onClick = model::syncHostStart, enabled = !model.syncWorking, icon = Icons.Refresh)
                val own = model.syncAddress
                if (own != null) {
                    val message = stringResource(R.string.sync_link_message, "$WEB_APP#$own")
                    LinkButton(stringResource(R.string.sync_send_link), Icons.Share, onClick = {
                        val send = Intent(Intent.ACTION_SEND).setType("text/plain")
                            .putExtra(Intent.EXTRA_TEXT, message)
                        context.startActivity(Intent.createChooser(send, null))
                    })
                    Text(stringResource(R.string.sync_send_link_text), style = MaterialTheme.typography.bodySmall, color = palette.secondary)
                }

                HorizontalDivider(color = palette.rule)
                SectionLabel(stringResource(R.string.sync_other_phone))
                Text(stringResource(R.string.sync_other_phone_text), style = MaterialTheme.typography.bodyMedium, color = palette.secondary)
                OutlinedTextField(
                    value = address,
                    onValueChange = { address = it.take(24) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.sync_address)) },
                    placeholder = { Text("192.168.1.20:52814") },
                    singleLine = true,
                    enabled = !model.syncWorking,
                    textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.None, autoCorrectEnabled = false, keyboardType = KeyboardType.Uri),
                )
                OutlinedTextField(
                    value = code,
                    onValueChange = { code = it.take(20) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text(stringResource(R.string.sync_code)) },
                    placeholder = { Text("XXXX-XXXX-XXXX") },
                    singleLine = true,
                    enabled = !model.syncWorking,
                    textStyle = LocalTextStyle.current.copy(fontFamily = FontFamily.Monospace),
                    keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, autoCorrectEnabled = false, keyboardType = KeyboardType.Password),
                )
                PrimaryButton(
                    stringResource(if (model.syncWorking) R.string.sync_working else R.string.sync_join),
                    onClick = {
                        model.syncJoin(address, code)
                        code = ""
                    },
                    enabled = !model.syncWorking && address.isNotBlank() && code.isNotBlank(),
                    icon = Icons.Check,
                )
            }
        }
    }
}
