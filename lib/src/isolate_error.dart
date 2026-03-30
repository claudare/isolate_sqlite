/// Wraps any error for transport through a [SendPort].
///
/// Same isolate group = shared heap, so the original
/// exception passes through without serialization.
class IsolateError {
  final Object _error;

  const IsolateError(this._error);

  /// Throws the original error. Call on the receiving side.
  Never throwError() => throw _error;
}
