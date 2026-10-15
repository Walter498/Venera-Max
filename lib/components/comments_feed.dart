import 'package:flutter/material.dart';
import 'package:venera/foundation/comments_controller.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';
import 'comment_sort_selector.dart';
export 'comment_sort_selector.dart';
export 'comment_context_stats.dart';

class CommentsFeed extends StatelessWidget {
  const CommentsFeed({super.key, required this.controller, required this.itemBuilder,
    this.parent, this.sorts = const [], this.totalLabel = '评论', this.onSortSelected});
  final CommentsController controller;
  final Widget Function(Comment) itemBuilder;
  final Widget? parent;
  final List<String> sorts;
  final String totalLabel;
  final ValueChanged<String>? onSortSelected;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: controller,
    builder: (context, _) => Column(children: [
      if (sorts.length > 1 && parent == null) Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(alignment: Alignment.centerLeft, child: CommentSortSelector(
          sorts: sorts, value: controller.sort,
          onSelected: onSortSelected ?? (sort) { controller.refresh(nextSort: sort); }))),
      if (controller.total != null) Align(alignment: Alignment.centerLeft,
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('$totalLabel ${controller.total}'))),
      Expanded(child: controller.loading ? const Center(child: CircularProgressIndicator()) :
        controller.error != null ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(controller.error!, textAlign: TextAlign.center),
          TextButton(onPressed: controller.refresh, child: const Text('重试')),
        ])) : RefreshIndicator(onRefresh: controller.refresh,
          child: NotificationListener<ScrollNotification>(onNotification: (notification) {
            if (notification is ScrollUpdateNotification && notification.metrics.extentAfter < 180 &&
                controller.pageError == null) {
              controller.loadMore();
            }
            return false;
          }, child: ListView.builder(physics: const AlwaysScrollableScrollPhysics(),
            itemCount: controller.comments.length + 2,
            itemBuilder: (context,index) {
              if (index == 0) return parent ?? const SizedBox.shrink();
              if (index <= controller.comments.length) return itemBuilder(controller.comments[index-1]);
              if (controller.pageError != null) {
                return Padding(padding: const EdgeInsets.all(16),
                  child: Column(children: [Text(controller.pageError!),
                    TextButton(onPressed: controller.loadMore, child: const Text('重试下一页'))]));
              }
              if (controller.loadingMore) {
                return const Padding(padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()));
              }
              if (controller.hasMore) {
                return TextButton(onPressed: controller.loadMore,
                  child: const Text('加载更多评论'));
              }
              if (controller.comments.isEmpty) {
                return const Padding(padding: EdgeInsets.all(24),
                  child: Center(child: Text('暂无评论')));
              }
              return const SizedBox(height: 24);
            })))),
    ]));
}
