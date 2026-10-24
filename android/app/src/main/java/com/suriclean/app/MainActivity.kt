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

    private val launcher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        // cache screen result, or the next app in the uninstall queue
        vm.onSystemResult(r.resultCode == RESULT_OK)
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
                    try { launcher.launch(pending) } catch (e: Exception) {
                        @Suppress("DEPRECATION")
                        if (pending.action == android.content.Intent.ACTION_UNINSTALL_PACKAGE) {
                            // some phones refuse the uninstall-with-result screen: use the plain one
                            try { launcher.launch(android.content.Intent(android.content.Intent.ACTION_DELETE, pending.data)) }
                            catch (e2: Exception) { vm.showToast("Android non mi lascia disinstallare: usa ⚙️ sull'app ♡"); vm.uninstallQueue.clear() }
                        } else { vm.showToast("Android non ha aperto la schermata richiesta"); vm.onSystemResult(false) }
                    }
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
