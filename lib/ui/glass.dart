import 'package:flutter/material.dart';
import 'package:liquid_design/liquid_design.dart';

/// خلفية سودا (OLED). الزجاج بيبان على المحتوى اللي وراه (القايمة والفيديو).
class GlassBackground extends StatelessWidget {
  const GlassBackground({super.key, this.child});
  final Widget? child;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Colors.black, child: child);
}

/// سطح Liquid Glass حقيقي: على iOS 26+ بيستخدم زجاج Apple النيتيف (UIGlassEffect)،
/// وعلى الأقدم/غيره بيرجع لـ blur عادي.
/// ملاحظة: متحطش Glass جوّه Glass تاني (زجاج على زجاج بيطلع وحش).
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius = 28,
    this.padding = const EdgeInsets.all(12),
    this.blur = 28, // محفوظ للتوافق، النيتيف بيتحكم فيه النظام
    this.tint,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double blur;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      tintColor: tint,
      interactive: false,
      fallback: LiquidGlassFallback.frosted,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// زر دايري زجاجي (للاستخدام لوحده، مش جوّه Glass).
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
    return LiquidGlass(
      tintColor: tint,
      interactive: true,
      fallback: LiquidGlassFallback.frosted,
      child: ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onPressed,
            child: Center(child: Icon(icon, size: iconSize, color: Colors.white)),
          ),
        ),
      ),
    );
  }
}
