import 'package:flutter/material.dart';
import 'package:venera/pages/favorites/favorites_page.dart';
import 'package:venera/pages/favorites/shelf_page.dart';
import 'package:venera/utils/translations.dart';

/// 兼容层：同时保留 Venera 3.0 新版收藏页和我们的书架/足迹/网络收藏页。
/// 两套页面使用同一份本地数据，不清理、不迁移、不覆盖用户配置。
class FavoritesHubPage extends StatelessWidget {
  const FavoritesHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Material(
        child: Column(
          children: [
            SizedBox(
              height: 46,
              child: TabBar(
                tabs: [
                  Tab(text: 'Favorites'.tl),
                  const Tab(text: '我们的书架'),
                ],
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [FavoritesPage(), ShelfPage()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
