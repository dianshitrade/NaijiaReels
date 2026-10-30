import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reports [child]'s laid-out height after every layout that changes it.
/// Used to keep subtitles strictly above the bottom info area.
class MeasureSize extends SingleChildRenderObjectWidget {
  const MeasureSize({super.key, required this.onHeight, required Widget super.child});
  final ValueChanged<double> onHeight;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMeasure(onHeight);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) =>
      (renderObject as _RenderMeasure).onHeight = onHeight;
}

class _RenderMeasure extends RenderProxyBox {
  _RenderMeasure(this.onHeight);
  ValueChanged<double> onHeight;
  double? _last;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (h == _last) return;
    _last = h;
    WidgetsBinding.instance.addPostFrameCallback((_) => onHeight(h));
  }
}

/// Subtitle bottom offset (from the screen bottom) that keeps the cue's bottom
/// edge [gap] px above an info area anchored [infoBottom] px from the bottom.
double subtitleBottomAbove({required double infoBottom, required double infoHeight, double gap = 12, double min = 0}) {
  final v = infoBottom + infoHeight + gap;
  return v < min ? min : v;
}
