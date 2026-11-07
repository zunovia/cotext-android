import 'dart:convert';

import 'package:cotext/bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseBridgeMessage', () {
    test('reads every message type of the contract', () {
      expect(parseBridgeMessage('{"type":"hello"}'), isA<HelloCommand>());
      expect(parseBridgeMessage('{"type":"stt.stop"}'), isA<SttStopCommand>());
      expect(parseBridgeMessage('{"type":"review.request"}'), isA<ReviewRequestCommand>());

      final start = parseBridgeMessage('{"type":"stt.start","lang":"ja-JP"}');
      expect(start, isA<SttStartCommand>());
      expect((start! as SttStartCommand).lang, 'ja-JP');

      final share = parseBridgeMessage(jsonEncode({'type': 'share', 'text': 'Cotext をどうぞ'}));
      expect((share! as ShareCommand).text, 'Cotext をどうぞ');
    });

    test('accepts the five caption languages', () {
      for (final lang in ['ja-JP', 'en-US', 'vi-VN', 'zh-CN', 'id-ID', 'ja']) {
        expect(parseBridgeMessage(jsonEncode({'type': 'stt.start', 'lang': lang})),
            isA<SttStartCommand>(), reason: lang);
      }
    });

    test('ignores malformed messages', () {
      for (final raw in [
        '',
        'not json',
        '[]',
        '"hello"',
        'null',
        '{}',
        '{"type":"unknown"}',
        '{"type":1}',
        '{"type":"stt.start"}',
        '{"type":"stt.start","lang":5}',
        '{"type":"stt.start","lang":"ja-JP\'); alert(1); //"}',
        '{"type":"stt.start","lang":""}',
        '{"type":"share"}',
        '{"type":"share","text":42}',
        '{"type":"share","text":"   "}',
      ]) {
        expect(parseBridgeMessage(raw), isNull, reason: raw);
      }
    });

    test('share text is cut to 500 characters', () {
      final long = 'あ' * 600;
      final share = parseBridgeMessage(jsonEncode({'type': 'share', 'text': long}))! as ShareCommand;
      expect(share.text.length, 500);
    });
  });

  test('truncateChars keeps emoji whole', () {
    expect(truncateChars('ab😀cd', 3), 'ab😀');
    expect(truncateChars('abc', 5), 'abc');
    expect(truncateChars('😀' * 501, 500).runes.length, 500);
  });

  group('scripts to the page', () {
    test('dispatch script fires a cotext-native event with JSON detail', () {
      final script = buildDispatchScript({'type': 'stt.final', 'text': 'こんにちは'});
      expect(script, startsWith("window.dispatchEvent(new CustomEvent('cotext-native', { detail: "));
      expect(script, contains('"type":"stt.final"'));
      expect(script, contains('"text":"こんにちは"'));
    });

    test('recognized text cannot break out of the script', () {
      final script = buildDispatchScript({'type': 'stt.final', 'text': "'\"); alert(1); //\u2028"});
      final json = script.substring(
          script.indexOf('detail: ') + 'detail: '.length, script.lastIndexOf(' })'));
      expect(jsonDecode(json), {'type': 'stt.final', 'text': "'\"); alert(1); //\u2028"});
      expect(script.contains('\u2028'), isFalse);
    });

    test('ready script sets window.__cotextNative and sends ready', () {
      final script =
          buildReadyScript(const NativeCaps(stt: true, review: false, share: true), '1.0.5');
      expect(
          script,
          startsWith('window.__cotextNative = '
              '{"caps":{"stt":true,"review":false,"share":true},"version":"1.0.5"};'));
      expect(script, contains('"type":"ready","caps":{"stt":true,"review":false,"share":true}'));
      expect(script, contains('"version":"1.0.5"'));
    });
  });

  test('review is requested at most once per launch', () {
    final gate = ReviewGate();
    expect(gate.tryUse(), isTrue);
    expect(gate.tryUse(), isFalse);
    expect(gate.tryUse(), isFalse);
  });
}
