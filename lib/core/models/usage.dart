import 'package:freezed_annotation/freezed_annotation.dart';

part 'usage.freezed.dart';
part 'usage.g.dart';

@freezed
class QuotaItem with _$QuotaItem {
  const factory QuotaItem({
    required String resource,
    required int used,
    required int limit,
  }) = _QuotaItem;

  factory QuotaItem.fromJson(Map<String, dynamic> json) =>
      _$QuotaItemFromJson(json);
}

extension QuotaItemX on QuotaItem {
  double get fraction => limit > 0 ? (used / limit).clamp(0.0, 1.0) : 0.0;
  bool get isNearLimit => fraction >= 0.8;
  bool get isExhausted => used >= limit;
}

class UsageSummary {
  const UsageSummary({required this.quotas, required this.tier});

  final List<QuotaItem> quotas;
  final String tier;

  bool get isFree => tier == 'free';

  // Parses the flat key→{count, free_limit} map from GET /usage/current.
  static List<QuotaItem> parseQuotas(Map<String, dynamic> data) {
    final items = <QuotaItem>[];
    for (final entry in data.entries) {
      final v = entry.value;
      if (v is Map<String, dynamic>) {
        final used = (v['count'] as num?)?.toInt() ?? 0;
        final limit = (v['free_limit'] as num?)?.toInt() ?? 0;
        items.add(QuotaItem(resource: entry.key, used: used, limit: limit));
      }
    }
    return items;
  }
}
