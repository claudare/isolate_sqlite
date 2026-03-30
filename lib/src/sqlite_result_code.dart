/// Common SQLite result codes relevant to application logic.
///
/// Reference: https://www.sqlite.org/rescode.html
abstract final class SqliteResultCode {
  // ── Primary ────────────────────────────────────────────────────

  static const error = 1;
  static const busy = 5;
  static const locked = 6;
  static const readonly = 8;
  static const full = 13;
  static const constraint = 19;
  static const mismatch = 20;
  static const range = 25;
  static const notadb = 26;

  // ── Extended: busy ─────────────────────────────────────────────

  static const busyRecovery = 261;
  static const busySnapshot = 517;
  static const busyTimeout = 773;

  // ── Extended: constraint ───────────────────────────────────────

  static const constraintCheck = 275;
  static const constraintForeignKey = 787;
  static const constraintNotNull = 1299;
  static const constraintPrimaryKey = 1555;
  static const constraintUnique = 2067;
  static const constraintRowId = 2579;

  /// Extract primary code from any extended code.
  static int primaryOf(int extendedCode) => extendedCode & 0xFF;
}
