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
      header.offBits - BitmapFileHeader.structureSize,
    ));
    final pixels = _parsePixels(
      buffer.asUint8List().sublist(header.offBits).buffer,
      header,
      info,
    );

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
        return buffer.asUint8List().expand((element) => [
              element & 1 << 7 == 0 ? 0 : 1,
              element & 1 << 6 == 0 ? 0 : 1,
              element & 1 << 5 == 0 ? 0 : 1,
              element & 1 << 4 == 0 ? 0 : 1,
              element & 1 << 3 == 0 ? 0 : 1,
              element & 1 << 2 == 0 ? 0 : 1,
              element & 1 << 1 == 0 ? 0 : 1,
              element & 1 << 0 == 0 ? 0 : 1,
            ]);
      case 4:
        return buffer.asUint8List().expand((element) => [
              element & (1 << 7 | 1 << 6 | 1 << 5 | 1 << 4),
              element & (1 << 3 | 1 << 2 | 1 << 1 | 1 << 0),
            ]);
      case 8:
        return buffer.asUint8List();
      case 16:
        return buffer.asUint16List().map((e) {
          final isBitField = info.header.compression == BICompression.bitFields;

          // Default color masks for 16bpp.
          // 0x7c00 = 0111 1100 0000 0000 (red)
          //  0x3e0 = 0000 0011 1110 0000 (green)
          //   0x1f = 0000 0000 0001 1111 (blue)
          final redMask = isBitField ? info.redMask : 0x7c00;
          final greenMask = isBitField ? info.greenMask : 0x3e0;
          final blueMask = isBitField ? info.blueMask : 0x1f;

          var offsetRed = 0;
          var offsetGreen = 0;
          var offsetBlue = 0;

          // Specify offsets for make ARGB model.
          if (isBitField) {
            while ((redMask & (1 << offsetRed)) == 0) offsetRed++;
            while ((greenMask & (1 << offsetGreen)) == 0) offsetGreen++;
            while ((blueMask & (1 << offsetBlue)) == 0) offsetBlue++;
          } else {
            offsetRed = 10;
            offsetRed = 5;
          }

          // Red and green values have already shifted to the left respectively.
          // So shift remain bits for each. But blue color must start from least
          // significant bit. So shift to the right.
          return 0xff000000 |
              ((e & redMask) << (16 - offsetRed)) |
              ((e & greenMask) << (8 - offsetGreen)) |
              (e & blueMask) >> offsetBlue;
        }).toList();
      case 24:
        return buffer
            .asUint8List()
            .fold<List<List<int>>>(
                [[]],
                (bgrList, value) => bgrList.last.length < 3
                    ? (bgrList..last.add(value))
                    : (bgrList..add([value])))
            .map((e) => 0xff000000 | e[2] << 16 | e[1] << 8 | e[0])
            .toList();
      case 32:
        return buffer.asUint32List().map((e) {
          final isBitField = info.header.compression == BICompression.bitFields;
          final redMask = isBitField ? info.redMask : 0x00ff0000;
          final greenMask = isBitField ? info.greenMask : 0x0000ff00;
          final blueMask = isBitField ? info.blueMask : 0x000000ff;

          return isBitField
              ? (e & info.blueMask) | (e & info.greenMask) | (e & info.redMask)
              : 0xff000000 | e;
        }).toList();
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
  final List<RGBQuad> colors;
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
    final colors = <RGBQuad>[];

    var offset = header.size;

    int redMask;
    int greenMask;
    int blueMask;

    if (header.compression == BICompression.bitFields &&
        (header.bitCount == 16 || header.bitCount == 32)) {
      redMask = bytes.getUint32(offset, Endian.little);
      offset += 4;
      greenMask = bytes.getUint32(offset, Endian.little);
      offset += 4;
      blueMask = bytes.getUint32(offset, Endian.little);
    }

    for (; offset < bytes.lengthInBytes; offset += 4) {
      colors.add(RGBQuad.fromBytes(bytes.buffer.asByteData(offset, 4)));
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

class RGBQuad {
  final int blue;
  final int green;
  final int red;
  final int reserved;

  const RGBQuad._({this.blue, this.green, this.red, this.reserved})
      : assert(reserved == 0);

  factory RGBQuad.fromBytes(ByteData bytes) => RGBQuad._(
        blue: bytes.getUint8(0),
        green: bytes.getUint8(1),
        red: bytes.getUint8(2),
        reserved: bytes.getUint8(3),
      );
}
