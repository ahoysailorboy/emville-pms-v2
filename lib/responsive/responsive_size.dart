// lib/responsive/responsive_size.dart
import 'package:flutter/material.dart';
import 'responsive_extensions.dart';

/// A central place to define and scale your commonly used sizes.
/// Uses `.rw(context)` and `.rh(context)` extensions you already have.
class ResponsiveSize {
  final BuildContext context;

  ResponsiveSize(this.context);

  /// Factory to quickly access: `ResponsiveSize.of(context)`
  factory ResponsiveSize.of(BuildContext context) {
    return ResponsiveSize(context);
  }

  /// Font scaling
  double font(double px) => px.rw(context);

  /// Icon scaling
  double icon(double px) => px.rw(context);

  /// Width scaling
  double w(double px) => px.rw(context);

  /// Height scaling
  double h(double px) => px.rh(context);

  /// Radius scaling
  double radius(double px) => px.rw(context);

  /// Spacing (usually height-based, but can be tuned)
  double space(double px) => px.rh(context);

  /// Predefined tokens (optional, extend as needed)
  double get small => 8.rw(context);
  double get medium => 16.rw(context);
  double get large => 24.rw(context);

  /// 🔹 Static helper for max panel width, e.g. auth/login cards
  static double panelMaxWidth(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    if (w < 480) return 420; // compact phones
    if (w < 600) return 460; // default card width
    if (w < 900) return 560; // medium devices
    return 720; // wide screens
  }
}
