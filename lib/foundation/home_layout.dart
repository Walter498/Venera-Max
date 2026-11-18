import 'package:flutter/material.dart';
import 'package:venera/foundation/appdata.dart';
import 'package:venera/foundation/comic_source/comic_source.dart';

/// Metadata for a single customizable section on the home page.
///
/// The home page header (search bar + sync status) is fixed and not part of
/// this list — only the content sections below it can be reordered or hidden.
class HomeSectionMeta {
  /// Stable identifier persisted in settings. Never change these strings.
  final String id;

  /// Translation key for the section's display name.
  final String titleKey;

  final IconData icon;

  const HomeSectionMeta(this.id, this.titleKey, this.icon);
}

/// The canonical list of customizable home sections, in their default order.
///
/// Adding a new section here (with a fresh, never-reused id) is all that is
/// required for migration: [normalizeHomeLayout] appends any known section
/// missing from a stored/synced config to the end, visible by default.
const List<HomeSectionMeta> kHomeSections = [
  HomeSectionMeta('sourceHome', 'Source Home', Icons.home_outlined),
  // Keep the original compact home order: the source feed is followed by
  // lightweight task/library entries. Reading shelves remain available from
  // their dedicated pages and can still be enabled from Edit Home.
  HomeSectionMeta('comicSource', 'Comic Source', Icons.source_outlined),
  HomeSectionMeta('followUpdates', 'Follow Updates', Icons.dynamic_feed),
  HomeSectionMeta('imageFavorites', 'Image Favorites', Icons.image_outlined),
  HomeSectionMeta('history', 'History', Icons.history),
  HomeSectionMeta('readLater', 'Read Later', Icons.watch_later_outlined),
  HomeSectionMeta('translatedComics', 'Translation Library', Icons.translate),
  HomeSectionMeta('local', 'Local', Icons.local_library_outlined),
  HomeSectionMeta('webdavLibrary', 'WebDAV Library', Icons.cloud_outlined),
  HomeSectionMeta('collections', 'Collections', Icons.library_books_outlined),
];

HomeSectionMeta? homeSectionMetaById(String id) {
  for (var s in kHomeSections) {
    if (s.id == id) return s;
  }
  return null;
}

/// A single entry in the persisted home layout: a section id plus whether it
/// is currently shown.
class HomeSectionConfig {
  final String id;
  final bool visible;

  const HomeSectionConfig(this.id, this.visible);

  Map<String, dynamic> toJson() => {'id': id, 'visible': visible};

  HomeSectionConfig copyWith({bool? visible}) =>
      HomeSectionConfig(id, visible ?? this.visible);
}

/// The default layout restores the compact source-first home. The reading
/// shelves stay available in Edit Home but do not displace the unified source
/// grid on a fresh install or after Reset to Default.
List<HomeSectionConfig> defaultHomeLayout() {
  const visibleByDefault = {
    'sourceHome',
    'comicSource',
    'followUpdates',
    'imageFavorites',
  };
  return [
    for (final s in kHomeSections)
      HomeSectionConfig(s.id, visibleByDefault.contains(s.id)),
  ];
}

/// Reads the raw `homeSections` setting and normalizes it for rendering:
///
/// * entries with unknown ids (e.g. a section removed in a newer build, or
///   corrupt data) are dropped;
/// * any known section missing from the stored config is appended at the end
///   and kept visible for backward-compatible settings migration; a new
///   install with no stored config uses [defaultHomeLayout].
///
/// The result always contains exactly the ids in [kHomeSections], each once.
List<HomeSectionConfig> normalizeHomeLayout() {
  var raw = appdata.settings['homeSections'];
  var result = <HomeSectionConfig>[];
  var seen = <String>{};
  if (raw is List) {
    for (var item in raw) {
      if (item is! Map) continue;
      var id = item['id'];
      if (id is! String || seen.contains(id)) continue;
      if (homeSectionMetaById(id) == null) continue;
      result.add(HomeSectionConfig(id, item['visible'] != false));
      seen.add(id);
    }
  }
  if (raw is! List) {
    return defaultHomeLayout();
  }

  // Builds before the source feed was restored persisted every shelf as
  // visible, or placed sourceHome after the shelf. Treat that exact legacy
  // shape as the old compact default instead of reintroducing a mixed home
  // page after upgrade. Explicitly edited layouts are left untouched.
  final hasSourceHome = result.any((entry) => entry.id == 'sourceHome');
  final isLegacyDefault =
      result.length == kHomeSections.length &&
      result.every((entry) => entry.visible) &&
      (!hasSourceHome || result.first.id != 'sourceHome');
  if (isLegacyDefault) {
    return defaultHomeLayout();
  }

  for (var s in kHomeSections) {
    if (!seen.contains(s.id)) {
      // An existing saved layout is an explicit user/config migration case;
      // preserve the historical append-visible behavior for newly introduced
      // sections. Fresh installs use [defaultHomeLayout] above.
      result.add(HomeSectionConfig(s.id, true));
    }
  }
  return result;
}

/// Persists [layout] back to settings, preserving any unknown ids from the
/// previously stored config by appending them at the end.
///
/// Keeping unknown ids matters for cross-version sync: if this (older) build
/// doesn't recognize a section a newer build added, round-tripping the config
/// through here must not silently drop it. [normalizeHomeLayout] hides unknown
/// ids from rendering, so they stay inert until a build that knows them reads
/// the config again.
void saveHomeLayout(List<HomeSectionConfig> layout) {
  var known = layout.map((e) => e.id).toSet();
  var preserved = <Map<String, dynamic>>[];
  var raw = appdata.settings['homeSections'];
  if (raw is List) {
    for (var item in raw) {
      if (item is! Map) continue;
      var id = item['id'];
      if (id is! String || known.contains(id)) continue;
      if (homeSectionMetaById(id) != null) continue;
      preserved.add({'id': id, 'visible': item['visible'] != false});
    }
  }
  appdata.settings['homeSections'] = [
    ...layout.map((e) => e.toJson()),
    ...preserved,
  ];
  appdata.saveData();
}

// ---------------------------------------------------------------------------
// Image Favorites tabs (the Tags / Authors / Comics switcher inside the home
// page's "Image Favorites" card). Reuses the same config shape & migration
// rules as the home sections above; persisted under `imageFavoritesTabs` and
// synced/exported via the normal settings path.
// ---------------------------------------------------------------------------

const List<HomeSectionMeta> kImageFavoritesTabs = [
  HomeSectionMeta('tags', 'Tags', Icons.tag),
  HomeSectionMeta('authors', 'Authors', Icons.person_outline),
  HomeSectionMeta('comics', 'Comics', Icons.menu_book_outlined),
];

HomeSectionMeta? imageFavoritesTabMetaById(String id) {
  for (var t in kImageFavoritesTabs) {
    if (t.id == id) return t;
  }
  return null;
}

List<HomeSectionConfig> defaultImageFavoritesTabs() =>
    kImageFavoritesTabs.map((t) => HomeSectionConfig(t.id, true)).toList();

/// See [normalizeHomeLayout] — same rules, applied to `imageFavoritesTabs`.
List<HomeSectionConfig> normalizeImageFavoritesTabs() {
  var raw = appdata.settings['imageFavoritesTabs'];
  var result = <HomeSectionConfig>[];
  var seen = <String>{};
  if (raw is List) {
    for (var item in raw) {
      if (item is! Map) continue;
      var id = item['id'];
      if (id is! String || seen.contains(id)) continue;
      if (imageFavoritesTabMetaById(id) == null) continue;
      result.add(HomeSectionConfig(id, item['visible'] != false));
      seen.add(id);
    }
  }
  for (var t in kImageFavoritesTabs) {
    if (!seen.contains(t.id)) {
      result.add(HomeSectionConfig(t.id, true));
    }
  }
  return result;
}

/// See [saveHomeLayout] — same rules, applied to `imageFavoritesTabs`.
void saveImageFavoritesTabs(List<HomeSectionConfig> tabs) {
  var known = tabs.map((e) => e.id).toSet();
  var preserved = <Map<String, dynamic>>[];
  var raw = appdata.settings['imageFavoritesTabs'];
  if (raw is List) {
    for (var item in raw) {
      if (item is! Map) continue;
      var id = item['id'];
      if (id is! String || known.contains(id)) continue;
      if (imageFavoritesTabMetaById(id) != null) continue;
      preserved.add({'id': id, 'visible': item['visible'] != false});
    }
  }
  appdata.settings['imageFavoritesTabs'] = [
    ...tabs.map((e) => e.toJson()),
    ...preserved,
  ];
  appdata.saveData();
}

/// 首页显示的漫画源。空集合代表所有提供探索页的源。
List<String> homeDisplaySourceKeys() {
  final raw = appdata.settings['homeDisplaySources'];
  if (raw is List) {
    return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
  }
  return const [];
}

/// 首页实际可显示的源：未设置时返回全部有探索页的源。
List<String> effectiveHomeDisplaySourceKeys() {
  final configured = homeDisplaySourceKeys();
  if (configured.isNotEmpty) {
    return configured.where((k) => ComicSource.find(k) != null).toList();
  }
  return [
    for (final source in ComicSource.all())
      if (source.explorePages.isNotEmpty) source.key,
  ];
}
