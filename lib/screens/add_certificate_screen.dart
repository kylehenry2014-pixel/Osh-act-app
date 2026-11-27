import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../data/certificates_repository.dart';
import '../data/download_allowance_service.dart';
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
  bool _picking = false;
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
    if (_saving || _picking) return;

    setState(() {
      _picking = true;
      _error = null;
    });

    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );

      if (!mounted) return;

      if (picked != null) {
        setState(() {
          if (!_imagePaths.contains(picked.path)) {
            _imagePaths.add(picked.path);
          }
        });
      }
    } catch (_) {
      if (!mounted) return;

      setState(() => _error =
          'Could not access the camera. '
          'Check your device permissions.');
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  Future<void> _uploadPhotos() async {
    if (_saving || _picking) return;

    setState(() {
      _picking = true;
      _error = null;
    });

    try {
      final picked = await _picker.pickMultiImage(
        imageQuality: 85,
      );

      if (!mounted) return;

      if (picked.isNotEmpty) {
        setState(() {
          for (final image in picked) {
            if (!_imagePaths.contains(image.path)) {
              _imagePaths.add(image.path);
            }
          }
        });
      }
    } catch (_) {
      if (!mounted) return;

      setState(() => _error =
          'Could not access photos. '
          'Check your device permissions.');
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  void _removePage(int index) {
    if (_saving || _picking) return;

    if (index < 0 || index >= _imagePaths.length) {
      return;
    }

    // Remove only from the temporary editing list.
    // No permanent file is deleted here.
    setState(() {
      _imagePaths.removeAt(index);
      _error = null;
    });
  }

  Future<void> _pickExpiryDate() async {
    if (_saving || _picking) return;
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
              .copyWith(primary: AppPalette.of(context).accent, onPrimary: Theme.of(context).brightness == Brightness.dark ? AppColors.ink : Colors.white),
        ),
        child: child!,
      ),
    );
    if (mounted && picked != null) setState(() => _expiryDate = picked);
  }

  Future<void> _save() async {
    if (_saving || _picking) return;

    final name = _nameController.text.trim();
    final notes = _notesController.text.trim();
    final expiryDate = _expiryDate;
    final selectedPaths = List<String>.of(_imagePaths);

    if (name.isEmpty) {
      setState(() => _error =
          'Please give this certificate a name.');
      return;
    }

    if (selectedPaths.isEmpty) {
      setState(() => _error =
          'Please take or choose at least one photo.');
      return;
    }

    if (expiryDate == null) {
      setState(() => _error =
          'Please set an expiry date.');
      return;
    }

    // Lock before the first asynchronous operation.
    setState(() {
      _saving = true;
      _error = null;
    });

    FocusScope.of(context).unfocus();

    bool saved = false;

    try {
      // Validate selected files before using the allowance.
      for (final path in selectedPaths) {
        final file = File(path);

        if (!await file.exists() ||
            await file.length() == 0) {
          throw StateError(
            'A selected photo is missing or empty. '
            'Please remove or replace it.',
          );
        }
      }

      // Notification permission failures must not
      // prevent a customer from saving a certificate.
      try {
        await NotificationService.instance
            .requestPermissions();
      } catch (error) {
        debugPrint(
          'Certificate notification permission unavailable: $error',
        );
      }

      if (!mounted) return;

      if (_isEditing) {
        await CertificatesRepository.instance
            .editCertificate(
          certId: widget.existing!.id,
          name: name,
          selectedPaths: selectedPaths,
          expiryDate: expiryDate,
          notes: notes,
        );
      } else {
        // The repository consumes the allowance after
        // successfully preparing all certificate pages.
        await CertificatesRepository.instance.add(
          name: name,
          sourceImagePaths: selectedPaths,
          expiryDate: expiryDate,
          notes: notes.isEmpty ? null : notes,
        );
      }

      saved = true;
    } on DownloadLimitException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } catch (error) {
      debugPrint('Certificate save failed: $error');

      if (mounted) {
        setState(() => _error =
            'Could not save this certificate. '
            'Please check your selected photos and '
            'available device storage, then try again.');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }

    if (saved && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: PremiumSectionAppBar(
        automaticallyImplyLeading: false,
        leading: BackButton(
          onPressed: () {
            if (!_saving) Navigator.of(context).maybePop();
          },
        ),
        title: _isEditing ? 'Edit Certificate' : 'Add Certificate',
        titleSize: 18,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _PagesPicker(
              enabled: !_saving && !_picking,
              imagePaths: _imagePaths,
              onCamera: _takePhoto,
              onGallery: _uploadPhotos,
              onRemove: _removePage,
            ),
            const SizedBox(height: 20),
            Text('Certificate name',
                style: AppText.label(size: 11, color: AppPalette.of(context).secondaryText)),
            const SizedBox(height: 6),
            TextField(
              controller: _nameController,
              enabled: !_saving && !_picking,
              style: AppText.body(size: 15, color: AppPalette.of(context).text),
              decoration: _inputDecoration(
                  'e.g. Fire Equipment Service, Medical Certificate'),
            ),
            const SizedBox(height: 20),
            Text('Expiry date',
                style: AppText.label(size: 11, color: AppPalette.of(context).secondaryText)),
            const SizedBox(height: 6),
            InkWell(
              onTap: (_saving || _picking) ? null : _pickExpiryDate,
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: AppPalette.of(context).surface,
                  border: Border.all(color: AppPalette.of(context).border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined,
                        size: 18, color: AppPalette.of(context).secondaryText),
                    const SizedBox(width: 10),
                    Text(
                      _expiryDate == null
                          ? 'Select a date'
                          : '${_expiryDate!.day.toString().padLeft(2, '0')}/${_expiryDate!.month.toString().padLeft(2, '0')}/${_expiryDate!.year}',
                      style: AppText.body(
                          size: 15,
                          color: _expiryDate == null
                              ? AppPalette.of(context).secondaryText
                              : AppPalette.of(context).text),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text('Notes (optional)',
                style: AppText.label(size: 11, color: AppPalette.of(context).secondaryText)),
            const SizedBox(height: 6),
            TextField(
              controller: _notesController,
              enabled: !_saving && !_picking,
              style: AppText.body(size: 15, color: AppPalette.of(context).text),
              maxLines: 3,
              decoration: _inputDecoration(
                  'Any extra details, e.g. issuing body or reference number'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!,
                  style: AppText.label(size: 12, color: AppPalette.of(context).error)),
            ],
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: (_saving || _picking) ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppPalette.of(context).accent,
                  foregroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.ink : Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2)),
                ),
                child: _saving
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Theme.of(context).brightness == Brightness.dark ? AppColors.ink : Colors.white))
                    : Text(_isEditing ? 'Save Changes' : 'Save Certificate'),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle: AppText.body(size: 14, color: AppPalette.of(context).secondaryText),
        filled: true,
        fillColor: AppPalette.of(context).surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: AppPalette.of(context).border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: AppPalette.of(context).border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: AppPalette.of(context).accent)),
      );
}

class _PagesPicker extends StatelessWidget {
  final List<String> imagePaths;
  final bool enabled;
  final VoidCallback onCamera;
  final VoidCallback onGallery;
  final void Function(int index) onRemove;

  const _PagesPicker({
    required this.imagePaths,
    required this.enabled,
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
                style: AppText.label(size: 11, color: AppPalette.of(context).secondaryText)),
            if (imagePaths.length > 1) ...[
              const SizedBox(width: 6),
              Text('(${imagePaths.length} pages)',
                  style: AppText.label(size: 11, color: AppPalette.of(context).accent)),
            ],
          ],
        ),
        const SizedBox(height: 6),
        if (imagePaths.isEmpty)
          Container(
            height: 140,
            width: double.infinity,
            decoration: BoxDecoration(
                color: AppPalette.of(context).surface,
                border: Border.all(color: AppPalette.of(context).border)),
            child: Center(
              child: Icon(Icons.description_outlined,
                  size: 36, color: AppPalette.of(context).secondaryText),
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
                onRemove: enabled ? () => onRemove(index) : null,
              ),
            ),
          ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: enabled ? onCamera : null,
                icon: const Icon(Icons.camera_alt_outlined, size: 18),
                label: Text(imagePaths.isEmpty ? 'Take Photo' : 'Add Page'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppPalette.of(context).text,
                  side: BorderSide(color: AppPalette.of(context).border),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: enabled ? onGallery : null,
                icon: const Icon(Icons.upload_outlined, size: 18),
                label: const Text('Upload'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppPalette.of(context).text,
                  side: BorderSide(color: AppPalette.of(context).border),
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
            style: AppText.label(size: 10, color: AppPalette.of(context).secondaryText),
          ),
        ],
      ],
    );
  }
}

class _PageThumbnail extends StatelessWidget {
  final String imagePath;
  final int pageNumber;
  final VoidCallback? onRemove;

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
          decoration: BoxDecoration(border: Border.all(color: AppPalette.of(context).border)),
          child: Image.file(
            File(imagePath),
            fit: BoxFit.cover,
            width: 90,
            height: 110,
            errorBuilder: (_, __, ___) => Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: AppPalette.of(context).secondaryText,
              ),
            ),
          ),
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
