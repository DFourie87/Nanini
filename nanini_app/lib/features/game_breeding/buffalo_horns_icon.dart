import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A Cape buffalo's head and horns, shaped on PO20's -- each horn out and a
/// little down from the head, then sweeping up to its tip -- as an icon (the Herd tab's): drawn in the
/// icon colour and size where it sits, like any [Icon].
class BuffaloHornsIcon extends StatelessWidget {
  const BuffaloHornsIcon({super.key, this.size});
  final double? size;

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final s = size ?? theme.size ?? 24;
    return SizedBox(width: s, height: s, child: CustomPaint(painter: _HornsPainter(theme.color ?? Colors.black)));
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
    // One horn on a 24 × 24 grid, shaped on PO20's: from the top of the head
    // out and a little down, then sweeping up to a tip that turns slightly
    // in; thick at the base, thin at the tip. The other is its mirror image.
    const p0 = Offset(9.2, 8.8), p1 = Offset(4.6, 12.2), p2 = Offset(0.2, 10.4), p3 = Offset(2.9, 3.2);
    Offset at(double t) {
      final u = 1 - t;
      return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t);
    }

    final left = <Offset>[], right = <Offset>[];
    const n = 40;
    for (var i = 0; i <= n; i++) {
      final t = i / n;
      final a = at(math.max(0, t - 0.01)), b = at(math.min(1, t + 0.01));
      final d = b - a;
      final normal = Offset(-d.dy, d.dx) / d.distance;
      final w = 2.8 * (1 - t) + 0.45 * t; // width
      left.add(at(t) + normal * (w / 2));
      right.add(at(t) - normal * (w / 2));
    }
    final horn = Path()..addPolygon([...left, ...right.reversed], true);
    // An ear under the horn, pointing out.
    final ear = Path()
      ..moveTo(9.0, 11.0)
      ..quadraticBezierTo(6.6, 10.6, 5.0, 12.6)
      ..quadraticBezierTo(7.2, 13.8, 9.2, 13.0)
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
    // The head: a rounded forehead between the horns, the long face
    // narrowing to the muzzle.
    canvas.drawPath(
      Path()
        ..moveTo(8.8, 9.4)
        ..cubicTo(9.0, 5.6, 15.0, 5.6, 15.2, 9.4)
        ..cubicTo(15.4, 12.6, 14.4, 15.0, 14.2, 18.6)
        ..cubicTo(14.0, 21.4, 10.0, 21.4, 9.8, 18.6)
        ..cubicTo(9.6, 15.0, 8.6, 12.6, 8.8, 9.4)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(_HornsPainter old) => old.color != color;
}
