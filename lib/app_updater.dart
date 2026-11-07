import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_policy.dart';

/// Play in-app update (flexible). Every call is wrapped: development and sideloaded
/// builds are not known to Play, which answers with an error — doing nothing is correct.
class AppUpdater {
  AppUpdater({required this.onReady});

  /// Called (possibly more than once) when the update has been downloaded.
  final VoidCallback onReady;

  static const _keyVersion = 'update.lastPromptVersion';
  static const _keyAt = 'update.lastPromptAt';

  StreamSubscription<InstallStatus>? _installSub;
  bool _recorded = false;

  Future<void> checkOnLaunch() async {
    try {
      final info = await InAppUpdate.checkForUpdate();
      final prefs = await SharedPreferences.getInstance();
      final lastAtMs = prefs.getInt(_keyAt);
      final action = decideUpdateAction(
        facts: UpdateFacts(
          updateAvailable: info.updateAvailability == UpdateAvailability.updateAvailable,
          flexibleAllowed: info.flexibleUpdateAllowed,
          availableVersionCode: info.availableVersionCode,
          downloaded: info.installStatus == InstallStatus.downloaded,
          inProgress: const {
            InstallStatus.pending,
            InstallStatus.downloading,
            InstallStatus.installing,
          }.contains(info.installStatus),
        ),
        lastPromptVersion: prefs.getInt(_keyVersion),
        lastPromptAt: lastAtMs == null ? null : DateTime.fromMillisecondsSinceEpoch(lastAtMs),
        now: DateTime.now(),
      );
      switch (action) {
        case UpdateAction.none:
          return;
        case UpdateAction.showReady:
          onReady();
          return;
        case UpdateAction.prompt:
          await _prompt(prefs, info.availableVersionCode!);
      }
    } catch (e) {
      debugPrint('[update] check skipped: $e');
    }
  }

  Future<void> _prompt(SharedPreferences prefs, int versionCode) async {
    // Record only when Play actually showed its confirmation screen: the person
    // accepted (the download starts) or declined.
    Future<void> record() async {
      if (_recorded) return;
      _recorded = true;
      await prefs.setInt(_keyVersion, versionCode);
      await prefs.setInt(_keyAt, DateTime.now().millisecondsSinceEpoch);
    }

    await _installSub?.cancel();
    _installSub = InAppUpdate.installUpdateListener.listen(
      (status) {
        if (status == InstallStatus.pending || status == InstallStatus.downloading) {
          unawaited(record().catchError((Object e) => debugPrint('[update] $e')));
        } else if (status == InstallStatus.downloaded) {
          unawaited(record().catchError((Object e) => debugPrint('[update] $e')));
          onReady();
        }
      },
      onError: (Object e) => debugPrint('[update] listener: $e'),
    );

    try {
      final result = await InAppUpdate.startFlexibleUpdate();
      switch (result) {
        case AppUpdateResult.success: // returned once the download has finished
          await record();
          onReady();
        case AppUpdateResult.userDeniedUpdate:
          await record();
        case AppUpdateResult.inAppUpdateFailed:
          break;
      }
    } on PlatformException catch (e) {
      debugPrint('[update] flexible update failed: ${e.code} ${e.message}');
    }
  }

  /// Installs the downloaded update; Play restarts the app. The plugin never
  /// completes this call, so it is not awaited.
  void completeUpdate() {
    unawaited(
      InAppUpdate.completeFlexibleUpdate()
          .catchError((Object e) => debugPrint('[update] complete failed: $e')),
    );
  }

  void dispose() {
    unawaited(_installSub?.cancel());
  }
}
