import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'brand_logo.dart';

/// 9:16 rounded cover. Falls back to a branded gradient with the title.
class CoverImage extends StatelessWidget {
  const CoverImage(this.url,
      {super.key, this.title = '', this.radius = 12, this.showFallbackTitle = true});
  final String url;
  final String title;
  final double radius;
  /// Set false when the parent already overlays the title (e.g. DramaCard).
  final bool showFallbackTitle;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 9 / 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: url.isEmpty
            ? CoverFallback(title: title, showTitle: showFallbackTitle)
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(color: AppColors.surfaceHigh),
                errorWidget: (_, __, ___) => CoverFallback(title: title, showTitle: showFallbackTitle),
              ),
      ),
    );
  }
}

class CoverFallback extends StatelessWidget {
  const CoverFallback({super.key, this.title = '', this.showTitle = true});
  final String title;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final hue = (title.hashCode % 60).abs().toDouble();
    final c1 = HSLColor.fromAHSL(1, 140 + hue, 0.65, 0.22).toColor();
    return Container(
      key: const Key('coverFallback'),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c1, const Color(0xFF0B0F0D)],
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Opacity(opacity: 0.9, child: BrandMark(size: 22)),
        const Spacer(),
        if (!showTitle)
          const Center(child: Opacity(opacity: 0.35, child: BrandMark(size: 48))),
        if (!showTitle) const Spacer(),
        if (showTitle && title.isNotEmpty)
          Text(title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 15, height: 1.15, color: Colors.white)),
        if (showTitle) ...[
          const SizedBox(height: 4),
          const SizedBox(height: 14, child: BrandLogo(fontSize: 11, showMark: false)),
        ],
      ]),
    );
  }
}
