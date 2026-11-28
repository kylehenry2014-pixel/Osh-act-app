import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';
import '../data/ad_service.dart';
import '../data/connectivity_service.dart';
import '../data/iso_repository.dart';
import '../data/certificates_repository.dart';
import '../data/subscription_repository.dart';
import 'bookmarks_screen.dart';
import 'certificates_screen.dart';
import 'chat_screen.dart';
import 'sds_screen.dart';
import 'signage_screen.dart';
import 'daily_citation_screen.dart';
import 'subscription_screen.dart';
import 'toolbox_talks_screen.dart';

const String _kFormspreeEndpoint = 'https://formspree.io/f/mkjwqjze';
const String _kPrivacyPolicyUrl = 'https://ohs-act-app.web.app/privacy.html';

class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  static const _chatFeatureKey = 'chat';
  static const _certificatesFeatureKey = 'certificates';

  bool _openingProtectedFeature = false;

  bool _canContinueFeatureOpen() {
    return mounted &&
        ModalRoute.of(context)?.isCurrent == true &&
        TickerMode.of(context);
  }

  Future<void> _runProtectedFeatureOpen(
    Future<void> Function() operation,
  ) async {
    if (_openingProtectedFeature ||
        !_canContinueFeatureOpen()) {
      return;
    }

    _openingProtectedFeature = true;

    try {
      await operation();
    } catch (error) {
      debugPrint(
        'Feature opening failed: ${error.runtimeType}',
      );

      if (mounted && _canContinueFeatureOpen()) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to open this feature. Please try again.',
            ),
          ),
        );
      }
    } finally {
      _openingProtectedFeature = false;
    }
  }

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

  Future<void> _openPrivacyPolicy() async {
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(_kPrivacyPolicyUrl),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      launched = false;
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open the privacy policy. Please try again.'),
        ),
      );
    }
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

  Future<void> _openChat() {
    return _runProtectedFeatureOpen(_openChatInternal);
  }

  Future<void> _openChatInternal() async {
    if (!await _checkOnlineOrWarn('use the Safety Chat Bot')) return;
    if (!mounted || !_canContinueFeatureOpen()) return;
    if (SubscriptionRepository.instance.isPro) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const ChatScreen(),
      ));
      return;
    }
    final adCount =
        await AdService.instance.nextRequiredAdCount(_chatFeatureKey);
    if (!mounted || !_canContinueFeatureOpen()) return;
    final confirmed = await _confirmWatchAds(adCount, 'ask a question');
    if (!mounted || confirmed != true || !_canContinueFeatureOpen()) return;

    final earned = await AdService.instance.watchAds(adCount);
    if (!mounted || !_canContinueFeatureOpen()) return;

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
    if (!mounted || !_canContinueFeatureOpen()) return;

    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const ChatScreen(),
    ));
  }

  Future<void> _openCertificates() {
    return _runProtectedFeatureOpen(
      _openCertificatesInternal,
    );
  }

  Future<void> _openCertificatesInternal() async {
    if (!await _checkOnlineOrWarn('view your certificate reminders')) return;
    if (!mounted || !_canContinueFeatureOpen()) return;
    if (SubscriptionRepository.instance.isPro) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => const CertificatesScreen(),
      ));
      if (mounted) setState(() {});
      return;
    }
    final adCount =
        await AdService.instance.nextRequiredAdCount(_certificatesFeatureKey);
    if (!mounted || !_canContinueFeatureOpen()) return;
    final confirmed =
        await _confirmWatchAds(adCount, 'view your certificate reminders');
    if (!mounted || confirmed != true || !_canContinueFeatureOpen()) return;

    final earned = await AdService.instance.watchAds(adCount);
    if (!mounted || !_canContinueFeatureOpen()) return;

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
    if (!mounted || !_canContinueFeatureOpen()) return;

    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => const CertificatesScreen(),
    ));
    if (mounted) setState(() {});
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
      _statusMessage = 'Sending...';
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
      if (!mounted) return;
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
      if (!mounted) return;
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

  IconData _featureIcon(String title) {
    switch (title) {
      case 'Settings':
        return AppIcons.settingsOutlined;
      case 'Bookmarks':
        return AppIcons.bookmarkRounded;
      case 'Safety Chat Bot':
        return AppIcons.chatBubbleOutline;
      case 'Toolbox Talks':
        return AppIcons.groupsOutlined;
      case 'SDS Finder':
        return AppIcons.scienceOutlined;
      case 'Certificate Reminders':
        return AppIcons.workspacePremiumOutlined;
      case 'Signage':
        return AppIcons.warningAmberRounded;
      case 'Daily Citation':
        return AppIcons.menuBookOutlined;
      case 'Checklists':
        return AppIcons.checklist;
      case 'ISO Standards':
        return AppIcons.verifiedUserOutlined;
      case 'Legal Appointments':
        return AppIcons.assignmentIndOutlined;
      case 'Investigations':
        return AppIcons.manageSearch;
      case 'Procedures':
        return AppIcons.descriptionOutlined;
      case 'Safety Videos':
        return AppIcons.playCircleOutline;
      case 'Safety Consultant Finder':
        return AppIcons.personSearchOutlined;
      case 'Safety Quiz Game':
        return AppIcons.quizOutlined;
      default:
        return AppIcons.folderOutlined;
    }
  }

  Widget _card({
    required VoidCallback onTap,
    required String title,
    required String subtitle,
    bool comingSoon = false,
  }) {
    return _MorePressCard(
      onTap: onTap,
      dark: false,
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: _MoreStyle.darkGradient,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _MoreStyle.gold,
                  width: 1.2,
                ),
              ),
              child: Icon(
                _featureIcon(title),
                color: _MoreStyle.lightGold,
                size: 25,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (comingSoon) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8DCC0),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        'COMING SOON',
                        style: TextStyle(
                          color: Color(0xFF75501C),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.7,
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                  ],
                  Text(
                    title,
                    style: AppText.headline(
                      size: 15,
                      weight: FontWeight.w700,
                    ).copyWith(color: AppPalette.of(context).text),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: AppText.body(
                      size: 12,
                      color: AppPalette.of(context).secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              AppIcons.chevronRightRounded,
              color: Theme.of(context).brightness == Brightness.dark ? _MoreStyle.lightGold : _MoreStyle.bronze,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 23,
              decoration: BoxDecoration(
                gradient: _MoreStyle.goldGradient,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: AppText.headline(
                  size: 19,
                  weight: FontWeight.w700,
                ).copyWith(color: AppPalette.of(context).text),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          subtitle,
          style: AppText.body(
            size: 12,
            color: AppPalette.of(context).secondaryText,
          ),
        ),
        const SizedBox(height: 15),
      ],
    );
  }

  Widget _subscriptionBanner(bool isPro) {
    return _MorePressCard(
      dark: true,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => const SubscriptionScreen(),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _MoreTape(),
          Padding(
            padding: const EdgeInsets.all(17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ShaderMask(
                      shaderCallback: (bounds) =>
                          _MoreStyle.goldGradient.createShader(bounds),
                      child: const Icon(
                        AppIcons.workspacePremium,
                        size: 44,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isPro
                                ? 'Premium Membership'
                                : 'Upgrade to Pro',
                            style: AppText.headline(
                              size: 21,
                              weight: FontWeight.w800,
                            ).copyWith(
                              color: _MoreStyle.lightGold,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            isPro
                                ? 'Your premium benefits are active.'
                                : 'Remove ads and increase your daily limits.',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFD6D2C5),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 17),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    gradient: _MoreStyle.goldGradient,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _MoreStyle.lightGold,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          isPro
                              ? 'Your Subscription'
                              : 'Explore Premium',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _MoreStyle.ink,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const Icon(
                        AppIcons.chevronRightRounded,
                        color: _MoreStyle.ink,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          const _MoreHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 24),
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable:
                      SubscriptionRepository.instance.isProNotifier,
                  builder: (context, isPro, _) {
                    return _subscriptionBanner(isPro);
                  },
                ),
                const SizedBox(height: 18),
                _card(
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (settingsContext) =>
                            SettingsScreen(
                          onOpenSubscription: () {
                            Navigator.of(settingsContext).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    const SubscriptionScreen(),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  },
                  title: 'Settings',
                  subtitle: 'Notifications and application preferences',
                ),
                const SizedBox(height: 26),
                _sectionTitle(
                  'Safety Tools',
                  'Your professional safety resources.',
                ),
                _card(
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const BookmarksScreen(),
                      ),
                    );
                  },
                  title: 'Bookmarks',
                  subtitle: 'Access your saved legislation',
                ),
                const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                _card(
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const SignageScreen(),
                    ));
                  },
                  title: 'Signage',
                  subtitle: '132 safety signs',
                ),
                const SizedBox(height: 12),
                _card(
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const DailyCitationScreen(),
                    ));
                  },
                  title: 'Daily Citation',
                  subtitle: 'A section from the Acts, every day at 12:00',
                ),
                const SizedBox(height: 28),
                const _MoreTape(),
                const SizedBox(height: 20),
                _sectionTitle(
                  'Coming Soon',
                  'More professional tools are on the way.',
                ),
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
                const SizedBox(height: 12),
                _card(
                  onTap: () => _showComingSoon('Procedures'),
                  title: 'Procedures',
                  subtitle: 'Standard operating procedures',
                  comingSoon: true,
                ),
                const SizedBox(height: 12),
                _card(
                  onTap: () => _showComingSoon('Safety Videos'),
                  title: 'Safety Videos',
                  subtitle: 'Training and induction videos',
                  comingSoon: true,
                ),
                const SizedBox(height: 12),
                _card(
                  onTap: () => _showComingSoon('Safety Consultant Finder'),
                  title: 'Safety Consultant Finder',
                  subtitle: 'Find registered safety professionals in your area',
                  comingSoon: true,
                ),
                const SizedBox(height: 12),
                _card(
                  onTap: () => _showComingSoon('Safety Quiz Game'),
                  title: 'Safety Quiz Game',
                  subtitle: 'Test your knowledge of the OHS Act and Regulations',
                  comingSoon: true,
                ),
                const SizedBox(height: 40),
                Divider(color: AppPalette.of(context).border),
                const SizedBox(height: 16),
                Text(
                  'Text is taken from the official Acts and Regulations published in the Government Gazette. Sources include the South African Government (gov.za), LawLibrary / Laws.Africa (CC BY 4.0) and Acts Online. This app is an independent, unofficial reference tool. For legal purposes, consult the official Government Gazette.',
                  style: AppText.label(size: 10.5, color: AppPalette.of(context).secondaryText),
                ),
                const SizedBox(height: 14),
                InkWell(
                  onTap: _openPrivacyPolicy,
                  child: Text(
                    'Privacy Policy',
                    style: AppText.label(size: 12, color: AppPalette.of(context).accent)
                        .copyWith(decoration: TextDecoration.underline),
                  ),
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
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(
                  AppIcons.bugReportOutlined,
                  color: Theme.of(context).brightness == Brightness.dark ? _MoreStyle.lightGold : _MoreStyle.bronze,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Report a bug',
                    style: AppText.headline(size: 14).copyWith(color: AppPalette.of(context).text),
                  ),
                ),
                Icon(
                  open
                      ? AppIcons.expandLess
                      : AppIcons.expandMore,
                  color: Theme.of(context).brightness == Brightness.dark ? _MoreStyle.lightGold : _MoreStyle.bronze,
                ),
              ],
            ),
          ),
        ),
        if (open) ...[
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            maxLength: 2000,
            minLines: 3,
            maxLines: 6,
            style: AppText.body(size: 14, color: AppPalette.of(context).text),
            decoration: InputDecoration(
              hintText: 'Describe the bug you found...',
              hintStyle: AppText.label(
                  size: 12, color: AppPalette.of(context).secondaryText.withValues(alpha: 0.7)),
              filled: true,
              fillColor: AppPalette.of(context).surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppPalette.of(context).text, width: 1.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppPalette.of(context).text, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: AppPalette.of(context).accent, width: 1.5),
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
                    backgroundColor: AppPalette.of(context).text,
                    foregroundColor: AppPalette.of(context).surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: AppPalette.of(context).text, width: 1.5),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: Text('Submit',
                      style: AppText.label(
                          size: 11.5, color: AppPalette.of(context).surface)),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: submitting ? null : onCancel,
                style: OutlinedButton.styleFrom(
                  backgroundColor: AppPalette.of(context).surface,
                  side: BorderSide(color: AppPalette.of(context).text, width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                ),
                child: Text('Cancel',
                    style: AppText.label(size: 11.5, color: AppPalette.of(context).text)),
              ),
            ],
          ),
          if (statusMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              statusMessage!,
              style: AppText.label(
                  size: 11,
                  color: statusIsError ? AppPalette.of(context).error : AppPalette.of(context).accent),
            ),
          ],
        ],
      ],
    );
  }
}


// =====================================================
// PREMIUM INDUSTRIAL MORE SCREEN
// =====================================================

class _MoreStyle {
  static const ink = Color(0xFF171916);
  static const gold = Color(0xFFDA9B2A);
  static const lightGold = Color(0xFFFFE4A0);
  static const bronze = Color(0xFF95621C);

  static const darkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF41443D),
      Color(0xFF20231E),
      Color(0xFF10120F),
      Color(0xFF292B25),
    ],
    stops: [0, 0.28, 0.72, 1],
  );

  static const goldGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFFFF0B8),
      Color(0xFFF1BC50),
      Color(0xFFDA9B2A),
      Color(0xFFAD7115),
    ],
    stops: [0, 0.28, 0.65, 1],
  );

  static const metallicBorder = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF95621C),
      Color(0xFFFFE4A0),
      Color(0xFFDA9B2A),
      Color(0xFF805014),
      Color(0xFFFFD77A),
    ],
  );

  static const creamGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFFFFCF3),
      Color(0xFFF7F3E6),
      Color(0xFFECE0C5),
    ],
  );
}

// =====================================================
// PREMIUM HEADER
// =====================================================

class _MoreHeader extends StatelessWidget {
  const _MoreHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: _MoreStyle.darkGradient,
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(22, 16, 22, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'OHS ACT & REGULATIONS',
                  style: TextStyle(
                    color: _MoreStyle.lightGold,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Your professional safety companion',
                  style: TextStyle(
                    color: Color(0xFFD6D2C5),
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          _MoreTape(),
        ],
      ),
    );
  }
}

// =====================================================
// SMOOTH INTERACTIVE METALLIC CARD
// =====================================================

class _MorePressCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final bool dark;

  const _MorePressCard({
    required this.child,
    required this.onTap,
    required this.dark,
  });

  @override
  State<_MorePressCard> createState() =>
      _MorePressCardState();
}

class _MorePressCardState extends State<_MorePressCard> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final reducedMotion =
        MediaQuery.of(context).disableAnimations;

    final radius = widget.dark ? 20.0 : 15.0;

    return AnimatedScale(
      scale: _pressed && !reducedMotion ? 0.985 : 1,
      duration: reducedMotion
          ? Duration.zero
          : const Duration(milliseconds: 130),
      curve: Curves.easeOutCubic,
      child: Container(
        padding: EdgeInsets.all(widget.dark ? 2 : 1.2),
        decoration: BoxDecoration(
          gradient: _MoreStyle.metallicBorder,
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: widget.dark
                  ? const Color(0x33000000)
                  : const Color(0x16000000),
              blurRadius: widget.dark ? 14 : 6,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: widget.dark ||
                    Theme.of(context).brightness == Brightness.dark
                ? _MoreStyle.darkGradient
                : _MoreStyle.creamGradient,
            borderRadius: BorderRadius.circular(radius - 1),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap,
              onHighlightChanged: _setPressed,
              splashColor: const Color(0x22DA9B2A),
              highlightColor: const Color(0x11DA9B2A),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

// =====================================================
// ANIMATED INDUSTRIAL DANGER TAPE
// =====================================================

class _MoreTape extends StatefulWidget {
  const _MoreTape();

  @override
  State<_MoreTape> createState() => _MoreTapeState();
}

class _MoreTapeState extends State<_MoreTape>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (MediaQuery.of(context).disableAnimations) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        height: 7,
        width: double.infinity,
        child: CustomPaint(
          painter: _MoreTapePainter(_controller),
        ),
      ),
    );
  }
}

class _MoreTapePainter extends CustomPainter {
  final Animation<double> animation;

  _MoreTapePainter(this.animation)
      : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    canvas.save();
    canvas.clipRect(rect);

    canvas.drawRect(
      rect,
      Paint()..color = _MoreStyle.ink,
    );

    final paint = Paint()
      ..shader = _MoreStyle.goldGradient.createShader(rect);

    const double width = 16;
    const double period = width * 2;

    final shift = animation.value * period;

    for (
      double x = -period * 2 + shift;
      x < size.width + period;
      x += period
    ) {
      final path = Path()
        ..moveTo(x, size.height)
        ..lineTo(x + width, size.height)
        ..lineTo(x + width + size.height, 0)
        ..lineTo(x + size.height, 0)
        ..close();

      canvas.drawPath(path, paint);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(
    covariant _MoreTapePainter oldDelegate,
  ) => oldDelegate.animation != animation;
}
