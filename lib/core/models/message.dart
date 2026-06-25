import 'package:freezed_annotation/freezed_annotation.dart';

part 'message.freezed.dart';
part 'message.g.dart';

@freezed
class Message with _$Message {
  const factory Message({
    required String id,
    @JsonKey(name: 'from') required String fromAgent,
    @JsonKey(name: 'to', defaultValue: '') @Default('') String toAgent,
    required String message,
    @Default('normal') String priority,
    required String timestamp,
    @Default(false) bool read,
  }) = _Message;

  factory Message.fromJson(Map<String, dynamic> json) => _$MessageFromJson(json);
}

extension MessageX on Message {
  DateTime get time {
    try {
      return DateTime.parse(timestamp);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }
}
