import 'package:flutter/material.dart';

import '../theme/nanini_theme.dart';

/// Farm pictures drawn in code for the capture app's diesel activities --
/// there are no emoji for these.
///
/// A knapsack chemical sprayer drawn in code -- there's no sprayer emoji, so
/// the capture app's "Spraying and Fertilizing" choice uses this.
class SprayerIcon extends StatelessWidget {
  const SprayerIcon({super.key, this.size = 44});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: _SprayerPainter()),
  );
}

class _SprayerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 48 x 48 grid, scaled to fit.
    final s = size.width / 48;
    canvas.save();
    canvas.scale(s);

    final ink = Paint()
      ..color = NaniniColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // Tank, with its filler cap and a level line.
    final tank = RRect.fromRectAndRadius(const Rect.fromLTWH(5, 12, 20, 31), const Radius.circular(5));
    canvas.drawRRect(tank, Paint()..color = NaniniColors.green);
    canvas.drawRRect(tank, ink);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(10, 7, 10, 6), const Radius.circular(1.5)), Paint()..color = NaniniColors.ink);
    canvas.drawLine(const Offset(9, 22), const Offset(21, 22), ink..strokeWidth = 1.5);

    // Pump handle along the side.
    canvas.drawLine(const Offset(4, 18), const Offset(4, 38), ink..strokeWidth = 2.5);

    // Hose from the bottom of the tank round to the lance.
    final hose = Path()
      ..moveTo(25, 38)
      ..cubicTo(33, 40, 34, 32, 30, 27);
    canvas.drawPath(hose, ink..strokeWidth = 2.5);

    // Lance and nozzle.
    canvas.drawLine(const Offset(30, 27), const Offset(39, 13), ink..strokeWidth = 3);
    canvas.drawLine(const Offset(38, 12), const Offset(41, 14), ink..strokeWidth = 4);

    // Spray mist fanning out of the nozzle.
    final mist = Paint()..color = NaniniColors.green;
    for (final (x, y, r) in const [
      (43.0, 9.0, 1.6),
      (45.5, 12.5, 1.4),
      (41.5, 5.5, 1.4),
      (46.5, 7.0, 1.2),
      (44.0, 3.0, 1.1),
      (47.0, 2.5, 0.9),
      (47.2, 11.0, 0.9),
    ]) {
      canvas.drawCircle(Offset(x, y), r, mist);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Wood colour for posts and handles (same as the hub's rifle stock).
const _wood = Color(0xFF7A4A24);

Paint _stroke(double w, [Color c = NaniniColors.ink]) => Paint()
  ..color = c
  ..style = PaintingStyle.stroke
  ..strokeWidth = w
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

abstract class _GridPainter extends CustomPainter {
  /// Draws on a 48 x 48 grid, scaled to the widget's size.
  void draw(Canvas canvas);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 48);
    draw(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FarmIcon extends StatelessWidget {
  const _FarmIcon(this.painter, this.size);
  final CustomPainter painter;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(painter: painter),
  );
}

/// Commercial stand-alone generator: enclosed canopy on a base skid, with
/// air vents, a control panel and an exhaust stack.
class GeneratorIcon extends StatelessWidget {
  const GeneratorIcon({super.key, this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => _FarmIcon(_GeneratorPainter(), size);
}

class _GeneratorPainter extends _GridPainter {
  @override
  void draw(Canvas canvas) {
    // Exhaust stack with rain cap, behind the canopy.
    canvas.drawRect(const Rect.fromLTWH(34, 6, 4, 10), Paint()..color = NaniniColors.muted);
    canvas.drawRect(const Rect.fromLTWH(34, 6, 4, 10), _stroke(1.2));
    canvas.drawLine(const Offset(32, 6), const Offset(40, 6), _stroke(2));
    // Enclosure (canopy) with a slightly overhanging roof.
    const body = Rect.fromLTWH(3, 16, 42, 23);
    canvas.drawRect(body, Paint()..color = NaniniColors.amber);
    canvas.drawRect(body, _stroke(1.8));
    canvas.drawLine(const Offset(2, 16), const Offset(46, 16), _stroke(2.5));
    // Air vents (louvres) on the left side.
    for (final y in const [21.0, 25.0, 29.0, 33.0]) {
      canvas.drawLine(Offset(7, y), Offset(22, y), _stroke(1.6));
    }
    // Door seam and control panel with a lightning bolt.
    canvas.drawLine(const Offset(26, 16), const Offset(26, 39), _stroke(1.2));
    const panel = Rect.fromLTWH(30, 20, 11, 13);
    canvas.drawRect(panel, Paint()..color = NaniniColors.ink);
    final bolt = Path()
      ..moveTo(36.5, 21.5)
      ..lineTo(32.5, 27.5)
      ..lineTo(35.5, 27.5)
      ..lineTo(33.5, 31.5)
      ..lineTo(38.5, 25.5)
      ..lineTo(35.5, 25.5)
      ..lineTo(37.5, 21.5)
      ..close();
    canvas.drawPath(bolt, Paint()..color = NaniniColors.amber);
    // Base skid.
    canvas.drawRect(const Rect.fromLTWH(1, 39, 46, 4), Paint()..color = NaniniColors.ink);
    canvas.drawRect(const Rect.fromLTWH(5, 43, 5, 2), Paint()..color = NaniniColors.ink);
    canvas.drawRect(const Rect.fromLTWH(38, 43, 5, 2), Paint()..color = NaniniColors.ink);
  }
}

/// Wooden farm fence with a gravel road in front -- roads and fences.
class FenceIcon extends StatelessWidget {
  const FenceIcon({super.key, this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => _FarmIcon(_FencePainter(), size);
}

class _FencePainter extends _GridPainter {
  @override
  void draw(Canvas canvas) {
    final wood = Paint()..color = _wood;
    // Rails behind the posts.
    for (final y in const [12.0, 22.0]) {
      final rail = Rect.fromLTWH(2, y, 44, 4.5);
      canvas.drawRect(rail, wood);
      canvas.drawRect(rail, _stroke(1.2));
    }
    // Posts with pointed tops.
    for (final x in const [5.0, 20.0, 35.0]) {
      final post = Path()
        ..moveTo(x, 8)
        ..lineTo(x + 4, 3)
        ..lineTo(x + 8, 8)
        ..lineTo(x + 8, 32)
        ..lineTo(x, 32)
        ..close();
      canvas.drawPath(post, wood);
      canvas.drawPath(post, _stroke(1.5));
    }
    // Grass verge, then the gravel road in front of the fence.
    canvas.drawRect(const Rect.fromLTWH(0, 32, 48, 3), Paint()..color = NaniniColors.green);
    const road = Rect.fromLTWH(0, 35, 48, 11);
    canvas.drawRect(road, Paint()..color = NaniniColors.line);
    canvas.drawLine(const Offset(0, 46), const Offset(48, 46), _stroke(1.2, NaniniColors.muted));
    final gravel = Paint()..color = NaniniColors.muted;
    for (final (x, y, r) in const [
      (4.0, 38.0, 0.9), (10.0, 42.5, 1.1), (15.5, 38.5, 0.8), (21.0, 43.0, 0.9), (26.0, 39.0, 1.1),
      (31.5, 42.0, 0.8), (36.0, 38.0, 0.9), (41.5, 43.0, 1.1), (45.0, 39.5, 0.8), (7.0, 44.5, 0.7),
      (18.5, 45.0, 0.7), (33.5, 45.0, 0.7), (28.5, 36.8, 0.6), (12.5, 36.8, 0.6), (39.0, 36.8, 0.6),
    ]) {
      canvas.drawCircle(Offset(x, y), r, gravel);
    }
  }
}

/// Tractor pulling a loaded trailer.
class TractorTrailerIcon extends StatelessWidget {
  const TractorTrailerIcon({super.key, this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => _FarmIcon(_TractorTrailerPainter(), size);
}

class _TractorTrailerPainter extends _GridPainter {
  @override
  void draw(Canvas canvas) {
    final ink = Paint()..color = NaniniColors.ink;
    // Trailer (left): load box, draw bar, one wheel.
    final box = Rect.fromLTWH(1, 22, 17, 11);
    canvas.drawRect(box, Paint()..color = NaniniColors.amber);
    canvas.drawRect(box, _stroke(1.5));
    canvas.drawLine(const Offset(18, 31), const Offset(24, 31), _stroke(2));
    canvas.drawCircle(const Offset(9.5, 36), 4.5, ink);
    canvas.drawCircle(const Offset(9.5, 36), 1.6, Paint()..color = NaniniColors.paper);

    // Tractor (right): bonnet, cab, exhaust, big rear wheel, small front wheel.
    final green = Paint()..color = NaniniColors.green;
    final bonnet = Rect.fromLTWH(33, 23, 13, 9);
    canvas.drawRect(bonnet, green);
    canvas.drawRect(bonnet, _stroke(1.5));
    final cab = Path()
      ..moveTo(22, 32)
      ..lineTo(22, 12)
      ..lineTo(34, 12)
      ..lineTo(34, 32)
      ..close();
    canvas.drawPath(cab, green);
    canvas.drawPath(cab, _stroke(1.5));
    canvas.drawRect(const Rect.fromLTWH(25, 15, 6, 7), Paint()..color = NaniniColors.paper);
    canvas.drawLine(const Offset(42, 23), const Offset(42, 17), _stroke(2));
    canvas.drawCircle(const Offset(27, 36), 8, ink);
    canvas.drawCircle(const Offset(27, 36), 3, Paint()..color = NaniniColors.paper);
    canvas.drawCircle(const Offset(42, 38), 5, ink);
    canvas.drawCircle(const Offset(42, 38), 1.8, Paint()..color = NaniniColors.paper);
  }
}

/// Butternut squash (there's no butternut emoji -- 🎃 is a pumpkin): long pale
/// neck, round bulb, stem on top.
class ButternutIcon extends StatelessWidget {
  const ButternutIcon({super.key, this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => _FarmIcon(_ButternutPainter(), size);
}

class _ButternutPainter extends _GridPainter {
  /// Butternut skin: pale tan-orange.
  static const _skin = Color(0xFFE9B872);

  @override
  void draw(Canvas canvas) {
    // Drawn upright, then tilted so the long shape fills the square.
    canvas.translate(24, 24);
    canvas.rotate(-0.72);
    canvas.scale(0.86); // the fuller shape still fits the square when tilted
    canvas.translate(-24, -26);

    // Stem.
    final stem = Path()
      ..moveTo(22.6, 3.5)
      ..lineTo(22.8, -1.5)
      ..quadraticBezierTo(25, -2.5, 26, -1)
      ..lineTo(25.4, 3.5)
      ..close();
    canvas.drawPath(stem, Paint()..color = const Color(0xFF6B7F3A));
    canvas.drawPath(stem, _stroke(1.2));

    // Body: a full, rounded neck swelling into a big round bulb.
    final body = Path()
      ..moveTo(19.5, 4.5)
      ..quadraticBezierTo(24, 2.5, 28.5, 4.5)
      ..cubicTo(31.5, 11, 31, 20, 33.5, 26.5)
      ..cubicTo(39.5, 30.5, 41.5, 39, 38.5, 44)
      ..cubicTo(35, 50.5, 13, 50.5, 9.5, 44)
      ..cubicTo(6.5, 39, 8.5, 30.5, 14.5, 26.5)
      ..cubicTo(17, 20, 16.5, 11, 19.5, 4.5)
      ..close();
    canvas.drawPath(body, Paint()..color = _skin);

    // Roundness: a shaded right side and a soft shine down the left.
    canvas.save();
    canvas.clipPath(body);
    final shade = Path()
      ..moveTo(25.5, 4)
      ..cubicTo(27.5, 12, 26.5, 21, 28.5, 28.5)
      ..cubicTo(33.5, 32.5, 34.5, 40, 32, 44.5)
      ..cubicTo(29.5, 48, 24, 49.5, 20, 49.5)
      ..lineTo(44, 49.5)
      ..lineTo(44, 4)
      ..close();
    canvas.drawPath(shade, Paint()..color = const Color(0xFFD9974A));
    canvas.restore();
    canvas.drawPath(
      Path()..moveTo(20.5, 9)..cubicTo(19.8, 16, 19.5, 22, 17, 28.5)..moveTo(14, 33)..cubicTo(11.5, 36, 11.5, 40, 13, 42.5),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round,
    );

    // Faint ribs.
    final rib = _stroke(1, const Color(0xFFC98F45));
    canvas.drawPath(Path()..moveTo(22.8, 7)..cubicTo(22.5, 18, 21, 27, 18, 36), rib);
    canvas.drawPath(Path()..moveTo(25.2, 7)..cubicTo(25.5, 18, 27, 27, 30, 36), rib);
    canvas.drawPath(body, _stroke(1.8));
  }
}

/// A Peppadew (🌶️ is a long chilli): a small, smooth, glossy red pepper,
/// round with a little point at the bottom, a green cap hugging the top and
/// a short thick stem.
class PeppadewIcon extends StatelessWidget {
  const PeppadewIcon({super.key, this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => _FarmIcon(_PeppadewPainter(), size);
}

class _PeppadewPainter extends _GridPainter {
  static const _skin = Color(0xFFE0262B);
  static const _shade = Color(0xFFA9181D);
  static const _green = Color(0xFF4F7F2B);
  static const _darkGreen = Color(0xFF365C1C);

  @override
  void draw(Canvas canvas) {
    // Body: round shoulders, swelling out and drawing in to a small point.
    final body = Path()
      ..moveTo(24, 14)
      ..cubicTo(32, 12, 41.5, 17, 41.5, 27.5)
      ..cubicTo(41.5, 37, 34, 42.5, 26.5, 43.3)
      ..quadraticBezierTo(24.6, 43.6, 24, 45.2)
      ..quadraticBezierTo(23.4, 43.6, 21.5, 43.3)
      ..cubicTo(14, 42.5, 6.5, 37, 6.5, 27.5)
      ..cubicTo(6.5, 17, 16, 12, 24, 14)
      ..close();
    canvas.drawPath(body, Paint()..color = _skin);

    // Roundness: shade low on the right, then glossy highlights upper left.
    canvas.save();
    canvas.clipPath(body);
    canvas.drawCircle(const Offset(31, 35), 16, Paint()..color = _shade.withValues(alpha: 0.6));
    canvas.drawCircle(const Offset(21.5, 26), 15.5, Paint()..color = _skin);
    canvas.restore();
    canvas.drawPath(
      Path()..moveTo(11.5, 28)..cubicTo(11, 23.5, 13, 19.5, 17, 17.5),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(const Offset(13.5, 32), 1.4, Paint()..color = Colors.white.withValues(alpha: 0.6));
    canvas.drawPath(body, _stroke(1.8));

    // Green cap (calyx): a cup over the top, its edge in soft points.
    final cap = Path()
      ..moveTo(15.5, 16.5)
      ..quadraticBezierTo(17, 11, 24, 10.5)
      ..quadraticBezierTo(31, 11, 32.5, 16.5)
      ..quadraticBezierTo(30.5, 16, 29.5, 18)
      ..quadraticBezierTo(27, 16.5, 24, 18.5)
      ..quadraticBezierTo(21, 16.5, 18.5, 18)
      ..quadraticBezierTo(17.5, 16, 15.5, 16.5)
      ..close();
    canvas.drawPath(cap, Paint()..color = _green);
    canvas.drawPath(cap, _stroke(1.3));

    // Stem: short and thick, bent a little.
    final stem = Path()
      ..moveTo(22, 11.5)
      ..quadraticBezierTo(21.5, 6, 25, 3)
      ..lineTo(28, 4.5)
      ..quadraticBezierTo(25.5, 7.5, 26, 11.5)
      ..close();
    canvas.drawPath(stem, Paint()..color = _darkGreen);
    canvas.drawPath(stem, _stroke(1.3));
  }
}

/// A bell pepper in its colour (red, yellow or green), for the packaging
/// pepper screens.
class PepperIcon extends StatelessWidget {
  const PepperIcon({super.key, required this.colour, this.size = 44});
  final PepperColour colour;
  final double size;
  @override
  Widget build(BuildContext context) => _FarmIcon(_PepperPainter(colour), size);
}

enum PepperColour {
  red(Color(0xFFD7261E), Color(0xFF9E1612)),
  yellow(Color(0xFFF5C518), Color(0xFFC99A06)),
  green(Color(0xFF3E9B2F), Color(0xFF26691C));

  const PepperColour(this.skin, this.shade);
  final Color skin;
  final Color shade;

  /// "5kgRed" -> red, etc.
  static PepperColour of(String key) => key.endsWith('Red')
      ? red
      : key.endsWith('Yellow')
          ? yellow
          : green;
}

class _PepperPainter extends _GridPainter {
  _PepperPainter(this.colour);
  final PepperColour colour;

  @override
  void draw(Canvas canvas) {
    // Body: broad shoulders, three lobes at the bottom.
    final body = Path()
      ..moveTo(24, 11)
      ..cubicTo(30, 8.5, 41, 9.5, 41.5, 19)
      ..cubicTo(42, 27, 40.5, 36, 37, 41.5)
      ..cubicTo(34.5, 45, 30.5, 45, 29, 42.5)
      ..cubicTo(27, 45.5, 21, 45.5, 19, 42.5)
      ..cubicTo(17.5, 45, 13.5, 45, 11, 41.5)
      ..cubicTo(7.5, 36, 6, 27, 6.5, 19)
      ..cubicTo(7, 9.5, 18, 8.5, 24, 11)
      ..close();
    canvas.drawPath(body, Paint()..color = colour.skin);

    // Creases between the lobes, and a shine on the left shoulder.
    final crease = _stroke(1.4, colour.shade);
    canvas.drawPath(Path()..moveTo(18, 16)..cubicTo(16.5, 26, 17, 35, 19, 42.5), crease);
    canvas.drawPath(Path()..moveTo(30, 16)..cubicTo(31.5, 26, 31, 35, 29, 42.5), crease);
    canvas.drawPath(
      Path()..moveTo(11.5, 18)..cubicTo(11, 23, 11.5, 28, 13, 32),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(body, _stroke(1.8));

    // Green cap and stem on top.
    const stemGreen = Color(0xFF2E6B22);
    final cap = Path()
      ..moveTo(16.5, 12)
      ..quadraticBezierTo(24, 7, 31.5, 12)
      ..quadraticBezierTo(24, 15, 16.5, 12)
      ..close();
    canvas.drawPath(cap, Paint()..color = stemGreen);
    canvas.drawPath(cap, _stroke(1.2));
    final stem = Path()
      ..moveTo(22.5, 10)
      ..quadraticBezierTo(22, 5, 25.5, 2.5)
      ..lineTo(27.5, 4)
      ..quadraticBezierTo(25, 6, 25.5, 10)
      ..close();
    canvas.drawPath(stem, Paint()..color = stemGreen);
    canvas.drawPath(stem, _stroke(1.2));
  }
}
