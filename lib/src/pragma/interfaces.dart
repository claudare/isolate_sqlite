//
abstract interface class QueryOrChange<T> {
  T query();
  void change(T value);
}

abstract interface class QuerySetOrClear<T> {
  T query();
  void set(T value);
  void clear();
}
