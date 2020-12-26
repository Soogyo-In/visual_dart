import 'dart:io';

import 'bitmap_file.dart';

void main() {
  final gray = File('./images/color_4x4.bmp');
  final byteBuffer = gray.readAsBytesSync().buffer;
  final bitmap = BitmapFile.fromBuffer(byteBuffer);

  for (final pixel in bitmap.pixels) {
    print(pixel.toRadixString(16).padLeft(6));
  }
}
