import 'dart:ui' show Locale;

/// Texts shown by the Android shell itself (the web app has its own i18n).
/// Same languages and fallback as the web app: ja / en / vi / zh / id,
/// first supported device language wins, otherwise English.
class AppStrings {
  const AppStrings({
    required this.micTitle,
    required this.micBody,
    required this.later,
    required this.openSettings,
    required this.loadErrorTitle,
    required this.loadErrorBody,
    required this.reload,
  });

  final String micTitle;
  final String micBody;
  final String later;
  final String openSettings;
  final String loadErrorTitle;
  final String loadErrorBody;
  final String reload;

  static const Map<String, AppStrings> all = {
    'ja': AppStrings(
      micTitle: 'マイクの許可が必要です',
      micBody: 'Cotextは音声機能を使用するためにマイクへのアクセスが必要です。\n'
          '設定画面からマイクの使用を許可してください。',
      later: '後で',
      openSettings: '設定を開く',
      loadErrorTitle: 'ページを読み込めませんでした',
      loadErrorBody: 'インターネット接続を確認して、もう一度お試しください。',
      reload: '再読み込み',
    ),
    'en': AppStrings(
      micTitle: 'Microphone access needed',
      micBody: 'Cotext needs access to the microphone for its voice features.\n'
          'Please allow microphone access in Settings.',
      later: 'Later',
      openSettings: 'Open Settings',
      loadErrorTitle: "Couldn't load the page",
      loadErrorBody: 'Check your internet connection and try again.',
      reload: 'Reload',
    ),
    'vi': AppStrings(
      micTitle: 'Cần quyền truy cập micro',
      micBody: 'Cotext cần truy cập micro để dùng các tính năng giọng nói.\n'
          'Vui lòng cho phép dùng micro trong phần Cài đặt.',
      later: 'Để sau',
      openSettings: 'Mở Cài đặt',
      loadErrorTitle: 'Không thể tải trang',
      loadErrorBody: 'Vui lòng kiểm tra kết nối Internet rồi thử lại.',
      reload: 'Tải lại',
    ),
    'zh': AppStrings(
      micTitle: '需要麦克风权限',
      micBody: 'Cotext 的语音功能需要使用麦克风。\n'
          '请在设置中允许使用麦克风。',
      later: '以后再说',
      openSettings: '打开设置',
      loadErrorTitle: '无法加载页面',
      loadErrorBody: '请检查网络连接后重试。',
      reload: '重新加载',
    ),
    'id': AppStrings(
      micTitle: 'Izin mikrofon diperlukan',
      micBody: 'Cotext memerlukan akses ke mikrofon untuk fitur suara.\n'
          'Silakan izinkan penggunaan mikrofon di Pengaturan.',
      later: 'Nanti',
      openSettings: 'Buka Pengaturan',
      loadErrorTitle: 'Halaman tidak dapat dimuat',
      loadErrorBody: 'Periksa koneksi internet Anda, lalu coba lagi.',
      reload: 'Muat ulang',
    ),
  };

  /// [locales] is the device's preferred list, most preferred first.
  static AppStrings resolve(List<Locale> locales) {
    for (final locale in locales) {
      // Android still reports Indonesian as the legacy code "in" on some devices.
      final code = locale.languageCode == 'in' ? 'id' : locale.languageCode;
      final strings = all[code];
      if (strings != null) return strings;
    }
    return locales.isEmpty ? all['ja']! : all['en']!;
  }
}
