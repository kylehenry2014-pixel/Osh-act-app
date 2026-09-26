import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

/// Thrown when the daily download/add allowance has been used up.
class DownloadLimitException implements Exception {
  final String message;
  DownloadLimitException(this.message);
}

/// Checks and consumes one unit of the shared daily download/add
/// allowance (Toolbox Talks saves, SDS saves, adding a Certificate) -
/// 2/day for free users, 20/day for Pro, enforced server-side via the
/// checkDownloadAllowance Cloud Function so it can't be bypassed by
/// clearing local app data.
class DownloadAllowanceService {
  DownloadAllowanceService._();
  static final DownloadAllowanceService instance = DownloadAllowanceService._();

  /// Call this right before actually performing a save/download/add.
  /// Throws [DownloadLimitException] if the daily limit has been
  /// reached - the caller should show that message and not proceed.
  Future<void> checkAndConsume() async {
    if (Firebase.apps.isEmpty) {
      throw DownloadLimitException(
          'Not connected yet. Please try again in a moment.');
    }
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('checkDownloadAllowance');
      await callable.call();
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'resource-exhausted') {
        throw DownloadLimitException(
            e.message ?? "You've reached today's download limit.");
      }
      throw DownloadLimitException(
          'Something went wrong checking your download allowance. Please try again.');
    }
  }
}
