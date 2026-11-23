import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import '../data/ad_service.dart';
import '../data/download_allowance_service.dart';
import '../data/saved_documents_repository.dart';
import '../data/signage_repository.dart';
import '../data/subscription_repository.dart';
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
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
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
    if (!SubscriptionRepository.instance.isPro) {
      final adCount =
          await AdService.instance.nextRequiredAdCount(_openFeatureKey);
      if (!mounted) return;
      final confirmed = await _confirmWatchAd();
      if (confirmed != true) return;

      final earned = await AdService.instance.watchAds(adCount);
      if (!mounted) return;
      if (!earned) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                "You'll need to watch the ad through to the end to open this sign."),
          ),
        );
        return;
      }
      await AdService.instance.recordUnlockedRequest(_openFeatureKey);
      if (!mounted) return;
    }

    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SignDetailScreen(sign: sign),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        title: Text('Signage', style: AppText.headline(size: 18)),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.amberDeep));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!,
                  style: AppText.body(), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _load,
                child: Text('Try again',
                    style: AppText.label(size: 12, color: AppColors.amberDeep)),
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
            style: AppText.label(size: 12),
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
              style: AppText.label(size: 11, color: AppColors.amberDeep),
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
                onTap: () => _openSign(signs[i]),
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
  final VoidCallback onTap;
  const _SignCard({required this.sign, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.paperRaised,
          border: Border.all(color: AppColors.line),
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
                  errorBuilder: (context, error, stack) => const Icon(
                    Icons.image_not_supported_outlined,
                    color: AppColors.steel,
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
                style: AppText.headline(size: 13, weight: FontWeight.w600),
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

  Future<void> _download() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      await DownloadAllowanceService.instance.checkAndConsume();

      final sign = widget.sign;
      final data = await rootBundle.load(sign.file);
      final dir = await getTemporaryDirectory();
      final ext = sign.file.contains('.') ? sign.file.split('.').last : 'webp';
      final tmp = File('${dir.path}/${sign.id}.$ext');
      await tmp.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );

      await SavedDocumentsRepository.instance.saveDocument(
        sourcePath: tmp.path,
        name: sign.label,
        category: 'Signage',
      );
      try {
        await tmp.delete();
      } catch (_) {}

      _snack('Saved to My Documents.');
    } on DownloadLimitException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not save this sign. Please try again.');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sign = widget.sign;
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        title: Text('Signage', style: AppText.headline(size: 18)),
        iconTheme: const IconThemeData(color: AppColors.ink),
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
                color: AppColors.paperRaised,
                border: Border.all(color: AppColors.line),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Center(
                child: Image.asset(
                  sign.file,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) => const Icon(
                    Icons.image_not_supported_outlined,
                    size: 48,
                    color: AppColors.steel,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              sign.group.toUpperCase(),
              style: AppText.label(size: 11, color: AppColors.amberDeep),
            ),
            const SizedBox(height: 6),
            Text(sign.label, style: AppText.headline(size: 20)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _downloading ? null : _download,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.ink,
                  foregroundColor: AppColors.paperRaised,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(2),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _downloading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.paperRaised,
                        ),
                      )
                    : Text('Save to My Documents',
                        style: AppText.label(
                            size: 12, color: AppColors.paperRaised)),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Generic guidance only. Safety signs must comply with the '
              'applicable SANS standards (for example SANS 1186) and your '
              'site risk assessment. Check the requirements before you '
              'display a sign.',
              style: AppText.label(size: 10.5),
            ),
          ],
        ),
      ),
    );
  }
}
