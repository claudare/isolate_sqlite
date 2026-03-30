import 'sqlite_result_code.dart';

// TODO: use SqliteException instead
class IsolateSqliteException implements Exception {
  final String message;
  final int? sqliteResultCode;
  final String? explanation;

  IsolateSqliteException(
    this.message, {
    this.sqliteResultCode,
    this.explanation,
  });

  /// Primary code (lower 8 bits of the extended code).
  int? get primaryCode => sqliteResultCode != null
      ? SqliteResultCode.primaryOf(sqliteResultCode!)
      : null;

  bool get isBusy => primaryCode == SqliteResultCode.busy;
  bool get isLocked => primaryCode == SqliteResultCode.locked;
  bool get isReadonly => primaryCode == SqliteResultCode.readonly;
  bool get isConstraint => primaryCode == SqliteResultCode.constraint;

  bool get isUniqueViolation =>
      sqliteResultCode == SqliteResultCode.constraintUnique;
  bool get isPrimaryKeyViolation =>
      sqliteResultCode == SqliteResultCode.constraintPrimaryKey;
  bool get isForeignKeyViolation =>
      sqliteResultCode == SqliteResultCode.constraintForeignKey;
  bool get isNotNullViolation =>
      sqliteResultCode == SqliteResultCode.constraintNotNull;
  bool get isCheckViolation =>
      sqliteResultCode == SqliteResultCode.constraintCheck;

  @override
  String toString() =>
      'IsolateSqliteException: $message'
      '${sqliteResultCode != null ? ' (code: $sqliteResultCode)' : ''}'
      '${explanation != null ? '\n  $explanation' : ''}';
}
