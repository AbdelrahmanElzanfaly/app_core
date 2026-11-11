import 'package:app_core/app_core.dart';
import 'package:app_network/app_network.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const converter = AppFailureConverter();
  final request = RequestOptions(path: '/items');

  AppFailure convert(DioExceptionType type, {Object? error}) => converter
      .convert(DioException(requestOptions: request, type: type, error: error));

  AppFailure convertStatus(int status, {Object? body}) => converter.convert(
    DioException.badResponse(
      statusCode: status,
      requestOptions: request,
      response: Response<Object?>(
        requestOptions: request,
        statusCode: status,
        data: body,
      ),
    ),
  );

  group('transport failures', () {
    for (final type in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.transformTimeout,
    ]) {
      test('${type.name} is a timeout', () {
        expect(convert(type).type, FailureType.timeout);
      });
    }

    test('a connection error is no network', () {
      expect(
        convert(DioExceptionType.connectionError).type,
        FailureType.network,
      );
    });

    test('a request the connectivity gate refused is no network', () {
      final failure = converter.convert(
        DioException.connectionError(
          requestOptions: request,
          reason: 'The device has no network connection.',
          error: const NoNetworkException(),
        ),
      );

      expect(failure.type, FailureType.network);
      expect(failure.statusCode, isNull);
    });

    test('an already converted failure keeps its type', () {
      expect(
        convert(
          DioExceptionType.unknown,
          error: const AppFailure(FailureType.unauthorized),
        ).type,
        FailureType.unauthorized,
      );
    });
  });

  group('status mapping is unchanged', () {
    for (final (status, type) in [
      (401, FailureType.unauthorized),
      (403, FailureType.forbidden),
      (404, FailureType.notFound),
      (400, FailureType.badRequest),
      (409, FailureType.badRequest),
      (429, FailureType.badRequest),
      (500, FailureType.server),
      (503, FailureType.server),
    ]) {
      test('$status is ${type.name}', () {
        final failure = convertStatus(status);
        expect(failure.type, type);
        expect(failure.statusCode, status);
      });
    }

    test('reads code and message from a JSON error body', () {
      final failure = convertStatus(
        400,
        body: {'error': 'invalid_grant', 'error_description': 'Expired.'},
      );

      expect(failure.code, 'invalid_grant');
      expect(failure.message, 'Expired.');
    });
  });

  group('isTransient', () {
    for (final type in FailureType.values) {
      final transient = {
        FailureType.network,
        FailureType.timeout,
        FailureType.server,
      }.contains(type);
      test('${type.name}: $transient', () {
        expect(AppFailure(type).isTransient, transient);
      });
    }
  });
}
