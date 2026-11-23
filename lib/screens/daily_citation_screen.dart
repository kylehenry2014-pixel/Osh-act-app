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
  bool _enabled = false;
  Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _sources = _service.availableSources();
    _load();
  }

  Future<void> _load() async {
    final enabled = await _service.isEnabled();
    final selected = await _service.selectedSources();
    if (!mounted) return;
    setState(() {
      _enabled = enabled;
      _selected = selected;
      _loading = false;
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _toggle(bool value) async {
    final result = await _service.setEnabled(value);
    if (!mounted) return;
    setState(() => _enabled = result);
    if (value && !result) {
      _snack(
          'Notifications are turned off for this app. Turn them on in your phone settings, then try again.');
    }
  }

  Future<void> _toggleSource(String key, bool value) async {
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
    setState(() => _selected = next);
    await _service.setSelectedSources(next);
  }

  Future<void> _sendTest() async {
    final ok = await _service.sendTest();
    _snack(ok
        ? 'Test notification sent.'
        : 'Could not send a test. Check that notifications are allowed for this app.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        title: Text('Daily Citation', style: AppText.headline(size: 18)),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.amberDeep))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Text(
                  'Get one section from the Acts and Regulations as a '
                  'notification every day at 12:00.',
                  style: AppText.body(size: 14, color: AppColors.steel),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Send a daily citation',
                      style:
                          AppText.headline(size: 16, weight: FontWeight.w600)),
                  subtitle: Text('Every day at 12:00',
                      style: AppText.label(size: 11)),
                  value: _enabled,
                  onChanged: _toggle,
                ),
                const Divider(color: AppColors.line),
                const SizedBox(height: 8),
                Text('ACTS TO INCLUDE',
                    style: AppText.label(size: 11, color: AppColors.amberDeep)),
                const SizedBox(height: 4),
                for (final s in _sources)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _selected.contains(s.key),
                    onChanged: (v) => _toggleSource(s.key, v ?? false),
                    title: Text(s.label, style: AppText.body(size: 14)),
                  ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _sendTest,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: AppColors.paperRaised,
                    side: const BorderSide(color: AppColors.ink, width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(2)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text('Send a test notification',
                      style: AppText.label(size: 11.5, color: AppColors.ink)),
                ),
              ],
            ),
    );
  }
}
