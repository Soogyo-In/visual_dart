import 'dart:convert';
import 'dart:typed_data';

enum ColorModel { rgba, bgra, argb, abgr }

class BitmapFile {
  final BitmapFileHeader header;
  final BitmapInfo info;

  /// ARGB format.
  final Iterable<int> _pixels;

  const BitmapFile._(this.header, this.info, this._pixels);

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

  Uint8List getPixels8888([
    ColorModel model = ColorModel.bgra,
    bool topDown = false,
  ]) {
    final formed = _getPixelColorBy(model).toList();
    final clipped = List.generate(
      info.header.unsignedHeight,
      (index) {
        final start = index * info.header.paddedWidth * 4;
        return formed.sublist(start, start + info.header.width * 4)
          ..addAll(List.filled(
            (info.header.paddedWidth - info.header.width) * 4,
            0,
          ));
      },
    );
    Iterable<int> pixels;

    if (topDown) {
      pixels = info.header.height < 0
          ? clipped.reversed.expand((element) => element)
          : clipped.expand((element) => element);
    } else {
      pixels = info.header.height < 0
          ? clipped.expand((element) => element)
          : clipped.reversed.expand((element) => element);
    }

    return Uint8List.fromList(pixels.toList());
  }

  Uint32List getPixels32([
    ColorModel model = ColorModel.bgra,
    bool topDown = false,
  ]) {
    final pixels8888 = getPixels8888();
    final pixels32 = List.generate(pixels8888.length ~/ 4,
            (index) => pixels8888.sublist(index * 4, index * 4 + 4))
        .expand(
            (element) => [element[0] | element[1] | element[2] | element[3]])
        .toList();

    return Uint32List.fromList(pixels32);
  }

  static Iterable<int> _parsePixels(
    ByteBuffer buffer,
    BitmapFileHeader header,
    BitmapInfo info,
  ) {
    switch (info.header.bitCount) {
      case 0:
        return [];
      case 1:
        return buffer.asUint8List().expand((pixel) => [
              info.colors[(pixel >> 7) & 1].argb,
              info.colors[(pixel >> 6) & 1].argb,
              info.colors[(pixel >> 5) & 1].argb,
              info.colors[(pixel >> 4) & 1].argb,
              info.colors[(pixel >> 3) & 1].argb,
              info.colors[(pixel >> 2) & 1].argb,
              info.colors[(pixel >> 1) & 1].argb,
              info.colors[pixel & 1].argb,
            ]);
      case 4:
        return buffer.asUint8List().expand((pixel) => [
              info.colors[(pixel >> 4) & 0xf].argb,
              info.colors[pixel & 0xf].argb,
            ]);
      case 8:
        return buffer.asUint8List().map((pixel) => info.colors[pixel].argb);
      case 16:
        return buffer.asUint16List().map((pixel) {
          final isBitField = info.header.compression == BICompression.bitFields;

          // Default color masks for 16bpp.
          // 0x7c00 = 0111 1100 0000 0000 (red)
          //  0x3e0 = 0000 0011 1110 0000 (green)
          //   0x1f = 0000 0000 0001 1111 (blue)
          final maskR = isBitField ? info.redMask : 0x7c00;
          final maskG = isBitField ? info.greenMask : 0x3e0;
          final maskB = isBitField ? info.blueMask : 0x1f;
          final rgb = _getColorFromBitMasks(pixel, maskR, maskG, maskB);

          return 0xff000000 | (rgb[0] << 16) | (rgb[1] << 8) | rgb[2];
        });
      case 24:
        return buffer.asUint8List().fold<List<List<int>>>(
          [[]],
          (bgrList, value) => bgrList.last.length < 3
              ? (bgrList..last.add(value))
              : (bgrList..add([value])),
        ).map(
          (pixel) => 0xff000000 | pixel[2] << 16 | pixel[1] << 8 | pixel[0],
        );
      case 32:
        return buffer.asUint32List().map((pixel) {
          final isBitField = info.header.compression == BICompression.bitFields;

          if (isBitField) {
            final rgb = _getColorFromBitMasks(
              pixel,
              info.redMask,
              info.greenMask,
              info.blueMask,
            );

            return 0xff000000 | (rgb[0] << 16) | (rgb[1] << 8) | rgb[2];
          } else {
            return 0xff000000 | pixel;
          }
        });
      default:
        throw Exception('Unsupported bit count (${info.header.bitCount}).');
    }
  }

  static int _makeSolidMask(int length) {
    int mask = 0;

    while (length > 0) {
      mask |= 1 << --length;
    }

    return mask;
  }

  /// Returns color value [List] order by red, green, blue.
  static List<int> _getColorFromBitMasks(
    int pixel,
    int maskR,
    int maskG,
    int maskB,
  ) {
    var offsetR = 0;
    var offsetG = 0;
    var offsetB = 0;
    var bitCntR = 0;
    var bitCntG = 0;
    var bitCntB = 0;

    // Specify offsets for make ARGB model.
    while (maskR > 0) {
      if ((maskR & (1 << offsetR)) == 0) {
        offsetR++;
      } else if (((maskR >> offsetR) & (1 << bitCntR)) != 0) {
        bitCntR++;
      } else {
        break;
      }
    }
    while (maskG > 0) {
      if ((maskG & (1 << offsetG)) == 0) {
        offsetG++;
      } else if ((maskG >> offsetG) & (1 << bitCntG) != 0) {
        bitCntG++;
      } else {
        break;
      }
    }
    while (maskB > 0) {
      if ((maskB & (1 << offsetB)) == 0) {
        offsetB++;
      } else if ((maskB >> offsetB) & (1 << bitCntB) != 0) {
        bitCntB++;
      } else {
        break;
      }
    }

    // x = max value for bitCntR or bitCntG or bitCntB.
    // y = max value for 8-bit.
    // n = value in x.
    // m = value in y.
    // n / x = m / y
    // m = ny / x
    final red = bitCntR == 0
        ? 0
        : (((pixel & maskR) >> offsetR) * 0xff) / _makeSolidMask(bitCntR);
    final green = bitCntG == 0
        ? 0
        : (((pixel & maskG) >> offsetG) * 0xff) / _makeSolidMask(bitCntG);
    final blue = bitCntB == 0
        ? 0
        : (((pixel & maskB) >> offsetB) * 0xff) / _makeSolidMask(bitCntB);

    return [red.round(), green.round(), blue.round()];
  }

  Iterable<int> _getPixelColorBy(ColorModel model) {
    switch (model) {
      case ColorModel.rgba:
        return _pixels.expand((element) => [
              (element & 0x00ff0000) >> 16,
              (element & 0x0000ff00) >> 8,
              element & 0x000000ff,
              (element & 0xff000000) >> 24,
            ]);
        break;
      case ColorModel.bgra:
        return _pixels.expand((element) => [
              element & 0x000000ff,
              (element & 0x0000ff00) >> 8,
              (element & 0x00ff0000) >> 16,
              (element & 0xff000000) >> 24,
            ]);
        break;
      case ColorModel.argb:
        return _pixels.expand((element) => [
              (element & 0xff000000) >> 24,
              (element & 0x00ff0000) >> 16,
              (element & 0x0000ff00) >> 8,
              element & 0x000000ff,
            ]);
        break;
      case ColorModel.abgr:
        return _pixels.expand((element) => [
              (element & 0xff000000) >> 24,
              element & 0x000000ff,
              (element & 0x0000ff00) >> 8,
              (element & 0x00ff0000) >> 16,
            ]);
        break;
      default:
        throw Exception('Cannot rearrange bytes by null.');
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
      offset += 4;
    }

    for (; offset < bytes.lengthInBytes; offset += 4) {
      colors.add(
        RGBQuad.fromBytes(
          bytes.buffer.asByteData(offset + bytes.offsetInBytes, 4),
        ),
      );
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
        assert([0, 1, 4, 8, 16, 24, 32].contains(bitCount)) {
    if (size != 40) {
      throw Exception('Unsupported Bitmap version. Only support version 3.');
    }
  }

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

  int get paddedWidth => (width * bitCount) % 32 == 0
      ? width
      : ((((width * bitCount) / 32).ceil()) * 32) ~/ bitCount;

  int get unsignedHeight => height < 0 ? -height : height;
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

  int get argb => 0xff000000 | red << 16 | green << 8 | blue;
}
