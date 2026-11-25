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
  bool _savingSds = false;
  bool _openingBrowser = false;

  bool get _busy =>
      _searching || _savingSds || _openingBrowser;
  SdsResult? _result;
  String? _error;
  bool _errorIsQuota = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showError(
    String message, {
    bool isQuota = false,
  }) {
    if (!mounted) return;

    setState(() {
      _error = message;
      _errorIsQuota = isQuota;
    });
  }

  void _showNotice(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool _beginSearch() {
    if (!mounted || _busy) return false;

    if (SdsRepository.instance.isBusy) {
      _showError(
        'An SDS search is already running. '
        'Please wait for it to finish.',
      );
      return false;
    }

    FocusScope.of(context).unfocus();

    setState(() {
      _searching = true;
      _error = null;
      _errorIsQuota = false;
    });

    return true;
  }

  Future<bool> _checkConnection() async {
    final online = await ConnectivityService.instance
        .isOnline()
        .timeout(const Duration(seconds: 10));

    if (!mounted) return false;

    if (!online) {
      _showError(
        'You need an internet connection '
        'to search for an SDS.',
      );
    }

    return online;
  }

  Future<void> _runSearch(
    Future<SdsResult> Function() search,
  ) async {
    if (!mounted) return;

    final isPro =
        SubscriptionRepository.instance.isPro;

    setState(() {
      _result = null;
      _error = null;
      _errorIsQuota = false;
    });

    final result =
        await AdService.instance.runWithAd<SdsResult>(
      isPro: isPro,
      task: search,
    );

    if (!mounted) return;

    if (result == null) {
      _showError(
        "You'll need to watch the ad through "
        'to the end to see this result. '
        'Please try again.',
      );
      return;
    }

    setState(() {
      _result = result;
    });
  }

  Future<void> _searchByText() async {
    final query = _controller.text.trim();

    if (query.isEmpty) {
      if (!_busy) {
        _showError(
          'Please enter a product or chemical name.',
        );
      }
      return;
    }

    if (!_beginSearch()) return;

    try {
      if (!await _checkConnection()) return;
      if (!mounted) return;

      await _runSearch(
        () => SdsRepository.instance.findByText(query),
      );

    } on SdsException catch (error) {
      _showError(
        error.message,
        isQuota: error.isQuotaExceeded,
      );

    } catch (error) {
      debugPrint('SDS text search failed: $error');

      _showError(
        'Could not complete the SDS search. '
        'Please check your connection and try again.',
      );

    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  Future<void> _searchByPhoto() async {
    if (!_beginSearch()) return;

    final query = _controller.text.trim();

    try {
      if (!await _checkConnection()) return;
      if (!mounted) return;

      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 70,
        maxWidth: 1800,
        maxHeight: 1800,
      );

      if (!mounted || photo == null) return;

      final imageSize = await photo.length();

      if (!mounted) return;

      if (imageSize == 0) {
        _showError(
          'The photograph is empty. '
          'Please take another photo.',
        );
        return;
      }

      if (imageSize > 5 * 1024 * 1024) {
        _showError(
          'The photograph is too large. '
          'Please take another photo.',
        );
        return;
      }

      final bytes = await photo.readAsBytes();

      if (!mounted) return;

      if (bytes.length > 5 * 1024 * 1024) {
        _showError('The photograph is too large.');
        return;
      }

      final mediaType = _detectImageType(bytes);

      if (mediaType == null) {
        _showError(
          'Unsupported image format. '
          'Please use a JPEG or PNG photograph.',
        );
        return;
      }

      final encodedImage = base64Encode(bytes);

      await _runSearch(
        () => SdsRepository.instance.findByImage(
          imageBase64: encodedImage,
          imageMediaType: mediaType,
          query: query.isEmpty ? null : query,
        ),
      );

    } on SdsException catch (error) {
      _showError(
        error.message,
        isQuota: error.isQuotaExceeded,
      );

    } catch (error) {
      debugPrint('SDS photo search failed: $error');

      _showError(
        'Could not capture or process the photograph. '
        'Check your camera permissions and try again.',
      );

    } finally {
      if (mounted) {
        setState(() => _searching = false);
      }
    }
  }

  String? _detectImageType(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'image/jpeg';
    }

    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0D &&
        bytes[5] == 0x0A &&
        bytes[6] == 0x1A &&
        bytes[7] == 0x0A) {
      return 'image/png';
    }

    return null;
  }

  Uri? _validatedUri(String? value) {
    if (value == null) return null;

    final uri = Uri.tryParse(value.trim());

    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        (uri.scheme != 'https' &&
            uri.scheme != 'http')) {
      return null;
    }

    return uri;
  }

  bool _isPdf(List<int> bytes) {
    // PDF signature: %PDF-
    return bytes.length >= 5 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46 &&
        bytes[4] == 0x2D;
  }

  Future<void> _saveSds() async {
    if (!mounted || _busy) {
      throw StateError('Another operation is active.');
    }

    final result = _result;
    final uri = _validatedUri(result?.sdsUrl);

    if (result == null ||
        !result.found ||
        !result.directPdf ||
        uri == null) {
      _showNotice('No valid SDS download is available.');
      throw StateError('Invalid SDS download.');
    }

    setState(() => _savingSds = true);

    Directory? temporaryFolder;
    final client = http.Client();

    try {
      final response = await client.get(uri).timeout(
        const Duration(seconds: 45),
      );

      if (!mounted) {
        throw StateError('Download screen closed.');
      }

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        throw StateError(
          'Download failed (HTTP ${response.statusCode}).',
        );
      }

      if (!_isPdf(response.bodyBytes)) {
        throw StateError(
          'The website did not return a PDF document.',
        );
      }

      final tempDir = await getTemporaryDirectory();

      temporaryFolder = await tempDir.createTemp(
        'ohs_sds_',
      );

      final safeName = (result.productName ?? 'SDS')
          .replaceAll(RegExp(r'[^a-zA-Z0-9 _-]'), '')
          .trim();

      final fileName = safeName.isEmpty
          ? 'SDS'
          : safeName.length > 80
              ? safeName.substring(0, 80)
              : safeName;

      final tempFile = File(
        '${temporaryFolder.path}/$fileName.pdf',
      );

      await tempFile.writeAsBytes(
        response.bodyBytes,
        flush: true,
      );

      if (!mounted) {
        throw StateError('Download screen closed.');
      }

      if (await tempFile.length() != response.bodyBytes.length) {
        throw StateError('The prepared PDF is incomplete.');
      }

      if (!mounted ||
          ModalRoute.of(context)?.isCurrent != true) {
        throw StateError('Download screen closed.');
      }

      // The PDF is now retrieved, checked and prepared.
      await DownloadAllowanceService.instance.checkAndConsume();

      if (!mounted ||
          ModalRoute.of(context)?.isCurrent != true) {
        throw StateError('Download screen closed.');
      }

      final savedPath = await FlutterFileDialog.saveFile(
        params: SaveFileDialogParams(
          sourceFilePath: tempFile.path,
        ),
      );

      if (savedPath == null || savedPath.isEmpty) {
        throw StateError(
          'Save cancelled. Your download allowance was already used.',
        );
      }

      _showNotice('Safety Data Sheet saved successfully.');

    } on DownloadLimitException catch (error) {
      _showNotice(error.message);
      rethrow;

    } catch (error) {
      debugPrint('SDS download failed: $error');

      _showNotice(
        error is StateError
            ? error.message.toString()
            : 'Could not save this SDS. '
              'Please check your connection and try again.',
      );

      rethrow;

    } finally {
      client.close();

      if (temporaryFolder != null) {
        try {
          await temporaryFolder.delete(recursive: true);
        } catch (error) {
          debugPrint('SDS temporary file cleanup failed: $error');
        }
      }

      if (mounted) {
        setState(() => _savingSds = false);
      }
    }
  }

  Future<void> _openInBrowser() async {
    if (!mounted || _busy) return;

    final uri = _validatedUri(_result?.sdsUrl);

    if (uri == null) {
      _showNotice('No valid SDS link is available.');
      return;
    }

    setState(() => _openingBrowser = true);

    try {
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        _showNotice('Could not open the SDS website.');
      }

    } catch (error) {
      debugPrint('SDS browser launch failed: $error');
      _showNotice('Could not open the SDS website.');

    } finally {
      if (mounted) {
        setState(() => _openingBrowser = false);
      }
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
                    enabled: !_busy,
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
                  onPressed: _busy ? null : _searchByPhoto,
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
                onPressed: _busy ? null : _searchByText,
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
                onPressed: _busy ? null : _openInBrowser,
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
          IgnorePointer(
            ignoring: _busy,
            child: AnimatedDownloadButton(
              onDownload: _saveSds,
              idleLabel: 'Save SDS',
            ),
          ),
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
