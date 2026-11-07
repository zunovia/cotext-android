/// Keyless speech recognition with the device's recognizer (Android SpeechRecognizer
/// through the speech_to_text plugin). The controller logic is plugin-free and tested
/// in test/native_stt_test.dart with a fake engine.
///
/// Android's recognizer ends after each utterance or a few seconds of silence. The web
/// app wants one continuous session between `stt.start` and `stt.stop`, so the
/// controller restarts it until it is told to stop.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Error codes of the bridge (`stt.error`).
abstract final class SttErrorCode {
  static const permission = 'permission';
  static const unavailable = 'unavailable';
  static const language = 'language';
  static const network = 'network';
  static const other = 'other';
}

enum SttErrorKind {
  /// Silence or nothing recognized: restart quietly.
  silent,

  /// Microphone permission missing: stop.
  permission,

  /// The language is not available on this device: stop.
  language,

  /// Network or server: retry, give up after [maxConsecutiveFailures].
  network,

  /// Anything else (busy, client, audio...): retry, give up after [maxConsecutiveFailures].
  retry,
}

/// Maps a speech_to_text error message (e.g. `error_no_match`) to what to do.
SttErrorKind classifySttError(String errorMsg) {
  final msg = errorMsg.trim();
  if (msg == 'error_no_match' || msg == 'error_speech_timeout') return SttErrorKind.silent;
  if (msg == 'error_permission' || msg == 'error_insufficient_permissions') {
    return SttErrorKind.permission;
  }
  if (msg == 'error_language_not_supported' || msg == 'error_language_unavailable') {
    return SttErrorKind.language;
  }
  if (msg.startsWith('error_network') || msg == 'error_server') return SttErrorKind.network;
  return SttErrorKind.retry;
}

const Map<String, List<String>> _languageAliases = {
  'zh': ['zh', 'cmn'],
  'id': ['id', 'in'],
};

/// Picks the recognizer locale for a BCP-47 tag (`ja-JP` → `ja_JP`).
///
/// Exact match first, then the same language (preferring the same region), else
/// null. When the device lists no locales at all (some recognizers do not report
/// them), the converted id is used as is.
String? resolveLocaleId(String bcp47, List<String> available) {
  final requested = bcp47.replaceAll('-', '_');
  if (available.isEmpty) return requested;

  String norm(String id) => id.replaceAll('-', '_').toLowerCase();
  final want = norm(requested);
  for (final id in available) {
    if (norm(id) == want) return id;
  }

  final parts = want.split('_');
  final lang = parts.first;
  final region = parts.length > 1 ? parts.last : null;
  final langs = _languageAliases[lang] ?? [lang];
  final sameLanguage = available.where((id) => langs.contains(norm(id).split('_').first)).toList();
  if (sameLanguage.isEmpty) return null;
  if (region != null) {
    for (final id in sameLanguage) {
      if (norm(id).split('_').contains(region)) return id;
    }
  }
  return sameLanguage.first;
}

/// The part of the recognizer the controller needs (faked in tests).
abstract class SttEngine {
  /// False when recognition cannot be used (no recognizer or no permission).
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String errorMsg) onError,
  });

  Future<bool> hasMicPermission();

  Future<List<String>> localeIds();

  Future<void> listen({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
  });

  Future<void> stop();
}

/// Statuses reported by speech_to_text.
abstract final class SttStatus {
  static const listening = 'listening';
  static const notListening = 'notListening';
  static const done = 'done';
}

typedef TimerFactory = Timer Function(Duration delay, void Function() callback);

/// Runs one continuous session for the bridge and reports bridge events through [send].
class NativeSttController {
  NativeSttController({
    required this.engine,
    required this.send,
    TimerFactory? timer,
  }) : _timer = timer ?? Timer.new;

  final SttEngine engine;

  /// Receives `detail` maps (`stt.state`, `stt.partial`, `stt.final`, `stt.error`).
  final void Function(Map<String, Object?> detail) send;
  final TimerFactory _timer;

  static const restartDelay = Duration(milliseconds: 300);
  static const retryDelay = Duration(milliseconds: 1000);

  /// After `notListening` the plugin sends `done` once the final result is in.
  /// If it never comes (the utterance ended without a final result), restart anyway.
  static const doneFallback = Duration(seconds: 3);
  static const maxConsecutiveFailures = 5;

  bool _initialized = false;
  bool _active = false;
  bool _listening = false; // what the web was last told
  String? _localeId;
  int _generation = 0; // bumped for every listen() and stop; stale callbacks are ignored
  int _failures = 0;
  String _lastFailureCode = SttErrorCode.other;
  String _pendingPartial = '';
  bool _runEnded = false; // `done` and the fallback may both arrive for one run
  Timer? _restartTimer;
  Timer? _fallbackTimer;

  bool get isActive => _active;

  Future<void> start(String lang) async {
    if (_active) _end(sendState: false);
    _active = true;
    _failures = 0;
    final generation = ++_generation;

    if (!_initialized) {
      bool ok;
      try {
        ok = await engine.initialize(onStatus: _onStatus, onError: _onError);
      } catch (e) {
        debugPrint('[stt] initialize failed: $e');
        ok = false;
      }
      if (generation != _generation) return;
      if (!ok) {
        bool granted;
        try {
          granted = await engine.hasMicPermission();
        } catch (_) {
          granted = true;
        }
        if (generation != _generation) return;
        _fail(granted ? SttErrorCode.unavailable : SttErrorCode.permission);
        return;
      }
      _initialized = true;
    }

    List<String> locales;
    try {
      locales = await engine.localeIds();
    } catch (e) {
      debugPrint('[stt] locales failed: $e');
      locales = const [];
    }
    if (generation != _generation) return;
    final localeId = resolveLocaleId(lang, locales);
    if (localeId == null) {
      _fail(SttErrorCode.language);
      return;
    }
    _localeId = localeId;
    _setListening(true);
    await _listen();
  }

  /// Stops the session (from `stt.stop`, a page change or the app going to the background).
  void stop() {
    if (!_active) return;
    _end(sendState: true);
  }

  void dispose() {
    _active = false;
    _generation++;
    _cancelTimers();
  }

  Future<void> _listen() async {
    if (!_active) return;
    final generation = ++_generation;
    _pendingPartial = '';
    _runEnded = false;
    try {
      await engine.listen(
        localeId: _localeId!,
        onResult: (text, isFinal) {
          if (generation != _generation || !_active) return;
          _failures = 0;
          if (isFinal) {
            _pendingPartial = '';
            if (text.trim().isNotEmpty) send({'type': 'stt.final', 'text': text});
          } else {
            _pendingPartial = text;
            send({'type': 'stt.partial', 'text': text});
          }
        },
      );
    } catch (e) {
      debugPrint('[stt] listen failed: $e');
      if (generation != _generation) return;
      _countFailure(SttErrorCode.other);
      if (_active) _scheduleRestart(retryDelay);
    }
  }

  void _onStatus(String status) {
    if (!_active) return;
    if (status == SttStatus.done) {
      _sessionEnded();
    } else if (status == SttStatus.notListening) {
      _fallbackTimer?.cancel();
      _fallbackTimer = _timer(doneFallback, _sessionEnded);
    }
  }

  void _onError(String errorMsg) {
    if (!_active) return;
    switch (classifySttError(errorMsg)) {
      case SttErrorKind.silent:
        return; // `done` follows and restarts quietly
      case SttErrorKind.permission:
        _fail(SttErrorCode.permission);
      case SttErrorKind.language:
        _fail(SttErrorCode.language);
      case SttErrorKind.network:
        _countFailure(SttErrorCode.network);
      case SttErrorKind.retry:
        _countFailure(SttErrorCode.other);
    }
  }

  void _countFailure(String code) {
    _failures++;
    _lastFailureCode = code;
    if (_failures >= maxConsecutiveFailures) _fail(_lastFailureCode);
  }

  /// One recognizer run finished: keep what was heard and start the next run.
  void _sessionEnded() {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
    if (!_active || _runEnded) return;
    _runEnded = true;
    _flushPartial();
    _scheduleRestart(_failures > 0 ? retryDelay : restartDelay);
  }

  void _scheduleRestart(Duration delay) {
    if (_restartTimer != null) return;
    // Results of the finished run arriving late would duplicate the flushed text.
    _generation++;
    _restartTimer = _timer(delay, () {
      _restartTimer = null;
      unawaited(_listen());
    });
  }

  /// A run that ended on a partial result never gets its final one once the next
  /// run starts, so the partial becomes the final line.
  void _flushPartial() {
    final text = _pendingPartial;
    _pendingPartial = '';
    if (text.trim().isNotEmpty) send({'type': 'stt.final', 'text': text});
  }

  void _fail(String code) {
    _end(sendState: true);
    send({'type': 'stt.error', 'code': code});
  }

  void _end({required bool sendState}) {
    final wasRunning = _active;
    _active = false;
    _generation++;
    _cancelTimers();
    _flushPartial();
    if (wasRunning && _initialized) {
      unawaited(engine.stop().catchError((Object e) => debugPrint('[stt] stop failed: $e')));
    }
    if (sendState) {
      _setListening(false, force: true);
    } else {
      _listening = false;
    }
  }

  void _setListening(bool value, {bool force = false}) {
    if (_listening == value && !force) return;
    _listening = value;
    send({'type': 'stt.state', 'listening': value});
  }

  void _cancelTimers() {
    _restartTimer?.cancel();
    _restartTimer = null;
    _fallbackTimer?.cancel();
    _fallbackTimer = null;
  }
}

/// [SttEngine] backed by the speech_to_text plugin.
class SpeechToTextEngine implements SttEngine {
  final SpeechToText _speech = SpeechToText();

  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String errorMsg) onError,
  }) {
    return _speech.initialize(
      onStatus: onStatus,
      onError: (SpeechRecognitionError e) => onError(e.errorMsg),
    );
  }

  @override
  Future<bool> hasMicPermission() => Permission.microphone.isGranted;

  @override
  Future<List<String>> localeIds() async =>
      (await _speech.locales()).map((l) => l.localeId).toList();

  @override
  Future<void> listen({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
  }) async {
    await _speech.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: localeId,
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: false,
      ),
    );
  }

  @override
  Future<void> stop() => _speech.stop();
}

/// Whether the device has a speech recognition service (checked natively in
/// MainActivity; needs the RecognitionService `<queries>` entry on Android 11+).
Future<bool> isRecognitionAvailable() async {
  try {
    return await const MethodChannel('online.surc.cotext/speech')
            .invokeMethod<bool>('isRecognitionAvailable') ??
        false;
  } on MissingPluginException {
    return true; // older template without the channel: let `stt.start` find out
  } catch (e) {
    debugPrint('[stt] availability check failed: $e');
    return true;
  }
}
