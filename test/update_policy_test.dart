import 'package:cotext/update_policy.dart';
import 'package:flutter_test/flutter_test.dart';

UpdateFacts facts({
  bool available = true,
  bool flexible = true,
  int? version = 8,
  bool downloaded = false,
  bool inProgress = false,
}) =>
    UpdateFacts(
      updateAvailable: available,
      flexibleAllowed: flexible,
      availableVersionCode: version,
      downloaded: downloaded,
      inProgress: inProgress,
    );

void main() {
  final now = DateTime(2026, 11, 7, 12);

  UpdateAction decide(UpdateFacts f, {int? lastVersion, DateTime? lastAt}) =>
      decideUpdateAction(facts: f, lastPromptVersion: lastVersion, lastPromptAt: lastAt, now: now);

  test('prompts for a new version never offered before', () {
    expect(decide(facts()), UpdateAction.prompt);
    expect(decide(facts(), lastVersion: 7, lastAt: now), UpdateAction.prompt);
  });

  test('waits 3 days before offering the same version again', () {
    expect(decide(facts(), lastVersion: 8, lastAt: now.subtract(const Duration(hours: 1))),
        UpdateAction.none);
    expect(
        decide(facts(),
            lastVersion: 8, lastAt: now.subtract(const Duration(days: 3, seconds: -1))),
        UpdateAction.none);
    expect(decide(facts(), lastVersion: 8, lastAt: now.subtract(const Duration(days: 3))),
        UpdateAction.prompt);
    expect(decide(facts(), lastVersion: 8, lastAt: now.subtract(const Duration(days: 10))),
        UpdateAction.prompt);
  });

  test('a clock set backwards counts as just asked', () {
    expect(decide(facts(), lastVersion: 8, lastAt: now.add(const Duration(days: 1))),
        UpdateAction.none);
  });

  test('no prompt without an update, flexible permission or version code', () {
    expect(decide(facts(available: false)), UpdateAction.none);
    expect(decide(facts(flexible: false)), UpdateAction.none);
    expect(decide(facts(version: null)), UpdateAction.none);
  });

  test('an already downloaded update shows the bar, even if asked recently', () {
    expect(decide(facts(downloaded: true), lastVersion: 8, lastAt: now), UpdateAction.showReady);
    expect(decide(facts(available: false, downloaded: true)), UpdateAction.showReady);
  });

  test('a download in progress is left alone', () {
    expect(decide(facts(inProgress: true)), UpdateAction.none);
  });
}
