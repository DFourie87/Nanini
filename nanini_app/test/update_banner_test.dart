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

  testWidgets('downloading: progress, and it keeps going outside the app', (tester) async {
    appUpdater = AppUpdater('nanini-capture.apk', currentBuild: 180)
      ..latestBuild = 181
      ..progress = 0.42;
    await pump(tester);
    expect(find.text('Downloading update… 42%'), findsOneWidget);
    expect(find.text('You can use other apps -- it keeps downloading.'), findsOneWidget);
    expect(find.text('UPDATE'), findsNothing);
    appUpdater!
      ..note = 'Weak signal -- carries on by itself'
      ..notifyListeners();
    await tester.pump();
    expect(find.text('Weak signal -- carries on by itself'), findsOneWidget);
  });

  testWidgets('downloaded while away: INSTALL (even off Wi-Fi)', (tester) async {
    appUpdater = AppUpdater('nanini-capture.apk', currentBuild: 180)
      ..latestBuild = 181
      ..readyPath = '/x/nanini-capture.apk';
    await pump(tester, enabled: false);
    expect(find.text('Update downloaded'), findsOneWidget);
    expect(find.text('INSTALL'), findsOneWidget);
  });

  testWidgets('local builds never offer updates', (tester) async {
    appUpdater = AppUpdater('app-release.apk', currentBuild: 0)..latestBuild = 999;
    await pump(tester);
    expect(find.text('UPDATE'), findsNothing);
  });
}
