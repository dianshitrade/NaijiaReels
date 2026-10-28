import 'package:flutter/material.dart';

import '../../app/theme.dart';

class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.fontSize = 32});
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800),
        children: const [
          TextSpan(text: 'Naija', style: TextStyle(color: AppColors.primary)),
          TextSpan(text: 'Reels', style: TextStyle(color: AppColors.gold)),
        ],
      ),
    );
  }
}
