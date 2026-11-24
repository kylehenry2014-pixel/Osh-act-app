import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';

/// Thrown when the daily download/add allowance has been used up.
class DownloadLimitException implements Exception {
  final String message;
  DownloadLimitException(this.message);
}

/// What the server reports after one unit has been consumed. [limit] is 0
/// when an older server version did not send the numbers.
class DownloadAllowance {
  final int used;
  final int limit;
  const DownloadAllowance(this.used, this.limit);
}

/// Checks and consumes one unit of a daily download/add allowance, enforced
/// server-side via the checkDownloadAllowance Cloud Function so it can't be
/// bypassed by clearing local app data.
///
/// With no [feature], this is the shared pool (Toolbox Talks saves, SDS
/// saves, adding a Certificate): 2/day free, 20/day Pro.
/// With feature 'signage', signage downloads have their own pool:
/// 2/day free, 5/day Pro.
class DownloadAllowanceService {
  DownloadAllowanceService._();
  static final DownloadAllowanceService instance = DownloadAllowanceService._();

  /// Call this right before actually performing a save/download/add.
  /// Throws [DownloadLimitException] if the daily limit has been
  /// reached - the caller should show that message and not proceed.
  Future<DownloadAllowance> checkAndConsume({String? feature}) async {
    if (Firebase.apps.isEmpty) {
      throw DownloadLimitException(
          'Not connected yet. Please try again in a moment.');
    }
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('checkDownloadAllowance');
      final result = await callable
          .call(feature == null ? null : <String, dynamic>{'feature': feature});
      final data = result.data;
      var used = 0;
      var limit = 0;
      if (data is Map) {
        used = (data['used'] as num?)?.toInt() ?? 0;
        limit = (data['limit'] as num?)?.toInt() ?? 0;
      }
      return DownloadAllowance(used, limit);
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