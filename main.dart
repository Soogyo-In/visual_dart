import 'dart:io';

import 'bitmap_file.dart';

void main() {
  final gray = File('./images/rgb32bfdef.bmp');
  final byteBuffer = gray.readAsBytesSync().buffer;
  final bitmap = BitmapFile.fromBuffer(byteBuffer);

  // for (final pixel in bitmap.pixels) {
  //   print(pixel.toRadixString(16).padLeft(8));
  // }
}
