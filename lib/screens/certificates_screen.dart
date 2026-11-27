import 'dart:io';
import 'package:flutter/material.dart';
import '../data/certificates_repository.dart';
import '../models/certificate.dart';
import '../theme/app_theme.dart';
import 'add_certificate_screen.dart';

/// Lists all saved certificates, colour-coded by expiry status (valid /
/// expiring soon / expired), soonest expiry first. Tap to view full-size
/// with edit/delete; the "+" button adds a new one via camera or upload.
/// A certificate can span multiple photo pages (e.g. a full medical pack).
class CertificatesScreen extends StatefulWidget {
  const CertificatesScreen({super.key});

  @override
  State<CertificatesScreen> createState() => _CertificatesScreenState();
}

class _CertificatesScreenState extends State<CertificatesScreen> {
  Future<void> _openAdd() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const AddCertificateScreen()),
    );
    if (mounted && saved == true) setState(() {});
  }

  Future<void> _openDetail(Certificate cert) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => _CertificateDetailScreen(certificate: cert)),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final certs = CertificatesRepository.instance.all;

    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: PremiumSectionAppBar(
        title: 'Certificate Reminders',
        titleSize: 18,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAdd,
        backgroundColor: AppPalette.of(context).accent,
        foregroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.ink : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        child: const Icon(Icons.add),
      ),
      body: certs.isEmpty
          ? _EmptyState(onAdd: _openAdd)
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
              itemCount: certs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) => _CertificateCard(
                certificate: certs[index],
                onTap: () => _openDetail(certs[index]),
              ),
            ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.badge_outlined, size: 40, color: AppPalette.of(context).secondaryText),
            const SizedBox(height: 16),
            Text(
              'No certificates saved yet. Add photos of a certificate - even a multi-page one like a full medical pack - and set its expiry date, and this app will remind you before it lapses.',
              textAlign: TextAlign.center,
              style: AppText.body(size: 14, color: AppPalette.of(context).secondaryText),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add Certificate'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppPalette.of(context).accent,
                foregroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.ink : Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CertificateCard extends StatelessWidget {
  final Certificate certificate;
  final VoidCallback onTap;

  const _CertificateCard({required this.certificate, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final (statusColor, statusLabel) = _statusInfo(context, certificate);
    final pageCount = certificate.imagePaths.length;

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppPalette.of(context).surface,
          border: Border.all(color: AppPalette.of(context).border),
        ),
        child: Row(
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: Image.file(
                    File(certificate.imagePaths.isEmpty ? '' : certificate.imagePaths.first),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 56,
                      height: 56,
                      color: AppPalette.of(context).border,
                      child: Icon(Icons.description_outlined,
                          color: AppPalette.of(context).secondaryText),
                    ),
                  ),
                ),
                if (pageCount > 1)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.ink,
                          borderRadius: BorderRadius.circular(8)),
                      child: Text('$pageCount',
                          style: AppText.label(size: 9, color: Colors.white)),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(certificate.name,
                      style:
                          AppText.headline(size: 15, weight: FontWeight.w600).copyWith(color: AppPalette.of(context).text)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: statusColor, shape: BoxShape.circle)),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(statusLabel,
                              style:
                                  AppText.label(size: 11, color: statusColor))),
                    ],
                  ),
                  if (pageCount > 1) ...[
                    const SizedBox(height: 2),
                    Text('$pageCount pages',
                        style: AppText.label(size: 10, color: AppPalette.of(context).secondaryText)),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppPalette.of(context).secondaryText),
          ],
        ),
      ),
    );
  }

  (Color, String) _statusInfo(BuildContext context, Certificate cert) {
    final days = cert.daysUntilExpiry;
    switch (cert.status) {
      case CertificateStatus.expired:
        return (
          AppPalette.of(context).error,
          'Expired ${-days} day${-days == 1 ? '' : 's'} ago'
        );
      case CertificateStatus.expiringSoon:
        return (
          AppPalette.of(context).accent,
          'Expires in $days day${days == 1 ? '' : 's'}'
        );
      case CertificateStatus.valid:
        return (AppPalette.of(context).success, 'Valid - expires in $days days');
    }
  }
}

class _CertificateDetailScreen extends StatefulWidget {
  final Certificate certificate;
  const _CertificateDetailScreen({required this.certificate});

  @override
  State<_CertificateDetailScreen> createState() =>
      _CertificateDetailScreenState();
}

class _CertificateDetailScreenState extends State<_CertificateDetailScreen> {
  late Certificate _certificate;
  int _pageIndex = 0;
  bool _deleting = false;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _certificate = widget.certificate;
  }

  Future<void> _edit() async {
    if (_deleting || _editing) return;

    setState(() => _editing = true);

    try {
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => AddCertificateScreen(
            existing: _certificate,
          ),
        ),
      );

      if (!mounted || saved != true) return;

      for (final certificate
          in CertificatesRepository.instance.all) {
        if (certificate.id == _certificate.id) {
          setState(() {
            _certificate = certificate;
            _pageIndex = 0;
          });
          break;
        }
      }
    } finally {
      if (mounted) {
        setState(() => _editing = false);
      }
    }
  }

  Future<void> _confirmDelete() async {
    if (_deleting || _editing) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete certificate?', style: AppText.headline(size: 17).copyWith(color: AppPalette.of(context).text)),
        content: Text(
          'This will permanently delete "${_certificate.name}" and all ${_certificate.imagePaths.length > 1 ? '${_certificate.imagePaths.length} of its saved photos' : 'its saved photo'}. This cannot be undone.',
          style: AppText.body(size: 14, color: AppPalette.of(context).text),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete', style: TextStyle(color: AppPalette.of(context).error)),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _deleting) {
      return;
    }

    setState(() => _deleting = true);

    bool deleted = false;

    try {
      await CertificatesRepository.instance
          .delete(_certificate.id);

      deleted = true;
    } catch (error) {
      debugPrint('Certificate deletion failed: $error');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not delete the certificate. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }

    if (deleted && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cert = _certificate;
    final pages = cert.imagePaths;

    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: PremiumSectionAppBar(
        title: cert.name,
        titleSize: 17,
        actions: [
          IconButton(icon: const Icon(Icons.edit_outlined), onPressed: (_deleting || _editing) ? null : _edit),
          IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: (_deleting || _editing) ? null : _confirmDelete),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (pages.length > 1) ...[
              Text('Page ${_pageIndex + 1} of ${pages.length}',
                  style: AppText.label(size: 11, color: AppPalette.of(context).secondaryText)),
              const SizedBox(height: 6),
            ],
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: pages.isEmpty
                  ? const Center(
                      child: Text('No certificate photos available.'),
                    )
                  : Image.file(
                      File(pages[_pageIndex]),
                      width: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text(
                            'This certificate photo is unavailable.',
                          ),
                        ),
                      ),
                    ),
            ),
            if (pages.length > 1) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 70,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: pages.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) => InkWell(
                    onTap: () => setState(() => _pageIndex = index),
                    child: Container(
                      width: 56,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: index == _pageIndex
                              ? AppPalette.of(context).accent
                              : AppPalette.of(context).border,
                          width: index == _pageIndex ? 2 : 1,
                        ),
                      ),
                      child: Image.file(File(pages[index]), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Text('Expiry date',
                style: AppText.label(size: 11, color: AppPalette.of(context).secondaryText)),
            const SizedBox(height: 4),
            Text(
              '${cert.expiryDate.day.toString().padLeft(2, '0')}/${cert.expiryDate.month.toString().padLeft(2, '0')}/${cert.expiryDate.year}',
              style: AppText.body(size: 16, color: AppPalette.of(context).text),
            ),
            if (cert.notes != null && cert.notes!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Notes',
                  style: AppText.label(size: 11, color: AppPalette.of(context).secondaryText)),
              const SizedBox(height: 4),
              Text(cert.notes!, style: AppText.body(size: 14, color: AppPalette.of(context).text)),
            ],
          ],
        ),
      ),
    );
  }
}
