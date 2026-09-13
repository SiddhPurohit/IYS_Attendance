import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A drawn lotus — the app's signature motif, used wherever the 🪷 emoji
/// used to sit. Vector, so it stays crisp at any size and can be tinted.
class LotusIcon extends StatelessWidget {
  final double size;

  /// Front row of petals.
  final Color petalColor;

  /// Back row. Keep it a distinctly paler (or darker) tint of [petalColor] —
  /// the two rows overlap, and without contrast the bloom reads as a
  /// starburst rather than layered petals.
  final Color backPetalColor;
  final Color heartColor;

  const LotusIcon({
    super.key,
    this.size = 48,
    this.petalColor = AppColors.saffron,
    this.backPetalColor = const Color(0xFFF7D79A),
    this.heartColor = AppColors.saffronDark,
  });

  /// White bloom for use on the saffron/teal gradient surfaces.
  const LotusIcon.light({super.key, this.size = 48})
    : petalColor = Colors.white,
      backPetalColor = const Color(0xFFCFE7E2),
      heartColor = const Color(0xFFF0B429);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _LotusPainter(
          petalColor: petalColor,
          backPetalColor: backPetalColor,
          heartColor: heartColor,
        ),
      ),
    );
  }
}

class _LotusPainter extends CustomPainter {
  final Color petalColor;
  final Color backPetalColor;
  final Color heartColor;

  _LotusPainter({
    required this.petalColor,
    required this.backPetalColor,
    required this.heartColor,
  });

  /// A petal pointing along +x from the origin: the lens where two circles
  /// overlap. Both pass through the origin and the tip, so the shape comes
  /// to a point at each end — the same geometry as the launcher icon.
  Path _petal(double length, double halfWidth) {
    final k = (length * length / 4 - halfWidth * halfWidth) / (2 * halfWidth);
    final radius = halfWidth + k;
    final upper = Path()
      ..addOval(
        Rect.fromCircle(center: Offset(length / 2, -k), radius: radius),
      );
    final lower = Path()
      ..addOval(Rect.fromCircle(center: Offset(length / 2, k), radius: radius));
    return Path.combine(PathOperation.intersect, upper, lower);
  }

  void _drawRow(
    Canvas canvas,
    Offset centre,
    Path petal,
    Paint paint,
    double phase,
  ) {
    for (var i = 0; i < 8; i++) {
      canvas.save();
      canvas.translate(centre.dx, centre.dy);
      canvas.rotate(i * math.pi / 4 + phase);
      canvas.drawPath(petal, paint);
      canvas.restore();
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;

    // Back row, offset half a step so it shows between the front petals.
    _drawRow(
      canvas,
      c,
      _petal(r, r * 0.225),
      Paint()..color = backPetalColor,
      math.pi / 8,
    );

    // Front row.
    _drawRow(
      canvas,
      c,
      _petal(r * 0.78, r * 0.195),
      Paint()..color = petalColor,
      0,
    );

    canvas.drawCircle(c, r * 0.10, Paint()..color = heartColor);
  }

  @override
  bool shouldRepaint(_LotusPainter old) =>
      old.petalColor != petalColor ||
      old.backPetalColor != backPetalColor ||
      old.heartColor != heartColor;
}

/// A peacock feather — Krsna's crown. Used as a soft watermark behind
/// headers rather than as a foreground icon.
class PeacockFeather extends StatelessWidget {
  final double size;
  final double opacity;

  const PeacockFeather({super.key, this.size = 120, this.opacity = 0.18});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size * 1.6,
      child: CustomPaint(painter: _FeatherPainter(opacity: opacity)),
    );
  }
}

class _FeatherPainter extends CustomPainter {
  final double opacity;

  _FeatherPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final eye = Offset(cx, h * 0.27);
    final eyeR = w * 0.30;
    final barbTop = h * 0.40;

    // Plume: many fine barbs sweeping down and out from the shaft, longest
    // just under the eye. Drawn before the shaft so it sits behind it.
    const count = 20;
    for (var i = 0; i < count; i++) {
      final t = i / (count - 1);
      final y = barbTop + t * (h * 0.92 - barbTop);
      final length = w * 0.46 * (1 - t * 0.72);
      final droop = 0.55 + t * 0.5; // barbs angle further down lower on
      final paint = Paint()
        ..color = Color.lerp(
          AppColors.tealLight,
          AppColors.teal,
          t,
        )!.withValues(alpha: opacity * (0.85 - t * 0.25))
        ..strokeWidth = w * 0.013
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;

      for (final side in const [-1.0, 1.0]) {
        final end = Offset(
          cx + side * length * math.cos(droop),
          y + length * math.sin(droop),
        );
        canvas.drawPath(
          Path()
            ..moveTo(cx, y)
            ..quadraticBezierTo(
              cx + side * length * 0.55,
              y + length * 0.12,
              end.dx,
              end.dy,
            ),
          paint,
        );
      }
    }

    // Shaft.
    canvas.drawLine(
      Offset(cx, h * 0.36),
      Offset(cx, h * 0.94),
      Paint()
        ..color = AppColors.tealDark.withValues(alpha: opacity * 0.9)
        ..strokeWidth = w * 0.022
        ..strokeCap = StrokeCap.round,
    );

    // The eye: concentric ovals, outer green through gold to a dark heart.
    void oval(double rx, double ry, Color color, [double alphaScale = 1.0]) {
      canvas.drawOval(
        Rect.fromCenter(center: eye, width: rx * 2, height: ry * 2),
        Paint()..color = color.withValues(alpha: opacity * alphaScale),
      );
    }

    oval(eyeR, eyeR * 1.22, AppColors.tealLight);
    oval(eyeR * 0.80, eyeR * 0.98, AppColors.peacockGreen);
    oval(eyeR * 0.62, eyeR * 0.76, AppColors.saffron);
    oval(eyeR * 0.42, eyeR * 0.54, AppColors.peacockBlue);
    oval(eyeR * 0.22, eyeR * 0.30, AppColors.tealDark);
  }

  @override
  bool shouldRepaint(_FeatherPainter old) => old.opacity != opacity;
}

/// Soft saffron-to-teal wash with a feather watermark, for screen headers.
class SacredHeader extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry? borderRadius;

  const SacredHeader({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 20, 20, 24),
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.circular(24),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(gradient: AppGradients.sacred),
            ),
          ),
          Positioned(
            right: -14,
            top: -22,
            child: Transform.rotate(
              angle: 0.35,
              child: const PeacockFeather(size: 120, opacity: 0.22),
            ),
          ),
          Padding(padding: padding, child: child),
        ],
      ),
    );
  }
}
