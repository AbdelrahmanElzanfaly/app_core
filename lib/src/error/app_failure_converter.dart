import 'package:dio/dio.dart';
import 'package:app_network/app_network.dart';

import 'app_failure.dart';

/// Converts every Dio failure into an [AppFailure].
///
/// Reads `code` / `message` (and OAuth's `error` / `error_description`) from
/// a JSON error body when there is one.
class AppFailureConverter implements NetworkErrorConverter {
  const AppFailureConverter();

  @override
  AppFailure convert(DioException error) {
    final status = error.response?.statusCode;
    final body = error.response?.data;

    String? code;
    String? message;
    if (body is Map) {
      code = (body['code'] ?? body['error'])?.toString();
      message = (body['message'] ?? body['error_description'])?.toString();
    }

    final type = switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => FailureType.timeout,
      DioExceptionType.connectionError => FailureType.network,
      DioExceptionType.badResponse => switch (status) {
        401 => FailureType.unauthorized,
        403 => FailureType.forbidden,
        404 => FailureType.notFound,
        final s? when s >= 500 => FailureType.server,
        final s? when s >= 400 => FailureType.badRequest,
        _ => FailureType.unknown,
      },
      _ => error.error is AppFailure
          ? (error.error! as AppFailure).type
          : FailureType.network,
    };

    return AppFailure(type, code: code, message: message, statusCode: status);
  }
}
