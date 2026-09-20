import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../theme/app_theme.dart';
import '../data/ad_service.dart';
import '../data/connectivity_service.dart';
import '../data/iso_repository.dart';
import '../data/certificates_repository.dart';
import '../data/subscription_repository.dart';
import 'certificates_screen.dart';
import 'chat_screen.dart';
import 'sds_screen.dart';
import 'subscription_screen.dart';
import 'toolbox_talks_screen.dart';

const String _kFormspreeEndpoint = 'https://formspree.io/f/mkjwqjze';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  static const _chatFeatureKey = 'chat';
  static const _certificatesFeatureKey = 'certificates';

  bool _bugFormOpen = false;
  final _descriptionController = TextEditingController();
  bool _submitting = false;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  void _showComingSoon(String featureName) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$featureName is coming soon.')),
    );
  }

  Future<bool?> _confirmWatchAds(int adCount, String actionLabel) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Watch an ad to continue'),
        content: Text(
          adCount == 1
              ? 'Watch a short ad to $actionLabel.'
              : 'Watch $adCount ads back-to-back to $actionLabel.',
        ),
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

  Future<bool> _checkOnlineOrWarn(String actionLabel) async {
    final online = await ConnectivityService.instance.isOnline();
    if (!online && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('You need an internet connection to $actionLabel.')),
      );
    }
    return online;
  }

  Future<void> _openChat() async {
    if (!await _checkOnlineOrWarn('use the Safety Chat Bot')) return;
    if (SubscriptionRepository.instance.isPro) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const ChatScreen(),
      ));
      return;
    }
    final adCount =
        await AdService.instance.nextRequiredAdCount(_chatFeatureKey);
    if (!mounted) return;
    final confirmed = await _confirmWatchAds(adCount, 'ask a question');
    if (confirmed != true) return;

    final earned = await AdService.instance.watchAds(adCount);
    if (!mounted) return;

    if (!earned) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            adCount == 1
                ? "You'll need to watch the ad through to the end to unlock this."
                : "You'll need to watch all $adCount ads through to the end to unlock this.",
          ),
        ),
      );
      return;
    }
    await AdService.instance.recordUnlockedRequest(_chatFeatureKey);
    if (!mounted) return;

    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ChatScreen(),
    ));
  }

  Future<void> _openCertificates() async {
    if (!await _checkOnlineOrWarn('view your certificate reminders')) return;
    if (SubscriptionRepository.instance.isPro) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const CertificatesScreen(),
      ));
      setState(() {});
      return;
    }
    final adCount =
        await AdService.instance.nextRequiredAdCount(_certificatesFeatureKey);
    if (!mounted) return;
    final confirmed =
        await _confirmWatchAds(adCount, 'view your certificate reminders');
    if (confirmed != true) return;

    final earned = await AdService.instance.watchAds(adCount);
    if (!mounted) return;

    if (!earned) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            adCount == 1
                ? "You'll need to watch the ad through to the end to unlock this."
                : "You'll need to watch all $adCount ads through to the end to unlock this.",
          ),
        ),
      );
      return;
    }
    await AdService.instance.recordUnlockedRequest(_certificatesFeatureKey);
    if (!mounted) return;

    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const CertificatesScreen(),
    ));
    setState(() {});
  }

  Future<void> _openToolboxTalks() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ToolboxTalksScreen(),
    ));
  }

  Future<void> _submitBugReport() async {
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      setState(() {
        _statusMessage = 'Please describe the bug first.';
        _statusIsError = true;
      });
      return;
    }
    setState(() {
      _submitting = true;
      _statusMessage = 'Sending…';
      _statusIsError = false;
    });
    try {
      final res = await http.post(
        Uri.parse(_kFormspreeEndpoint),
        headers: {'Accept': 'application/json'},
        body: {
          'message': description,
          '_subject': 'OHS Act App - Bug Report',
        },
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        setState(() {
          _statusMessage = 'Thanks - your report has been sent.';
          _statusIsError = false;
          _descriptionController.clear();
        });
        await Future.delayed(const Duration(milliseconds: 1800));
        if (mounted) {
          setState(() {
            _bugFormOpen = false;
            _statusMessage = null;
          });
        }
      } else {
        setState(() {
          _statusMessage = 'Something went wrong. Please try again.';
          _statusIsError = true;
        });
      }
    } catch (_) {
      setState(() {
        _statusMessage = 'Network error. Please try again.';
        _statusIsError = true;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _cancelBugForm() {
    setState(() {
      _bugFormOpen = false;
      _descriptionController.clear();
      _statusMessage = null;
    });
  }

  Widget _card({
    required VoidCallback onTap,
    required String title,
    required String subtitle,
    bool comingSoon = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.paperRaised,
          border: Border.all(color: AppColors.line),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (comingSoon) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.steel,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: Text(
                        'COMING SOON',
                        style: AppText.label(size: 10, color: Colors.white)
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 2),
                  ],
                  Text(title,
                      style:
                          AppText.headline(size: 16, weight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: AppText.label(size: 11)),
                ],
              ),
            ),
            Icon(
              comingSoon ? Icons.chevron_right : Icons.arrow_forward,
              size: comingSoon ? 24 : 18,
              color: AppColors.steel,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const HazardStripe(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable:
                      SubscriptionRepository.instance.isProNotifier,
                  builder: (context, isPro, _) {
                    if (isPro) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: InkWell(
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => const SubscriptionScreen()),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.amberDeep,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.workspace_premium_outlined,
                                  color: Colors.white),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Remove Ads',
                                        style: AppText.headline(
                                                size: 16,
                                                weight: FontWeight.w700)
                                            .copyWith(color: Colors.white)),
                                    const SizedBox(height: 2),
                                    Text(
                                        'Skip ads on Chat Bot, Toolbox Talks & Certificates',
                                        style: AppText.label(
                                            size: 11, color: Colors.white)),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                _card(
                  onTap: _openChat,
                  title: 'Safety Chat Bot',
                  subtitle: 'Ask what applies to your business',
                ),
                const SizedBox(height: 12),
                _card(
                  onTap: _openToolboxTalks,
                  title: 'Toolbox Talks',
                  subtitle: '1000 talks across 50 categories',
                ),
                const SizedBox(height: 12),
                _card(
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const SdsScreen(),
                    ));
                  },
                  title: 'SDS Finder',
                  subtitle: 'Find a chemical Safety Data Sheet',
                ),
                const SizedBox(height: 12),
                _card(
                  onTap: _openCertificates,
                  title: 'Certificate Reminders',
                  subtitle:
                      '${CertificatesRepository.instance.all.length} saved',
                ),
                const SizedBox(height: 28),
                const Divider(color: AppColors.line),
                const SizedBox(height: 16),
                _card(
                  onTap: () => _showComingSoon('Checklists'),
                  title: 'Checklists',
                  subtitle: 'Site safety checklists',
                  comingSoon: true,
                ),
                const SizedBox(height: 12),
                _card(
                  onTap: () => _showComingSoon('ISO Standards'),
                  title: 'International Organization for Standardization',
                  subtitle: '${IsoRepository.instance.all.length} clauses',
                  comingSoon: true,
                ),
                const SizedBox(height: 12),
                _card(
                  onTap: () => _showComingSoon('Legal Appointments'),
                  title: 'Legal Appointments',
                  subtitle: 'OHS Act appointment letter templates',
                  comingSoon: true,
                ),
                const SizedBox(height: 12),
                _card(
                  onTap: () => _showComingSoon('Investigations'),
                  title: 'Investigations',
                  subtitle: 'Incident investigation & reporting forms',
                  comingSoon: true,
                ),
                const SizedBox(height: 40),
                const Divider(color: AppColors.line),
                const SizedBox(height: 16),
                Text(
                  'Text sourced from LawLibrary / Laws.Africa (CC BY 4.0), the Government Gazette, SAFLII, and Acts Online, checked current as of 2026. Every planned regulation set is complete: the OHS Act plus 25 full regulation sets across General, Health, Mechanical and Electrical categories. This app is an unofficial reference tool; for legal purposes consult the Government Gazette.',
                  style: AppText.label(size: 10.5),
                ),
                const SizedBox(height: 14),
                _BugReportSection(
                  open: _bugFormOpen,
                  onToggle: () => setState(() => _bugFormOpen = !_bugFormOpen),
                  controller: _descriptionController,
                  submitting: _submitting,
                  statusMessage: _statusMessage,
                  statusIsError: _statusIsError,
                  onSubmit: _submitBugReport,
                  onCancel: _cancelBugForm,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BugReportSection extends StatelessWidget {
  final bool open;
  final VoidCallback onToggle;
  final TextEditingController controller;
  final bool submitting;
  final String? statusMessage;
  final bool statusIsError;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  const _BugReportSection({
    required this.open,
    required this.onToggle,
    required this.controller,
    required this.submitting,
    required this.statusMessage,
    required this.statusIsError,
    required this.onSubmit,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: onToggle,
          child: Text('🐛 Report a bug',
              style: AppText.label(size: 12, color: AppColors.ink)),
        ),
        if (open) ...[
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLength: 2000,
            minLines: 3,
            maxLines: 6,
            style: AppText.body(size: 14),
            decoration: InputDecoration(
              hintText: 'Describe the bug you found...',
              hintStyle: AppText.label(
                  size: 12, color: AppColors.steel.withValues(alpha: 0.7)),
              filled: true,
              fillColor: AppColors.paperRaised,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: const BorderSide(color: AppColors.ink, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide: const BorderSide(color: AppColors.ink, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(2),
                borderSide:
                    const BorderSide(color: AppColors.amberDeep, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: submitting ? null : onSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.ink,
                    foregroundColor: AppColors.paperRaised,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2),
                      side: const BorderSide(color: AppColors.ink, width: 1.5),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text('Submit',
                      style: AppText.label(
                          size: 11.5, color: AppColors.paperRaised)),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: submitting ? null : onCancel,
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppColors.paperRaised,
                  side: const BorderSide(color: AppColors.ink, width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(2)),
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                ),
                child: Text('Cancel',
                    style: AppText.label(size: 11.5, color: AppColors.ink)),
              ),
            ],
          ),
          if (statusMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              statusMessage!,
              style: AppText.label(
                  size: 11,
                  color: statusIsError ? AppColors.red : AppColors.amberDeep),
            ),
          ],
        ],
      ],
    );
  }
}
