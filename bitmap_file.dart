import 'dart:convert';
import 'dart:typed_data';

class BitmapFile {
  final BitmapFileHeader header;
  final BitmapInfo info;
  final List<int> pixels;

  const BitmapFile._(this.header, this.info, this.pixels);

  factory BitmapFile.fromBuffer(ByteBuffer buffer) {
    final header = BitmapFileHeader.fromBytes(
      buffer.asByteData(0, BitmapFileHeader.structureSize),
    );
    final info = BitmapInfo.fromBytes(buffer.asByteData(
      BitmapFileHeader.structureSize,
      header.offBits,
    ));
    final pixels = _parsePixels(buffer, header, info);

    return BitmapFile._(header, info, pixels);
  }

  static List<int> _parsePixels(
    ByteBuffer buffer,
    BitmapFileHeader header,
    BitmapInfo info,
  ) {
    switch (info.header.bitCount) {
      case 0:
        return [];
      case 1:
        return buffer
            .asUint8List()
            .skip(header.offBits)
            .expand((element) => [
                  element & 1 << 7 == 0 ? 0 : 1,
                  element & 1 << 6 == 0 ? 0 : 1,
                  element & 1 << 5 == 0 ? 0 : 1,
                  element & 1 << 4 == 0 ? 0 : 1,
                  element & 1 << 3 == 0 ? 0 : 1,
                  element & 1 << 2 == 0 ? 0 : 1,
                  element & 1 << 1 == 0 ? 0 : 1,
                  element & 1 << 0 == 0 ? 0 : 1,
                ])
            .toList();
      case 4:
        return buffer
            .asUint8List()
            .skip(header.offBits)
            .expand((element) => [
                  element & (1 << 7 | 1 << 6 | 1 << 5 | 1 << 4),
                  element & (1 << 3 | 1 << 2 | 1 << 1 | 1 << 0),
                ])
            .toList();
      case 8:
        return buffer.asUint8List().skip(header.offBits).toList();
      case 16:
        final values = buffer.asUint16List().skip(header.offBits ~/ 2);
        return info.header.compression == BICompression.bitFields
            ? values
                .map((element) =>
                    (element & info.blueMask) |
                    (element & info.greenMask) |
                    (element & info.redMask))
                .toList()
            : values
                .map((element) =>
                    (element &
                        (1 << 14 | 1 << 13 | 1 << 12 | 1 << 11 | 1 << 10)) |
                    (element & (1 << 9 | 1 << 8 | 1 << 7 | 1 << 6 | 1 << 5)) |
                    (element & (1 << 4 | 1 << 3 | 1 << 2 | 1 << 1 | 1 << 0)))
                .toList();
      case 24:
        return buffer
            .asUint8List()
            .skip(header.offBits)
            .fold<List<List<int>>>(
                [[]],
                (subList, value) => subList.last.length < 3
                    ? (subList..last.add(value))
                    : (subList..add([value])))
            .map((e) => e[0] << 16 | e[1] << 8 | e[2])
            .toList();
      case 32:
        final values = buffer.asUint32List().skip(header.offBits ~/ 4);
        return info.header.compression == BICompression.bitFields
            ? values
                .map((element) =>
                    (element & info.blueMask) |
                    (element & info.greenMask) |
                    (element & info.redMask))
                .toList()
            : values.toList();
      default:
        throw Exception('Unsupported bit count (${info.header.bitCount}).');
    }
  }
}

class BitmapFileHeader {
  static const int structureSize = 14;
  final String type;
  final int size;
  final int reserved1;
  final int reserved2;
  final int offBits;

  const BitmapFileHeader._({
    this.type,
    this.size,
    this.reserved1,
    this.reserved2,
    this.offBits,
  })  : assert(type == 'BM'),
        assert(reserved1 == 0),
        assert(reserved2 == 0);

  factory BitmapFileHeader.fromBytes(ByteData bytes) => BitmapFileHeader._(
        type: ascii.decode([bytes.getUint8(0), bytes.getUint8(1)]),
        size: bytes.getUint32(2, Endian.little),
        reserved1: bytes.getUint16(6, Endian.little),
        reserved2: bytes.getUint16(8, Endian.little),
        offBits: bytes.getUint32(10, Endian.little),
      );
}

enum BICompression { rgb, rle8, rle4, bitFields, jpeg, png }

class BitmapInfo {
  final BitmapInfoHeader header;
  final List<RgbQuad> colors;
  final int redMask;
  final int greenMask;
  final int blueMask;

  const BitmapInfo._(
    this.header,
    this.colors, {
    this.redMask,
    this.greenMask,
    this.blueMask,
  });

  factory BitmapInfo.fromBytes(ByteData bytes) {
    final header = BitmapInfoHeader.fromBytes(bytes);
    final colors = <RgbQuad>[];

    var offset = bytes.offsetInBytes + header.size;

    int redMask;
    int greenMask;
    int blueMask;

    if (header.compression == BICompression.bitFields &&
        (header.bitCount == 16 || header.bitCount == 32)) {
      redMask = bytes.getUint32(offset);
      offset += 4;
      greenMask = bytes.getUint32(offset);
      offset += 4;
      blueMask = bytes.getUint32(offset);
    }

    for (; offset < bytes.lengthInBytes; offset += 4) {
      colors.add(RgbQuad.fromBytes(bytes.buffer.asByteData(offset, 4)));
    }

    return BitmapInfo._(
      header,
      colors,
      redMask: redMask,
      greenMask: greenMask,
      blueMask: blueMask,
    );
  }
}

class BitmapInfoHeader {
  final int size;
  final int width;
  final int height;
  final int planes;
  final int bitCount;
  final BICompression compression;
  final int sizeImage;
  final int xPelsPerMeter;
  final int yPelsPerMeter;
  final int clrUsed;
  final int clrImportant;

  BitmapInfoHeader._({
    this.size,
    this.width,
    this.height,
    this.planes,
    this.bitCount,
    this.compression,
    this.sizeImage,
    this.xPelsPerMeter,
    this.yPelsPerMeter,
    this.clrUsed,
    this.clrImportant,
  })  : assert(height < 0
            ? (compression == BICompression.rgb ||
                compression == BICompression.bitFields)
            : true),
        assert(planes == 1),
        assert([0, 1, 4, 8, 16, 24, 32].contains(bitCount));

  factory BitmapInfoHeader.fromBytes(ByteData bytes) => BitmapInfoHeader._(
        size: bytes.getUint32(0, Endian.little),
        width: bytes.getInt32(4, Endian.little),
        height: bytes.getInt32(8, Endian.little),
        planes: bytes.getUint16(12, Endian.little),
        bitCount: bytes.getUint16(14, Endian.little),
        compression: BICompression.values[bytes.getUint32(16, Endian.little)],
        sizeImage: bytes.getUint32(20, Endian.little),
        xPelsPerMeter: bytes.getUint32(24, Endian.little),
        yPelsPerMeter: bytes.getUint32(28, Endian.little),
        clrUsed: bytes.getUint32(32, Endian.little),
        clrImportant: bytes.getUint32(36, Endian.little),
      );
}

class RgbQuad {
  final int blue;
  final int green;
  final int red;
  final int reserved;

  const RgbQuad._({this.blue, this.green, this.red, this.reserved})
      : assert(reserved == 0);

  factory RgbQuad.fromBytes(ByteData bytes) => RgbQuad._(
        blue: bytes.getUint8(0),
        green: bytes.getUint8(1),
        red: bytes.getUint8(2),
        reserved: bytes.getUint8(3),
      );
}
