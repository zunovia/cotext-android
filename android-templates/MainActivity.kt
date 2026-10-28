package online.surc.cotext

import android.os.Bundle
import androidx.activity.enableEdgeToEdge
import io.flutter.embedding.android.FlutterFragmentActivity

// Draw behind the system bars on every Android version, not only on 15+ where it is
// enforced (Play recommendation). The Flutter side keeps content clear of the bars
// with SafeArea. FlutterFragmentActivity is a ComponentActivity, which enableEdgeToEdge needs.
class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
    }
}
