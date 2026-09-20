Future<List<R>> chunkedMap<T, R>(
  List<T> items,
  R Function(T) transform, {
  int chunkSize = 25,
}) async {
  final result = <R>[];
  for (var i = 0; i < items.length; i += chunkSize) {
    final end = (i + chunkSize).clamp(0, items.length);
    for (var j = i; j < end; j++) {
      result.add(transform(items[j]));
    }
    if (end < items.length) {
      await Future<void>.delayed(Duration.zero);
    }
  }
  return result;
}
