import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:path_provider/path_provider.dart';
import '../data/ad_service.dart';
import '../data/document_integrity.dart';
import '../data/download_allowance_service.dart';
import '../data/saved_documents_repository.dart';
import '../data/signage_repository.dart';
import '../data/subscription_repository.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

class SignageScreen extends StatefulWidget {
  const SignageScreen({super.key});

  @override
  State<SignageScreen> createState() => _SignageScreenState();
}

class _SignageScreenState extends State<SignageScreen> {
  static const _openFeatureKey = 'signage_open';

  final _repo = SignageRepository.instance;
  bool _loading = true;
  bool _openingSign = false;
  bool _loadInProgress = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted || _loadInProgress) return;
    _loadInProgress = true;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _repo.load();
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load the signage library. Please try again.';
      });
    } finally {
      _loadInProgress = false;
    }
  }

  Future<bool?> _confirmWatchAd() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Watch an ad to continue'),
        content: const Text('Watch a short ad to open this sign.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Watch'),
          ),
        ],
      ),
    );
  }

  Future<void> _openSign(SafetySign sign) async {
    if (!mounted || _openingSign || _loading) return;

    setState(() => _openingSign = true);

    try {
      if (!SubscriptionRepository.instance.isPro) {
        final adCount = await AdService.instance
            .nextRequiredAdCount(_openFeatureKey);

        if (!mounted ||
            ModalRoute.of(context)?.isCurrent != true) {
          return;
        }

        final confirmed = await _confirmWatchAd();

        if (!mounted || confirmed != true) return;

        final earned =
            await AdService.instance.watchAds(adCount);

        if (!mounted) return;

        if (!earned) {
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            const SnackBar(
              content: Text(
                "You'll need to complete the required ads "
                "to open this sign.",
              ),
            ),
          );
          return;
        }

        await AdService.instance
            .recordUnlockedRequest(_openFeatureKey);
      }

      if (!mounted ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SignDetailScreen(sign: sign),
        ),
      );
    } catch (error) {
      debugPrint('Sign opening failed: $error');

      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Could not open this sign. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _openingSign = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: const PremiumSectionAppBar(
        title: 'Signage',
        titleSize: 18,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return Center(
          child: CircularProgressIndicator(color: AppPalette.of(context).accent));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  style: AppText.body(color: AppPalette.of(context).text), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _load,
                child: Text('Try again',
                    style: AppText.label(size: 12, color: AppPalette.of(context).accent)),
              ),
            ],
          ),
        ),
      );
    }

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
          child: Text(
            '${_repo.all.length} safety signs - tap a sign to open it',
            style: AppText.label(size: 12, color: AppPalette.of(context).secondaryText),
          ),
        ),
      ),
    ];

    for (final group in _repo.groups) {
      final signs = _repo.signsInGroup(group);
      if (signs.isEmpty) continue;
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 8),
            child: Text(
              group.toUpperCase(),
              style: AppText.label(size: 11, color: AppPalette.of(context).accent),
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _SignCard(
                sign: signs[i],
                onTap: _openingSign ? null : () => _openSign(signs[i]),
              ),
              childCount: signs.length,
            ),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
          ),
        ),
      );
    }
    slivers.add(const SliverToBoxAdapter(child: SizedBox(height: 24)));

    return CustomScrollView(slivers: slivers);
  }
}

class _SignCard extends StatelessWidget {
  final SafetySign sign;
  final VoidCallback? onTap;
  const _SignCard({required this.sign, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppPalette.of(context).surface,
          border: Border.all(color: AppPalette.of(context).border),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Image.asset(
                  sign.file,
                  fit: BoxFit.contain,
                  cacheWidth: 360,
                  errorBuilder: (context, error, stack) => Icon(
                    AppIcons.imageNotSupportedOutlined,
                    color: AppPalette.of(context).secondaryText,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Text(
                sign.label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppText.headline(size: 13, weight: FontWeight.w600).copyWith(color: AppPalette.of(context).text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SignDetailScreen extends StatefulWidget {
  final SafetySign sign;
  const SignDetailScreen({super.key, required this.sign});

  @override
  State<SignDetailScreen> createState() => _SignDetailScreenState();
}

class _SignDetailScreenState extends State<SignDetailScreen> {
  bool _downloading = false;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Converts the bundled WebP sign into PNG bytes, which every phone gallery,
  /// printer app and document editor can open.
  Future<Uint8List> _assetAsPng(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final bytes =
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final codec = await ui.instantiateImageCodec(bytes);

    try {
      final frame = await codec.getNextFrame();

      try {
        final byteData = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );

        if (byteData == null) {
          throw StateError('Could not convert the sign to PNG');
        }

        return byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        );
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  /// A safe file name made from the sign label, for example "No_smoking".
  String _safeFileName(String label, String fallback) {
    final cleaned = label
        .replaceAll(RegExp(r'[^A-Za-z0-9 _-]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    if (cleaned.isEmpty) return fallback;
    return cleaned.length > 60 ? cleaned.substring(0, 60) : cleaned;
  }

  Future<void> _download() async {
    if (!mounted || _downloading) return;
    setState(() => _downloading = true);

    Directory? temporaryFolder;

    try {
      final sign = widget.sign;
      final png = await _assetAsPng(sign.file);
      final fileName = _safeFileName(sign.label, sign.id);
      final dir = await getTemporaryDirectory();
      final folder = await dir.createTemp('ohs_sign_');
      temporaryFolder = folder;

      final tmp = File('${folder.path}/$fileName.png');
      await tmp.writeAsBytes(png, flush: true);

      if (png.isEmpty || await tmp.length() != png.length) {
        throw StateError('The prepared sign is incomplete.');
      }

      await DocumentIntegrity.validateFile(
        tmp,
        expectedExtension: 'png',
      );

      // Check local document storage before consuming allowance.
      await SavedDocumentsRepository.instance.load();

      if (!mounted ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }

      final allowance = await DownloadAllowanceService.instance
          .checkAndConsume(feature: 'signage');

      // Keep a copy inside the app (My Documents) ...
      await SavedDocumentsRepository.instance.saveDocument(
        sourcePath: tmp.path,
        name: sign.label,
        category: 'Signage',
      );

      // ... and let the user save a copy to the phone itself (Downloads,
      // Pictures, or any folder) through the system save dialog.
      if (!mounted ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }

      String? savedPath;
      bool externalExportFailed = false;

      try {
        savedPath = await FlutterFileDialog.saveFile(
          params: SaveFileDialogParams(
            sourceFilePath: tmp.path,
            fileName: '$fileName.png',
          ),
        );
      } catch (error) {
        debugPrint('External sign export failed: $error');
        externalExportFailed = true;
        savedPath = null;
      }

      final left = allowance.remaining;
      final leftText = allowance.limit > 0 && left >= 0
          ? ' $left of ${allowance.limit} signage downloads left today.'
          : '';
      final String outcomeMessage;

      if (externalExportFailed) {
        outcomeMessage =
            'Saved to My Documents, but the phone export failed.';
      } else if (savedPath != null && savedPath.isNotEmpty) {
        outcomeMessage =
            'Saved to your phone and My Documents.';
      } else {
        outcomeMessage =
            'Saved to My Documents. Phone export cancelled.';
      }

      _snack(outcomeMessage + leftText);
    } on DownloadLimitException catch (e) {
      _snack(e.message);
    } catch (error) {
      debugPrint('Sign download failed: $error');
      _snack('Could not save this sign. Please try again.');
    } finally {
      try {
        await temporaryFolder?.delete(recursive: true);
      } catch (error) {
        debugPrint('Temporary sign cleanup failed: $error');
      }

      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sign = widget.sign;
    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: const PremiumSectionAppBar(
        title: 'Signage',
        titleSize: 18,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 300,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppPalette.of(context).surface,
                border: Border.all(color: AppPalette.of(context).border),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Center(
                child: Image.asset(
                  sign.file,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => Icon(
                    AppIcons.imageNotSupportedOutlined,
                    size: 48,
                    color: AppPalette.of(context).secondaryText,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              sign.group.toUpperCase(),
              style: AppText.label(size: 11, color: AppPalette.of(context).accent),
            ),
            const SizedBox(height: 6),
            Text(sign.label, style: AppText.headline(size: 20).copyWith(color: AppPalette.of(context).text)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _downloading ? null : _download,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).brightness == Brightness.dark ? AppPalette.of(context).accent : AppColors.ink,
                  foregroundColor: Theme.of(context).brightness == Brightness.dark ? AppColors.ink : AppColors.paperRaised,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(2),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _downloading
                    ? SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).brightness == Brightness.dark ? AppColors.ink : AppColors.paperRaised,
                        ),
                      )
                    : Text('Download',
                        style: AppText.label(
                            size: 12, color: Theme.of(context).brightness == Brightness.dark ? AppColors.ink : AppColors.paperRaised)),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Free: 2 signage downloads a day. Pro: 5 a day.',
                style: AppText.label(size: 11, color: AppPalette.of(context).secondaryText),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Generic guidance only. Safety signs must comply with the '
              'applicable SANS standards (for example SANS 1186) and your '
              'site risk assessment. Check the requirements before you '
              'display a sign.',
              style: AppText.label(size: 10.5, color: AppPalette.of(context).secondaryText),
            ),
          ],
        ),
      ),
    );
  }
}