import 'result.dart';
import 'service_failure.dart';

/// What every operation that crosses a module boundary returns. It completes
/// with a failure rather than throwing, and no transport exception escapes.
typedef ServiceResult<T> = Future<Result<T, ServiceFailure>>;
