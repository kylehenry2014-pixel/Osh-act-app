import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

/// Result of an SDS lookup - either a confirmed match (with a link that may
/// or may not resolve to a direct PDF), or an honest "couldn't find it".
class SdsResult {
  final bool found;
  final String? productName;
  final String? manufacturer;
  final String? sdsUrl;
  final bool directPdf;
  final String message;

  SdsResult({
    required this.found,
    this.productName,
    this.manufacturer,
    this.sdsUrl,
    this.directPdf = false,
    required this.message,
  });

  factory SdsResult.fromMap(Map<String, dynamic> data) => SdsResult(
        found: data['found'] as bool? ?? false,
        productName: data['productName'] as String?,
        manufacturer: data['manufacturer'] as String?,
        sdsUrl: data['sdsUrl'] as String?,
        directPdf: data['directPdf'] as bool? ?? false,
        message: data['message'] as String? ?? '',
      );
}

class SdsException implements Exception {
  final String message;
  SdsException(this.message);
}

/// Calls the findSds Cloud Function - either with a text query, or with a
/// photo of a chemical container/label. Uses the same safe
/// Firebase.apps.isEmpty guard as every other Firebase-backed repository in
/// this app, since eager Firebase access before the app connects is what
/// caused the More-screen-blank crash bug earlier in this project.
class SdsRepository {
  static final SdsRepository instance = SdsRepository._();
  SdsRepository._();

  FirebaseFunctions? get _functions {
    if (Firebase.apps.isEmpty) return null;
    return FirebaseFunctions.instance;
  }

  Future<SdsResult> findByText(String query) async {
    final functions = _functions;
    if (functions == null) {
      throw SdsException('Not connected yet. Please try again in a moment.');
    }
    try {
      final callable = functions.httpsCallable('findSds');
      final result = await callable.call({'query': query});
      return SdsResult.fromMap(Map<String, dynamic>.from(result.data as Map));
    } on FirebaseFunctionsException catch (e) {
      throw SdsException(
          e.message ?? 'Something went wrong searching for the SDS.');
    }
  }

  Future<SdsResult> findByImage({
    required String imageBase64,
    required String imageMediaType,
    String? query,
  }) async {
    final functions = _functions;
    if (functions == null) {
      throw SdsException('Not connected yet. Please try again in a moment.');
    }
    try {
      final callable = functions.httpsCallable('findSds');
      final result = await callable.call({
        'imageBase64': imageBase64,
        'imageMediaType': imageMediaType,
        if (query != null && query.isNotEmpty) 'query': query,
      });
      return SdsResult.fromMap(Map<String, dynamic>.from(result.data as Map));
    } on FirebaseFunctionsException catch (e) {
      throw SdsException(
          e.message ?? 'Something went wrong searching for the SDS.');
    }
  }
}
