import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

/// What went wrong, in terms a screen can act on.
enum FailureType {
  /// No connection, DNS, TLS — the request never got an answer.
  network,

  /// The server took too long.
  timeout,

  /// 401: the session is missing or no longer valid.
  unauthorized,

  /// 403: signed in, but not allowed.
  forbidden,

  /// 404.
  notFound,

  /// Any other 4xx: the request itself was rejected.
  badRequest,

  /// 5xx.
  server,

  /// Anything not covered above.
  unknown,
}

/// The one error type that crosses layers.
///
/// Repositories return it inside a `Result`; blocs hand it to `handleError`.
class AppFailure extends Equatable implements Exception {
  const AppFailure(this.type, {this.code, this.message, this.statusCode});

  final FailureType type;

  /// A machine-readable code from the server, when it sent one.
  final String? code;

  /// A human-readable message from the server, when it sent one.
  final String? message;

  final int? statusCode;

  /// Whatever was thrown, as an [AppFailure].
  factory AppFailure.from(Object error) => switch (error) {
    AppFailure() => error,
    DioException(error: final AppFailure converted) => converted,
    _ => AppFailure(FailureType.unknown, message: error.toString()),
  };

  @override
  List<Object?> get props => [type, code, message, statusCode];

  @override
  String toString() => 'AppFailure($type, $statusCode, $code, $message)';
}
