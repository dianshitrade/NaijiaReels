import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// "NaijaReels" wordmark. Always a single line: FittedBox scales it down
/// instead of wrapping (320dp / large text scale safe).
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.fontSize = 32, this.showMark = true});
  final double fontSize;
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final text = Text.rich(
      TextSpan(
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900, letterSpacing: -0.5),
        children: const [
          TextSpan(text: 'Naija', style: TextStyle(color: AppColors.primary)),
          TextSpan(text: 'Reels', style: TextStyle(color: Colors.white)),
        ],
      ),
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      textScaler: TextScaler.noScaling,
    );
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (showMark) ...[BrandMark(size: fontSize * 1.1), SizedBox(width: fontSize * 0.3)],
        text,
      ]),
    );
  }
}

/// Small square green play mark.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 32});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.28),
          gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.greenDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
        ),
        child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: size * 0.75),
      );
}
