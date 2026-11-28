import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/app_rating_service.dart';
import '../data/app_update_service.dart';
import '../data/notification_inbox_repository.dart';
import '../data/notification_schedule_repository.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import 'daily_citation_screen.dart';
import 'notifications_screen.dart';
import 'subscription_screen.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onOpenSubscription;

  const SettingsScreen({
    super.key,
    this.onOpenSubscription,
  });

  @override
  State<SettingsScreen> createState() =>
      _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _inbox = NotificationInboxRepository.instance;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      try {
        await NotificationScheduleRepository.instance
            .reconcileDue();
      } catch (error) {
        debugPrint(
          'Notification reconciliation unavailable: $error',
        );
      }

      await _inbox.load();
    } catch (_) {
      debugPrint('Settings notification count unavailable.');
    }
  }

  void _open(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => screen,
      ),
    );
  }

  Future<void> _openPrivacyPolicy() async {
    try {
      final opened = await launchUrl(
        Uri.parse(
          'https://ohs-act-app.web.app/privacy.html',
        ),
        mode: LaunchMode.externalApplication,
      );

      if (!opened) {
        throw StateError('Unable to open privacy policy.');
      }
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open the privacy policy.'),
        ),
      );
    }
  }

  Future<void> _rateApp() async {
    try {
      final service = AppRatingService.instance;

      await service.init();

      final opened = await service.openGooglePlay();

      if (!opened) {
        throw StateError('Unable to open Google Play.');
      }
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to open Google Play. Please try again.',
          ),
        ),
      );
    }
  }

  void _showCertificateReminders() {
    final palette = AppPalette.of(context);

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: palette.surface,
        title: Text(
          'Certificate reminders',
          style: AppText.headline(size: 20)
              .copyWith(color: palette.text),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Reminders are scheduled at 09:00 '
                'before your saved certificates expire.',
                style: AppText.body(
                  size: 14,
                  color: palette.secondaryText,
                ),
              ),
              const SizedBox(height: 16),
              for (final interval in const [
                '30 days before expiry',
                '14 days before expiry',
                '7 days before expiry',
                '1 day before expiry',
                'On the expiry date',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(
                        AppIcons.notificationsOutlined,
                        color: palette.accent,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          interval,
                          style: AppText.body(
                            size: 13,
                            color: palette.text,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Text(
                'Delivery depends on device permissions '
                'and notification settings.',
                style: AppText.body(
                  size: 12,
                  color: palette.secondaryText,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(),
            child: Text(
              'Close',
              style: TextStyle(color: palette.accent),
            ),
          ),
        ],
      ),
    );
  }

  bool _openingAbout = false;

  Future<void> _showAbout() async {
    if (_openingAbout) return;
    _openingAbout = true;

    final service = AppUpdateService.instance;

    try {
      try {
        await service.loadInstalledVersion().timeout(
          const Duration(seconds: 5),
        );
      } catch (_) {
        debugPrint('About version information unavailable.');
      }

      if (!mounted ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }

      final palette = AppPalette.of(context);

      final versionLabel =
          service.installedVersionLabel;

      final openHistory = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AboutDialog(
          applicationName: 'OHS Act & Regulations',
          applicationVersion: versionLabel == null
              ? 'Version unavailable'
              : 'Version $versionLabel',
          applicationIcon: Icon(
            AppIcons.healthAndSafetyOutlined,
            size: 42,
            color: palette.accent,
          ),
          children: [
            Text(
              'Occupational health and safety legislation, '
              'reference material and professional safety tools.',
              style: AppText.body(
                size: 14,
                color: palette.text,
              ),
            ),
            const SizedBox(height: 18),
            Divider(color: palette.border),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                AppIcons.historyRounded,
                color: palette.accent,
              ),
              title: Text(
                'Release history',
                style: AppText.headline(size: 14)
                    .copyWith(color: palette.text),
              ),
              trailing: Icon(
                AppIcons.chevronRightRounded,
                color: palette.secondaryText,
              ),
              onTap: () =>
                  Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      );

      if (openHistory == true &&
          mounted &&
          ModalRoute.of(context)?.isCurrent == true) {
        _open(
          const NotificationsScreen(
            initialTab: 2,
            showSettingsShortcut: false,
          ),
        );
      }
    } finally {
      _openingAbout = false;
    }
  }

  Widget _heading(String title) {
    final palette = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Text(
        title,
        style: AppText.label(
          size: 11,
          color: palette.accent,
        ).copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Widget _group(List<Widget> children) {
    final palette = AppPalette.of(context);

    return Card(
      margin: EdgeInsets.zero,
      color: palette.surface,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.border),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                indent: 16,
                endIndent: 16,
                color: palette.border,
              ),
            children[i],
          ],
        ],
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? indicator,
  }) {
    final palette = AppPalette.of(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 16,
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                icon,
                size: 23,
                color: palette.accent,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppText.headline(size: 15)
                        .copyWith(color: palette.text),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: AppText.body(
                      size: 12,
                      color: palette.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            if (indicator != null) ...[
              const SizedBox(width: 8),
              indicator,
            ],
            const SizedBox(width: 8),
            Icon(
              AppIcons.chevronRightRounded,
              color: palette.secondaryText,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _notificationTile() {
    return ListenableBuilder(
      listenable: _inbox,
      builder: (context, _) {
        final palette = AppPalette.of(context);
        final count = _inbox.unreadCount;

        return _tile(
          icon: AppIcons.notificationsActiveOutlined,
          title: 'Notifications',
          subtitle: _inbox.hasStorageDamage
              ? 'Notification history unavailable'
              : 'Reminders and announcements',
          onTap: () => _open(
            const NotificationsScreen(
              showSettingsShortcut: false,
            ),
          ),
          indicator: _inbox.isLoaded &&
                  !_inbox.hasStorageDamage &&
                  count > 0
              ? Semantics(
                  label: '$count unread notifications',
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: palette.accent,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      count > 99 ? '99+' : '$count',
                      style: AppText.label(
                        size: 11,
                        color: const Color(0xFF171916),
                      ).copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Scaffold(
      backgroundColor: palette.background,
      body: SafeArea(
        child: Column(
          children: [
            PremiumHeaderSurface(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  16, 16, 16, 18,
                ),
                child: Row(
                  children: [
                    PremiumHeaderButton(
                      icon: AppIcons.arrowBackRounded,
                      tooltip: 'Back',
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Settings',
                            style: AppText.headline(size: 23)
                                .copyWith(
                              color: const Color(0xFFF7F3E6),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Manage your app experience',
                            style: AppText.label(
                              size: 11,
                              color: const Color(0xFFC5C6BB),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  16, 0, 16, 28,
                ),
                children: [
                  _heading('PERSONALISATION'),
                  _group([
                    _notificationTile(),
                  ]),
                  _heading('PREFERENCES'),
                  _group([
                    _tile(
                      icon: AppIcons.menuBookOutlined,
                      title: 'Daily Citation',
                      subtitle: 'Manage sources and reminders',
                      onTap: () => _open(
                        const DailyCitationScreen(),
                      ),
                    ),
                    _tile(
                      icon: AppIcons.eventAvailableOutlined,
                      title: 'Certificate reminders',
                      subtitle: 'View expiry reminder intervals',
                      onTap: _showCertificateReminders,
                    ),
                  ]),
                  _heading('APPLICATION'),
                  _group([
                    _tile(
                      icon: AppIcons.workspacePremiumOutlined,
                      title: 'Subscription',
                      subtitle: 'Manage your membership',
                      onTap: widget.onOpenSubscription ??
                          () => _open(
                                const SubscriptionScreen(),
                              ),
                    ),
                    _tile(
                      icon: AppIcons.historyRounded,
                      title: "What's new",
                      subtitle: 'App updates and release history',
                      onTap: () => _open(
                        const NotificationsScreen(
                          initialTab: 2,
                          showSettingsShortcut: false,
                        ),
                      ),
                    ),
                    _tile(
                      icon: AppIcons.starOutlineRounded,
                      title: 'Rate the App',
                      subtitle: 'Share your feedback on Google Play',
                      onTap: () {
                        _rateApp();
                      },
                    ),
                    _tile(
                      icon: AppIcons.privacyTipOutlined,
                      title: 'Privacy policy',
                      subtitle: 'Privacy and data protection',
                      onTap: () {
                        _openPrivacyPolicy();
                      },
                    ),
                    _tile(
                      icon: AppIcons.infoOutlineRounded,
                      title: 'About the app',
                      subtitle: 'Application information',
                      onTap: _showAbout,
                    ),
                  ]),
                  const SizedBox(height: 30),
                  Text(
                    'OHS Act & Regulations',
                    textAlign: TextAlign.center,
                    style: AppText.label(
                      size: 11,
                      color: palette.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}