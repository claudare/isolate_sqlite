import 'internal_helpers.dart';

class Row {
  final Map<String, int> _columnIndex;
  final List<Object?> _values;

  /// Construct from an existing index map.
  const Row.fromIndex(Map<String, int> columnIndex, this._values)
    : _columnIndex = columnIndex,
      assert(columnIndex.length == _values.length);

  /// Construct from a list of column names and values.
  Row(List<String> columnNames, this._values)
    : _columnIndex = buildIndex(columnNames),
      assert(columnNames.length == _values.length);

  List<Object?> get values => _values;

  Iterable<String> get columnNames => _columnIndex.keys;

  /// Type-safe access by column name.
  /// Mapping with sqlite is the following:
  /// TEXT -> String
  /// INTEGER -> int
  /// REAL -> double
  /// BLOB -> Uint8List
  /// NULL -> null
  ///
  /// Nullability of [T] is respected:
  /// - `row.field<String>('x')`  — throws if database returns null
  /// - `row.field<String?>('x')` — returns null if null
  ///
  /// Usage examples:
  /// ```dart
  /// final name = row.field<String>('name'); // String
  /// final bytes = row.field<Uint8List?>('bytes'); // Uint8List?
  /// final int age = row.field('age')
  /// ```
  ///
  /// Do not cast the result, because descriptive errors will not be thrown:
  /// ```dart
  /// final id = row.field('id') as String;
  /// ```
  T field<T>(String name) {
    final idx = _columnIndex[name];
    if (idx == null) throw ArgumentError('Unknown field name: $name');
    return _cast<T>(_values[idx], 'Field "$name"');
  }

  /// Type-safe access by column index.
  T fieldAt<T>(int index) {
    return _cast<T>(_values[index], 'Field at index $index');
  }

  /// Raw index access. Returns the underlying [Object?] without casting.
  Object? operator [](int index) {
    return _values[index];
  }

  static T _cast<T>(Object? value, String fieldDesc) {
    if (value is T) return value;
    // value is not T — could be a null into a non-nullable type, or a type mismatch
    if (value == null) {
      throw StateError('$fieldDesc is null but expected non-nullable $T');
    }
    throw StateError('$fieldDesc is ${value.runtimeType}, expected $T');
  }
}
