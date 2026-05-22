import 'package:isolate_sqlite/isolate_sqlite.dart' show Database;

import 'execute_result.dart';
import 'row.dart';
import 'rows.dart';

/// TODO: docs on this
class SyncContext {
  final Database _db;
  const SyncContext(this._db);

  Database get db => _db;

  Rows query(String sql, [List<Object?> params = const []]) {
    final resultSet = _db.select(sql, params);
    return Rows(resultSet.columnNames, resultSet.rows);
  }

  Row? queryRow(String sql, [List<Object?> params = const []]) {
    final rows = query(sql, params);

    if (rows.length > 1) {
      throw StateError('More than one row returned for queryRow');
    }

    return rows.isEmpty ? null : rows[0];
  }

  T queryValue<T>(String sql, [List<Object?> params = const []]) {
    final rows = query(sql, params);
    if (rows.length > 1) {
      throw StateError('More than one row returned for queryValue');
    }

    if (rows.isEmpty) {
      if (null is T) return null as T;
      throw StateError('No rows returned but expected non-nullable $T');
    }
    return rows[0].fieldAt<T>(0);
  }

  ExecuteResult execute(String sql, [List<Object?> params = const []]) {
    _db.execute(sql, params);
    final rowId = _db.lastInsertRowId;
    final modified = _db.updatedRows;
    return ExecuteResult(rowId, modified);
  }
}
