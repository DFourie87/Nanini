import 'package:flutter/material.dart';
import '../theme/nanini_theme.dart';

/// A knapsack chemical sprayer drawn in code -- there's no sprayer emoji, so
/// the capture app's "Spraying and Fertilizing" choice uses this.
class SprayerIcon extends StatelessWidget {
  const SprayerIcon({super.key, this.size = 44});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _SprayerPainter()));
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
      (43.0, 9.0, 1.6), (45.5, 12.5, 1.4), (41.5, 5.5, 1.4), (46.5, 7.0, 1.2),
      (44.0, 3.0, 1.1), (47.0, 2.5, 0.9), (47.2, 11.0, 0.9),
    ]) {
      canvas.drawCircle(Offset(x, y), r, mist);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
