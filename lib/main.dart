import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'app_info.dart';
import 'app_updater.dart';
import 'bridge.dart';
import 'native_stt.dart';
import 'strings.dart';
import 'url_policy.dart';

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

class _WebViewScreenState extends State<WebViewScreen> with WidgetsBindingObserver {
  late final WebViewController _controller;
  late final NativeSttController _stt;
  late final AppUpdater _updater;
  late final Future<NativeCaps> _caps;
  final ReviewGate _reviewGate = ReviewGate();

  bool _isLoading = true;
  bool _hasError = false;
  bool _updateReady = false;
  bool _updateBarHidden = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _stt = NativeSttController(engine: SpeechToTextEngine(), send: _sendToPage);
    _updater = AppUpdater(onReady: () {
      if (mounted && !_updateReady) setState(() => _updateReady = true);
    });
    _caps = _detectCaps();
    _initWebView();
    _startApp();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_updater.checkOnLaunch()));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stt.dispose();
    _updater.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Not on `inactive`: the permission dialog and the notification shade cause it.
    if (state == AppLifecycleState.hidden || state == AppLifecycleState.paused) {
      _stt.stop();
    }
  }

  Future<NativeCaps> _detectCaps() async {
    var review = false;
    try {
      review = await InAppReview.instance.isAvailable();
    } catch (e) {
      debugPrint('[review] availability check failed: $e');
    }
    return NativeCaps(stt: await isRecognitionAvailable(), review: review, share: true);
  }

  /// Request microphone permission, then load the WebView URL.
  Future<void> _startApp() async {
    final status = await Permission.microphone.request();
    if (status.isPermanentlyDenied && mounted) {
      _showPermissionDeniedDialog();
    }
    _controller.loadRequest(Uri.parse(appUrl));
  }

  /// Read on every use so a language change in device settings applies at once.
  AppStrings get _s =>
      AppStrings.resolve(WidgetsBinding.instance.platformDispatcher.locales);

  void _showPermissionDeniedDialog() {
    final s = _s;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.micTitle),
        content: Text(s.micBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.later),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              openAppSettings();
            },
            child: Text(s.openSettings),
          ),
        ],
      ),
    );
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(userAgent)
      ..addJavaScriptChannel(channelName, onMessageReceived: _onPageMessage)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (request.isMainFrame && shouldOpenExternally(request.url)) {
              unawaited(_openExternally(request.url));
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) {
            // A new document cannot receive the old session's events.
            _stt.stop();
            if (mounted) setState(() { _isLoading = true; _hasError = false; });
          },
          onPageFinished: (url) {
            if (mounted) setState(() => _isLoading = false);
            unawaited(_sendReady(url));
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

  Future<void> _openExternally(String url) async {
    try {
      final uri = Uri.parse(url);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        debugPrint('[link] no app to open $url');
      }
    } catch (e) {
      debugPrint('[link] could not open $url: $e');
    }
  }

  Future<void> _sendReady(String url) async {
    if (!isTrustedUrl(url)) return;
    try {
      final caps = await _caps;
      await _controller.runJavaScript(buildReadyScript(caps, appVersion));
    } catch (e) {
      debugPrint('[bridge] ready failed: $e');
    }
  }

  /// Sends one event to the page, only while the WebView shows the trusted site.
  void _sendToPage(Map<String, Object?> detail) {
    unawaited(() async {
      try {
        if (!isTrustedUrl(await _controller.currentUrl())) return;
        await _controller.runJavaScript(buildDispatchScript(detail));
      } catch (e) {
        debugPrint('[bridge] send failed: $e');
      }
    }());
  }

  Future<void> _onPageMessage(JavaScriptMessage message) async {
    try {
      // Ignore messages from any other site the WebView may have navigated to.
      if (!isTrustedUrl(await _controller.currentUrl())) return;
      final command = parseBridgeMessage(message.message);
      switch (command) {
        case null:
          return;
        case HelloCommand():
          final url = await _controller.currentUrl();
          if (url != null) await _sendReady(url);
        case SttStartCommand(:final lang):
          await _stt.start(lang);
        case SttStopCommand():
          _stt.stop();
        case ReviewRequestCommand():
          if (!_reviewGate.tryUse()) return;
          final review = InAppReview.instance;
          if (await review.isAvailable()) await review.requestReview();
        case ShareCommand(:final text):
          await SharePlus.instance.share(ShareParams(text: text));
      }
    } catch (e) {
      debugPrint('[bridge] message failed: $e');
    }
  }

  void _retry() {
    setState(() { _hasError = false; _isLoading = true; });
    _controller.loadRequest(Uri.parse(appUrl));
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
          // The update bar pushes the page down instead of covering it: the web app
          // keeps its big record button at the bottom, so the bar goes on top.
          child: Column(
            children: [
              if (_updateReady && !_updateBarHidden) _buildUpdateBar(),
              Expanded(
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
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpdateBar() {
    final s = _s;
    return MaterialBanner(
      content: Text(s.updateReady),
      leading: const Icon(Icons.system_update, color: Color(0xFF3B6FD9)),
      actions: [
        TextButton(
          // Hidden until the next launch.
          onPressed: () => setState(() => _updateBarHidden = true),
          child: Text(s.updateLater),
        ),
        FilledButton(
          onPressed: _updater.completeUpdate,
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFF3B6FD9)),
          child: Text(s.updateRestart),
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    final s = _s;
    // Opaque, so the WebView's own error page underneath does not show through.
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              Text(
                s.loadErrorTitle,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                s.loadErrorBody,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: Text(s.reload),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B6FD9),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
