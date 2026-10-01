import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nanini_app/features/hours/pdf_view_page.dart';
import 'package:printing/printing.dart';

/// Three pages: a landscape A4, then two portrait A4.
Stream<PdfRaster> _fakeRaster(Uint8List pdf, List<int>? pages, double dpi) async* {
  const sizes = [(11.69, 8.27), (8.27, 11.69), (8.27, 11.69)];
  for (final i in pages ?? [0, 1, 2]) {
    final w = (sizes[i].$1 * dpi).round(), h = (sizes[i].$2 * dpi).round();
    yield PdfRaster(w, h, Uint8List(w * h * 4));
  }
}

/// Lets the (real) page drawing finish; spinners never settle.
Future<void> _settle(WidgetTester tester) async {
  for (var n = 0; n < 6; n++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: page));
    await _settle(tester);
  }

  testWidgets('a page at a time, arrows to the next, double-tap zooms', (tester) async {
    await pump(tester, PdfViewPage(title: 'Summary: Haaskraal', pdf: () async => Uint8List(1), raster: _fakeRaster));
    expect(find.textContaining('Summary: Haaskraal', findRichText: true), findsOneWidget);
    expect(find.textContaining('Page 1 of 3'), findsOneWidget);
    expect(find.byTooltip('Print'), findsOneWidget);
    expect(find.byTooltip('Share'), findsOneWidget);
    expect(find.byTooltip('Turn sideways'), findsOneWidget);

    await tester.tap(find.byTooltip('Next page'));
    await _settle(tester);
    expect(find.textContaining('Page 2 of 3'), findsOneWidget);

    // Double-tap: zoomed in (2.5x); again: back to the whole page.
    final viewer = find.byType(InteractiveViewer).first;
    TransformationController ctl() => tester.widget<InteractiveViewer>(viewer).transformationController!;
    await tester.tap(viewer);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(viewer);
    await _settle(tester);
    expect(ctl().value.getMaxScaleOnAxis(), closeTo(2.5, 0.01));
    await tester.tap(viewer);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(viewer);
    await _settle(tester);
    expect(ctl().value.getMaxScaleOnAxis(), closeTo(1, 0.01));
  });

  testWidgets('approve step: Back to edit / Approve under the page, no share', (tester) async {
    bool? result;
    await pump(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await Navigator.of(context).push<bool>(MaterialPageRoute(
                builder: (ctx) => PdfViewPage(
                  title: 'Payroll',
                  pdf: () async => Uint8List(1),
                  share: false,
                  raster: _fakeRaster,
                  bottom: Builder(builder: (ctx) => FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve'))),
                ),
              ));
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await _settle(tester);
    expect(find.byTooltip('Share'), findsNothing);
    expect(find.textContaining('Page 1 of 3'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await _settle(tester);
    expect(result, isTrue);
  });
}
