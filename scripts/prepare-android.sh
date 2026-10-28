#!/usr/bin/env bash
# Generate android/ with `flutter create` and apply the Cotext templates.
# android/ is not committed; CI (both jobs) and local test builds run this from the repo root.
set -euo pipefail

flutter create --project-name cotext --org online.surc --platforms android --no-pub .
# flutter create rewrites these; keep the committed versions.
git checkout -- pubspec.yaml lib/
# Its sample test targets a counter app that does not exist here.
rm -f test/widget_test.dart

rm -f android/app/build.gradle android/app/build.gradle.kts android/settings.gradle android/settings.gradle.kts
cp android-templates/app-build.gradle.kts android/app/build.gradle.kts
cp android-templates/settings.gradle.kts android/settings.gradle.kts
cp android-templates/proguard-rules.pro android/app/proguard-rules.pro

KT_DIR=android/app/src/main/kotlin/online/surc/cotext
rm -rf android/app/src/main/kotlin android/app/src/main/java
mkdir -p "$KT_DIR"
cp android-templates/MainActivity.kt "$KT_DIR/MainActivity.kt"

MANIFEST=android/app/src/main/AndroidManifest.xml
sed -i '/<manifest/a\    <uses-permission android:name="android.permission.RECORD_AUDIO"/>\n    <uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.MODIFY_AUDIO_SETTINGS"/>' "$MANIFEST"
sed -i 's/android:label="cotext"/android:label="Cotext"/' "$MANIFEST"
grep -q 'RECORD_AUDIO' "$MANIFEST"
grep -q 'android:label="Cotext"' "$MANIFEST"
