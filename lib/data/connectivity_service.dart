import 'package:connectivity_plus/connectivity_plus.dart';

/// Checks whether the device currently has an internet connection. Used to
/// block access to the three ad-gated features (Chat Bot, Checklists,
/// Certificate Reminders) when offline - Chat Bot needs a live network
/// call regardless, and the other two are ad-supported, which also
/// requires connectivity.
class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  Future<bool> isOnline() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return !result.contains(ConnectivityResult.none);
    } catch (_) {
      // If the check itself fails, fail open (assume online) rather than
      // blocking the user over a broken check.
      return true;
    }
  }
}
