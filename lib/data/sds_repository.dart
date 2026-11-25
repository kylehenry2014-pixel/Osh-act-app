import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

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

  factory SdsResult.fromMap(
    Map<String, dynamic> data,
  ) {
    return SdsResult(
      found: data['found'] as bool? ?? false,
      productName: data['productName'] as String?,
      manufacturer: data['manufacturer'] as String?,
      sdsUrl: data['sdsUrl'] as String?,
      directPdf: data['directPdf'] as bool? ?? false,
      message: data['message'] as String? ?? '',
    );
  }
}

class SdsException implements Exception {
  final String message;
  final bool isQuotaExceeded;

  SdsException(
    this.message, {
    this.isQuotaExceeded = false,
  });

  @override
  String toString() => message;
}

class SdsRepository {
  static final SdsRepository instance =
      SdsRepository._();

  SdsRepository._();

  Future<SdsResult>? _activeRequest;
  String? _activeRequestKey;

  bool get isBusy => _activeRequest != null;

  FirebaseFunctions? get _functions {
    if (Firebase.apps.isEmpty) return null;

    return FirebaseFunctions.instance;
  }

  Future<SdsResult> findByText(
    String query,
  ) async {
    final cleanQuery = query.trim();

    if (cleanQuery.isEmpty) {
      throw SdsException(
        'Please enter a chemical or product name.',
      );
    }

    return _runRequest({
      'query': cleanQuery,
    });
  }

  Future<SdsResult> findByImage({
    required String imageBase64,
    required String imageMediaType,
    String? query,
  }) async {
    if (imageBase64.trim().isEmpty) {
      throw SdsException(
        'The selected image is empty. '
        'Please choose another photo.',
      );
    }

    final mediaType =
        imageMediaType.trim().toLowerCase();

    if (!mediaType.startsWith('image/')) {
      throw SdsException(
        'The selected file is not a supported image.',
      );
    }

    final cleanQuery = query?.trim();

    return _runRequest({
      'imageBase64': imageBase64,
      'imageMediaType': mediaType,
      if (cleanQuery != null &&
          cleanQuery.isNotEmpty)
        'query': cleanQuery,
    });
  }

  Future<SdsResult> _runRequest(
    Map<String, dynamic> payload,
  ) async {
    final functions = _functions;

    if (functions == null) {
      throw SdsException(
        'Not connected yet. '
        'Please try again in a moment.',
      );
    }

    final requestKey = jsonEncode(payload);

    final active = _activeRequest;

    if (active != null) {
      if (_activeRequestKey == requestKey) {
        return active;
      }

      throw SdsException(
        'An SDS search is already running. '
        'Please wait for it to finish.',
      );
    }

    _activeRequestKey = requestKey;

    final request = _execute(
      functions,
      payload,
    );

    _activeRequest = request;

    try {
      return await request;
    } finally {
      _activeRequest = null;
      _activeRequestKey = null;
    }
  }

  Future<SdsResult> _execute(
    FirebaseFunctions functions,
    Map<String, dynamic> payload,
  ) async {
    try {
      final callable = functions.httpsCallable(
        'findSds',
        options: HttpsCallableOptions(
          timeout: const Duration(seconds: 60),
        ),
      );

      final result = await callable.call(payload);

      final data = result.data;

      if (data is! Map) {
        throw SdsException(
          'The SDS service returned an invalid response. '
          'Please try again.',
        );
      }

      return SdsResult.fromMap(
        Map<String, dynamic>.from(data),
      );

    } on SdsException {
      rethrow;

    } on FirebaseFunctionsException catch (error) {
      throw SdsException(
        _friendlyMessage(error),
        isQuotaExceeded:
            error.code == 'resource-exhausted',
      );

    } catch (_) {
      throw SdsException(
        'Could not complete the SDS search. '
        'Check your connection and try again.',
      );
    }
  }

  String _friendlyMessage(
    FirebaseFunctionsException error,
  ) {
    switch (error.code) {
      case 'resource-exhausted':
        return error.message ??
            'You have reached your daily SDS search limit.';

      case 'deadline-exceeded':
        return 'The SDS search is taking too long. '
            'Please try again.';

      case 'unavailable':
        return 'The SDS service is temporarily unavailable. '
            'Please try again shortly.';

      case 'unauthenticated':
        return 'Your connection could not be verified. '
            'Please try again in a moment.';

      case 'permission-denied':
        return 'Access to the SDS service '
            'could not be verified.';

      case 'invalid-argument':
        return error.message ??
            'Please check your search details.';

      default:
        return 'Something went wrong searching '
            'for the SDS. Please try again.';
    }
  }
}