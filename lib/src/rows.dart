import 'dart:collection' show ListMixin;

import 'package:isolate_sqlite/src/internal_helpers.dart';

import 'row.dart';

final class Rows with ListMixin<Row> implements Iterable<Row> {
  final List<List<Object?>> _data;
  final Map<String, int> _columnIndex;

  Rows(List<String> columnNames, this._data)
    : _columnIndex = buildIndex(columnNames);

  /// raw data, as returned by the database
  List<List<Object?>> get data => _data;

  Iterable<String> get columnNames => _columnIndex.keys;

  @override
  Row operator [](int index) => Row.fromIndex(_columnIndex, _data[index]);

  @override
  int get length => _data.length;

  @override
  set length(int newLength) {
    throw UnsupportedError("Can't change rows");
  }

  @override
  void operator []=(int index, Row value) {
    throw UnsupportedError("Can't change rows");
  }
}
