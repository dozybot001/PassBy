package cn.tenonai.apps.passby.system

import android.app.KeyguardManager
import android.content.Context
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity

/**
 * The one door in front of the notebook: the system verifies the person with a fingerprint or face,
 * or with the screen lock when there is neither. The app only learns whether it succeeded.
 */
object Gate {
    /** How long the app can be out of sight before it asks again. */
    const val AWAY_LIMIT_MS = 5 * 60 * 1000L

    /** False when the phone has no PIN, pattern or password. Then there is nothing to verify against. */
    fun deviceHasLock(context: Context): Boolean =
        context.getSystemService(KeyguardManager::class.java).isDeviceSecure

    fun authenticate(activity: FragmentActivity, title: String, subtitle: String?, onResult: (Boolean) -> Unit) {
        val callback = object : BiometricPrompt.AuthenticationCallback() {
            override fun onAuthenticationSucceeded(result: BiometricPrompt.AuthenticationResult) = onResult(true)

            // Cancelled, timed out, or locked out. A single finger that did not match is not reported
            // here; the prompt stays open for another try.
            override fun onAuthenticationError(errorCode: Int, errString: CharSequence) = onResult(false)
        }
        val info = BiometricPrompt.PromptInfo.Builder()
            .setTitle(title)
            .apply { if (subtitle != null) setSubtitle(subtitle) }
            .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_WEAK or BiometricManager.Authenticators.DEVICE_CREDENTIAL)
            .setConfirmationRequired(false)
            .build()
        BiometricPrompt(activity, ContextCompat.getMainExecutor(activity), callback).authenticate(info)
    }
}
