import '../error/app_failure.dart';

/// The outcome of an operation that can fail: [data] or [error], never both.
class Result<T> {
  const Result.success(T this.data) : error = null;

  const Result.failure(AppFailure this.error) : data = null;

  final T? data;
  final AppFailure? error;

  bool get isSuccess => error == null;
  bool get isFailure => error != null;

  /// Runs [body] and wraps whatever it returns or throws.
  static Future<Result<T>> guard<T>(Future<T> Function() body) async {
    try {
      return Result.success(await body());
    } catch (error) {
      return Result.failure(AppFailure.from(error));
    }
  }
}
