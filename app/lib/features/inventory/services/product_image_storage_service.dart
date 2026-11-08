import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Stores product photos in permanent application-support storage.
///
/// Only the relative path returned by [pickAndStoreImage] should be saved in
/// the products table. Do not save the original picker path in SQLite.
class ProductImageStorageService {
  ProductImageStorageService({FilePicker? filePicker})
      : _filePicker = filePicker;

  final FilePicker? _filePicker;

  FilePicker get _picker => _filePicker ?? FilePicker.platform;
  final Uuid _uuid = const Uuid();

  static const String _directoryName = 'product_images';

  /// Opens the platform file picker and copies the selected image into
  /// SOKOPOA's permanent local product-image directory.
  ///
  /// Returns a relative path such as `product_images/<uuid>.jpg`, or null
  /// when the user cancels the picker.
  Future<String?> pickAndStoreImage() async {
    final result = await _picker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );

    if (result == null || result.files.isEmpty) return null;

    final pickedFile = result.files.single;
    final extension = _safeExtension(pickedFile.extension);
    final fileName = '${_uuid.v4()}$extension';
    final relativePath = p.join(_directoryName, fileName);

    final supportDirectory = await getApplicationSupportDirectory();
    final imageDirectory = Directory(
      p.join(supportDirectory.path, _directoryName),
    );
    await imageDirectory.create(recursive: true);

    final destination = File(p.join(imageDirectory.path, fileName));

    try {
      final sourcePath = pickedFile.path;
      if (sourcePath != null && sourcePath.isNotEmpty) {
        await File(sourcePath).copy(destination.path);
      } else {
        final bytes = pickedFile.bytes;
        if (bytes == null || bytes.isEmpty) {
          throw StateError('The selected image could not be read.');
        }
        await destination.writeAsBytes(bytes, flush: true);
      }

      if (!await destination.exists() || await destination.length() == 0) {
        throw StateError('The selected image was not saved correctly.');
      }

      return relativePath.replaceAll('\\', '/');
    } catch (_) {
      if (await destination.exists()) {
        await destination.delete();
      }
      rethrow;
    }
  }

  /// Resolves a database-relative image path to a local file.
  /// Returns null if the path is empty, invalid, or the file is missing.
  Future<File?> resolveImageFile(String? relativePath) async {
    if (relativePath == null || relativePath.trim().isEmpty) return null;

    final normalized = p.normalize(relativePath.trim());
    if (p.isAbsolute(normalized) ||
        normalized == '..' ||
        normalized.startsWith('..${p.separator}')) {
      return null;
    }

    final supportDirectory = await getApplicationSupportDirectory();
    final root = p.normalize(supportDirectory.path);
    final filePath = p.normalize(p.join(root, normalized));

    if (!p.isWithin(root, filePath)) return null;

    final file = File(filePath);
    if (!await file.exists()) return null;
    return file;
  }

  /// Deletes an image only when its relative path points inside the
  /// product_images directory. Call this only after the database has been
  /// successfully updated to reference a replacement image.
  Future<void> deleteImage(String? relativePath) async {
    if (relativePath == null || relativePath.trim().isEmpty) return;

    final normalized = p.normalize(relativePath.trim());
    final expectedPrefix = '$_directoryName${p.separator}';
    if (p.isAbsolute(normalized) || !normalized.startsWith(expectedPrefix)) {
      return;
    }

    final file = await resolveImageFile(normalized);
    if (file != null) await file.delete();
  }

  String _safeExtension(String? extension) {
    final cleaned = extension?.toLowerCase().replaceAll('.', '').trim();
    if (cleaned == null || cleaned.isEmpty) return '.img';
    if (!RegExp(r'^[a-z0-9]{1,8}$').hasMatch(cleaned)) return '.img';
    return '.$cleaned';
  }
}
