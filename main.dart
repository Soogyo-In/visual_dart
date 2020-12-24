import 'dart:convert';
import 'dart:io';

import 'dart:typed_data';

void main() {
  final gray = File('./images/gray_4x4.bmp');
  final byteBuffer = gray.readAsBytesSync().buffer;
  final bitmap = BitmapFile.fromBuffer(byteBuffer);
}

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
    final pixels = buffer.asUint8List().skip(header.offBits).toList();

    return BitmapFile._(header, info, pixels);
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
