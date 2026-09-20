import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../data/certificates_repository.dart';
import '../data/notification_service.dart';
import '../models/certificate.dart';
import '../theme/app_theme.dart';

/// Add a new certificate, or edit an existing one (pass [existing] to edit).
/// A certificate can hold multiple photo pages - useful for something like
/// a full medical examination pack that spans several pages.
class AddCertificateScreen extends StatefulWidget {
  final Certificate? existing;
  const AddCertificateScreen({super.key, this.existing});

  @override
  State<AddCertificateScreen> createState() => _AddCertificateScreenState();
}

class _AddCertificateScreenState extends State<AddCertificateScreen> {
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final _picker = ImagePicker();

  List<String> _imagePaths = [];
  DateTime? _expiryDate;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _nameController.text = existing.name;
      _notesController.text = existing.notes ?? '';
      _imagePaths = [...existing.imagePaths];
      _expiryDate = existing.expiryDate;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _takePhoto() async {
    try {
      final picked =
          await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (picked != null) {
        setState(() => _imagePaths.add(picked.path));
      }
    } catch (e) {
      setState(() => _error =
          'Could not access the camera. Check app permissions in your device settings.');
    }
  }

  Future<void> _uploadPhotos() async {
    try {
      // Multi-select so a whole stack of pages can be added in one go.
      final picked = await _picker.pickMultiImage(imageQuality: 85);
      if (picked.isNotEmpty) {
        setState(() => _imagePaths.addAll(picked.map((f) => f.path)));
      }
    } catch (e) {
      setState(() => _error =
          'Could not access photos. Check app permissions in your device settings.');
    }
  }

  void _removePage(int index) {
    setState(() => _imagePaths.removeAt(index));
  }

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _expiryDate ?? now.add(const Duration(days: 30)),
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 20),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context)
              .colorScheme
              .copyWith(primary: AppColors.amberDeep),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _expiryDate = picked);
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please give this certificate a name.');
      return;
    }
    if (_imagePaths.isEmpty) {
      setState(() => _error =
          'Please take or choose at least one photo of the certificate.');
      return;
    }
    if (_expiryDate == null) {
      setState(() => _error = 'Please set an expiry date.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await NotificationService.instance.requestPermissions();

      if (_isEditing) {
        final existing = widget.existing!;
        final keptExistingPaths =
            _imagePaths.where((p) => existing.imagePaths.contains(p)).toList();
        final removedPaths =
            existing.imagePaths.where((p) => !_imagePaths.contains(p)).toList();
        final newlyPickedPaths =
            _imagePaths.where((p) => !existing.imagePaths.contains(p)).toList();

        // Delete any pages the user removed during this edit.
        for (final path in removedPaths) {
          final file = File(path);
          if (await file.exists()) {
            try {
              await file.delete();
            } catch (_) {
              // Non-fatal - an orphaned file is a minor storage cost.
            }
          }
        }

        // Copy any newly added pages into permanent app storage.
        var finalImagePaths = keptExistingPaths;
        if (newlyPickedPaths.isNotEmpty) {
          final withNewPages = await CertificatesRepository.instance
              .addPages(existing.id, newlyPickedPaths);
          // addPages always appends new pages at the end of the *original*
          // stored list (unaffected by any removals we handled above), so
          // the newly copied paths are exactly the last N entries here.
          final newlyCopiedPaths = withNewPages.imagePaths.sublist(
              withNewPages.imagePaths.length - newlyPickedPaths.length);
          finalImagePaths = [...keptExistingPaths, ...newlyCopiedPaths];
        }

        final updated = existing.copyWith(
          name: name,
          imagePaths: finalImagePaths,
          expiryDate: _expiryDate!,
          notes: _notesController.text.trim(),
        );
        await CertificatesRepository.instance.update(updated);
      } else {
        await CertificatesRepository.instance.add(
          name: name,
          sourceImagePaths: _imagePaths,
          expiryDate: _expiryDate!,
          notes: _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = 'Could not save this certificate: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        title: Text(_isEditing ? 'Edit Certificate' : 'Add Certificate',
            style: AppText.headline(size: 18)),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PagesPicker(
              imagePaths: _imagePaths,
              onCamera: _takePhoto,
              onGallery: _uploadPhotos,
              onRemove: _removePage,
            ),
            const SizedBox(height: 20),
            Text('Certificate name',
                style: AppText.label(size: 11, color: AppColors.steel)),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              style: AppText.body(size: 15),
              decoration: _inputDecoration(
                  'e.g. Fire Equipment Service, Medical Certificate'),
            ),
            const SizedBox(height: 20),
            Text('Expiry date',
                style: AppText.label(size: 11, color: AppColors.steel)),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickExpiryDate,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.paperRaised,
                  border: Border.all(color: AppColors.line),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 18, color: AppColors.steel),
                    const SizedBox(width: 10),
                    Text(
                      _expiryDate == null
                          ? 'Select a date'
                          : '${_expiryDate!.day.toString().padLeft(2, '0')}/${_expiryDate!.month.toString().padLeft(2, '0')}/${_expiryDate!.year}',
                      style: AppText.body(
                          size: 15,
                          color: _expiryDate == null
                              ? AppColors.steel
                              : AppColors.ink),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Notes (optional)',
                style: AppText.label(size: 11, color: AppColors.steel)),
            const SizedBox(height: 6),
            TextField(
              controller: _notesController,
              style: AppText.body(size: 15),
              maxLines: 3,
              decoration: _inputDecoration(
                  'Any extra details, e.g. issuing body or reference number'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!,
                  style: AppText.label(size: 12, color: AppColors.red)),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.amberDeep,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text(_isEditing ? 'Save Changes' : 'Save Certificate'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: AppText.body(size: 14, color: AppColors.steel),
        filled: true,
        fillColor: AppColors.paperRaised,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: AppColors.line)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: AppColors.line)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: AppColors.amberDeep)),
      );
}

class _PagesPicker extends StatelessWidget {
  final List<String> imagePaths;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final void Function(int index) onRemove;

  const _PagesPicker({
    required this.imagePaths,
    required this.onCamera,
    required this.onGallery,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Photos',
                style: AppText.label(size: 11, color: AppColors.steel)),
            if (imagePaths.length > 1) ...[
              const SizedBox(width: 6),
              Text('(${imagePaths.length} pages)',
                  style: AppText.label(size: 11, color: AppColors.amberDeep)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        if (imagePaths.isEmpty)
          Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
                color: AppColors.paperRaised,
                border: Border.all(color: AppColors.line)),
            child: Center(
              child: Icon(Icons.description_outlined,
                  size: 36, color: AppColors.steel),
            ),
          )
        else
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: imagePaths.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) => _PageThumbnail(
                imagePath: imagePaths[index],
                pageNumber: index + 1,
                onRemove: () => onRemove(index),
              ),
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onCamera,
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: Text(imagePaths.isEmpty ? 'Take Photo' : 'Add Page'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ink,
                  side: BorderSide(color: AppColors.line),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onGallery,
                icon: const Icon(Icons.upload_outlined, size: 18),
                label: const Text('Upload'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ink,
                  side: BorderSide(color: AppColors.line),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
          ],
        ),
        if (imagePaths.length > 1) ...[
          const SizedBox(height: 6),
          Text(
            'You can select multiple photos from Upload at once, or add pages one at a time with Take Photo / Add Page.',
            style: AppText.label(size: 10, color: AppColors.steel),
          ),
        ],
      ],
    );
  }
}

class _PageThumbnail extends StatelessWidget {
  final String imagePath;
  final int pageNumber;
  final VoidCallback onRemove;

  const _PageThumbnail(
      {required this.imagePath,
      required this.pageNumber,
      required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 90,
          height: 110,
          decoration: BoxDecoration(border: Border.all(color: AppColors.line)),
          child: Image.file(File(imagePath),
              fit: BoxFit.cover, width: 90, height: 110),
        ),
        Positioned(
          left: 4,
          bottom: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            color: AppColors.ink.withValues(alpha: 0.75),
            child: Text('$pageNumber',
                style: AppText.label(size: 10, color: Colors.white)),
          ),
        ),
        Positioned(
          right: -2,
          top: -2,
          child: InkWell(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                  color: AppColors.red, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}
