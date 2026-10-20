/// Optional chapter facts. Unknown likes stay unknown, never fabricated as zero.
class ChapterMetadata {
  const ChapterMetadata({this.updateTime, this.tencentUpdateTime, this.likesCount, this.likesSource});

  final String? updateTime;
  final String? tencentUpdateTime;
  final int? likesCount;
  final String? likesSource;

  factory ChapterMetadata.fromJson(Map<dynamic, dynamic> json) {
    final raw = json['likesCount'];
    return ChapterMetadata(
      updateTime: _text(json['updateTime']),
      tencentUpdateTime: _text(json['tencentUpdateTime']),
      likesCount: raw is num && raw.isFinite && raw >= 0 &&
          raw <= 9007199254740991 && raw == raw.truncateToDouble()
          ? raw.toInt() : null,
      likesSource: _text(json['likesSource']),
    );
  }

  static String? _text(dynamic value) => value is String && value.trim().isNotEmpty
      ? value.trim() : null;

  static Map<String, ChapterMetadata> parse(dynamic value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        if (entry.value is Map)
          entry.key.toString(): ChapterMetadata.fromJson(entry.value as Map),
    };
  }

  ChapterMetadata merge(ChapterMetadata other) => ChapterMetadata(
    updateTime: other.updateTime ?? updateTime,
    tencentUpdateTime: other.tencentUpdateTime ?? tencentUpdateTime,
    likesCount: other.likesCount ?? likesCount,
    likesSource: other.likesSource ?? likesSource,
  );

  String? get displayDate {
    final date = updateTime;
    if (date == null) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(date);
    if (m == null) return date;
    return '${m[1]!.substring(2)}-${m[2]}-${m[3]}';
  }

  String? get displayLikes {
    final count = likesCount;
    if (count == null) return null;
    if (count < 10000) return '$count';
    final value = (count / 10000).toStringAsFixed(1);
    return '${value.endsWith('.0') ? value.substring(0, value.length - 2) : value}万';
  }

  Map<String, dynamic> toJson({bool includeLikes = true}) => {
    if (updateTime != null) 'updateTime': updateTime,
    if (tencentUpdateTime != null) 'tencentUpdateTime': tencentUpdateTime,
    if (includeLikes && likesCount != null) 'likesCount': likesCount,
    if (includeLikes && likesSource != null) 'likesSource': likesSource,
  };
}
