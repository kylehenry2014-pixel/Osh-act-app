import 'package:flutter/material.dart';
import '../data/ad_service.dart';
import '../data/app_update_service.dart';

import '../data/notification_inbox_repository.dart';
import '../data/certificates_repository.dart';
import '../data/entries_repository.dart';
import '../data/legislation_access_service.dart';
import 'certificates_screen.dart';
import 'detail_screen.dart';
import '../data/notification_schedule_repository.dart';
import '../data/release_history.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import 'settings_screen.dart';

class NotificationsScreen extends StatefulWidget {
  final int initialTab;
  final String? initialPayload;
  final bool showSettingsShortcut;

  const NotificationsScreen({
    super.key,
    this.initialTab = 0,
    this.initialPayload,
    this.showSettingsShortcut = true,
  }) : assert(initialTab >= 0 && initialTab <= 2);

  @override
  State<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState
    extends State<NotificationsScreen> {
  final _inbox = NotificationInboxRepository.instance;
  final _versionService = AppUpdateService.instance;
  late Future<void> _versionFuture;

  late int _selectedTab;
  bool _loading = true;
  bool _failed = false;
  bool _openingNotification = false;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
    _versionFuture = _loadVersionSafely();
    _load();

    if (widget.initialPayload != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openInitialPayload();
      });
    }
  }

  Future<void> _loadVersionSafely() async {
    try {
      await _versionService.loadInstalledVersion().timeout(
        const Duration(seconds: 5),
      );
    } catch (_) {
      debugPrint('Updates version information unavailable.');
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });

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
      if (mounted) {
        setState(() => _failed = true);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _perform(
    Future<void> Function() operation,
  ) async {
    try {
      await operation();
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to save notification changes. Please try again.',
          ),
        ),
      );
    }
  }

  IconData _notificationIcon(
    InboxNotificationType type,
  ) {
    switch (type) {
      case InboxNotificationType.dailyCitation:
        return AppIcons.menuBookOutlined;
      case InboxNotificationType.certificateReminder:
        return AppIcons.workspacePremiumOutlined;
      case InboxNotificationType.appUpdate:
        return AppIcons.systemUpdateAltRounded;
      case InboxNotificationType.general:
        return AppIcons.notificationsOutlined;
    }
  }

  Widget _emptyState(
    IconData icon,
    String title,
    String message,
  ) {
    final palette = AppPalette.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: palette.accent),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.headline(size: 20)
                  .copyWith(color: palette.text),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppText.body(
                size: 13,
                color: palette.secondaryText,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabs() {
    final palette = AppPalette.of(context);
    const labels = ['All', 'Unread', 'Updates'];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          for (int i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(
              child: Semantics(
                selected: _selectedTab == i,
                button: true,
                child: Material(
                  color: _selectedTab == i
                      ? const Color(0xFFDA9B2A)
                      : palette.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      setState(() => _selectedTab = i);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 13,
                      ),
                      child: Text(
                        labels[i],
                        textAlign: TextAlign.center,
                        style: AppText.label(
                          size: 13,
                          color: _selectedTab == i
                              ? const Color(0xFF171916)
                              : palette.text,
                        ).copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showNavigationMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  bool get _canNavigate {
    if (!mounted ||
        WidgetsBinding.instance.lifecycleState !=
            AppLifecycleState.resumed ||
        !TickerMode.of(context) ||
        AdService.instance.isBusy) {
      return false;
    }

    final route = ModalRoute.of(context);

    if (route?.isCurrent != true) return false;

    final animation = route?.animation;
    final secondary = route?.secondaryAnimation;

    return (animation == null ||
            animation.status == AnimationStatus.completed) &&
        (secondary == null ||
            secondary.status == AnimationStatus.dismissed);
  }

  Future<bool> _waitForNavigationReady() async {
    for (var attempt = 0; attempt < 100; attempt++) {
      if (!mounted) return false;

      if (_canNavigate && !_openingNotification) {
        return true;
      }

      await Future<void>.delayed(
        const Duration(milliseconds: 100),
      );
    }

    return false;
  }

  Future<void> _openInitialPayload() async {
    final payload = widget.initialPayload;

    if (payload == null) return;

    final ready = await _waitForNavigationReady();

    if (!mounted) return;

    if (!ready || !_canNavigate) {
      _showNavigationMessage(
        'Unable to open the notification automatically. '
        'Please select it from your notification history.',
      );
      return;
    }

    final separator = payload.indexOf(':');

    if (separator <= 0 ||
        separator == payload.length - 1) {
      return;
    }

    final kind = payload.substring(0, separator);
    final reference = payload.substring(separator + 1);

    if (reference.trim().isEmpty) return;

    final InboxNotificationType type;

    switch (kind) {
      case 'certificate':
        type = InboxNotificationType.certificateReminder;
        break;
      case 'citation':
        type = InboxNotificationType.dailyCitation;
        break;
      default:
        return;
    }

    await _openNotification(
      InboxNotification(
        id: 'external_notification_navigation',
        type: type,
        title: 'Notification',
        message: '',
        createdAt: DateTime.now().toUtc(),
        referenceId: reference,
      ),
      markRead: false,
    );
  }

  Future<void> _openNotification(
    InboxNotification item, {
    bool markRead = true,
  }) async {
    if (_openingNotification || !_canNavigate) return;

    _openingNotification = true;

    try {
      if (markRead) {
        await _perform(
          () => _inbox.markAsRead(item.id),
        );
      }

      if (!_canNavigate) return;

      final reference = item.referenceId;

      switch (item.type) {
        case InboxNotificationType.appUpdate:
          setState(() => _selectedTab = 2);
          return;

        case InboxNotificationType.general:
          return;

        case InboxNotificationType.certificateReminder:
          await CertificatesRepository.instance.load();

          if (!mounted || !_canNavigate) return;

          final matches = CertificatesRepository.instance.all
              .where((certificate) =>
                  certificate.id == reference)
              .toList();

          if (matches.length != 1) {
            _showNavigationMessage(
              'This certificate is no longer available.',
            );
            return;
          }

          await Navigator.of(context).push<void>(
            MaterialPageRoute<void>(
              builder: (_) => CertificateDetailScreen(
                certificate: matches.single,
              ),
            ),
          );
          return;

        case InboxNotificationType.dailyCitation:
          await EntriesRepository.instance.load();

          if (!mounted || !_canNavigate) return;

          final repository = EntriesRepository.instance;
          final entry = reference == null
              ? null
              : repository.byId(reference);

          if (entry == null) {
            _showNavigationMessage(
              'This legislation section is no longer available.',
            );
            return;
          }

          final entries = repository.entriesInCollection(
            entry.collection,
          );

          await LegislationAccessService.instance.open(
            context: context,
            onOpen: () async {
              if (!_canNavigate) return;

              await Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => DetailScreen(
                    entries: entries,
                    initialId: entry.id,
                  ),
                ),
              );
            },
          );
          return;
      }
    } catch (error) {
      debugPrint(
        'Notification navigation failed: ${error.runtimeType}',
      );

      if (_canNavigate) {
        _showNavigationMessage(
          'Unable to open this notification. Please try again.',
        );
      }
    } finally {
      _openingNotification = false;
    }
  }

  Widget _deliveryInformation() {
    final palette = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            AppIcons.infoOutlineRounded,
            size: 17,
            color: palette.secondaryText,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'Reminder history reflects scheduled reminders. '
              'Device delivery may depend on notification '
              'permissions and system settings.',
              style: AppText.body(
                size: 12,
                color: palette.secondaryText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _notificationTimestamp(
    InboxNotification item,
    String date,
    String time,
  ) {
    final timestamp = '$date - $time';

    if (item.type == InboxNotificationType.dailyCitation &&
        item.id.startsWith('citation_test_')) {
      return 'Test notification - $timestamp';
    }

    if (item.type == InboxNotificationType.dailyCitation ||
        item.type == InboxNotificationType.certificateReminder) {
      return 'Scheduled reminder - $timestamp';
    }

    return timestamp;
  }

  Widget _notificationCard(InboxNotification item) {
    final palette = AppPalette.of(context);
    final local = item.createdAt.toLocal();
    final date = MaterialLocalizations.of(context)
        .formatShortDate(local);
    final time = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(local));

    return Card(
      color: palette.surface,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: item.isRead
              ? palette.border
              : palette.accent,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _openNotification(item),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _notificationIcon(item.type),
                color: palette.accent,
                size: 27,
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: AppText.headline(size: 15)
                          .copyWith(color: palette.text),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.message,
                      style: AppText.body(
                        size: 13,
                        color: palette.secondaryText,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _notificationTimestamp(
                        item,
                        date,
                        time,
                      ),
                      style: AppText.label(
                        size: 11,
                        color: palette.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              if (!item.isRead)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Semantics(
                    label: 'Unread',
                    child: Icon(
                      Icons.circle,
                      size: 8,
                      color: palette.accent,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _releaseCard(
    AppRelease release,
    bool latest,
  ) {
    final palette = AppPalette.of(context);

    return Card(
      color: palette.surface,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: latest ? palette.accent : palette.border,
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: latest,
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(
          AppIcons.systemUpdateAltRounded,
          color: palette.accent,
        ),
        title: Text(
          'Version ${release.version}',
          style: AppText.headline(size: 16)
              .copyWith(color: palette.text),
        ),
        subtitle: Text(
          '${release.releaseDate} - Build ${release.buildNumber}'
          '${latest ? ' - Latest release' : ''}',
          style: AppText.label(
            size: 11,
            color: palette.secondaryText,
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  release.summary,
                  style: AppText.body(
                    size: 13,
                    color: palette.text,
                  ),
                ),
                for (final type in ReleaseChangeType.values)
                  if (release.changesOfType(type).isNotEmpty) ...[
                    const SizedBox(height: 18),
                    Text(
                      type.label.toUpperCase(),
                      style: AppText.label(
                        size: 11,
                        color: palette.accent,
                      ).copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final change
                        in release.changesOfType(type))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Icon(
                              AppIcons.checkCircleOutline,
                              size: 17,
                              color: palette.accent,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                change.description,
                                style: AppText.body(
                                  size: 13,
                                  color: palette.text,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _installedVersionCard() {
    final palette = AppPalette.of(context);

    return Card(
      color: palette.surface,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 22),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: palette.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: FutureBuilder<void>(
          future: _versionFuture,
          builder: (context, snapshot) {
            final version = _versionService.installedVersion;
            final build = _versionService.installedBuild;
            final available = version != null && build != null;

            final loading = !available &&
                snapshot.connectionState != ConnectionState.done;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'INSTALLED VERSION',
                  style: AppText.label(
                    size: 11,
                    color: palette.secondaryText,
                  ).copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            available
                                ? version
                                : loading
                                    ? 'Loading...'
                                    : 'Unavailable',
                            style: AppText.headline(size: 28)
                                .copyWith(color: palette.text),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            available
                                ? 'Build $build'
                                : loading
                                    ? 'Reading installed package'
                                    : 'Unable to read package information',
                            style: AppText.body(
                              size: 13,
                              color: palette.secondaryText,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Icon(
                      AppIcons.infoOutlineRounded,
                      size: 30,
                      color: palette.accent,
                    ),
                  ],
                ),
                if (!available && !loading) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _versionFuture = _loadVersionSafely();
                      });
                    },
                    child: const Text('Try Again'),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _updates() {
    final palette = AppPalette.of(context);
    final releases = ReleaseHistory.newestFirst;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        _installedVersionCard(),
        Text(
          'Release history',
          style: AppText.headline(size: 18)
              .copyWith(color: palette.text),
        ),
        const SizedBox(height: 14),
        if (releases.isEmpty)
          _emptyState(
            AppIcons.historyRounded,
            'No release notes yet',
            'Verified release notes will appear here.',
          )
        else
          for (int index = 0; index < releases.length; index++)
            _releaseCard(releases[index], index == 0),
      ],
    );
  }

  Widget _notifications() {
    final palette = AppPalette.of(context);

    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          color: palette.accent,
        ),
      );
    }

    if (_failed || _inbox.hasStorageDamage) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Notifications could not be loaded. '
                'Your stored records have not been reset.',
                textAlign: TextAlign.center,
                style: AppText.body(color: palette.text),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _load,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    final items = _selectedTab == 1
        ? _inbox.unread
        : _inbox.all;

    if (items.isEmpty) {
      return _emptyState(
        AppIcons.notificationsNoneRounded,
        _selectedTab == 1
            ? "You're all caught up"
            : 'No notifications yet',
        _selectedTab == 1
            ? 'You have no unread notifications.'
            : 'Your reminders and announcements will appear here.',
      );
    }

    return Column(
      children: [
        if (_inbox.unreadCount > 0)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: TextButton(
                onPressed: () => _perform(
                  _inbox.markAllAsRead,
                ),
                child: const Text('Mark all as read'),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            itemCount: items.length,
            itemBuilder: (context, index) {
              return _notificationCard(items[index]);
            },
          ),
        ),
      ],
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
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
                            'Notifications',
                            style: AppText.headline(size: 23)
                                .copyWith(
                              color: const Color(0xFFF7F3E6),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Reminders and app updates',
                            style: AppText.label(
                              size: 11,
                              color: const Color(0xFFC5C6BB),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (widget.showSettingsShortcut) ...[
                      const SizedBox(width: 8),
                      PremiumHeaderButton(
                        icon: AppIcons.settingsOutlined,
                        tooltip: 'Settings',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  const SettingsScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            _tabs(),
            if (_selectedTab != 2)
              _deliveryInformation(),
            Expanded(
              child: ListenableBuilder(
                listenable: _inbox,
                builder: (context, child) {
                  return _selectedTab == 2
                      ? _updates()
                      : _notifications();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}