import 'package:freezed_annotation/freezed_annotation.dart';

part 'tab.freezed.dart';
part 'tab.g.dart';

/// Mirrors the backend Tab WaveObj.
@freezed
class WaveTab with _$WaveTab {
  const factory WaveTab({
    required String oid,
    required int version,
    @Default('') String name,
    @Default([]) List<String> blockIds,
  }) = _WaveTab;

  factory WaveTab.fromJson(Map<String, dynamic> json) =>
      _$WaveTabFromJson(json);
}
