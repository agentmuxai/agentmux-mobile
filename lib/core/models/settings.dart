import 'package:freezed_annotation/freezed_annotation.dart';

part 'settings.freezed.dart';
part 'settings.g.dart';

/// Subset of backend SettingsType relevant to mobile.
@freezed
class AppSettings with _$AppSettings {
  const factory AppSettings({
    // Terminal
    @Default(14.0) double termFontSize,
    @Default('') String termFontFamily,
    @Default('') String termTheme,
    @Default(5000) int termScrollback,
    @Default(true) bool termCopyOnSelect,

    // AI
    @Default('') String aiPreset,
    @Default('') String aiModel,

    // Telemetry
    @Default(false) bool telemetryEnabled,
  }) = _AppSettings;

  factory AppSettings.fromJson(Map<String, dynamic> json) =>
      _$AppSettingsFromJson(json);

  /// Parse from the flat "key:value" settings map used by the backend.
  factory AppSettings.fromSettingsMap(Map<String, dynamic> map) {
    return AppSettings(
      termFontSize: (map['term:fontsize'] as num?)?.toDouble() ?? 14.0,
      termFontFamily: map['term:fontfamily'] as String? ?? '',
      termTheme: map['term:theme'] as String? ?? '',
      termScrollback: map['term:scrollback'] as int? ?? 5000,
      termCopyOnSelect: map['term:copyonselect'] as bool? ?? true,
      aiPreset: map['ai:preset'] as String? ?? '',
      aiModel: map['ai:model'] as String? ?? '',
      telemetryEnabled: map['telemetry:enabled'] as bool? ?? false,
    );
  }
}
