package id.ac.uph.bearinvasion.bearch

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestHighestRefreshRate()
    }

    /**
     * Flutter apps run at 60Hz on Android unless they ask for more. Pick the
     * fastest display mode with the current resolution (e.g. 120Hz) so scrolling
     * matches the system UI. The OS may still lower it for battery saving.
     */
    private fun requestHighestRefreshRate() {
        val display = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else null)
            ?: @Suppress("DEPRECATION") windowManager.defaultDisplay
            ?: return
        val current = display.mode
        val best = display.supportedModes
            .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
            .maxByOrNull { it.refreshRate } ?: return
        window.attributes = window.attributes.also { it.preferredDisplayModeId = best.modeId }
    }
}
