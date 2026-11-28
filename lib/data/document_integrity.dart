import 'dart:io';

/// Basic document format validation.
///
/// Header validation is not malware scanning and does not
/// guarantee that the entire document is structurally valid.
class DocumentIntegrity {
  const DocumentIntegrity._();

  static const supportedExtensions = <String>{
    'png',
    'jpg',
    'jpeg',
    'webp',
    'pdf',
    'docx',
  };

  static String extensionFor(String fileName) {
    final match = RegExp(
      r'\.([a-zA-Z0-9]{1,10})$',
    ).firstMatch(fileName);

    final extension = match?.group(1)?.toLowerCase();

    if (extension == null ||
        !supportedExtensions.contains(extension)) {
      throw StateError('Unsupported document format.');
    }

    return extension;
  }

  static bool _matches(
    List<int> bytes,
    List<int> signature, {
    int offset = 0,
  }) {
    if (offset < 0 ||
        bytes.length < offset + signature.length) {
      return false;
    }

    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) {
        return false;
      }
    }

    return true;
  }

  static bool matchesHeader(
    List<int> bytes,
    String extension,
  ) {
    switch (extension.toLowerCase()) {
      case 'png':
        return _matches(bytes, const [
          0x89, 0x50, 0x4E, 0x47,
          0x0D, 0x0A, 0x1A, 0x0A,
        ]);

      case 'jpg':
      case 'jpeg':
        return _matches(bytes, const [
          0xFF, 0xD8, 0xFF,
        ]);

      case 'webp':
        return _matches(bytes, const [
          0x52, 0x49, 0x46, 0x46,
        ]) &&
            _matches(
              bytes,
              const [0x57, 0x45, 0x42, 0x50],
              offset: 8,
            );

      case 'pdf':
        return _matches(bytes, const [
          0x25, 0x50, 0x44, 0x46, 0x2D,
        ]);

      case 'docx':
        // A DOCX uses a ZIP container. This check does
        // not verify its internal Office XML structure.
        return _matches(bytes, const [
          0x50, 0x4B, 0x03, 0x04,
        ]);

      default:
        return false;
    }
  }

  static Future<void> validateFile(
    File file, {
    String? expectedExtension,
  }) async {
    final type = await FileSystemEntity.type(
      file.path,
      followLinks: false,
    );

    if (type != FileSystemEntityType.file) {
      throw StateError(
        'Document is missing or is not a regular file.',
      );
    }

    final extension = extensionFor(
      file.uri.pathSegments.last,
    );

    if (expectedExtension != null &&
        extension != expectedExtension.toLowerCase()) {
      throw StateError('Document extension mismatch.');
    }

    final handle = await file.open(mode: FileMode.read);

    try {
      final length = await handle.length();

      if (length == 0) {
        throw StateError('Document is empty.');
      }

      final header = await handle.read(16);

      if (!matchesHeader(header, extension)) {
        throw StateError(
          'Document content does not match its file format.',
        );
      }
    } finally {
      await handle.close();
    }
  }
}
