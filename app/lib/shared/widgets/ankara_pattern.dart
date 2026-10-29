import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Subtle West African textile motifs drawn in code (no bitmaps).
enum TextileStyle { ankara, adire }

class TextilePattern extends StatelessWidget {
  const TextilePattern({
    super.key,
    this.style = TextileStyle.ankara,
    this.color = const Color(0xFF00A859),
    this.opacity = 0.08,
    this.cell = 28,
    this.child,
  });
  final TextileStyle style;
  final Color color;
  final double opacity;
  final double cell;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: style == TextileStyle.ankara
            ? AnkaraPainter(color.withValues(alpha: opacity), cell)
            : AdirePainter(color.withValues(alpha: opacity), cell),
        child: child ?? const SizedBox.expand(),
      ),
    );
  }
}

/// Ankara wax-print feel: diamonds with a centre dot and petal rings.
class AnkaraPainter extends CustomPainter {
  AnkaraPainter(this.color, this.cell);
  final Color color;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final fill = Paint()..color = color;
    final h = cell / 2;
    var row = 0;
    for (double y = 0; y < size.height + cell; y += cell, row++) {
      final off = row.isOdd ? h : 0.0;
      for (double x = -h; x < size.width + cell; x += cell) {
        final c = Offset(x + off, y);
        final p = Path()
          ..moveTo(c.dx, c.dy - h * .8)
          ..lineTo(c.dx + h * .8, c.dy)
          ..lineTo(c.dx, c.dy + h * .8)
          ..lineTo(c.dx - h * .8, c.dy)
          ..close();
        canvas.drawPath(p, stroke);
        canvas.drawCircle(c, h * .32, stroke);
        canvas.drawCircle(c, h * .1, fill);
      }
    }
  }

  @override
  bool shouldRepaint(AnkaraPainter old) => old.color != color || old.cell != cell;
}

/// Adire (indigo resist-dye) feel: dotted grid with tied circles.
class AdirePainter extends CustomPainter {
  AdirePainter(this.color, this.cell);
  final Color color;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (double y = cell / 2; y < size.height + cell; y += cell) {
      for (double x = cell / 2; x < size.width + cell; x += cell) {
        final c = Offset(x, y);
        canvas.drawCircle(c, cell * .3, stroke);
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4;
          canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * cell * .18, 1.1, fill);
        }
        canvas.drawLine(Offset(x + cell / 2, y - cell * .2), Offset(x + cell / 2, y + cell * .2), stroke);
      }
    }
  }

  @override
  bool shouldRepaint(AdirePainter old) => old.color != color || old.cell != cell;
}
