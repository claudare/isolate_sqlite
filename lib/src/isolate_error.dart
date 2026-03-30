/// Wraps any error for transport through a [SendPort].
///
/// Same isolate group = shared heap, so the original
/// exception passes through without serialization.
class IsolateError {
  final Object _error;
  final String _stackTraceString;

  IsolateError(this._error, StackTrace stackTrace)
    : _stackTraceString = stackTrace.toString();

  /// Throws the original error. Call on the receiving side.
  Never throwError() => Error.throwWithStackTrace(
    _error,
    StackTrace.fromString(_stackTraceString.toString()),
  );
}
