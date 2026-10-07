import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

final class PngExportService {
  const PngExportService();

  Future<Uint8List> captureBoundary(
    GlobalKey boundaryKey, {
    double targetPixelWidth = 2160,
    double maxPixelRatio = 2.5,
    double maxPixelCount = 20000000,
  }) async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('Content is not ready to export.');

    final logicalWidth = boundary.size.width;
    final logicalHeight = boundary.size.height;
    if (logicalWidth <= 0 || logicalHeight <= 0) {
      throw StateError('Content has an invalid export size.');
    }

    final widthRatio = math.min(targetPixelWidth / logicalWidth, maxPixelRatio);
    final areaRatio = math.sqrt(maxPixelCount / (logicalWidth * logicalHeight));
    final ratio = math.min(widthRatio, areaRatio);
    if (!ratio.isFinite || ratio <= 0.05) {
      throw StateError('Content is too large to export safely as one PNG.');
    }
    final image = await boundary.toImage(pixelRatio: ratio);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw StateError('Unable to encode PNG output.');
      return byteData.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<bool> savePng({
    required Uint8List bytes,
    required String fileName,
    required String dialogTitle,
  }) async {
    final path = await FilePicker.saveFile(
      dialogTitle: dialogTitle,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['png'],
      bytes: bytes,
    );
    return path != null;
  }

  Future<void> sharePng({
    required Uint8List bytes,
    required String fileName,
    required String subject,
    required String text,
  }) async {
    await Share.shareXFiles(
      [
        XFile.fromData(
          bytes,
          mimeType: 'image/png',
        ),
      ],
      fileNameOverrides: [fileName],
      subject: subject,
      text: text,
    );
  }
}
