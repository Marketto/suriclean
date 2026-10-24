package com.suriclean.app

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.runtime.LaunchedEffect

class MainActivity : ComponentActivity() {
    private val vm: AppVM by viewModels()

    private val launcher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) {
        // after an uninstall dialog, go on with the next app in the queue
        if (vm.uninstallQueue.isNotEmpty()) vm.nextUninstall() else vm.refresh()
    }

    private val legacyPerms = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { vm.refresh() }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        if (Build.VERSION.SDK_INT < 30) {
            legacyPerms.launch(arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE, Manifest.permission.WRITE_EXTERNAL_STORAGE))
        }
        setContent {
            val pending = vm.pendingIntent
            LaunchedEffect(pending) {
                if (pending != null) {
                    vm.pendingIntent = null
                    try { launcher.launch(pending) } catch (e: Exception) { vm.showToast("Android non ha aperto la schermata richiesta") }
                }
            }
            SuriApp(vm)
        }
    }

    override fun onResume() {
        super.onResume()
        vm.refresh()
        Chiptune.start()
    }

    override fun onPause() {
        super.onPause()
        Chiptune.stop()
    }
}
