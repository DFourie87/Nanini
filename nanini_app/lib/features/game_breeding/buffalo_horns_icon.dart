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
    // One horn on a 24 × 24 grid, shaped on SPO20's: from the boss out and
    // down beside the head, then sweeping wide and up to a tip turned a
    // little in; heavy at the base, thin at the tip. The other is its mirror
    // image.
    const p0 = Offset(7.6, 8.4), p1 = Offset(4.6, 12.4), p2 = Offset(0.4, 12.2), p3 = Offset(1.8, 3.0);
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
      final w = 3.4 * (1 - t) + 0.45 * t; // width
      left.add(at(t) + normal * (w / 2));
      right.add(at(t) - normal * (w / 2));
    }
    final horn = Path()..addPolygon([...left, ...right.reversed], true);
    // An ear under the horn, pointing out.
    final ear = Path()
      ..moveTo(9.2, 11.6)
      ..quadraticBezierTo(7.0, 11.4, 5.6, 13.4)
      ..quadraticBezierTo(7.6, 14.4, 9.4, 13.6)
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
    // The boss: a heavy dome across the forehead, joining the horns.
    canvas.drawPath(
      Path()
        ..moveTo(6.0, 9.6)
        ..cubicTo(6.6, 4.4, 17.4, 4.4, 18.0, 9.6)
        ..cubicTo(15.6, 8.2, 8.4, 8.2, 6.0, 9.6)
        ..close(),
      paint,
    );
    // The head below it: broad at the eyes, narrowing to the muzzle.
    canvas.drawPath(
      Path()
        ..moveTo(9.2, 10.4)
        ..cubicTo(10.6, 9.8, 13.4, 9.8, 14.8, 10.4)
        ..cubicTo(15.2, 13.0, 14.4, 15.0, 14.0, 18.6)
        ..cubicTo(13.8, 21.2, 10.2, 21.2, 10.0, 18.6)
        ..cubicTo(9.6, 15.0, 8.8, 13.0, 9.2, 10.4)
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(_HornsPainter old) => old.color != color;
}
