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

/// Portable generator: frame, engine body, lightning bolt and sockets.
class GeneratorIcon extends StatelessWidget {
  const GeneratorIcon({super.key, this.size = 44});
  final double size;
  @override
  Widget build(BuildContext context) => _FarmIcon(_GeneratorPainter(), size);
}

class _GeneratorPainter extends _GridPainter {
  @override
  void draw(Canvas canvas) {
    // Roll frame with carry handle on top.
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(4, 12, 40, 28), const Radius.circular(3)), _stroke(2.5));
    canvas.drawLine(const Offset(14, 12), const Offset(14, 7), _stroke(2.5));
    canvas.drawLine(const Offset(34, 12), const Offset(34, 7), _stroke(2.5));
    canvas.drawLine(const Offset(14, 7), const Offset(34, 7), _stroke(2.5));
    // Body.
    final body = RRect.fromRectAndRadius(const Rect.fromLTWH(8, 16, 32, 20), const Radius.circular(3));
    canvas.drawRRect(body, Paint()..color = NaniniColors.amber);
    canvas.drawRRect(body, _stroke(1.5));
    // Lightning bolt.
    final bolt = Path()
      ..moveTo(21, 18)
      ..lineTo(15, 27)
      ..lineTo(20, 27)
      ..lineTo(17, 34)
      ..lineTo(25, 24)
      ..lineTo(20, 24)
      ..lineTo(23, 18)
      ..close();
    canvas.drawPath(bolt, Paint()..color = NaniniColors.ink);
    // Sockets.
    canvas.drawCircle(const Offset(32, 23), 2.2, Paint()..color = NaniniColors.ink);
    canvas.drawCircle(const Offset(32, 30), 2.2, Paint()..color = NaniniColors.ink);
    // Feet.
    canvas.drawLine(const Offset(8, 42), const Offset(12, 42), _stroke(3));
    canvas.drawLine(const Offset(36, 42), const Offset(40, 42), _stroke(3));
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
