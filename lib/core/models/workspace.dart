import 'package:freezed_annotation/freezed_annotation.dart';

part 'workspace.freezed.dart';
part 'workspace.g.dart';

/// Mirrors the backend Workspace WaveObj.
@freezed
class Workspace with _$Workspace {
  const factory Workspace({
    required String oid,
    required int version,
    @Default('') String name,
    @Default('') String icon,
    @Default('') String color,
    @Default([]) List<String> tabIds,
    @Default([]) List<String> pinnedTabIds,
    @Default('') String activeTabId,
  }) = _Workspace;

  factory Workspace.fromJson(Map<String, dynamic> json) =>
      _$WorkspaceFromJson(json);
}

/// Workspace list entry returned by ListWorkspaces RPC.
@freezed
class WorkspaceListEntry with _$WorkspaceListEntry {
  const factory WorkspaceListEntry({
    required String workspaceId,
    required String name,
    @Default('') String icon,
    @Default('') String color,
    @Default(0) int tabCount,
  }) = _WorkspaceListEntry;

  factory WorkspaceListEntry.fromJson(Map<String, dynamic> json) =>
      _$WorkspaceListEntryFromJson(json);
}
