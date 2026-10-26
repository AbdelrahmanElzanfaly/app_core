import 'result.dart';

/// One business operation: [P] in, a [Result] of [R] out.
abstract interface class FutureUseCase<P, R> {
  Future<Result<R>> call(P param);
}
