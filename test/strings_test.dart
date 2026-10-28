import 'dart:ui' show Locale;

import 'package:cotext/strings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all five languages are present and fully filled', () {
    expect(AppStrings.all.keys.toSet(), {'ja', 'en', 'vi', 'zh', 'id'});
    for (final s in AppStrings.all.values) {
      for (final text in [
        s.micTitle,
        s.micBody,
        s.later,
        s.openSettings,
        s.loadErrorTitle,
        s.loadErrorBody,
        s.reload,
      ]) {
        expect(text.trim(), isNotEmpty);
      }
    }
  });

  test('first supported device language wins', () {
    expect(
      AppStrings.resolve(const [Locale('fr'), Locale('vi', 'VN'), Locale('ja')]),
      same(AppStrings.all['vi']),
    );
    expect(
      AppStrings.resolve(const [Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')]),
      same(AppStrings.all['zh']),
    );
  });

  test('legacy Indonesian code "in" maps to id', () {
    expect(AppStrings.resolve(const [Locale('in', 'ID')]), same(AppStrings.all['id']));
  });

  test('unsupported languages fall back to English, empty list to Japanese', () {
    expect(AppStrings.resolve(const [Locale('fil'), Locale('ne')]), same(AppStrings.all['en']));
    expect(AppStrings.resolve(const []), same(AppStrings.all['ja']));
  });
}
