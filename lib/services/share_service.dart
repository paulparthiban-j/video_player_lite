import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'video_format_service.dart';

class ShareException implements Exception {
  final String message;

  const ShareException(this.message);

  @override
  String toString() => message;
}

class ShareService {
  static Future<XFile> prepareShareFile(String filePath) async {
    final sourceFile = File(filePath);
    if (!await sourceFile.exists()) {
      throw const ShareException('Video file not found');
    }

    final tempDir = await getTemporaryDirectory();
    final extension = path.extension(filePath);
    final baseName = path.basenameWithoutExtension(filePath);
    final safeBaseName = baseName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final exportPath = path.join(
      tempDir.path,
      'share_${DateTime.now().millisecondsSinceEpoch}_$safeBaseName$extension',
    );

    final exportedFile = await sourceFile.copy(exportPath);
    final mimeType = VideoFormatService.getMimeTypeForFile(filePath);

    return XFile(
      exportedFile.path,
      mimeType: mimeType,
      name: path.basename(exportedFile.path),
    );
  }
}
