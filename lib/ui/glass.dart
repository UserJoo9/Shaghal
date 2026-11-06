import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_design/liquid_design.dart';

import '../state/providers.dart';

/// خلفية سودا مع أضواء ناعمة بتتحرك ببطء، ولو في أغنية شغالة بيظهر غلافها مطموس خلف كل حاجة.
/// ده اللي بيدّي الزجاج حاجة يكسرها ويعكسها.
class GlassBackground extends ConsumerStatefulWidget {
  const GlassBackground({super.key, this.child});
  final Widget? child;

  @override
  ConsumerState<GlassBackground> createState() => _GlassBackgroundState();
}

class _GlassBackgroundState extends ConsumerState<GlassBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 40),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    ref.listenManual<bool>(scrollingProvider, (_, scrolling) {
      if (scrolling) {
        _c.stop();
      } else {
        _c.repeat();
      }
    });
  }

  Widget _orb(double t, int k, double phase, Color color, double alpha, double size) {
    final a = 2 * math.pi * (k * t + phase);
    return Align(
      alignment: Alignment(0.95 * math.sin(a), 0.95 * math.cos(a * 0.8 + phase * 6)),
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
  Widget build(BuildContext context) {
    final path = ref.watch(currentItemProvider.select((v) => v.value?.path));
    final art = path == null ? null : ref.watch(thumbProvider(path)).value;

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // غلاف الأغنية الحالية مطموس
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 700),
            child: art == null
                ? const SizedBox.expand(key: ValueKey('no-art'))
                : RepaintBoundary(
                    key: ValueKey(art),
                    child: Opacity(
                      opacity: 0.42,
                      child: ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: 50,
                          sigmaY: 50,
                          tileMode: TileMode.clamp,
                        ),
                        child: Image.file(
                          File(art),
                          fit: BoxFit.cover,
                          cacheWidth: 200,
                          width: double.infinity,
                          height: double.infinity,
                        ),
                      ),
                    ),
                  ),
          ),
          // أضواء بتتحرك ببطء
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (_, __) => Stack(
                fit: StackFit.expand,
                children: [
                  _orb(_c.value, 1, 0.00, const Color(0xFF6A4DFF), 0.30, 460),
                  _orb(_c.value, 1, 0.38, const Color(0xFF0A84FF), 0.24, 420),
                  _orb(_c.value, 2, 0.71, const Color(0xFFFF3B8E), 0.18, 380),
                ],
              ),
            ),
          ),
          if (widget.child != null) widget.child!,
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


/// يخلّي محتوى الصفحة من اليمين لليسار من غير ما يقلب اتجاه التنقل
/// (عشان سحب الرجوع يفضل من حافة الشمال).
class Rtl extends StatelessWidget {
  const Rtl({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Directionality(textDirection: TextDirection.rtl, child: child);
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
