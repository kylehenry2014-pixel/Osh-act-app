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
  Future<void> _open(SavedDocument document) async {
    final result = await OpenFile.open(document.filePath);
    if (!mounted) return;
    if (result.type != ResultType.done) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not open this document: ${result.message}')),
      );
    }
  }

  Future<void> _confirmDelete(SavedDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${document.name}"?',
            style: AppText.headline(size: 17)),
        content: Text(
          'This removes your saved copy. You can save it again later if you still have the original download.',
          style: AppText.body(size: 14),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: TextStyle(color: AppColors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await SavedDocumentsRepository.instance.delete(document.id);
      if (mounted) setState(() {});
    }
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
      body: documents.isEmpty
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
                  onTap: () => _open(document),
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
                          onPressed: () => _confirmDelete(document),
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
