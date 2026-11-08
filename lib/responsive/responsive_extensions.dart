// lib/responsive/responsive_extensions.dart
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'breakpoints.dart';

/// Baseline device (iPhone 12/13-ish)
const _baselineW = 390.0;
const _baselineH = 844.0;

extension ResponsiveContext on BuildContext {
  MediaQueryData get mq => MediaQuery.of(this);
  Size get screenSize => mq.size;
  double get sw => screenSize.width;
  double get sh => screenSize.height;
  double get textScale => mq.textScaler.scale(1.0);

  bool get isXS => sw < Breakpoints.xs;
  bool get isSM => sw >= Breakpoints.xs && sw < Breakpoints.sm;
  bool get isMD => sw >= Breakpoints.sm && sw < Breakpoints.md;
  bool get isLG => sw >= Breakpoints.md && sw < Breakpoints.lg;
  bool get isXL => sw >= Breakpoints.lg;

  bool get isPhone => sw < Breakpoints.sm;
  bool get isTablet => sw >= Breakpoints.sm && sw < Breakpoints.lg;
  bool get isDesktop => sw >= Breakpoints.lg;

  /// Suggested drawer width
  double get drawerWidth {
    if (isPhone) return math.min(sw * 0.86, 340);
    if (isTablet) return 360;
    return 380;
  }
}

extension ResponsiveNumber on num {
  /// Scale by width (use for paddings, icon sizes, radii)
  double rw(BuildContext context, {double min = 0.85, double max = 1.25}) {
    final s = (context.sw / _baselineW).clamp(min, max);
    return this * s;
  }

  /// Scale by height (use sparingly for vertical spacing)
  double rh(BuildContext context, {double min = 0.85, double max = 1.25}) {
    final s = (context.sh / _baselineH).clamp(min, max);
    return this * s;
  }

  /// Scale for font sizes; respects user text scaling
  double sp(BuildContext context, {double min = 0.90, double max = 1.20}) {
    final widthScale = (context.sw / _baselineW).clamp(min, max);
    final userScale = context.textScale.clamp(0.85, 1.30);
    return this * widthScale * userScale;
  }
}

/// Choose values per breakpoint
class ResponsiveValue<T> {
  final T fallback;
  final T? xs, sm, md, lg, xl;

  const ResponsiveValue({
    required this.fallback,
    this.xs,
    this.sm,
    this.md,
    this.lg,
    this.xl,
  });

  T of(BuildContext c) {
    if (c.isXL && xl != null) return xl as T;
    if (c.isLG && lg != null) return lg as T;
    if (c.isMD && md != null) return md as T;
    if (c.isSM && sm != null) return sm as T;
    if (c.isXS && xs != null) return xs as T;
    return fallback;
  }
}
