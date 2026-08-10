/// Splits a byte buffer just before any trailing incomplete UTF-8 sequence.
///
/// PTY output arrives in arbitrary WebSocket frames, so a multi-byte character
/// can straddle two frames. Decoding each frame independently turns those into
/// replacement characters; holding the partial tail back until its remaining
/// bytes arrive decodes correctly.
({List<int> complete, List<int> incomplete}) splitTrailingIncompleteUtf8(
  List<int> bytes,
) {
  if (bytes.isEmpty) return (complete: bytes, incomplete: const []);

  // Walk back over continuation bytes (10xxxxxx) to find the last lead byte.
  var i = bytes.length - 1;
  var continuations = 0;
  while (i >= 0 && (bytes[i] & 0xC0) == 0x80) {
    continuations++;
    i--;
    // A sequence is at most 4 bytes, so more than 3 continuations means the
    // data is malformed — let the decoder deal with it.
    if (continuations > 3) return (complete: bytes, incomplete: const []);
  }
  if (i < 0) return (complete: bytes, incomplete: const []);

  final lead = bytes[i];
  final int expected;
  if ((lead & 0x80) == 0x00) {
    expected = 1;
  } else if ((lead & 0xE0) == 0xC0) {
    expected = 2;
  } else if ((lead & 0xF0) == 0xE0) {
    expected = 3;
  } else if ((lead & 0xF8) == 0xF0) {
    expected = 4;
  } else {
    // Not a valid lead byte; nothing useful to hold back.
    return (complete: bytes, incomplete: const []);
  }

  final present = continuations + 1;
  if (present >= expected) return (complete: bytes, incomplete: const []);
  return (complete: bytes.sublist(0, i), incomplete: bytes.sublist(i));
}
