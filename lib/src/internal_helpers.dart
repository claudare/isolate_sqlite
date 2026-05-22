// helper to create a name to index map from a list of column names
Map<String, int> buildIndex(List<String> columnNames) {
  final map = <String, int>{};
  for (int i = 0; i < columnNames.length; i++) {
    assert(!map.containsKey(columnNames[i]), 'duplicate keys are not allowed');
    map[columnNames[i]] = i;
  }
  return map;
}
