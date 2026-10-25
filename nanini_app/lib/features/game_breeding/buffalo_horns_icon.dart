import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A Cape buffalo bull's head and horns, shaped on SPO20's -- the boss across
/// the forehead, each horn out and down, then sweeping up to its tip -- as an icon (the Herd tab's): drawn in the
/// icon colour and size where it sits, like any [Icon].
class BuffaloHornsIcon extends StatelessWidget {
  const BuffaloHornsIcon({super.key, this.size, this.color});
  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    return SizedBox(width: s, height: s, child: CustomPaint(painter: _HornsPainter(color ?? theme.color ?? Colors.black)));
  }
}

class _HornsPainter extends CustomPainter {
  _HornsPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas.scale(k);
    final paint = Paint()..color = color;
    // One horn on a 24 × 24 grid, shaped on SPO20's: growing out of the boss,
    // out and down beside the head, then sweeping wide and up to its tip;
    // heavy at the base, thin at the tip. The other is its mirror image.
    const p0 = Offset(9.6, 6.4), p1 = Offset(5.2, 10.4), p2 = Offset(0.6, 17.6), p3 = Offset(1.6, 3.4);
    Offset at(double t) {
      final u = 1 - t;
      return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t);
    }

    final left = <Offset>[], right = <Offset>[];
    const n = 48;
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      final a = at(math.max(0, t - 0.01)), b = at(math.min(1, t + 0.01));
      final d = b - a;
      final normal = Offset(-d.dy, d.dx) / d.distance;
      final w = 4.0 * (1 - t) + 0.45 * t; // width
      left.add(at(t) + normal * (w / 2));
      right.add(at(t) - normal * (w / 2));
    }
    final horn = Path()..addPolygon([...left, ...right.reversed], true);
    // A broad ear hanging out and down under the horn.
    final ear = Path()
      ..moveTo(8.6, 12.0)
      ..cubicTo(7.4, 11.8, 5.6, 12.6, 4.8, 14.2)
      ..cubicTo(6.0, 15.4, 7.8, 15.0, 8.9, 14.4)
      ..close();
    for (final mirror in [false, true]) {
      canvas.save();
      if (mirror) {
        canvas.translate(24, 0);
        canvas.scale(-1, 1);
      }
      canvas.drawPath(horn, paint);
      canvas.drawPath(ear, paint);
      canvas.restore();
    }
    // The head in one piece with the boss: the heavy dome across the
    // forehead (parted in the middle), a broad face and a wide, square
    // muzzle; eyes and nostrils left open.
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..moveTo(12, 5.1)
        ..cubicTo(13.2, 3.9, 17.6, 4.4, 18.0, 8.8)
        ..cubicTo(16.8, 9.2, 15.9, 9.7, 15.8, 10.8)
        ..cubicTo(15.8, 13.4, 15.1, 15.2, 15.4, 17.4)
        ..cubicTo(15.7, 20.2, 14.4, 21.2, 12, 21.2)
        ..cubicTo(9.6, 21.2, 8.3, 20.2, 8.6, 17.4)
        ..cubicTo(8.9, 15.2, 8.2, 13.4, 8.2, 10.8)
        ..cubicTo(8.1, 9.7, 7.2, 9.2, 6.0, 8.8)
        ..cubicTo(6.4, 4.4, 10.8, 3.9, 12, 5.1)
        ..close()
        ..addOval(Rect.fromCircle(center: const Offset(10.1, 11.9), radius: 0.6))
        ..addOval(Rect.fromCircle(center: const Offset(13.9, 11.9), radius: 0.6))
        ..addOval(Rect.fromCenter(center: const Offset(10.8, 18.7), width: 1.3, height: 1.0))
        ..addOval(Rect.fromCenter(center: const Offset(13.2, 18.7), width: 1.3, height: 1.0)),
      paint,
    );
  }

  @override
  bool shouldRepaint(_HornsPainter old) => old.color != color;
}
