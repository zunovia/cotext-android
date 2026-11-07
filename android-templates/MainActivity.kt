package online.surc.cotext

import android.graphics.Color
import android.os.Bundle
import android.speech.SpeechRecognizer
import androidx.activity.SystemBarStyle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// Draw behind the system bars on every Android version, not only on 15+ where it is
// enforced (Play recommendation). The Flutter side keeps content clear of the bars
// with SafeArea. FlutterFragmentActivity is a ComponentActivity, which enableEdgeToEdge needs.
//
// The UI (Flutter theme and the web page) is light-only, so the bars use the light style
// (dark icons). The default follows night mode and drew white icons on the light
// background in dark mode.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.light(Color.TRANSPARENT, Color.TRANSPARENT),
        )
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine) // registers the plugins
        // Tells the web app (caps.stt in `ready`) whether keyless recognition can work.
        // Needs the RecognitionService <queries> entry on Android 11+ (prepare-android.sh).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "online.surc.cotext/speech")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isRecognitionAvailable" ->
                        result.success(SpeechRecognizer.isRecognitionAvailable(this))
                    else -> result.notImplemented()
                }
            }
    }
}
