import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/core/update/app_updater.dart';
import 'package:nanini_app/core/update/update_banner.dart';

void main() {
  tearDown(() => appUpdater = null);

  Future<void> pump(WidgetTester tester, {bool enabled = true}) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: UpdateBanner(enabled: enabled))),
      );

  testWidgets('no banner without a newer build', (tester) async {
    appUpdater = AppUpdater('nanini-capture.apk', currentBuild: 180)..latestBuild = 180;
    await pump(tester);
    expect(find.text('UPDATE'), findsNothing);
  });

  testWidgets('newer build: UPDATE button', (tester) async {
    appUpdater = AppUpdater('nanini-capture.apk', currentBuild: 180)..latestBuild = 181;
    await pump(tester);
    expect(find.text('New version available'), findsOneWidget);
    expect(find.text('UPDATE'), findsOneWidget);
  });

  testWidgets('hidden while not allowed (capture phone off Wi-Fi)', (tester) async {
    appUpdater = AppUpdater('nanini-capture.apk', currentBuild: 180)..latestBuild = 181;
    await pump(tester, enabled: false);
    expect(find.text('UPDATE'), findsNothing);
  });

  testWidgets('local builds never offer updates', (tester) async {
    appUpdater = AppUpdater('app-release.apk', currentBuild: 0)..latestBuild = 999;
    await pump(tester);
    expect(find.text('UPDATE'), findsNothing);
  });
}
