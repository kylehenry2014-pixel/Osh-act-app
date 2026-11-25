import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Represents an allowance denial or an unsuccessful
/// allowance verification request.
class DownloadLimitException implements Exception {
  final String message;

  DownloadLimitException(this.message);
}

/// Server-reported allowance after one unit has been consumed.
/// A limit of zero indicates unavailable allowance counters.
class DownloadAllowance {
  final int used;
  final int limit;

  const DownloadAllowance(this.used, this.limit);

  bool get hasCounters => limit > 0;

  int get remaining {
    if (!hasCounters || used >= limit) return 0;
    return limit - used;
  }
}

/// Server-authorised daily download and certificate allowance.
///
/// Shared pool:
/// Free: 2/day.
/// Pro: 20/day.
///
/// Separate signage pool:
/// Free: 2/day.
/// Pro: 5/day.
///
/// The server remains responsible for entitlement verification,
/// daily limits and allowance consumption.
class DownloadAllowanceService {
  DownloadAllowanceService._();

  static final DownloadAllowanceService instance =
      DownloadAllowanceService._();

  static const _requestTimeout = Duration(seconds: 25);

  bool _requestInProgress = false;

  bool get isBusy => _requestInProgress;

  static const _uncertainMessage =
      'Could not confirm your download allowance. '
      'An allowance may already have been deducted. '
      'Please wait before trying again.';

  int? _readCounter(dynamic value) {
    if (value is! num ||
        !value.isFinite ||
        value < 0 ||
        value != value.truncateToDouble()) {
      return null;
    }

    return value.toInt();
  }

  DownloadAllowance _parseAllowance(dynamic data) {
    // Preserve compatibility with older successful responses
    // that do not contain allowance counters.
    if (data is! Map) {
      return const DownloadAllowance(0, 0);
    }

    if (data['allowed'] == false ||
        data['success'] == false) {
      throw DownloadLimitException(
        'The server did not authorise this download.',
      );
    }

    final used = _readCounter(data['used']);
    final limit = _readCounter(data['limit']);

    if (used == null ||
        limit == null ||
        limit == 0 ||
        used > limit) {
      debugPrint('Download allowance counters unavailable.');

      return const DownloadAllowance(0, 0);
    }

    return DownloadAllowance(used, limit);
  }

  /// Consume an allowance immediately before delivering a
  /// prepared document or committing a new certificate.
  ///
  /// Never automatically retry a consuming request.
  Future<DownloadAllowance> checkAndConsume({
    String? feature,
  }) async {
    if (feature != null && feature != 'signage') {
      throw DownloadLimitException(
        'Unsupported download category.',
      );
    }

    if (_requestInProgress) {
      throw DownloadLimitException(
        'Another download allowance request is active. '
        'Please wait for it to finish.',
      );
    }

    if (Firebase.apps.isEmpty) {
      throw DownloadLimitException(
        'Not connected yet. Please try again in a moment.',
      );
    }

    _requestInProgress = true;

    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable(
        'checkDownloadAllowance',
        options: HttpsCallableOptions(
          timeout: _requestTimeout,
        ),
      );

      final result = await callable.call(
        feature == null
            ? null
            : <String, dynamic>{
                'feature': feature,
              },
      );

      return _parseAllowance(result.data);

    } on DownloadLimitException {
      rethrow;

    } on TimeoutException {
      throw DownloadLimitException(_uncertainMessage);

    } on FirebaseFunctionsException catch (error) {
      debugPrint(
        'Download allowance request failed: ${error.code}',
      );

      switch (error.code) {
        case 'resource-exhausted':
          throw DownloadLimitException(
            error.message ??
                "You've reached today's download limit.",
          );

        case 'unauthenticated':
          throw DownloadLimitException(
            'Your session could not be verified. '
            'Please reopen the application.',
          );

        case 'permission-denied':
          throw DownloadLimitException(
            'The server did not authorise this download.',
          );

        case 'deadline-exceeded':
        case 'unavailable':
        case 'cancelled':
        case 'internal':
        case 'unknown':
          throw DownloadLimitException(_uncertainMessage);

        default:
          throw DownloadLimitException(
            'Could not verify your download allowance. '
            'Please try again later.',
          );
      }

    } catch (_) {
      debugPrint('Unexpected download allowance failure.');

      throw DownloadLimitException(_uncertainMessage);

    } finally {
      _requestInProgress = false;
    }
  }
}