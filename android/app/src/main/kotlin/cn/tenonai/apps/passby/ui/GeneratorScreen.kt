package cn.tenonai.apps.passby.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import cn.tenonai.apps.passby.R
import cn.tenonai.apps.passby.core.PasswordGenerator
import cn.tenonai.apps.passby.core.PasswordOptions
import kotlin.math.roundToInt

/** Makes a random password. From the editor it fills the password field; from the list it is only copied. */
@Composable
fun GeneratorScreen(model: AppViewModel, forEditor: Boolean) {
    var options by remember { mutableStateOf(PasswordOptions()) }
    var lengthText by remember { mutableStateOf(options.length.toString()) }
    // Counts the taps on Generate another, so the same options give a new password.
    var round by remember { mutableIntStateOf(0) }
    val password = remember(options, round) { if (options.isValid) PasswordGenerator.generate(options) else null }
    val lengthLabel = stringResource(R.string.password_length)

    fun setLength(text: String) {
        lengthText = text.filter { it.isDigit() }.take(4)
        // An unreadable or out-of-range length is kept as typed and reported; the last valid one is not used for it.
        options = options.copy(length = lengthText.toIntOrNull() ?: 0)
    }

    Page(title = stringResource(R.string.generator_open), onBack = { model.back() }) {
        Column(
            Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = PagePadding, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            SectionLabel(stringResource(R.string.generated_password))
            Text(
                password ?: "",
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(16.dp))
                    .background(palette.wash)
                    .heightIn(min = 72.dp)
                    .padding(16.dp),
                style = MaterialTheme.typography.titleMedium,
                fontFamily = FontFamily.Monospace,
            )
            SecondaryButton(stringResource(R.string.generate_another), onClick = { round++ }, enabled = options.isValid)

            SectionLabel(stringResource(R.string.length))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                val shown = options.length.coerceIn(PasswordOptions.COMMON_LENGTHS)
                Slider(
                    value = shown.toFloat(),
                    onValueChange = { setLength(it.roundToInt().toString()) },
                    modifier = Modifier.weight(1f).semantics { contentDescription = lengthLabel },
                    valueRange = PasswordOptions.COMMON_LENGTHS.first.toFloat()..PasswordOptions.COMMON_LENGTHS.last.toFloat(),
                    steps = PasswordOptions.COMMON_LENGTHS.last - PasswordOptions.COMMON_LENGTHS.first - 1,
                )
                OutlinedTextField(
                    value = lengthText,
                    onValueChange = { setLength(it) },
                    modifier = Modifier.width(96.dp).semantics { contentDescription = lengthLabel },
                    singleLine = true,
                    isError = options.length !in PasswordOptions.LENGTHS,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
                )
            }
            Text(
                stringResource(if (options.length in PasswordOptions.LENGTHS) R.string.generator_length_help else R.string.generator_length_error),
                style = MaterialTheme.typography.bodySmall,
                color = if (options.length in PasswordOptions.LENGTHS) palette.secondary else palette.accent,
            )

            Column {
                Toggle(stringResource(R.string.lowercase), options.lowercase) { options = options.copy(lowercase = it) }
                Toggle(stringResource(R.string.uppercase), options.uppercase) { options = options.copy(uppercase = it) }
                Toggle(stringResource(R.string.digits), options.digits) { options = options.copy(digits = it) }
                Toggle(stringResource(R.string.symbols), options.symbols) { options = options.copy(symbols = it) }
            }
            if (options.alphabets.isEmpty()) {
                Text(stringResource(R.string.generator_types_error), style = MaterialTheme.typography.bodySmall, color = palette.accent)
            }
            Text(stringResource(R.string.generator_tip), style = MaterialTheme.typography.bodySmall, color = palette.secondary)
        }
        Column(Modifier.fillMaxWidth().padding(horizontal = PagePadding, vertical = 12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            PrimaryButton(
                stringResource(if (forEditor) R.string.use_password else R.string.copy_password),
                onClick = {
                    if (password != null) {
                        if (forEditor) model.useGenerated(password) else model.copyGenerated(password)
                        model.back()
                    }
                },
                modifier = Modifier.fillMaxWidth(),
                enabled = password != null,
            )
            Text(
                stringResource(if (forEditor) R.string.generator_fill_note else R.string.generator_copy_note),
                style = MaterialTheme.typography.bodySmall,
                color = palette.secondary,
            )
        }
    }
}

/** A labelled switch. The whole row is one control for screen readers. */
@Composable
fun Toggle(label: String, checked: Boolean, enabled: Boolean = true, onChange: (Boolean) -> Unit) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = 52.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, Modifier.weight(1f), style = MaterialTheme.typography.bodyLarge)
        Switch(checked = checked, onCheckedChange = onChange, enabled = enabled, modifier = Modifier.semantics { contentDescription = label })
    }
}
