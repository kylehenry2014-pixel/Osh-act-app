import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ohs_act_regulations/data/document_integrity.dart';

void main() {
  const png = <int>[
    0x89, 0x50, 0x4E, 0x47,
    0x0D, 0x0A, 0x1A, 0x0A,
  ];

  const jpeg = <int>[0xFF, 0xD8, 0xFF];

  const webp = <int>[
    0x52, 0x49, 0x46, 0x46,
    0x00, 0x00, 0x00, 0x00,
    0x57, 0x45, 0x42, 0x50,
  ];

  const pdf = <int>[
    0x25, 0x50, 0x44, 0x46, 0x2D,
  ];

  const zip = <int>[
    0x50, 0x4B, 0x03, 0x04,
  ];

  group('Document extensions', () {
    test('accepts all supported extensions', () {
      for (final extension
          in DocumentIntegrity.supportedExtensions) {
        expect(
          DocumentIntegrity.extensionFor('file.$extension'),
          extension,
        );
      }
    });

    test('normalises uppercase extensions', () {
      expect(
        DocumentIntegrity.extensionFor('SAFETY.PNG'),
        'png',
      );
    });

    test('rejects unsupported extensions', () {
      for (final name in [
        'file.exe',
        'file.apk',
        'file.html',
        'file.svg',
        'file.pdf.exe',
      ]) {
        expect(
          () => DocumentIntegrity.extensionFor(name),
          throwsStateError,
        );
      }
    });

    test('rejects missing extensions', () {
      expect(
        () => DocumentIntegrity.extensionFor('document'),
        throwsStateError,
      );
    });
  });

  group('Document signatures', () {
    test('recognises PNG', () {
      expect(
        DocumentIntegrity.matchesHeader(png, 'png'),
        isTrue,
      );
    });

    test('recognises JPEG and JPG', () {
      expect(
        DocumentIntegrity.matchesHeader(jpeg, 'jpg'),
        isTrue,
      );
      expect(
        DocumentIntegrity.matchesHeader(jpeg, 'jpeg'),
        isTrue,
      );
    });

    test('recognises WebP', () {
      expect(
        DocumentIntegrity.matchesHeader(webp, 'webp'),
        isTrue,
      );
    });

    test('recognises PDF', () {
      expect(
        DocumentIntegrity.matchesHeader(pdf, 'pdf'),
        isTrue,
      );
    });

    test('recognises DOCX ZIP container header', () {
      expect(
        DocumentIntegrity.matchesHeader(zip, 'docx'),
        isTrue,
      );
    });

    test('rejects mismatched signatures', () {
      expect(
        DocumentIntegrity.matchesHeader(pdf, 'png'),
        isFalse,
      );
      expect(
        DocumentIntegrity.matchesHeader(png, 'pdf'),
        isFalse,
      );
    });

    test('rejects empty headers', () {
      for (final extension
          in DocumentIntegrity.supportedExtensions) {
        expect(
          DocumentIntegrity.matchesHeader([], extension),
          isFalse,
        );
      }
    });

    test('rejects truncated signatures', () {
      expect(
        DocumentIntegrity.matchesHeader(
          png.sublist(0, 4),
          'png',
        ),
        isFalse,
      );

      expect(
        DocumentIntegrity.matchesHeader(
          webp.sublist(0, 8),
          'webp',
        ),
        isFalse,
      );
    });

    test('rejects unsupported signature types', () {
      expect(
        DocumentIntegrity.matchesHeader(png, 'exe'),
        isFalse,
      );
    });
  });

  group('Physical document validation', () {
    late Directory temporaryDirectory;

    setUp(() async {
      temporaryDirectory =
          await Directory.systemTemp.createTemp(
        'ohs_document_integrity_test_',
      );
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    File testFile(String name) {
      return File(
        '${temporaryDirectory.path}'
        '${Platform.pathSeparator}$name',
      );
    }

    test('accepts matching file header', () async {
      final file = testFile('valid.png');

      await file.writeAsBytes(png, flush: true);

      await DocumentIntegrity.validateFile(
        file,
        expectedExtension: 'png',
      );
    });

    test('rejects disguised file content', () async {
      final file = testFile('disguised.png');

      await file.writeAsBytes(pdf, flush: true);

      await expectLater(
        DocumentIntegrity.validateFile(file),
        throwsStateError,
      );
    });

    test('rejects empty files', () async {
      final file = testFile('empty.pdf');

      await file.create();

      await expectLater(
        DocumentIntegrity.validateFile(file),
        throwsStateError,
      );
    });

    test('rejects missing files', () async {
      await expectLater(
        DocumentIntegrity.validateFile(
          testFile('missing.png'),
        ),
        throwsStateError,
      );
    });

    test('rejects expected extension mismatch', () async {
      final file = testFile('document.png');

      await file.writeAsBytes(png, flush: true);

      await expectLater(
        DocumentIntegrity.validateFile(
          file,
          expectedExtension: 'pdf',
        ),
        throwsStateError,
      );
    });

    test('rejects unsupported physical file formats', () async {
      final file = testFile('document.exe');

      await file.writeAsBytes(png, flush: true);

      await expectLater(
        DocumentIntegrity.validateFile(file),
        throwsStateError,
      );
    });

    test('rejects directories presented as files', () async {
      final directory = Directory(
        testFile('directory.png').path,
      );

      await directory.create();

      await expectLater(
        DocumentIntegrity.validateFile(
          File(directory.path),
        ),
        throwsStateError,
      );
    });

    test('rejects symbolic links', () async {
      final original = testFile('original.png');

      await original.writeAsBytes(png, flush: true);

      final link = Link(testFile('linked.png').path);

      await link.create(original.path);

      await expectLater(
        DocumentIntegrity.validateFile(File(link.path)),
        throwsStateError,
      );
    }, skip: Platform.isWindows
        ? 'Windows symbolic links may require privileges.'
        : false);
  });
}
