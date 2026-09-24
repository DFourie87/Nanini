import 'package:flutter/material.dart';
import '../../theme/nanini_theme.dart';

/// A scoped hunting rifle drawn in code -- there's no rifle emoji (🔫 is a
/// water pistol on most phones), so the Hunting hub tile uses this.
class RifleIcon extends StatelessWidget {
  const RifleIcon({super.key, this.height = 42});
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: height * 64 / 28,
      height: height,
      child: CustomPaint(painter: _RiflePainter()),
    );
  }
}

class _RiflePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Drawn on a 64 x 28 grid, scaled to fit.
    final s = size.width / 64;
    canvas.save();
    canvas.translate(0, (size.height - 28 * s) / 2);
    canvas.scale(s);

    final metal = Paint()..color = NaniniColors.ink;
    // Natural wood colour, like the other tiles' emoji -- the brand rust
    // made the stock look like a toy.
    final wood = Paint()..color = const Color(0xFF7A4A24);

    // Barrel and receiver.
    canvas.drawRRect(RRect.fromLTRBR(30, 11, 63.5, 13.2, const Radius.circular(0.8)), metal);
    canvas.drawRRect(RRect.fromLTRBR(20, 9.5, 35, 14.5, const Radius.circular(1)), metal);

    // Scope with its mounts.
    canvas.drawRRect(RRect.fromLTRBR(22, 4.2, 39, 7.8, const Radius.circular(1.8)), metal);
    canvas.drawRRect(RRect.fromLTRBR(38, 3.2, 42.5, 8.8, const Radius.circular(1.2)), metal);
    canvas.drawRRect(RRect.fromLTRBR(19.5, 4.6, 23, 7.4, const Radius.circular(1)), metal);
    canvas.drawRect(const Rect.fromLTRB(25, 7.5, 27, 9.8), metal);
    canvas.drawRect(const Rect.fromLTRB(34, 7.5, 36, 9.8), metal);

    // Trigger guard.
    final guard = Paint()
      ..color = NaniniColors.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawArc(const Rect.fromLTRB(24, 12, 30.5, 18), 0, 3.1416, false, guard);

    // Wooden forend under the barrel.
    canvas.drawRRect(RRect.fromLTRBR(34, 12.4, 50, 15.4, const Radius.circular(1.4)), wood);

    // Stock: from the back of the receiver down through the grip to the butt.
    final stock = Path()
      ..moveTo(21, 9.8)
      ..lineTo(10, 11)
      ..lineTo(1, 12.2)
      ..quadraticBezierTo(0, 12.4, 0, 13.6)
      ..lineTo(0, 21.2)
      ..quadraticBezierTo(0, 22.4, 1.4, 22.2)
      ..lineTo(4.5, 21.6)
      ..lineTo(13, 16.4)
      ..quadraticBezierTo(16, 15, 18.5, 17.8)
      ..lineTo(20.5, 20.2)
      ..lineTo(23.5, 19.6)
      ..lineTo(21.5, 14.5)
      ..close();
    canvas.drawPath(stock, wood);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
