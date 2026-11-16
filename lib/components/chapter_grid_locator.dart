import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Reveals a slot in a lazy sliver grid after expanding/replacing its section.
/// A post-frame callback alone neither mounts an offscreen SliverLayoutBuilder
/// nor requests the next frame. Bootstrap at the section, then correct against
/// the *new* grid geometry/scroll extents until positioning has settled.
Future<bool> revealChapterGrid({
  required GlobalKey gridKey,
  required GlobalKey sectionKey,
  required ScrollController controller,
  required int slot,
  required double topInset,
  required bool Function() isActive,
}) async {
  var stableFrames = 0;
  for (var attempt = 0; attempt < 12 && isActive(); attempt++) {
    final binding = WidgetsBinding.instance;
    binding.ensureVisualUpdate();
    await binding.endOfFrame;
    if (!isActive() || !controller.hasClients) return false;
    final position = controller.position;
    if (!position.hasContentDimensions) continue;
    final render = gridKey.currentContext?.findRenderObject();
    if (render is! RenderSliverGrid ||
        !render.attached || render.geometry == null) {
      final section = sectionKey.currentContext?.findRenderObject();
      if (section is RenderSliver && section.attached &&
          section.geometry != null) {
        final viewport = RenderAbstractViewport.maybeOf(section);
        if (viewport != null) {
          final offset = viewport.getOffsetToReveal(section, 0).offset - topInset;
          controller.jumpTo(offset.clamp(position.minScrollExtent,
              position.maxScrollExtent).toDouble());
        }
      }
      stableFrames = 0;
      continue;
    }
    final viewport = RenderAbstractViewport.maybeOf(render);
    if (viewport == null) continue;
    final layout = render.gridDelegate.getLayout(render.constraints);
    final cell = layout.getGeometryForChildIndex(slot);
    // Once mounted, use the real child as the final authority (nested sliver
    // groups/padding can adjust paint offsets during the first jump).
    RenderBox? targetChild;
    for (var child = render.firstChild; child != null;
        child = render.childAfter(child)) {
      final data = child.parentData as SliverMultiBoxAdaptorParentData;
      if (data.index == slot) {
        targetChild = child;
        break;
      }
    }
    final offset = targetChild != null && targetChild.hasSize
        ? viewport.getOffsetToReveal(targetChild, 0).offset - topInset
        : viewport.getOffsetToReveal(render, 0).offset +
            cell.scrollOffset - topInset;
    if (!offset.isFinite) return false;
    final target = offset.clamp(position.minScrollExtent,
        position.maxScrollExtent).toDouble();
    if (targetChild != null && (position.pixels - target).abs() <= 1) {
      if (++stableFrames >= 2) return true;
    } else {
      stableFrames = 0;
      controller.jumpTo(target);
    }
  }
  return false;
}
