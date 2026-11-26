/// Choosing a certificate file with the system's document picker.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// The contents of the file the user chooses, or null if none.
typedef ChooseCertificateFile = Future<Uint8List?> Function();

final certificateFileProvider = Provider<ChooseCertificateFile>(
  (ref) => _chooseFile,
);

// No type filter: certificate files come with many types, or none.
Future<Uint8List?> _chooseFile() async {
  final file = await openFile();
  if (file == null) return null;
  try {
    return await file.readAsBytes();
  } finally {
    await _removeCopy(file.path);
  }
}

// On Android the picker leaves a copy in the cache, which may be of a private
// key chosen by mistake. Elsewhere the path is the user's own file.
Future<void> _removeCopy(String path) async {
  if (!Platform.isAndroid) return;
  try {
    final cache = (await getTemporaryDirectory()).path;
    if (path.startsWith('$cache/')) await File(path).delete();
  } on FileSystemException {
    // Android clears the cache in time.
  }
}
