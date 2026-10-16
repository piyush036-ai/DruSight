/// Evidence-image storage (master spec sections 31, 58).
///
/// Invariant: the original capture bytes are written once, hashed, and never
/// modified. Every derived artefact (thumbnail, annotated overlay, rectified
/// crop) is a separate file that records what it was derived from.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../repositories/test_repository.dart';
import '../security/hashing.dart';

class ImageStorageService {
  ImageStorageService();

  Directory? _root;

  Future<Directory> _evidenceRoot() async {
    final Directory? cached = _root;
    if (cached != null) return cached;
    final Directory docs = await getApplicationDocumentsDirectory();
    final Directory dir = Directory(p.join(docs.path, 'evidence'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _root = dir;
    return dir;
  }

  /// Writes the untouched capture and returns its stored reference.
  ///
  /// The hash is computed over the bytes AS WRITTEN, before any decode, so it
  /// commits to the exact file on disk.
  Future<StoredImage> saveOriginal({
    required String testId,
    required Uint8List bytes,
    required DateTime capturedAtUtc,
    int? offsetSeconds,
  }) async {
    final Directory dir = Directory(
      p.join((await _evidenceRoot()).path, testId),
    );
    if (!await dir.exists()) await dir.create(recursive: true);

    final String suffix =
        offsetSeconds == null ? 'original' : 'seq_${offsetSeconds}s';
    final File file = File(p.join(dir.path, '$suffix.jpg'));

    if (await file.exists()) {
      throw StateError(
        'Refusing to overwrite an existing evidence image at ${file.path}.',
      );
    }
    await file.writeAsBytes(bytes, flush: true);

    final img.Image? decoded = img.decodeImage(bytes);

    return StoredImage(
      imageId: '$testId-$suffix',
      role: offsetSeconds == null ? 'ORIGINAL' : 'SEQUENCE',
      filePath: file.path,
      imageHash: Hashing.sha256OfImageBytes(bytes),
      widthPx: decoded?.width ?? 0,
      heightPx: decoded?.height ?? 0,
      byteSize: bytes.length,
      capturedAtUtc: capturedAtUtc,
      isOriginal: offsetSeconds == null,
      offsetSeconds: offsetSeconds,
    );
  }

  /// Writes a derived artefact alongside the original, never replacing it.
  Future<StoredImage> saveDerived({
    required String testId,
    required String role,
    required Uint8List bytes,
    required String derivedFromImageId,
  }) async {
    final Directory dir = Directory(
      p.join((await _evidenceRoot()).path, testId),
    );
    if (!await dir.exists()) await dir.create(recursive: true);

    final String name = '${role.toLowerCase()}.jpg';
    final File file = File(p.join(dir.path, name));
    await file.writeAsBytes(bytes, flush: true);

    final img.Image? decoded = img.decodeImage(bytes);
    return StoredImage(
      imageId: '$testId-${role.toLowerCase()}',
      role: role,
      filePath: file.path,
      imageHash: Hashing.sha256OfImageBytes(bytes),
      widthPx: decoded?.width ?? 0,
      heightPx: decoded?.height ?? 0,
      byteSize: bytes.length,
      capturedAtUtc: DateTime.now().toUtc(),
      isOriginal: false,
      derivedFrom: derivedFromImageId,
    );
  }

  Future<File?> originalFileFor(String testId) async {
    final File file = File(
      p.join((await _evidenceRoot()).path, testId, 'original.jpg'),
    );
    return await file.exists() ? file : null;
  }
}
