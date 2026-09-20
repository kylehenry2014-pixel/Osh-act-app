/// A saved certificate/document with an expiry date, tracked so the app can
/// remind the user before it lapses (fire equipment service certs, medical
/// certificates of fitness, competency certificates, etc). A certificate can
/// span multiple pages/photos - e.g. a full medical examination pack - so
/// [imagePaths] is a list, always with at least one entry.
class Certificate {
  final String id;
  final String name;
  final List<String> imagePaths; // local file paths, copied into app storage
  final DateTime expiryDate;
  final DateTime createdAt;
  final String? notes;

  const Certificate({
    required this.id,
    required this.name,
    required this.imagePaths,
    required this.expiryDate,
    required this.createdAt,
    this.notes,
  });

  /// Days remaining until expiry. Negative once expired.
  int get daysUntilExpiry => expiryDate.difference(DateTime.now()).inDays;

  CertificateStatus get status {
    final days = daysUntilExpiry;
    if (days < 0) return CertificateStatus.expired;
    if (days <= 30) return CertificateStatus.expiringSoon;
    return CertificateStatus.valid;
  }

  Certificate copyWith({
    String? name,
    List<String>? imagePaths,
    DateTime? expiryDate,
    String? notes,
  }) {
    return Certificate(
      id: id,
      name: name ?? this.name,
      imagePaths: imagePaths ?? this.imagePaths,
      expiryDate: expiryDate ?? this.expiryDate,
      createdAt: createdAt,
      notes: notes ?? this.notes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'imagePaths': imagePaths,
        'expiryDate': expiryDate.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'notes': notes,
      };

  factory Certificate.fromJson(Map<String, dynamic> json) {
    // Backward-compatible with the earlier single-photo version of this
    // feature, in case any certificate was saved during testing before
    // multi-page support existed.
    final rawPaths = json['imagePaths'];
    final paths = rawPaths is List
        ? rawPaths.map((e) => e as String).toList()
        : <String>[if (json['imagePath'] != null) json['imagePath'] as String];

    return Certificate(
      id: json['id'] as String,
      name: json['name'] as String,
      imagePaths: paths,
      expiryDate: DateTime.parse(json['expiryDate'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      notes: json['notes'] as String?,
    );
  }
}

enum CertificateStatus { valid, expiringSoon, expired }
