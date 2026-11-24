import 'package:material_ui/material_ui.dart';

/// The same linked-play mark is used in the launcher SVG and native icons.
class ClipShareMark extends StatelessWidget {
  const ClipShareMark({super.key, this.size = 36});
  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'ClipShare',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _MarkPainter()),
    ),
  );
}

class _MarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 1024, size.height / 1024);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 1024, 1024),
        const Radius.circular(256),
      ),
      Paint()..color = const Color(0xFF302435),
    );
    final link = Path()
      ..moveTo(530, 300)
      ..lineTo(600, 230)
      ..cubicTo(740, 90, 940, 290, 800, 430)
      ..lineTo(700, 530)
      ..moveTo(324, 494)
      ..lineTo(224, 594)
      ..cubicTo(84, 734, 284, 934, 424, 794)
      ..lineTo(494, 724);
    canvas.drawPath(
      link,
      Paint()
        ..color = const Color(0xFFF5C5A5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 76
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      Path()
        ..moveTo(430, 368)
        ..lineTo(430, 656)
        ..lineTo(650, 512)
        ..close(),
      Paint()..color = const Color(0xFFFAF7F2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
