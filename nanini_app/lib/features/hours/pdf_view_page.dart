import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';

/// A PDF full screen, made to be read on a phone: one page at a time (swipe
/// or the arrows for the next), pinch or double-tap to zoom in -- the page
/// is drawn sharp enough to read when zoomed -- and the screen turned
/// sideways for landscape pages ([landscape] starts that way; the rotate
/// button switches). [share] adds print and share; [bottom] sits under the
/// page (e.g. Run payroll's Back to edit / Approve).
class PdfViewPage extends StatefulWidget {
  const PdfViewPage({
    super.key,
    required this.title,
    required this.pdf,
    this.share = true,
    this.landscape = false,
    this.fileName = 'nanini.pdf',
    this.bottom,
    this.raster = _printingRaster,
  });

  final String title;
  final Future<Uint8List> Function() pdf;
  final bool share;
  final bool landscape;
  final String fileName;
  final Widget? bottom;

  /// Draws pages of the PDF ([Printing.raster]; a stand-in in tests).
  final Stream<PdfRaster> Function(Uint8List pdf, List<int>? pages, double dpi) raster;

  static Stream<PdfRaster> _printingRaster(Uint8List pdf, List<int>? pages, double dpi) => Printing.raster(pdf, pages: pages, dpi: dpi);

  @override
  State<PdfViewPage> createState() => _PdfViewPageState();
}

class _PdfViewPageState extends State<PdfViewPage> {
  static const _sizeDpi = 12.0;

  Uint8List? _bytes;
  Object? _error;

  /// Each page's size in inches.
  List<Size> _pages = const [];
  final _images = <int, ui.Image>{};
  final _loading = <int>{};
  final _zoom = <int, TransformationController>{};
  final _pageCtl = PageController();
  int _page = 0;
  bool _zoomed = false;
  late bool _sideways = widget.landscape;
  Offset? _tapAt;

  @override
  void initState() {
    super.initState();
    if (_sideways) _turn(true);
    _load();
  }

  @override
  void dispose() {
    // Back to the app's usual orientations.
    SystemChrome.setPreferredOrientations(const []);
    for (final i in _images.values) {
      i.dispose();
    }
    for (final c in _zoom.values) {
      c.dispose();
    }
    _pageCtl.dispose();
    super.dispose();
  }

  void _turn(bool sideways) {
    SystemChrome.setPreferredOrientations(sideways
        ? const [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
        : const [DeviceOrientation.portraitUp]);
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.pdf();
      // Page sizes from a tiny rendering (cheap).
      final sizes = <Size>[];
      await for (final r in widget.raster(bytes, null, _sizeDpi)) {
        sizes.add(Size(r.width / _sizeDpi, r.height / _sizeDpi));
      }
      if (!mounted) return;
      setState(() {
        _bytes = bytes;
        _pages = sizes;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  /// Draws page [i] sharp enough to zoom about 2.5x on this screen; only the
  /// page shown and its neighbours are kept.
  Future<void> _render(int i) async {
    final bytes = _bytes;
    if (bytes == null || i < 0 || i >= _pages.length || _images.containsKey(i) || _loading.contains(i)) return;
    _loading.add(i);
    final mq = MediaQuery.of(context);
    final px = mq.size.longestSide * mq.devicePixelRatio * 2.5;
    final dpi = (px / _pages[i].width).clamp(72.0, 220.0);
    try {
      final r = await widget.raster(bytes, [i], dpi).first;
      final img = await r.toImage();
      if (!mounted) {
        img.dispose();
        return;
      }
      setState(() => _images[i] = img);
      for (final k in _images.keys.where((k) => (k - _page).abs() > 1).toList()) {
        _images.remove(k)?.dispose();
      }
    } catch (e) {
      if (mounted) setState(() => _error ??= e);
    } finally {
      _loading.remove(i);
    }
  }

  TransformationController _ctl(int i) => _zoom.putIfAbsent(i, TransformationController.new);

  void _zoomChanged(int i) {
    final z = _ctl(i).value.getMaxScaleOnAxis() > 1.01;
    if (z != _zoomed) setState(() => _zoomed = z);
  }

  void _doubleTap(int i) {
    final c = _ctl(i);
    if (c.value.getMaxScaleOnAxis() > 1.01) {
      c.value = Matrix4.identity();
    } else {
      const s = 2.5;
      final p = _tapAt ?? Offset.zero;
      c.value = Matrix4.identity()
        ..translateByDouble(-p.dx * (s - 1), -p.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, 1, 1);
    }
    _zoomChanged(i);
  }

  void _goTo(int i) => _pageCtl.animateToPage(i, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);

  Future<void> _print() async {
    final b = _bytes;
    if (b != null) await Printing.layoutPdf(name: widget.fileName, onLayout: (_) async => b);
  }

  Future<void> _sharePdf() async {
    final b = _bytes;
    if (b != null) await Printing.sharePdf(bytes: b, filename: widget.fileName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: NaniniAppBar(
        title: widget.title,
        showManagerButton: false,
        actions: [
          IconButton(
            tooltip: _sideways ? 'Turn upright' : 'Turn sideways',
            icon: const Icon(Icons.screen_rotation),
            onPressed: () {
              setState(() => _sideways = !_sideways);
              _turn(_sideways);
            },
          ),
          if (widget.share) ...[
            IconButton(tooltip: 'Print', icon: const Icon(Icons.print_outlined), onPressed: _bytes == null ? null : _print),
            IconButton(tooltip: 'Share', icon: const Icon(Icons.share_outlined), onPressed: _bytes == null ? null : _sharePdf),
          ],
        ],
      ),
      body: _body(),
      bottomNavigationBar: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_pages.isNotEmpty)
              Row(
                children: [
                  IconButton(
                    tooltip: 'Previous page',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _page > 0 ? () => _goTo(_page - 1) : null,
                  ),
                  Expanded(
                    child: Text(
                      'Page ${_page + 1} of ${_pages.length} · pinch or double-tap to zoom',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: NaniniColors.muted, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next page',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _page < _pages.length - 1 ? () => _goTo(_page + 1) : null,
                  ),
                ],
              ),
            ?widget.bottom,
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not show the PDF: $_error', textAlign: TextAlign.center),
        ),
      );
    }
    if (_bytes == null) return const Center(child: CircularProgressIndicator());
    return ColoredBox(
      color: NaniniColors.line,
      child: PageView.builder(
        controller: _pageCtl,
        // Zoomed in: dragging moves around the page, not to the next one.
        physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
        itemCount: _pages.length,
        onPageChanged: (i) {
          final old = _page;
          setState(() {
            _page = i;
            _zoomed = false;
          });
          _zoom[old]?.value = Matrix4.identity();
        },
        itemBuilder: (context, i) {
          _render(i);
          _render(i + 1);
          final img = _images[i];
          final size = _pages[i];
          return GestureDetector(
            onDoubleTapDown: (d) => _tapAt = d.localPosition,
            onDoubleTap: () => _doubleTap(i),
            child: InteractiveViewer(
              transformationController: _ctl(i),
              minScale: 1,
              maxScale: 6,
              onInteractionEnd: (_) => _zoomChanged(i),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: AspectRatio(
                    aspectRatio: size.width / math.max(size.height, 0.01),
                    child: DecoratedBox(
                      decoration: const BoxDecoration(color: NaniniColors.paper),
                      child: img == null
                          ? const Center(child: CircularProgressIndicator())
                          : RawImage(image: img, fit: BoxFit.contain, filterQuality: FilterQuality.medium),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
