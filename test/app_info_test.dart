import 'dart:io';

import 'package:cotext/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('appVersion matches the version name in pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*([0-9.]+)\+(\d+)\s*$', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull);
    expect(match!.group(1), appVersion);
  });

  test('user agent carries the version', () {
    expect(userAgent, 'CotextAndroid/$appVersion');
  });
}
