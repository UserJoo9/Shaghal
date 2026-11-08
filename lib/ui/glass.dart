import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_design/liquid_design.dart';

import '../state/providers.dart';

/// ألوان بتتبدّل تلقائياً بين الداكن والفاتح.
extension AppInk on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
  Color get bg => isDark ? Colors.black : const Color(0xFFF2F2F7);
  Color get fg => isDark ? Colors.white : const Color(0xFF111114);
  Color fgA(double a) => fg.withValues(alpha: a);
  Color get fg70 => fgA(0.70);
  Color get fg54 => fgA(0.54);
  Color get fg38 => fgA(0.38);
  Color get fg24 => fgA(0.24);
}

/// خلفية سودا بإضاءة ملوّنة ثابتة، ولو في أغنية شغالة بيظهر غلافها مطموس خلف كل حاجة.
/// عمداً مفيش حركة ولا blur تقيل: الخلفية بتتـrasterize مرة واحدة (RepaintBoundary)
/// فالانتقال بين الصفحات والسكرول يفضلوا ناعمين، والزجاج لسه عنده حاجة يكسرها ويعكسها.
class GlassBackground extends ConsumerWidget {
  const GlassBackground({super.key, this.child});
  final Widget? child;

  static Widget _glow(Alignment at, Color color, double alpha, double size) {
    return Align(
      alignment: at,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(currentItemProvider.select((v) => v.value?.path));
    final art = path == null ? null : ref.watch(thumbProvider(path)).value;

    final k = context.isDark ? 1.0 : 0.5; // الإضاءة أخف في الوضع الفاتح

    return ColoredBox(
      color: context.bg,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // غلاف الأغنية الحالية: صورة صغيرة جداً متكبّرة = طمس رخيص من غير فلتر
                if (art != null)
                  Opacity(
                    opacity: 0.38 * k,
                    child: Image.file(
                      File(art),
                      key: ValueKey(art),
                      fit: BoxFit.cover,
                      cacheWidth: 24,
                      filterQuality: FilterQuality.high,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                _glow(const Alignment(-0.9, -0.85), const Color(0xFF6A4DFF), 0.42 * k, 520),
                _glow(const Alignment(1.0, -0.1), const Color(0xFF0A84FF), 0.32 * k, 480),
                _glow(const Alignment(-0.6, 0.95), const Color(0xFFFF3B8E), 0.26 * k, 460),
              ],
            ),
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
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
    this.interactive = false,
  });

  final Widget child;
  final bool interactive;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double blur;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    return LiquidGlass(
      tintColor: tint,
      interactive: interactive,
      fallback: LiquidGlassFallback.frosted,
      fallbackBlurSigma: 22,
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
            onTap: onPressed == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onPressed!();
                  },
            child: Center(child: Icon(icon,
                size: iconSize,
                color: tint != null ? Colors.white : context.fg)),
          ),
        ),
      ),
    );
  }
}


/// بيطبّق اتجاه اللغة الحالية على الصفحة (RTL للعربي، LTR للإنجليزي) من غير ما يقلب
/// اتجاه التنقل نفسه (عشان سحب الرجوع يفضل من حافة الشمال).
class Rtl extends ConsumerWidget {
  const Rtl({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ar = ref.watch(langProvider) == AppLang.ar;
    return Directionality(
      textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
      child: child,
    );
  }
}
