import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import '../data/ad_service.dart';
import '../data/connectivity_service.dart';
import '../data/download_allowance_service.dart';
import '../data/sds_repository.dart';
import '../data/subscription_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_download_button.dart';

class SdsScreen extends StatefulWidget {
  const SdsScreen({super.key});

  @override
  State<SdsScreen> createState() => _SdsScreenState();
}

class _SdsScreenState extends State<SdsScreen> {
  final _controller = TextEditingController();
  bool _searching = false;
  SdsResult? _result;
  String? _error;
  bool _errorIsQuota = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runSearch(Future<SdsResult> Function() search) async {
    final isPro = SubscriptionRepository.instance.isPro;

    setState(() {
      _searching = true;
      _error = null;
      _errorIsQuota = false;
      _result = null;
    });

    try {
      final result = await AdService.instance.runWithAd<SdsResult>(
        isPro: isPro,
        task: search,
      );

      if (!mounted) return;

      if (result == null) {
        setState(() {
          _searching = false;
          _error =
              "You'll need to watch the ad through to the end to see this result. Please try again.";
        });
        return;
      }

      setState(() {
        _searching = false;
        _result = result;
      });
    } on SdsException catch (e) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _error = e.message;
        _errorIsQuota = e.isQuotaExceeded;
      });
    }
  }

  Future<void> _searchByText() async {
    final query = _controller.text.trim();
    if (query.isEmpty || _searching) return;

    final online = await ConnectivityService.instance.isOnline();
    if (!online) {
      if (mounted) {
        setState(() =>
            _error = 'You need an internet connection to search for an SDS.');
      }
      return;
    }

    await _runSearch(() => SdsRepository.instance.findByText(query));
  }

  Future<void> _searchByPhoto() async {
    if (_searching) return;
    final online = await ConnectivityService.instance.isOnline();
    if (!online) {
      if (mounted) {
        setState(() =>
            _error = 'You need an internet connection to search for an SDS.');
      }
      return;
    }

    final picker = ImagePicker();
    final photo =
        await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (photo == null) return;

    await _runSearch(() async {
      final bytes = await File(photo.path).readAsBytes();
      final base64Image = base64Encode(bytes);
      return SdsRepository.instance.findByImage(
        imageBase64: base64Image,
        imageMediaType: 'image/jpeg',
        query: _controller.text.trim().isEmpty ? null : _controller.text.trim(),
      );
    });
  }

  Future<void> _saveSds() async {
    final result = _result;
    if (result == null || result.sdsUrl == null) return;

    // Shared daily download allowance (2/day free, 20/day Pro) - checked
    // first, before starting the actual download.
    try {
      await DownloadAllowanceService.instance.checkAndConsume();
    } on DownloadLimitException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }
      return;
    }

    try {
      final response = await http.get(Uri.parse(result.sdsUrl!));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Download failed (HTTP ${response.statusCode})');
      }
      final tempDir = await getTemporaryDirectory();
      final safeName = (result.productName ?? 'SDS')
          .replaceAll(RegExp(r'[^a-zA-Z0-9 ]'), '')
          .trim();
      final tempFile = File(
        '${tempDir.path}/${safeName.isEmpty ? 'SDS' : safeName}.pdf',
      );
      await tempFile.writeAsBytes(response.bodyBytes);
      await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(sourceFilePath: tempFile.path),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save this SDS: $e')),
        );
      }
      rethrow;
    }
  }

  Future<void> _openInBrowser() async {
    final url = _result?.sdsUrl;
    if (url == null) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        title: Text('SDS Finder', style: AppText.headline(size: 20)),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Type a product and brand, or photograph the container label, to find its official Safety Data Sheet.',
              style: AppText.body(size: 14, color: AppColors.steel),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    enabled: !_searching,
                    style: AppText.body(size: 14),
                    decoration: InputDecoration(
                      hintText: 'e.g. petrol by Engen',
                      hintStyle: AppText.body(size: 14, color: AppColors.steel),
                      filled: true,
                      fillColor: AppColors.paperRaised,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: AppColors.line),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: AppColors.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.zero,
                        borderSide: BorderSide(color: AppColors.amberDeep),
                      ),
                    ),
                    onSubmitted: (_) => _searchByText(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _searching ? null : _searchByPhoto,
                  icon: const Icon(Icons.camera_alt_outlined),
                  color: AppColors.amberDeep,
                  tooltip: 'Photograph the label',
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _searching ? null : _searchByText,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.ink,
                  foregroundColor: AppColors.paperRaised,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _searching
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text('Search',
                        style: AppText.label(
                            size: 12, color: AppColors.paperRaised)),
              ),
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: (_errorIsQuota ? AppColors.amberDeep : AppColors.red)
                    .withValues(alpha: 0.1),
                child: Row(
                  children: [
                    Icon(
                      _errorIsQuota
                          ? Icons.hourglass_bottom
                          : Icons.error_outline,
                      size: 16,
                      color:
                          _errorIsQuota ? AppColors.amberDeep : AppColors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: AppText.label(
                            size: 12,
                            color: _errorIsQuota
                                ? AppColors.amberDeep
                                : AppColors.red,
                          )),
                    ),
                  ],
                ),
              ),
            if (_result != null) _buildResult(_result!),
          ],
        ),
      ),
    );
  }

  Widget _buildResult(SdsResult result) {
    if (!result.found) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppColors.paperRaised,
            border: Border.all(color: AppColors.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Not found',
                style: AppText.headline(size: 15, weight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(result.message,
                style: AppText.body(size: 13, color: AppColors.steel)),
          ],
        ),
      );
    }

    if (!result.directPdf) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppColors.paperRaised,
            border: Border.all(color: AppColors.line)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: SizedBox(
                width: 140,
                height: 110,
                child: CustomPaint(painter: _PixelRobotPainter()),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Beep boop, access denied.',
              style: AppText.headline(size: 15, weight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Text(
              "This site doesn't trust bots (rude, but fair - I am one). I found ${result.productName ?? 'the product'}'s SDS, but couldn't grab it automatically. Tap below to open it yourself.",
              style: AppText.body(size: 13, color: AppColors.steel),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _openInBrowser,
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Open SDS in browser'),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppColors.paperRaised,
          border: Border.all(color: AppColors.line)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(result.productName ?? 'Safety Data Sheet',
              style: AppText.headline(size: 16, weight: FontWeight.w600)),
          if (result.manufacturer != null) ...[
            const SizedBox(height: 3),
            Text(result.manufacturer!, style: AppText.label(size: 11)),
          ],
          const SizedBox(height: 10),
          Text(result.message,
              style: AppText.body(size: 13, color: AppColors.steel)),
          const SizedBox(height: 14),
          AnimatedDownloadButton(onDownload: _saveSds, idleLabel: 'Save SDS'),
        ],
      ),
    );
  }
}

/// A small retro pixel-art robot for the "bot blocked" fallback state -
/// teal blocky head, one crossed-out eye, flat mouth, antenna.
class _PixelRobotPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final sx = size.width / 380;
    final sy = size.height / 300;
    Rect r(double x, double y, double w, double h) =>
        Rect.fromLTWH(x * sx, y * sy, w * sx, h * sy);

    final body = Paint()..color = AppColors.amberDeep;
    final dark = Paint()..color = AppColors.ink;
    final light = Paint()..color = Colors.white;
    final accent = Paint()..color = AppColors.red;

    canvas.drawRect(r(130, 40, 20, 20), dark);
    canvas.drawRect(r(130, 60, 20, 20), body);
    canvas.drawRect(r(110, 80, 160, 140), body);
    canvas.drawRect(r(110, 80, 160, 20), dark);
    canvas.drawRect(r(110, 200, 160, 20), dark);
    canvas.drawRect(r(110, 80, 20, 140), dark);
    canvas.drawRect(r(250, 80, 20, 140), dark);
    canvas.drawRect(r(70, 140, 20, 60), dark);
    canvas.drawRect(r(290, 140, 20, 60), dark);

    canvas.drawRect(r(150, 120, 20, 20), light);
    canvas.save();
    canvas.translate(160 * sx, 130 * sy);
    canvas.rotate(0.785398);
    canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: 30 * sx, height: 6 * sy),
        accent);
    canvas.rotate(-1.570796);
    canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: 30 * sx, height: 6 * sy),
        accent);
    canvas.restore();

    canvas.drawRect(r(210, 120, 20, 20), dark);
    canvas.drawRect(r(216, 126, 8, 8), light);

    canvas.drawRect(r(150, 170, 80, 14), dark);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
