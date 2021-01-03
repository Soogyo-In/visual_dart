import 'dart:io';

import 'bitmap_file.dart';

void main() {
  final gray = File('./images/pal1bg.bmp');
  final byteBuffer = gray.readAsBytesSync().buffer;
  final bitmap = BitmapFile.fromBuffer(byteBuffer);

  // for (final pixel in bitmap.pixels) {
  //   print(pixel.toRadixString(16).padLeft(8));
  // }
}
