import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_design/liquid_design.dart';

import '../state/providers.dart';

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

    return ColoredBox(
      color: Colors.black,
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
                    opacity: 0.38,
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
                _glow(const Alignment(-0.9, -0.85), const Color(0xFF6A4DFF), 0.42, 520),
                _glow(const Alignment(1.0, -0.1), const Color(0xFF0A84FF), 0.32, 480),
                _glow(const Alignment(-0.6, 0.95), const Color(0xFFFF3B8E), 0.26, 460),
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
            onTap: onPressed,
            child: Center(child: Icon(icon, size: iconSize, color: Colors.white)),
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

/// صف قايمة بمظهر زجاجي خفيف (تدرّج شفاف + حافة + لمعة علوية) من غير ما يعمل blur/refraction
/// لكل صف. ده اللي بيخلّي السكرول ناعم مع مئات الصفوف، والزجاج الحقيقي مخصّص
/// للعناصر الثابتة (الهيدر، الأزرار، شريط التشغيل، القوايم).
class GlassTile extends StatelessWidget {
  const GlassTile({
    super.key,
    required this.child,
    this.onTap,
    this.radius = 20,
    this.highlight = false,
    this.padding = const EdgeInsets.all(10),
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final bool highlight;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    final base = highlight ? const Color(0xFF0A84FF) : Colors.white;
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: r,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              base.withValues(alpha: highlight ? 0.34 : 0.16),
              base.withValues(alpha: highlight ? 0.12 : 0.04),
            ],
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: highlight ? 0.40 : 0.20),
            width: 0.8,
          ),
        ),
        child: ClipRRect(
          borderRadius: r,
          child: Stack(
            children: [
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: onTap,
                  child: Padding(padding: padding, child: child),
                ),
              ),
              // لمعة رفيعة على الحافة العلوية
              Positioned(
                top: 0,
                left: radius,
                right: radius,
                height: 1,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0),
                          Colors.white.withValues(alpha: 0.55),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
