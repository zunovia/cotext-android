import 'dart:async';

import 'package:cotext/native_stt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('classifySttError', () {
    test('silence and no match restart quietly', () {
      expect(classifySttError('error_no_match'), SttErrorKind.silent);
      expect(classifySttError('error_speech_timeout'), SttErrorKind.silent);
    });

    test('permission, language and network', () {
      expect(classifySttError('error_permission'), SttErrorKind.permission);
      expect(classifySttError('error_insufficient_permissions'),
          SttErrorKind.permission);
      expect(classifySttError('error_language_not_supported'),
          SttErrorKind.language);
      expect(classifySttError('error_language_unavailable'),
          SttErrorKind.language);
      expect(classifySttError('error_network'), SttErrorKind.network);
      expect(classifySttError('error_network_timeout'), SttErrorKind.network);
      expect(classifySttError('error_server'), SttErrorKind.network);
    });

    test('everything else is retried', () {
      for (final msg in [
        'error_busy',
        'error_client',
        'error_audio_error',
        'error_server_disconnected',
        'error_too_many_requests',
        'error_unknown (13)',
        '',
      ]) {
        expect(classifySttError(msg), SttErrorKind.retry, reason: msg);
      }
    });
  });

  group('resolveLocaleId', () {
    const device = [
      'en_US',
      'en_GB',
      'ja_JP',
      'cmn_CN',
      'vi_VN',
      'in_ID',
      'zh_TW'
    ];

    test('converts BCP-47 to the recognizer id', () {
      expect(resolveLocaleId('ja-JP', device), 'ja_JP');
      expect(resolveLocaleId('en-US', device), 'en_US');
      expect(resolveLocaleId('vi-VN', device), 'vi_VN');
    });

    test('falls back to the same language, preferring the same region', () {
      expect(resolveLocaleId('en-AU', device), 'en_US');
      expect(resolveLocaleId('zh-CN', device), 'cmn_CN');
      expect(resolveLocaleId('zh-CN', const ['zh_TW', 'zh_CN']), 'zh_CN');
      expect(resolveLocaleId('id-ID', device), 'in_ID');
      expect(resolveLocaleId('ja-JP', const ['ja-JP']), 'ja-JP');
      expect(resolveLocaleId('EN-us', device), 'en_US');
    });

    test('null when the language is missing', () {
      expect(resolveLocaleId('ko-KR', device), isNull);
      expect(resolveLocaleId('id-ID', const ['en_US']), isNull);
    });

    test('an empty device list uses the converted id', () {
      expect(resolveLocaleId('ja-JP', const []), 'ja_JP');
    });
  });

  group('NativeSttController', () {
    late FakeEngine engine;
    late List<Map<String, Object?>> sent;
    late List<FakeTimer> timers;
    late NativeSttController stt;

    setUp(() {
      engine = FakeEngine();
      sent = [];
      timers = [];
      stt = NativeSttController(
        engine: engine,
        send: sent.add,
        timer: (delay, callback) {
          final t = FakeTimer(delay, callback);
          timers.add(t);
          return t;
        },
      );
    });

    List<Object?> types() => sent.map((e) => e['type']).toList();

    /// Fires every pending timer once, letting the restarted listen() run.
    Future<void> fireTimers() async {
      final due = timers.where((t) => t.isActive).toList();
      for (final t in due) {
        t.fire();
      }
      await pumpEventQueue();
    }

    test('start reports listening and forwards partial and final results',
        () async {
      await stt.start('ja-JP');
      expect(engine.listenCalls, ['ja_JP']);
      expect(sent.first, {'type': 'stt.state', 'listening': true});

      engine.result('こん', false);
      engine.result('こんにちは', false);
      engine.result('こんにちは', true);
      expect(sent.sublist(1), [
        {'type': 'stt.partial', 'text': 'こん'},
        {'type': 'stt.partial', 'text': 'こんにちは'},
        {'type': 'stt.final', 'text': 'こんにちは'},
      ]);
    });

    test(
        'restarts after each utterance until stopped, without telling the page',
        () async {
      await stt.start('en-US');
      engine.result('hello', true);
      engine.status('notListening');
      engine.status('done');
      expect(timers.last.delay, NativeSttController.restartDelay);
      await fireTimers();
      expect(engine.listenCalls, ['en_US', 'en_US']);
      // Still one "listening: true" only: the restart is invisible to the page.
      expect(sent.where((e) => e['type'] == 'stt.state'), hasLength(1));

      stt.stop();
      expect(sent.last, {'type': 'stt.state', 'listening': false});
      expect(engine.stopCalls, 1);
      await fireTimers();
      expect(engine.listenCalls, hasLength(2));
    });

    test('silence and no match restart quietly', () async {
      await stt.start('ja-JP');
      engine.error('error_speech_timeout');
      engine.status('notListening');
      engine.status('done');
      await fireTimers();
      engine.error('error_no_match');
      engine.status('done');
      await fireTimers();
      expect(engine.listenCalls, hasLength(3));
      expect(types(), isNot(contains('stt.error')));
    });

    test('a run that ends on a partial result keeps it as the final line',
        () async {
      await stt.start('ja-JP');
      engine.result('ありがとう', false);
      engine.status('notListening'); // no final and no done follow
      expect(timers.last.delay, NativeSttController.doneFallback);
      await fireTimers(); // fallback → flush + schedule restart
      expect(sent.last, {'type': 'stt.final', 'text': 'ありがとう'});
      await fireTimers(); // restart
      expect(engine.listenCalls, hasLength(2));

      // A late final from the finished run is not sent twice.
      engine.staleResult(0, 'ありがとう', true);
      expect(sent.where((e) => e['type'] == 'stt.final'), hasLength(1));
    });

    test('done and the fallback for the same run restart only once', () async {
      await stt.start('ja-JP');
      engine.status('notListening');
      engine.status('done');
      await fireTimers();
      expect(engine.listenCalls, hasLength(2));
    });

    test('stop sends the pending partial as final before listening:false',
        () async {
      await stt.start('ja-JP');
      engine.result('途中まで', false);
      stt.stop();
      expect(sent.sublist(sent.length - 2), [
        {'type': 'stt.final', 'text': '途中まで'},
        {'type': 'stt.state', 'listening': false},
      ]);
      engine.result('途中まで話した', true); // arrives after stop
      expect(sent.last, {'type': 'stt.state', 'listening': false});
    });

    test('permission errors stop without restarting', () async {
      await stt.start('ja-JP');
      engine.error('error_permission');
      expect(sent.last, {'type': 'stt.error', 'code': 'permission'});
      expect(stt.isActive, isFalse);
      engine.status('done');
      await fireTimers();
      expect(engine.listenCalls, hasLength(1));
    });

    test('language errors from the recognizer stop', () async {
      await stt.start('vi-VN');
      engine.error('error_language_unavailable');
      expect(sent.last, {'type': 'stt.error', 'code': 'language'});
      expect(stt.isActive, isFalse);
    });

    test('a language missing on the device is reported before listening',
        () async {
      engine.locales = ['en_US'];
      await stt.start('vi-VN');
      expect(engine.listenCalls, isEmpty);
      expect(sent.last, {'type': 'stt.error', 'code': 'language'});
    });

    test('initialize failure: permission or unavailable', () async {
      engine.initOk = false;
      engine.micGranted = false;
      await stt.start('ja-JP');
      expect(sent.last, {'type': 'stt.error', 'code': 'permission'});

      engine.micGranted = true;
      await stt.start('ja-JP');
      expect(sent.last, {'type': 'stt.error', 'code': 'unavailable'});
      expect(engine.listenCalls, isEmpty);
    });

    test('five failures in a row give up', () async {
      await stt.start('ja-JP');
      for (var i = 0; i < 4; i++) {
        engine.error('error_busy');
        engine.status('done');
        expect(timers.last.delay, NativeSttController.retryDelay);
        await fireTimers();
      }
      expect(types(), isNot(contains('stt.error')));
      engine.error('error_client');
      expect(sent.last, {'type': 'stt.error', 'code': 'other'});
      expect(stt.isActive, isFalse);
    });

    test('network failures give up with network', () async {
      await stt.start('ja-JP');
      for (var i = 0; i < 5; i++) {
        engine.error('error_network');
        engine.status('done');
        await fireTimers();
      }
      expect(sent.last, {'type': 'stt.error', 'code': 'network'});
      expect(engine.listenCalls, hasLength(5));
    });

    test('a recognized result resets the failure count', () async {
      await stt.start('ja-JP');
      for (var i = 0; i < 4; i++) {
        engine.error('error_busy');
        engine.status('done');
        await fireTimers();
      }
      engine.result('はい', true);
      engine.error('error_busy');
      expect(types(), isNot(contains('stt.error')));
    });

    test('listen throwing counts as a failure and retries', () async {
      engine.listenThrows = true;
      await stt.start('ja-JP');
      for (var i = 0; i < 4; i++) {
        await fireTimers();
      }
      expect(engine.listenCalls, hasLength(5));
      expect(sent.last, {'type': 'stt.error', 'code': 'other'});
    });

    test('initializes the recognizer once', () async {
      await stt.start('ja-JP');
      stt.stop();
      await stt.start('en-US');
      expect(engine.initCalls, 1);
      expect(engine.listenCalls, ['ja_JP', 'en_US']);
    });

    test('start right after stop waits for the recognizer to finish stopping',
        () async {
      final gate = Completer<void>();
      engine.stopGate = gate.future;
      await stt.start('ja-JP');
      stt.stop();
      final restarted = stt.start('en-US');
      await Future<void>.delayed(Duration.zero);
      expect(engine.listenCalls, ['ja_JP'],
          reason: 'must not listen while stopping');
      gate.complete();
      await restarted;
      expect(engine.listenCalls, ['ja_JP', 'en_US']);
    });

    test('a start superseded while waiting for the stop never listens',
        () async {
      final gate = Completer<void>();
      engine.stopGate = gate.future;
      await stt.start('ja-JP');
      stt.stop();
      final restarted = stt.start('en-US');
      stt.stop();
      gate.complete();
      await restarted;
      expect(engine.listenCalls, ['ja_JP']);
    });

    test('stop when idle sends nothing', () {
      stt.stop();
      expect(sent, isEmpty);
    });
  });
}

class FakeEngine implements SttEngine {
  bool initOk = true;
  bool micGranted = true;
  bool listenThrows = false;
  List<String> locales = ['ja_JP', 'en_US', 'vi_VN', 'zh_CN', 'id_ID'];
  int initCalls = 0;
  int stopCalls = 0;
  Future<void>? stopGate;
  final List<String> listenCalls = [];
  final List<void Function(String, bool)> _resultCallbacks = [];
  void Function(String)? _onStatus;
  void Function(String)? _onError;

  void result(String text, bool isFinal) =>
      _resultCallbacks.last(text, isFinal);
  void staleResult(int run, String text, bool isFinal) =>
      _resultCallbacks[run](text, isFinal);
  void status(String s) => _onStatus!(s);
  void error(String e) => _onError!(e);

  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String errorMsg) onError,
  }) async {
    initCalls++;
    _onStatus = onStatus;
    _onError = onError;
    return initOk;
  }

  @override
  Future<bool> hasMicPermission() async => micGranted;

  @override
  Future<List<String>> localeIds() async => locales;

  @override
  Future<void> listen({
    required String localeId,
    required void Function(String text, bool isFinal) onResult,
  }) async {
    listenCalls.add(localeId);
    _resultCallbacks.add(onResult);
    if (listenThrows) throw StateError('listen failed');
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    await stopGate;
  }
}

class FakeTimer implements Timer {
  FakeTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}
