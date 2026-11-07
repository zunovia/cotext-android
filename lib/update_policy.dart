/// When to show Play's flexible-update prompt (pure; tested in test/update_policy_test.dart).
///
/// The same version is offered again only after [promptInterval], so a person who
/// said "no thanks" is not asked on every launch.
library;

const Duration promptInterval = Duration(days: 3);

enum UpdateAction {
  /// Nothing to do.
  none,

  /// Ask Play to show its update confirmation screen.
  prompt,

  /// An update has already been downloaded: show the "restart to update" bar.
  showReady,
}

/// What Play reported, without the plugin types (so this file stays pure Dart).
class UpdateFacts {
  const UpdateFacts({
    required this.updateAvailable,
    required this.flexibleAllowed,
    required this.availableVersionCode,
    required this.downloaded,
    required this.inProgress,
  });

  /// `updateAvailability == updateAvailable`.
  final bool updateAvailable;

  /// `flexibleUpdateAllowed`.
  final bool flexibleAllowed;

  final int? availableVersionCode;

  /// `installStatus == downloaded` (also true when it finished in an earlier run).
  final bool downloaded;

  /// A download is pending, running or installing.
  final bool inProgress;
}

UpdateAction decideUpdateAction({
  required UpdateFacts facts,
  required int? lastPromptVersion,
  required DateTime? lastPromptAt,
  required DateTime now,
}) {
  if (facts.downloaded) return UpdateAction.showReady;
  if (facts.inProgress) return UpdateAction.none;
  final version = facts.availableVersionCode;
  if (!facts.updateAvailable || !facts.flexibleAllowed || version == null) {
    return UpdateAction.none;
  }
  if (lastPromptVersion == version && lastPromptAt != null) {
    final elapsed = now.difference(lastPromptAt);
    // A clock set backwards gives a negative value: treat it as "just asked".
    if (elapsed < promptInterval) return UpdateAction.none;
  }
  return UpdateAction.prompt;
}
