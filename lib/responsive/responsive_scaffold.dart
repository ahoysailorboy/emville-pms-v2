// lib/responsive/responsive_scaffold.dart
import 'package:flutter/material.dart';
import 'responsive_extensions.dart';

/// A Scaffold that automatically chooses drawer layout & paddings.
class ResponsiveScaffold extends StatelessWidget {
  final PreferredSizeWidget? appBar;
  final Widget body;
  final Widget? drawer;
  final Widget? endDrawer;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final Color? backgroundColor;
  final EdgeInsets? bodyPadding;

  const ResponsiveScaffold({
    super.key,
    this.appBar,
    required this.body,
    this.drawer,
    this.endDrawer,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.backgroundColor,
    this.bodyPadding,
  });

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: bodyPadding ??
          EdgeInsets.symmetric(
            horizontal: ResponsiveValue<double>(
              fallback: 12.rw(context),
              md: 16.rw(context),
              lg: 24.rw(context),
              xl: 32.rw(context),
            ).of(context),
            vertical: 12.rw(context),
          ),
      child: body,
    );

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: appBar,
      drawer: drawer == null
          ? null
          : SizedBox(width: context.drawerWidth, child: drawer),
      endDrawer: endDrawer == null
          ? null
          : SizedBox(width: context.drawerWidth, child: endDrawer),
      body: content,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
    );
  }
}
