import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_inbox_repository.dart';
import 'release_history.dart';

/// Detects installed application updates and records
/// verified release announcements in the local inbox.
class AppUpdateService {
  AppUpdateService._();

  static final instance = AppUpdateService._();

  static const _versionKey =
      'app_update_last_installed_version_v1';

  static const _buildKey =
      'app_update_last_installed_build_v1';

  Future<void> _queue = Future<void>.value();

  String? _installedVersion;
  int? _installedBuild;

  String? get installedVersion => _installedVersion;
  int? get installedBuild => _installedBuild;

  Future<void> checkInstalledVersion() {
    final next = _queue.then((_) => _check());

    _queue = next.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );

    return next;
  }

  /// Reads installed package information independently of
  /// notification storage and release announcement processing.
  Future<void> loadInstalledVersion() async {
    if (_installedVersion != null && _installedBuild != null) {
      return;
    }

    final info = await PackageInfo.fromPlatform();

    final version = info.version.trim();
    final build = int.tryParse(info.buildNumber);

    if (version.isEmpty || build == null || build <= 0) {
      throw StateError(
        'Installed application version is invalid.',
      );
    }

    _installedVersion = version;
    _installedBuild = build;
  }

  /// Human-readable installed version for application screens.
  String? get installedVersionLabel {
    final version = _installedVersion;
    final build = _installedBuild;

    if (version == null || build == null) {
      return null;
    }

    return '$version (Build $build)';
  }

  Future<void> _check() async {
    await loadInstalledVersion();

    final version = _installedVersion!;
    final build = _installedBuild!;

    final prefs = await SharedPreferences.getInstance();

    final previousBuild = prefs.getInt(_buildKey);
    final previousVersion = prefs.getString(_versionKey);

    // First observation establishes a baseline.
    // Do not announce an update on a fresh installation.
    if (previousBuild == null ||
        previousVersion == null ||
        previousVersion.isEmpty) {
      await _saveBaseline(prefs, version, build);
      return;
    }

    // Ignore repeated launches and older builds.
    if (build <= previousBuild) {
      return;
    }

    final release = ReleaseHistory.findByBuild(build);

    // Only verified public releases may create announcements.
    if (release != null && release.version == version) {
      await NotificationInboxRepository.instance.add(
        InboxNotification(
          id: 'app_update_${release.identifier}',
          type: InboxNotificationType.appUpdate,
          title: 'Application updated to ${release.version}',
          message: release.summary,
          createdAt: DateTime.now().toUtc(),
          referenceId: release.identifier,
        ),
      );
    }

    // Save only after the inbox operation succeeds.
    // If saving fails, the stable notification ID prevents
    // duplicate announcements during a subsequent retry.
    await _saveBaseline(prefs, version, build);
  }

  Future<void> _saveBaseline(
    SharedPreferences prefs,
    String version,
    int build,
  ) async {
    if (!await prefs.setString(_versionKey, version)) {
      throw StateError(
        'Could not save installed application version.',
      );
    }

    if (!await prefs.setInt(_buildKey, build)) {
      throw StateError(
        'Could not save installed application build.',
      );
    }
  }
}