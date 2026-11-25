import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import '../data/saved_documents_repository.dart';
import '../models/saved_document.dart';
import '../theme/app_theme.dart';

/// Lists every document the user has saved from Checklists or Toolbox
/// Talks - a permanent local copy they can reopen or delete, rather than
/// relying on a one-off download they might lose track of.
class MyDocumentsScreen extends StatefulWidget {
  const MyDocumentsScreen({super.key});

  @override
  State<MyDocumentsScreen> createState() => _MyDocumentsScreenState();
}

class _MyDocumentsScreenState extends State<MyDocumentsScreen> {
  final _repo = SavedDocumentsRepository.instance;

  bool _operationBusy = false;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadDocuments();
  }

  void _snack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _loadDocuments() async {
    if (!mounted || _operationBusy) return;

    setState(() {
      _operationBusy = true;
      _loading = true;
      _loadError = null;
    });

    try {
      await _repo.load();
    } catch (error) {
      debugPrint('Document loading failed: $error');

      if (!mounted) return;

      _loadError =
          'Your saved documents could not be loaded. '
          'Existing files have not been deleted.';
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _operationBusy = false;
        });
      }
    }
  }

  Future<void> _open(SavedDocument document) async {
    if (!mounted || _operationBusy) return;

    setState(() => _operationBusy = true);

    try {
      final file = File(document.filePath);

      if (!await file.exists()) {
        _snack(
          'This document is no longer available on your device.',
        );
        return;
      }

      if (await file.length() == 0) {
        _snack(
          'This document is empty or damaged.',
        );
        return;
      }

      if (!mounted ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }

      final result = await OpenFile.open(document.filePath);

      if (!mounted) return;

      if (result.type != ResultType.done) {
        debugPrint('Document opening failed: ${result.message}');

        _snack(
          'Could not open this document. '
          'Check that a compatible application is installed.',
        );
      }
    } catch (error) {
      debugPrint('Document opening error: $error');

      _snack(
        'Unable to open this document. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _operationBusy = false);
      }
    }
  }

  Future<void> _confirmDelete(SavedDocument document) async {
    if (!mounted || _operationBusy) return;

    setState(() => _operationBusy = true);

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            'Delete "${document.name}"?',
            style: AppText.headline(size: 17),
          ),
          content: Text(
            'This removes your saved copy. You can save it '
            'again later if you still have the original download.',
            style: AppText.body(size: 14),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(true),
              child: Text(
                'Delete',
                style: TextStyle(color: AppColors.red),
              ),
            ),
          ],
        ),
      );

      if (!mounted || confirmed != true) return;

      await _repo.delete(document.id);

      _snack('Document removed from My Documents.');
    } catch (error) {
      debugPrint('Document deletion failed: $error');

      _snack(
        'Could not remove this document. Please try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _operationBusy = false);
      }
    }
  }

  Widget _buildLoadError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: 40,
              color: AppColors.steel,
            ),
            const SizedBox(height: 16),
            Text(
              _loadError!,
              textAlign: TextAlign.center,
              style: AppText.body(size: 14),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _operationBusy
                  ? null
                  : _loadDocuments,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final documents = SavedDocumentsRepository.instance.all;

    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        title: Text('My Documents', style: AppText.headline(size: 18)),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppColors.amberDeep,
              ),
            )
          : _loadError != null
              ? _buildLoadError()
              : documents.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open_outlined,
                        size: 40, color: AppColors.steel),
                    const SizedBox(height: 16),
                    Text(
                      'No documents saved yet. Save a checklist or toolbox talk to keep a permanent copy here.',
                      textAlign: TextAlign.center,
                      style: AppText.body(size: 14, color: AppColors.steel),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: documents.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final document = documents[index];
                return InkWell(
                  onTap: _operationBusy ? null : () => _open(document),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.paperRaised,
                      border: Border.all(color: AppColors.line),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.description_outlined,
                            color: AppColors.steel),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(document.name,
                                  style: AppText.headline(
                                      size: 15, weight: FontWeight.w600)),
                              const SizedBox(height: 3),
                              Text(document.category,
                                  style: AppText.label(size: 11)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline,
                              color: AppColors.steel),
                          onPressed: _operationBusy ? null : () => _confirmDelete(document),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
