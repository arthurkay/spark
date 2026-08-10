import 'dart:convert';
import 'dart:typed_data';

/// Memoized decoding of `data:` URIs.
///
/// Decoding inside `build` is doubly wasteful: the base64 work repeats on every
/// rebuild, and — because `MemoryImage` compares its byte list by *reference* —
/// a freshly allocated list is a brand new image-cache key every time, so the
/// image is fully re-decoded too. Returning the same [Uint8List] instance for a
/// given URI makes the image cache work as intended.
abstract final class DataUriCache {
  static const _maxEntries = 24;

  static final _bytes = <String, Uint8List?>{};
  static final _text = <String, String?>{};

  /// Decoded bytes for a base64 `data:` URI, or null if it can't be decoded.
  static Uint8List? bytesOf(String url) {
    if (_bytes.containsKey(url)) return _bytes[url];
    Uint8List? decoded;
    try {
      final comma = url.indexOf(',');
      if (comma != -1) decoded = base64Decode(url.substring(comma + 1));
    } catch (_) {
      decoded = null;
    }
    _put(_bytes, url, decoded);
    return decoded;
  }

  /// UTF-8 text of a base64 `data:` URI — used for inline SVG markup.
  static String? textOf(String url) {
    if (_text.containsKey(url)) return _text[url];
    String? decoded;
    final bytes = bytesOf(url);
    if (bytes != null) {
      try {
        decoded = utf8.decode(bytes);
      } catch (_) {
        decoded = null;
      }
    }
    _put(_text, url, decoded);
    return decoded;
  }

  static void _put<T>(Map<String, T> map, String key, T value) {
    if (map.length >= _maxEntries) map.remove(map.keys.first);
    map[key] = value;
  }
}

/// Physical-pixel decode width for an image displayed at [logicalWidth].
///
/// Without this images decode at full source resolution — a 4000px screenshot
/// costs ~48MB of decoded ARGB to draw 300px wide.
int decodeWidthFor(double logicalWidth, double devicePixelRatio) {
  return (logicalWidth * devicePixelRatio).round();
}
