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
  late File source;

  late bool rejectWrite;
  late bool throwOnWrite;
  late bool persistBeforeFailure;
  late bool rejectReload;

  late int writeAttempts;
  late int reloadAttempts;

  late SavedDocumentsRepository repository;

  SavedDocumentsRepository newRepository() {
    return SavedDocumentsRepository.forTesting(
      directoryProvider: () async => appDirectory,
      metadataWriter: (prefs, key, value) async {
        writeAttempts++;

        if (persistBeforeFailure) {
          await prefs.setString(key, value);
          return false;
        }

        if (throwOnWrite) {
          throw StateError('Simulated metadata write failure.');
        }

        if (rejectWrite) {
          return false;
        }

        return prefs.setString(key, value);
      },
      metadataReloader: (prefs) async {
        reloadAttempts++;

        if (rejectReload) {
          throw StateError('Simulated metadata reload failure.');
        }

        await prefs.reload();
      },
    );
  }

  Future<SavedDocument> saveDocument() {
    return repository.saveDocument(
      sourcePath: source.path,
      name: 'Safety document',
      category: 'Signage',
    );
  }

  Future<List<FileSystemEntity>> storedFiles() {
    return storedDirectory.list().toList();
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});

    rejectWrite = false;
    throwOnWrite = false;
    persistBeforeFailure = false;
    rejectReload = false;

    writeAttempts = 0;
    reloadAttempts = 0;

    sandbox = await Directory.systemTemp.createTemp(
      'ohs_metadata_recovery_test_',
    );

    final separator = Platform.pathSeparator;

    appDirectory = await Directory(
      '${sandbox.path}${separator}app',
    ).create();

    storedDirectory = await Directory(
      '${appDirectory.path}${separator}saved_documents',
    ).create();

    source = File(
      '${sandbox.path}${separator}source.png',
    );

    await source.writeAsBytes(png, flush: true);

    repository = newRepository();
  });

  tearDown(() async {
    SharedPreferences.setMockInitialValues({});

    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  group('Document metadata failure recovery', () {
    test('cleans up when metadata write is rejected', () async {
      rejectWrite = true;

      await expectLater(
        saveDocument(),
        throwsStateError,
      );

      expect(writeAttempts, 1);
      expect(reloadAttempts, 1);
      expect(repository.all, isEmpty);
      expect(await storedFiles(), isEmpty);
      expect(await source.exists(), isTrue);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(storageKey), isNull);
    });

    test('cleans up when metadata writer throws', () async {
      throwOnWrite = true;

      await expectLater(
        saveDocument(),
        throwsStateError,
      );

      expect(writeAttempts, 1);
      expect(reloadAttempts, 1);
      expect(repository.all, isEmpty);
      expect(await storedFiles(), isEmpty);
      expect(await source.exists(), isTrue);
    });

    test('recovers metadata persisted despite failure', () async {
      persistBeforeFailure = true;

      final document = await saveDocument();

      expect(writeAttempts, 1);
      expect(reloadAttempts, 1);
      expect(repository.all.single.id, document.id);

      expect(
        await File(document.filePath).readAsBytes(),
        orderedEquals(png),
      );

      final restored = newRepository();
      await restored.load();

      expect(restored.all.single.id, document.id);
      expect(await storedFiles(), hasLength(1));
    });

    test('preserves files when write and reload fail', () async {
      persistBeforeFailure = true;
      rejectReload = true;

      await expectLater(
        saveDocument(),
        throwsStateError,
      );

      expect(writeAttempts, 1);
      expect(reloadAttempts, 1);

      final files = await storedFiles();

      expect(files, hasLength(1));

      expect(
        await File(files.single.path).readAsBytes(),
        orderedEquals(png),
      );

      rejectReload = false;

      await repository.load();

      expect(repository.all, hasLength(1));

      expect(
        await File(repository.all.single.filePath).exists(),
        isTrue,
      );
    });

    test('preserves document when deletion metadata fails', () async {
      final document = await saveDocument();

      rejectWrite = true;

      await expectLater(
        repository.delete(document.id),
        throwsStateError,
      );

      expect(writeAttempts, 2);
      expect(reloadAttempts, 1);
      expect(repository.all.single.id, document.id);

      expect(
        await File(document.filePath).readAsBytes(),
        orderedEquals(png),
      );

      final restored = newRepository();
      await restored.load();

      expect(restored.all.single.id, document.id);
    });

    test('resumes operations after metadata recovery', () async {
      persistBeforeFailure = true;
      rejectReload = true;

      await expectLater(
        saveDocument(),
        throwsStateError,
      );

      expect(await storedFiles(), hasLength(1));

      persistBeforeFailure = false;
      rejectReload = false;

      await repository.load();

      final recovered = repository.all.single;
      final next = await saveDocument();

      expect(repository.all, hasLength(2));
      expect(recovered.id, isNot(next.id));

      await repository.delete(recovered.id);

      expect(repository.all.single.id, next.id);
      expect(await File(recovered.filePath).exists(), isFalse);
      expect(await File(next.filePath).exists(), isTrue);
      expect(await storedFiles(), hasLength(1));
    });
  });
}
