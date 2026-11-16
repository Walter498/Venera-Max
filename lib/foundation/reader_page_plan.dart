/// Maps a displayed slot to the ORIGINAL one-based page, even in RTL spreads.
int readerImagePageOrdinal(int startIndex, int pageCount, int slot,
    {required bool reversed}) {
  assert(startIndex >= 0 && pageCount > 0 && slot >= 0 && slot < pageCount);
  return reversed ? startIndex + pageCount - slot : startIndex + slot + 1;
}

/// Current page first, then later pages in order, then prior pages.
/// Other chapters cannot displace the current chapter's ready tasks.
int readerTranslationPriority(int page, int currentPage,
    {required bool sameChapter}) {
  if (!sameChapter) return 1000000 + page;
  final delta = page - currentPage;
  return delta >= 0 ? delta : 100000 - delta;
}
