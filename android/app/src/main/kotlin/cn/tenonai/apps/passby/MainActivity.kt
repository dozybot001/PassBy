package cn.tenonai.apps.passby

import android.os.Bundle
import android.view.WindowManager
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.fragment.app.FragmentActivity
import cn.tenonai.apps.passby.system.Gate
import cn.tenonai.apps.passby.ui.App
import cn.tenonai.apps.passby.ui.AppViewModel
import cn.tenonai.apps.passby.ui.PassByTheme

/** The app's only screen. It is a FragmentActivity because the system's verification prompt needs one. */
class MainActivity : FragmentActivity() {
    private val model: AppViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Keeps the notebook out of screenshots, screen recordings and the recent-apps preview.
        // Dialogs and menus inherit it.
        window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE)
        enableEdgeToEdge()
        setContent {
            PassByTheme {
                App(model, this)
            }
        }
    }

    override fun onStart() {
        super.onStart()
        model.onForeground(Gate.deviceHasLock(this))
    }

    override fun onStop() {
        super.onStop()
        model.onBackground()
    }
}
