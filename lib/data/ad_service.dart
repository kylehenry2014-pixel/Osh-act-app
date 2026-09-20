import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles the ad-gated unlock system used across the app's ad-gated
/// features (Chat Bot answers, Toolbox Talk "Open", SDS Finder searches,
/// Certificate Reminders).
///
/// Each feature is identified by a short [featureKey] (e.g. 'chat',
/// 'toolbox_talk_open', 'sds_finder', 'certificates'). Every request
/// requires watching exactly one rewarded ad to unlock - no escalation.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  // The real ad unit for the OSH Act App (AdMob console, "chat_unlock").
  static const String _rewardedAdUnitId =
      'ca-app-pub-5123635284859515/2402128555';

  // Google's official test ad unit ID - always serves a real, safe test ad.
  // Use this while developing so you never risk serving real ads to
  // yourself, which can get an AdMob account flagged for invalid traffic.
  // Swap _useTestAds to false before publishing to the Play Store.
  static const String _testRewardedAdUnitId =
      'ca-app-pub-3940256099942544/5224354917';
  static const bool _useTestAds = true;

  static String get _adUnitId =>
      _useTestAds ? _testRewardedAdUnitId : _rewardedAdUnitId;

  Future<void> init() async {
    await MobileAds.instance.initialize();
  }

  /// Always requires exactly one ad per request - no escalation.
  Future<int> nextRequiredAdCount(String featureKey) async {
    return 1;
  }

  /// Call once the user has successfully watched the required ad(s) for
  /// [featureKey], to record that this request is now unlocked.
  Future<void> recordUnlockedRequest(String featureKey) async {
    final prefs = await SharedPreferences.getInstance();
    final today = _dateKey();
    await prefs.setString('ads_${featureKey}_date', today);
    await prefs.setInt(
      'ads_${featureKey}_count',
      (prefs.getInt('ads_${featureKey}_count') ?? 0) + 1,
    );
  }

  String _dateKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month}-${now.day}';
  }

  Future<RewardedAd?> _loadAd() async {
    final completer = Completer<RewardedAd?>();
    RewardedAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) => completer.complete(ad),
        onAdFailedToLoad: (error) => completer.complete(null),
      ),
    );
    return completer.future;
  }

  Future<bool> _showAd(RewardedAd ad) async {
    final completer = Completer<bool>();
    var rewardEarned = false;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete(rewardEarned);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete(false);
      },
    );
    ad.show(onUserEarnedReward: (ad, reward) {
      rewardEarned = true;
    });
    return completer.future;
  }

  /// Shows [count] rewarded ads back-to-back. Returns true only if the
  /// user watched every single one through to completion and earned the
  /// reward each time; false if any ad failed to load, or the user
  /// dismissed one early without earning the reward - in which case no
  /// request should be unlocked and the caller should not proceed.
  Future<bool> watchAds(int count) async {
    for (var i = 0; i < count; i++) {
      final ad = await _loadAd();
      if (ad == null) return false;
      final earned = await _showAd(ad);
      if (!earned) return false;
    }
    return true;
  }
}
