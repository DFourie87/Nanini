import 'dart:typed_data';

/// A JPEG's "this way up" (EXIF orientation): which way the phone shows the
/// photo. A landscape sheet photographed with the phone upright is sideways
/// in the photo -- the text reader only reads text the right way up, so the
/// photo is also tried turned (by changing this note, not the picture).

/// EXIF orientation codes for the photo turned clockwise 0, 90, 180, 270 degrees.
const _byTurn = {0: 1, 90: 6, 180: 3, 270: 8};
const _turnOf = {1: 0, 6: 90, 3: 180, 8: 270};

/// The orientation code in [jpeg] (1: as stored), or null when it has none.
int? jpegOrientation(Uint8List jpeg) => _find(jpeg)?.value;

/// [jpeg] turned a further [degrees] clockwise (90, 180 or 270) when shown:
/// its orientation note changed, or added when it has none. Null if it isn't
/// a JPEG this can change (then the photo is only read as it is).
Uint8List? jpegTurned(Uint8List jpeg, int degrees) {
  if (jpeg.length < 4 || jpeg[0] != 0xFF || jpeg[1] != 0xD8) return null;
  final found = _find(jpeg);
  final now = _turnOf[found?.value ?? 1];
  if (now == null) return null; // a mirrored photo: left as it is
  final code = _byTurn[(now + degrees) % 360]!;
  if (found != null) {
    final out = Uint8List.fromList(jpeg);
    if (found.littleEndian) {
      out[found.at] = code;
      out[found.at + 1] = 0;
    } else {
      out[found.at] = 0;
      out[found.at + 1] = code;
    }
    return out;
  }
  // No orientation note: a small EXIF block with one, right after the start.
  final app1 = <int>[
    0xFF, 0xE1, 0x00, 0x22, // APP1, 34 bytes
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
    0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08, // big-endian TIFF, IFD0 at 8
    0x00, 0x01, // one entry
    0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, 0x00, code, 0x00, 0x00, // orientation
    0x00, 0x00, 0x00, 0x00, // no next IFD
  ];
  return Uint8List.fromList([jpeg[0], jpeg[1], ...app1, ...jpeg.sublist(2)]);
}

/// Where the orientation value is: (its first byte, byte order, value).
({int at, bool littleEndian, int value})? _find(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 4 <= b.length && b[i] == 0xFF) {
    final marker = b[i + 1];
    if (marker == 0xDA || marker == 0xD9) break; // the picture itself: no EXIF after it
    final len = (b[i + 2] << 8) | b[i + 3];
    if (len < 2) break;
    final start = i + 4, end = i + 2 + len;
    if (end > b.length) break;
    if (marker == 0xE1 && end - start > 14 && b[start] == 0x45 && b[start + 1] == 0x78 && b[start + 2] == 0x69 && b[start + 3] == 0x66) {
      final t = start + 6; // the TIFF header
      final little = b[t] == 0x49;
      int u16(int o) => little ? b[o] | (b[o + 1] << 8) : (b[o] << 8) | b[o + 1];
      int u32(int o) => little ? b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24) : (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
      final ifd = t + u32(t + 4);
      if (ifd + 2 > end) return null;
      final n = u16(ifd);
      for (var e = 0; e < n; e++) {
        final at = ifd + 2 + e * 12;
        if (at + 12 > end) break;
        if (u16(at) == 0x0112) return (at: at + 8, littleEndian: little, value: u16(at + 8));
      }
      return null;
    }
    i = end;
  }
  return null;
}
