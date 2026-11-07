/// Version of this shell, sent to the web app in `ready` and in the user agent.
/// Keep it equal to the version name in pubspec.yaml (test/app_info_test.dart checks).
const String appVersion = '1.0.6';

/// The web app looks for "CotextAndroid" (for example to hide its PWA install banner).
const String userAgent = 'CotextAndroid/$appVersion';
