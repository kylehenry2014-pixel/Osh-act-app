/// Categories used in public application release notes.
enum ReleaseChangeType {
  newFeature,
  improvement,
  bugFix,
  security,
  removed,
}

extension ReleaseChangeTypeLabel on ReleaseChangeType {
  String get label {
    switch (this) {
      case ReleaseChangeType.newFeature:
        return 'New Features';
      case ReleaseChangeType.improvement:
        return 'Improvements';
      case ReleaseChangeType.bugFix:
        return 'Bug Fixes';
      case ReleaseChangeType.security:
        return 'Security Updates';
      case ReleaseChangeType.removed:
        return 'Removed Features';
    }
  }
}

/// An individual change included in a public release.
class ReleaseChange {
  final ReleaseChangeType type;
  final String description;

  const ReleaseChange({
    required this.type,
    required this.description,
  });
}

/// A verified public application release.
class AppRelease {
  final String version;
  final int buildNumber;
  final String releaseDate;
  final String summary;
  final List<ReleaseChange> changes;

  const AppRelease({
    required this.version,
    required this.buildNumber,
    required this.releaseDate,
    required this.summary,
    required this.changes,
  });

  String get identifier => '$version+$buildNumber';

  List<ReleaseChange> changesOfType(ReleaseChangeType type) {
    return changes
        .where((change) => change.type == type)
        .toList(growable: false);
  }
}

/// Permanent, offline-accessible public release history.
///
/// Add verified release notes before each public release.
/// Keep previous entries intact.
/// Do not include unpublished development builds.
class ReleaseHistory {
  ReleaseHistory._();

  static const List<AppRelease> releases = <AppRelease>[
    // Verified public releases will be added here.
  ];

  static List<AppRelease> get newestFirst {
    final sorted = List<AppRelease>.of(releases);
    sorted.sort(
      (a, b) => b.buildNumber.compareTo(a.buildNumber),
    );
    return List<AppRelease>.unmodifiable(sorted);
  }

  static AppRelease? get latest {
    final sorted = newestFirst;
    return sorted.isEmpty ? null : sorted.first;
  }

  static AppRelease? findByBuild(int buildNumber) {
    for (final release in releases) {
      if (release.buildNumber == buildNumber) {
        return release;
      }
    }
    return null;
  }
}