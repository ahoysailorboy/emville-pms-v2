// lib/responsive/responsive_grid.dart
import 'package:flutter/widgets.dart';
import 'responsive_extensions.dart';

/// A simple responsive grid that picks column count by breakpoint.
class ResponsiveGrid extends StatelessWidget {
  final IndexedWidgetBuilder itemBuilder;
  final int itemCount;
  final EdgeInsets? padding;
  final double gap;
  final int? phoneColumns;
  final int? tabletColumns;
  final int? desktopColumns;
  final double? childAspectRatio;

  const ResponsiveGrid({
    super.key,
    required this.itemBuilder,
    required this.itemCount,
    this.padding,
    this.gap = 12,
    this.phoneColumns,
    this.tabletColumns,
    this.desktopColumns,
    this.childAspectRatio,
  });

  @override
  Widget build(BuildContext context) {
    final cols = ResponsiveValue<int>(
      fallback: phoneColumns ?? 2,
      md: tabletColumns ?? 3,
      lg: desktopColumns ?? 4,
      xl: (desktopColumns ?? 4) + 1,
    ).of(context);

    return GridView.builder(
      padding: padding ?? EdgeInsets.all(12.rw(context)),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: gap.rw(context),
        crossAxisSpacing: gap.rw(context),
        childAspectRatio: childAspectRatio ?? 1,
      ),
      itemBuilder: itemBuilder,
      itemCount: itemCount,
    );
  }
}
