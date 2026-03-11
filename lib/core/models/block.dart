import 'package:freezed_annotation/freezed_annotation.dart';

part 'block.freezed.dart';
part 'block.g.dart';

/// Mirrors the backend Block WaveObj.
@freezed
class Block with _$Block {
  const factory Block({
    required String oid,
    required int version,
    @Default('') String parentOref,
    @Default({}) Map<String, dynamic> meta,
    @Default([]) List<String> subBlockIds,
  }) = _Block;

  factory Block.fromJson(Map<String, dynamic> json) =>
      _$BlockFromJson(json);
}

/// Convenience extension to extract typed meta values.
extension BlockMeta on Block {
  String get viewType => meta['view'] as String? ?? '';
  String get controller => meta['controller'] as String? ?? '';
  String get connection => meta['connection'] as String? ?? '';
  String get cmd => meta['cmd'] as String? ?? '';
  String get cmdCwd => meta['cmd:cwd'] as String? ?? '';

  bool get isTerminal => viewType == 'term';
  bool get isAgent => viewType == 'agent';
}

/// Runtime status of a block's controller (PTY, agent, etc.).
@freezed
class BlockControllerStatus with _$BlockControllerStatus {
  const factory BlockControllerStatus({
    required String blockId,
    @Default(0) int version,
    @Default('') String shellProcStatus,
    @Default('') String shellProcConnName,
    int? shellProcExitCode,
  }) = _BlockControllerStatus;

  factory BlockControllerStatus.fromJson(Map<String, dynamic> json) =>
      _$BlockControllerStatusFromJson(json);
}
