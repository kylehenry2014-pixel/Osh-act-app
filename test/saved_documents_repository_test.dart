import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ohs_act_regulations/data/saved_documents_repository.dart';
import 'package:ohs_act_regulations/models/saved_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storageKey = 'saved_documents';

  const png = <int>[
    0x89, 0x50, 0x4E, 0x47,
    0x0D, 0x0A, 0x1A, 0x0A,
  ];

  late Directory sandbox;
  late Directory appDirectory;
  late Directory storedDirectory;
  late SavedDocumentsRepository repository;

  SavedDocumentsRepository newRepository() {
    return SavedDocumentsRepository.forTesting(
      directoryProvider: () async => appDirectory,
    );
  }

  File childFile(Directory directory, String name) {
    return File(
      '${directory.path}${Platform.pathSeparator}$name',
    );
  }

  SavedDocument record(String id, String path) {
    return SavedDocument(
      id: id,
      name: 'Test document',
      category: 'Security test',
      filePath: path,
      savedAt: DateTime.utc(2026, 1, 1),
    );
  }

  Future<void> seedRecords(
    List<SavedDocument> documents,
  ) async {
    SharedPreferences.setMockInitialValues({
      storageKey: jsonEncode(
        documents.map((item) => item.toJson()).toList(),
      ),
    });

    repository = newRepository();
  }

  Future<SavedDocument> saveValidDocument() async {
    final source = childFile(sandbox, 'source.png');

    await source.writeAsBytes(png, flush: true);

    return repository.saveDocument(
      sourcePath: source.path,
      name: 'Safety signage',
      category: 'Signage',
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});

    sandbox = await Directory.systemTemp.createTemp(
      'ohs_repository_security_test_',
    );

    appDirectory = await Directory(
      '${sandbox.path}${Platform.pathSeparator}app',
    ).create();

    storedDirectory = await Directory(
      '${appDirectory.path}'
      '${Platform.pathSeparator}saved_documents',
    ).create();

    repository = newRepository();
  });

  tearDown(() async {
    SharedPreferences.setMockInitialValues({});

    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  group('Secure document saving', () {
    test('saves and registers a valid document', () async {
      final document = await saveValidDocument();

      expect(repository.all, hasLength(1));

      expect(
        await File(document.filePath).readAsBytes(),
        orderedEquals(png),
      );

      final restored = newRepository();
      await restored.load();

      expect(restored.all.single.id, document.id);
    });

    test('rejects disguised document content', () async {
      final source = childFile(sandbox, 'invalid.png');

      await source.writeAsString('Not a PNG');

      await expectLater(
        repository.saveDocument(
          sourcePath: source.path,
          name: 'Invalid document',
          category: 'Test',
        ),
        throwsStateError,
      );

      expect(repository.all, isEmpty);
      expect(await storedDirectory.list().toList(), isEmpty);
    });

    test('rejects unsupported extensions', () async {
      final source = childFile(sandbox, 'invalid.exe');

      await source.writeAsBytes(png);

      await expectLater(
        repository.saveDocument(
          sourcePath: source.path,
          name: 'Unsupported document',
          category: 'Test',
        ),
        throwsStateError,
      );

      expect(repository.all, isEmpty);
    });

    test('creates independent destination files', () async {
      final first = await saveValidDocument();
      final second = await saveValidDocument();

      expect(first.id, isNot(second.id));
      expect(first.filePath, isNot(second.filePath));
      expect(await File(first.filePath).exists(), isTrue);
      expect(await File(second.filePath).exists(), isTrue);
      expect(repository.all, hasLength(2));
    });
  });

  group('Secure document opening', () {
    test('opens a registered valid document', () async {
      final document = await saveValidDocument();

      expect(
        await repository.validateForOpening(document.id),
        await File(document.filePath).resolveSymbolicLinks(),
      );
    });

    test('rejects external document paths', () async {
      final external = childFile(sandbox, 'external.png');

      await external.writeAsBytes(png);

      await seedRecords([
        record('external', external.path),
      ]);

      await expectLater(
        repository.validateForOpening('external'),
        throwsStateError,
      );

      expect(await external.exists(), isTrue);
    });

    test('rejects directory traversal', () async {
      final file = childFile(storedDirectory, 'valid.png');

      await file.writeAsBytes(png);

      final traversal =
          '${storedDirectory.path}/../saved_documents/valid.png';

      await seedRecords([
        record('traversal', traversal),
      ]);

      await expectLater(
        repository.validateForOpening('traversal'),
        throwsStateError,
      );
    });

    test('rejects symbolic link redirection', () async {
      final external = childFile(sandbox, 'external.png');

      await external.writeAsBytes(png);

      final link = Link(
        childFile(storedDirectory, 'redirect.png').path,
      );

      await link.create(external.path);

      await seedRecords([
        record('redirect', link.path),
      ]);

      await expectLater(
        repository.validateForOpening('redirect'),
        throwsStateError,
      );

      expect(await external.exists(), isTrue);
    }, skip: Platform.isWindows
        ? 'Windows symbolic links may require privileges.'
        : false);

    test('rejects missing physical documents', () async {
      await seedRecords([
        record(
          'missing',
          childFile(storedDirectory, 'missing.png').path,
        ),
      ]);

      await expectLater(
        repository.validateForOpening('missing'),
        throwsStateError,
      );
    });

    test('rejects unknown document identifiers', () async {
      await expectLater(
        repository.validateForOpening('unknown'),
        throwsStateError,
      );
    });

    test('rejects documents damaged after saving', () async {
      final document = await saveValidDocument();

      await File(document.filePath).writeAsString('Damaged');

      await expectLater(
        repository.validateForOpening(document.id),
        throwsStateError,
      );
    });
  });

  group('Metadata protection', () {
    test('rejects duplicate document identifiers', () async {
      final path = childFile(
        storedDirectory,
        'duplicate.png',
      ).path;

      await seedRecords([
        record('duplicate', path),
        record('duplicate', path),
      ]);

      final prefs = await SharedPreferences.getInstance();
      final original = prefs.getString(storageKey);

      await expectLater(
        repository.load(),
        throwsStateError,
      );

      expect(prefs.getString(storageKey), original);
    });

    test('preserves corrupted metadata', () async {
      const corrupted = '{invalid-json';

      SharedPreferences.setMockInitialValues({
        storageKey: corrupted,
      });

      repository = newRepository();

      await expectLater(
        repository.load(),
        throwsStateError,
      );

      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getString(storageKey), corrupted);
    });

    test('blocks saving when metadata is corrupted', () async {
      SharedPreferences.setMockInitialValues({
        storageKey: 'invalid',
      });

      repository = newRepository();

      await expectLater(
        saveValidDocument(),
        throwsStateError,
      );

      expect(await storedDirectory.list().toList(), isEmpty);

      final prefs = await SharedPreferences.getInstance();

      expect(prefs.getString(storageKey), 'invalid');
    });
  });

  group('Secure document deletion', () {
    test('deletes a valid unshared document', () async {
      final document = await saveValidDocument();

      await repository.delete(document.id);

      expect(repository.all, isEmpty);
      expect(await File(document.filePath).exists(), isFalse);

      final restored = newRepository();
      await restored.load();

      expect(restored.all, isEmpty);
    });

    test('preserves files referenced by another record', () async {
      final file = childFile(storedDirectory, 'shared.png');

      await file.writeAsBytes(png);

      await seedRecords([
        record('first', file.path),
        record('second', file.path),
      ]);

      await repository.delete('first');

      expect(await file.exists(), isTrue);
      expect(repository.all.single.id, 'second');

      await repository.delete('second');

      expect(await file.exists(), isFalse);
    });

    test('never deletes external files', () async {
      final external = childFile(sandbox, 'external.png');

      await external.writeAsBytes(png);

      await seedRecords([
        record('external', external.path),
      ]);

      await repository.delete('external');

      expect(repository.all, isEmpty);
      expect(await external.exists(), isTrue);
      expect(await external.readAsBytes(), orderedEquals(png));
    });

    test('allows damaged internal documents to be removed', () async {
      final document = await saveValidDocument();

      await File(document.filePath).writeAsString('Damaged');

      await repository.delete(document.id);

      expect(repository.all, isEmpty);
      expect(await File(document.filePath).exists(), isFalse);
    });

    test('handles missing files during deletion', () async {
      await seedRecords([
        record(
          'missing',
          childFile(storedDirectory, 'missing.png').path,
        ),
      ]);

      await repository.delete('missing');

      expect(repository.all, isEmpty);
    });

    test('preserves symbolic link targets during deletion', () async {
      final external = childFile(sandbox, 'external.png');

      await external.writeAsBytes(png);

      final link = Link(
        childFile(storedDirectory, 'redirect.png').path,
      );

      await link.create(external.path);

      await seedRecords([
        record('redirect', link.path),
      ]);

      await repository.delete('redirect');

      expect(await external.exists(), isTrue);
      expect(repository.all, isEmpty);
    }, skip: Platform.isWindows
        ? 'Windows symbolic links may require privileges.'
        : false);
  });
}
