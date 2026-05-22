import 'dart:collection' show ListMixin;

class Row {
  final List<Object?> _values;
  final Map<String, int> _index;

  // helper to create a name to index map from a list of column names
  static Map<String, int> calculateIndex(List<String> columnNames) {
    final map = <String, int>{};
    for (int i = 0; i < columnNames.length; i++) {
      assert(
        !map.containsKey(columnNames[i]),
        'duplicate keys are not allowed',
      );
      map[columnNames[i]] = i;
    }
    return map;
  }

  /// Construct from an existing name → index map.
  const Row(Map<String, int> nameToIndex, this._values)
    : _index = nameToIndex,
      assert(nameToIndex.length == _values.length);

  Iterable<String> get columnNames => _index.keys;

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
  T field<T>(String name) {
    final idx = _index[name];
    if (idx == null) throw ArgumentError('Unknown field name: $name');
    return _cast<T>(_values[idx], 'Field "$name"');
  }

  /// Raw index access. Returns the underlying [Object?] without casting.
  Object? operator [](int index) {
    if (index < 0 || index >= _values.length) {
      throw RangeError.index(index, _values, 'index', null, _values.length);
    }
    return _values[index];
  }

  /// Type-safe access by column index.
  T getAt<T>(int index) {
    if (index < 0 || index >= _values.length) {
      throw RangeError.index(index, _values, 'index', null, _values.length);
    }
    return _cast<T>(_values[index], 'Field at index $index');
  }
}

T _cast<T>(Object? value, String fieldDesc) {
  if (value is T) return value;
  // value is not T — could be a null into a non-nullable type, or a type mismatch
  if (value == null) {
    throw StateError('$fieldDesc is null but expected non-nullable $T');
  }
  throw StateError('$fieldDesc is ${value.runtimeType}, expected $T');
}

final class _RowsIterator implements Iterator<Row> {
  final Rows result;
  int index = -1;

  _RowsIterator(this.result);

  @override
  Row get current => Row(result._nameToIndex, result.rows[index]);

  @override
  bool moveNext() {
    index++;
    return index < result.rows.length;
  }
}

final class Rows with ListMixin<Row> implements Iterable<Row> {
  /// The raw row data.
  final List<List<Object?>> rows;
  late final Map<String, int> _nameToIndex;

  Rows(List<String> columnNames, this.rows) {
    _nameToIndex = Row.calculateIndex(columnNames);
  }

  Iterable<String> get columnNames => _nameToIndex.keys;

  @override
  Iterator<Row> get iterator => _RowsIterator(this);

  @override
  Row operator [](int index) => Row(_nameToIndex, rows[index]);

  @override
  int get length => rows.length;

  @override
  set length(int newLength) {
    throw UnsupportedError("Can't change rows");
  }

  @override
  void operator []=(int index, Row value) {
    throw UnsupportedError("Can't change rows");
  }
}

void testing() {
  {
    final row = Row(Row.calculateIndex(['name', 'age', 'nickname']), [
      'John',
      30,
      null,
    ]);

    final name = row.field<String>('name'); // String
    final age = row.field<int>('age'); // int
    final nickname = row.field<String?>('nickname'); // String?

    final int age2 = row.field('age'); // int

    final int age3 = row.getAt(1);

    print(
      'name: $name, age: $age, age2: $age2, age3: $age3, nickname: $nickname',
    );
  }

  {
    final rows = Rows(
      ['name', 'age', 'nickname'],
      [
        ['John', 30, null],
        ['Jane', 25, 'jane_doe'],
      ],
    );

    final direct = rows[0].field<String>('name'); // String

    for (final row in rows) {
      final name = row.field('name') as String;
      final age = row.field<int>('age');
      final nickname = row.field<String?>('nickname');

      print('name: $name, age: $age, nickname: $nickname');
    }
    // print('name: $name, age: $age, age2: $age2, nickname: $nickname');
  }
}
