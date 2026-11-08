// lib/responsive/responsive_theme.dart
import 'dart:ui' show lerpDouble; // needed for ThemeExtension.lerp
import 'package:flutter/material.dart';
import 'responsive_extensions.dart';

/// Optional: a ThemeExtension to keep common sizes in one place.
@immutable
class ResponsiveTokens extends ThemeExtension<ResponsiveTokens> {
  final double radius;
  final double padding;
  final double icon;

  const ResponsiveTokens({
    required this.radius,
    required this.padding,
    required this.icon,
  });

  factory ResponsiveTokens.of(BuildContext context) {
    return ResponsiveTokens(
      radius: 12.rw(context),
      padding: 12.rw(context),
      icon: 22.rw(context),
    );
  }

  @override
  ResponsiveTokens copyWith({
    double? radius,
    double? padding,
    double? icon,
  }) {
    return ResponsiveTokens(
      radius: radius ?? this.radius,
      padding: padding ?? this.padding,
      icon: icon ?? this.icon,
    );
  }

  @override
  ResponsiveTokens lerp(ThemeExtension<ResponsiveTokens>? other, double t) {
    if (other is! ResponsiveTokens) return this;
    return ResponsiveTokens(
      radius: lerpDouble(radius, other.radius, t)!,
      padding: lerpDouble(padding, other.padding, t)!,
      icon: lerpDouble(icon, other.icon, t)!,
    );
  }
}

/// ---------------------------------------------------------------------------
/// R: tiny convenience helper used across the app (and by ResponsiveText).
/// Uses your existing responsive_extensions (rw/rh) so it plugs right in.
/// ---------------------------------------------------------------------------
class R {
  /// Scale font sizes by width (keeps your existing `.rw(context)` behavior).
  static double font(BuildContext context, double px) => px.rw(context);

  /// Scale icons (often same as font).
  static double icon(BuildContext context, double px) => px.rw(context);

  /// Scale radii by width.
  static double radius(BuildContext context, double px) => px.rw(context);

  /// Scale spacing mostly by height (feel free to switch to `.rw` if you prefer).
  static double space(BuildContext context, double px) => px.rh(context);

  /// Quick access to tokens if you’ve attached them to ThemeData.extensions.
  static ResponsiveTokens tokens(BuildContext context) =>
      Theme.of(context).extension<ResponsiveTokens>() ??
      ResponsiveTokens.of(context);
}
