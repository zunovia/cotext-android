import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const CotextApp());
}

class CotextApp extends StatelessWidget {
  const CotextApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cotext',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF3B6FD9)),
        useMaterial3: true,
      ),
      home: const WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key});

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _hasError = false;

  static const _appUrl = 'https://koe-app.pages.dev/';

  @override
  void initState() {
    super.initState();
    _initWebView();
    _startApp();
  }

  /// Request microphone permission, then load the WebView URL.
  Future<void> _startApp() async {
    final status = await Permission.microphone.request();
    if (status.isPermanentlyDenied && mounted) {
      _showPermissionDeniedDialog();
    }
    _controller.loadRequest(Uri.parse(_appUrl));
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('マイクの許可が必要です'),
        content: const Text(
          'Cotextは音声機能を使用するためにマイクへのアクセスが必要です。\n'
          '設定画面からマイクの使用を許可してください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('後で'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            child: const Text('設定を開く'),
          ),
        ],
      ),
    );
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('CotextAndroid/1.0')
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() { _isLoading = true; _hasError = false; });
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (error) {
            // Only treat main frame errors as fatal
            if (error.isForMainFrame ?? false) {
              if (mounted) setState(() { _hasError = true; _isLoading = false; });
            }
          },
        ),
      );

    // Enable microphone access in WebView (Android only)
    if (defaultTargetPlatform == TargetPlatform.android) {
      final androidController =
          _controller.platform as AndroidWebViewController;
      androidController.setOnPlatformPermissionRequest((request) {
        // Only grant microphone permission; deny all others
        final allowedTypes = <WebViewPermissionResourceType>{
          WebViewPermissionResourceType.microphone,
        };
        if (request.types.any(allowedTypes.contains)) {
          request.grant();
        } else {
          request.deny();
        }
      });
    }
  }

  void _retry() {
    setState(() { _hasError = false; _isLoading = true; });
    _controller.loadRequest(Uri.parse(_appUrl));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else {
          if (context.mounted) {
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              WebViewWidget(controller: _controller),
              if (_hasError) _buildErrorView(),
              if (_isLoading && !_hasError)
                const Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFF3B6FD9),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text(
              'ページを読み込めませんでした',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'インターネット接続を確認して、もう一度お試しください。',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh),
              label: const Text('再読み込み'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B6FD9),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
