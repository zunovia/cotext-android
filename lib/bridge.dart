/// Messages between the web app and this shell (pure; tested in test/bridge_test.dart).
///
/// Web → Android: `window.CotextNative.postMessage(JSON.stringify(msg))`.
/// Android → Web: `window.dispatchEvent(new CustomEvent('cotext-native', { detail }))`.
/// See design-cotext-2026-11-update.md section 2.
library;

import 'dart:convert';

const String channelName = 'CotextNative';
const String eventName = 'cotext-native';
const int shareMaxLength = 500;

sealed class BridgeCommand {
  const BridgeCommand();
}

class HelloCommand extends BridgeCommand {
  const HelloCommand();
}

class SttStartCommand extends BridgeCommand {
  const SttStartCommand(this.lang);

  /// BCP-47, e.g. `ja-JP`.
  final String lang;
}

class SttStopCommand extends BridgeCommand {
  const SttStopCommand();
}

class ReviewRequestCommand extends BridgeCommand {
  const ReviewRequestCommand();
}

class ShareCommand extends BridgeCommand {
  const ShareCommand(this.text);

  /// Already cut to [shareMaxLength] characters.
  final String text;
}

final RegExp _bcp47 = RegExp(r'^[A-Za-z]{2,3}([-_][A-Za-z0-9]{2,8}){0,3}$');

/// Parses one message from the page. Anything malformed returns null (ignored).
BridgeCommand? parseBridgeMessage(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) return null;
  switch (decoded['type']) {
    case 'hello':
      return const HelloCommand();
    case 'stt.start':
      final lang = decoded['lang'];
      if (lang is! String || !_bcp47.hasMatch(lang)) return null;
      return SttStartCommand(lang);
    case 'stt.stop':
      return const SttStopCommand();
    case 'review.request':
      return const ReviewRequestCommand();
    case 'share':
      final text = decoded['text'];
      if (text is! String) return null;
      final cut = truncateChars(text, shareMaxLength);
      if (cut.trim().isEmpty) return null;
      return ShareCommand(cut);
    default:
      return null;
  }
}

/// Cuts [text] to at most [max] characters without splitting a surrogate pair
/// (emoji outside the BMP count as one).
String truncateChars(String text, int max) {
  final runes = text.runes;
  if (runes.length <= max) return text;
  return String.fromCharCodes(runes.take(max));
}

/// JSON is valid JavaScript except that older engines reject raw U+2028/U+2029
/// inside string literals.
String _jsLiteral(Object? value) =>
    jsonEncode(value).replaceAll('\u2028', r'\u2028').replaceAll('\u2029', r'\u2029');

/// Script that fires one `cotext-native` event with [detail].
String buildDispatchScript(Map<String, Object?> detail) =>
    "window.dispatchEvent(new CustomEvent('$eventName', { detail: ${_jsLiteral(detail)} }));";

/// What the shell can do, sent in `ready`.
class NativeCaps {
  const NativeCaps({required this.stt, required this.review, required this.share});

  final bool stt;
  final bool review;
  final bool share;

  Map<String, Object?> toJson() => {'stt': stt, 'review': review, 'share': share};
}

/// Sets `window.__cotextNative` and fires `ready`.
String buildReadyScript(NativeCaps caps, String version) {
  final info = {'caps': caps.toJson(), 'version': version};
  return 'window.__cotextNative = ${_jsLiteral(info)};'
      '${buildDispatchScript({'type': 'ready', ...info})}';
}

/// `review.request` shows Play's review flow at most once per app launch.
class ReviewGate {
  bool _used = false;

  /// True the first time only.
  bool tryUse() {
    if (_used) return false;
    _used = true;
    return true;
  }
}
