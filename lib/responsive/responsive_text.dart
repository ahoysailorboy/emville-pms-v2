// lib/responsive/responsive_text.dart
import 'package:flutter/material.dart';
import 'responsive_theme.dart'; // so you can reuse R.font etc.

class ResponsiveText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final double? fontSize;

  const ResponsiveText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.fontSize,
  });

  @override
  Widget build(BuildContext context) {
    final scaledStyle = (style ?? const TextStyle()).copyWith(
      fontSize: fontSize != null
          ? R.font(context, fontSize!) // scales font
          : (style?.fontSize != null
              ? R.font(context, style!.fontSize!)
              : null),
    );

    return Text(
      data,
      style: scaledStyle,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
