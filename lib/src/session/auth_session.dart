import 'package:equatable/equatable.dart';

/// The tokens a signed-in user holds.
class AuthSession extends Equatable {
  const AuthSession({
    required this.accessToken,
    this.refreshToken,
    this.expiresAt,
  });

  final String accessToken;
  final String? refreshToken;

  /// When [accessToken] stops being accepted, if the server said.
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  Map<String, String> toJson() => {
    'accessToken': accessToken,
    if (refreshToken != null) 'refreshToken': refreshToken!,
    if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
  };

  static AuthSession? fromJson(Map<String, String?> json) {
    final accessToken = json['accessToken'];
    if (accessToken == null || accessToken.isEmpty) return null;
    final expiresAt = json['expiresAt'];
    return AuthSession(
      accessToken: accessToken,
      refreshToken: json['refreshToken'],
      expiresAt: expiresAt == null ? null : DateTime.tryParse(expiresAt),
    );
  }

  @override
  List<Object?> get props => [accessToken, refreshToken, expiresAt];
}
