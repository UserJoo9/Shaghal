import 'dart:ui';

import 'package:flutter/material.dart';

/// خلفية ملوّنة عشان الزجاج يبان عليها.
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B1026), Color(0xFF1B1140), Color(0xFF0A2A3A)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const _Blob(Alignment(-0.9, -0.7), Color(0xFF7C4DFF), 340),
          const _Blob(Alignment(1.0, -0.1), Color(0xFF00B8D4), 300),
          const _Blob(Alignment(-0.6, 0.9), Color(0xFFFF4081), 320),
          if (child != null) child!,
        ],
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob(this.alignment, this.color, this.size);
  final Alignment alignment;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: 0.55), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// سطح زجاجي: blur + تدرّج شفاف + حافة لامعة.
/// استخدمه في العناصر القليلة (header، mini player، أزرار) مش في كل صف في القايمة،
/// لأن BackdropFilter غالي.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = const EdgeInsets.all(12),
    this.blur = 28,
    this.tint,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double blur;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    final base = tint ?? Colors.white;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: r,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: r,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: r,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  base.withValues(alpha: 0.26),
                  base.withValues(alpha: 0.07),
                ],
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.38),
                width: 0.8,
              ),
            ),
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 48,
    this.iconSize = 24,
    this.tint,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Glass(
        radius: size / 2,
        padding: EdgeInsets.zero,
        blur: 20,
        tint: tint,
        child: InkResponse(
          onTap: onPressed,
          child: Center(child: Icon(icon, size: iconSize, color: Colors.white)),
        ),
      ),
    );
  }
}
