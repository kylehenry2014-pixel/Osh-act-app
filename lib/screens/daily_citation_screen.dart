import 'package:flutter/material.dart';
import '../data/daily_citation_service.dart';
import '../theme/app_theme.dart';

class DailyCitationScreen extends StatefulWidget {
  const DailyCitationScreen({super.key});

  @override
  State<DailyCitationScreen> createState() => _DailyCitationScreenState();
}

class _DailyCitationScreenState extends State<DailyCitationScreen> {
  final _service = DailyCitationService.instance;
  late final List<CitationSource> _sources;
  bool _loading = true;
  bool _busy = false;
  String? _loadError;
  bool _enabled = false;
  Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _sources = _service.availableSources();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final enabled = await _service.isEnabled();
      final selected = await _service.selectedSources();

      if (!mounted) return;

      setState(() {
        _enabled = enabled;
        _selected = selected;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _loadError = 'Could not load daily citation settings.';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _snack(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _runOperation(
    Future<void> Function() operation,
  ) async {
    if (!mounted || _busy || _loading) return;

    setState(() => _busy = true);

    try {
      await operation();
    } catch (_) {
      if (!mounted) return;

      await _load();

      _snack(
        'Could not complete the citation update. '
        'Check your settings and try again.',
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _toggle(bool value) {
    return _runOperation(() async {
      final result = await _service.setEnabled(value);

      if (!mounted) return;

      await _load();

      if (value && !result) {
        _snack(
          'Allow notifications in your phone settings, '
          'then try again.',
        );
      }
    });
  }

  Future<void> _toggleSource(String key, bool value) {
    return _runOperation(() async {
      final next = Set<String>.from(_selected);

      if (value) {
        next.add(key);
      } else {
        if (next.length <= 1) {
          _snack('Keep at least one Act selected.');
          return;
        }

        next.remove(key);
      }

      await _service.setSelectedSources(next);

      if (!mounted) return;

      setState(() => _selected = next);
    });
  }

  Future<void> _sendTest() {
    return _runOperation(() async {
      final ok = await _service.sendTest();

      _snack(ok
          ? 'Test notification sent.'
          : 'Could not send a test notification. '
              'Check your notification permissions.');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.of(context).background,
      appBar: const PremiumSectionAppBar(
        title: 'Daily Citation',
        titleSize: 18,
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: AppPalette.of(context).accent))
          : _loadError != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _loadError!,
                          textAlign: TextAlign.center,
                          style: AppText.body(color: AppPalette.of(context).text),
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton(
                          onPressed: _busy ? null : _load,
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  'Get one section from the Acts and Regulations as a '
                  'notification every day at 12:00.',
                  style: AppText.body(size: 14, color: AppPalette.of(context).secondaryText),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Send a daily citation',
                      style:
                          AppText.headline(size: 16, weight: FontWeight.w600).copyWith(color: AppPalette.of(context).text)),
                  subtitle: Text('Every day at 12:00',
                      style: AppText.label(size: 11, color: AppPalette.of(context).secondaryText)),
                  value: _enabled,
                  onChanged: _busy ? null : _toggle,
                ),
                Divider(color: AppPalette.of(context).border),
                const SizedBox(height: 8),
                Text('ACTS TO INCLUDE',
                    style: AppText.label(size: 11, color: AppPalette.of(context).accent)),
                const SizedBox(height: 4),
                for (final s in _sources)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _selected.contains(s.key),
                    onChanged: _busy ? null : (v) => _toggleSource(s.key, v ?? false),
                    title: Text(s.label, style: AppText.body(size: 14, color: AppPalette.of(context).text)),
                  ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _busy ? null : _sendTest,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppPalette.of(context).surface,
                    side: BorderSide(color: AppPalette.of(context).text, width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(2)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text('Send a test notification',
                      style: AppText.label(size: 11.5, color: AppPalette.of(context).text)),
                ),
              ],
            ),
    );
  }
}
