import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Handles the ad-gated unlock system used across the app's ad-gated
/// features (Chat Bot answers, Toolbox Talk "Open"/"Save", SDS Finder
/// searches, Certificate Reminders).
///
/// Daily free/Pro usage caps for Chat Bot and SDS Finder are enforced
/// server-side, in the Cloud Functions those features call - not here.
/// This class's job is purely about the ad itself.
class AdService {
  AdService._();
  static final AdService instance = AdService._();

  static const String _rewardedAdUnitId =
      'ca-app-pub-5123635284859515/2402128555';

  static const String _testRewardedAdUnitId =
      'ca-app-pub-3940256099942544/5224354917';
  static const bool _useTestAds = true;

  static String get _adUnitId =>
      _useTestAds ? _testRewardedAdUnitId : _rewardedAdUnitId;

  Future<void> init() async {
    await MobileAds.instance.initialize();
  }

  Future<int> nextRequiredAdCount(String featureKey) async {
    return 1;
  }

  Future<void> recordUnlockedRequest(String featureKey) async {}

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

  Future<bool> watchAds(int count) async {
    for (var i = 0; i < count; i++) {
      final ad = await _loadAd();
      if (ad == null) return false;
      final earned = await _showAd(ad);
      if (!earned) return false;
    }
    return true;
  }

  Future<T?> runWithAd<T>({
    required bool isPro,
    required Future<T> Function() task,
  }) async {
    if (isPro) {
      return task();
    }

    T? taskResult;
    Object? taskError;
    StackTrace? taskStack;
    final taskFuture = task().then((v) {
      taskResult = v;
    }).catchError((Object e, StackTrace st) {
      taskError = e;
      taskStack = st;
    });

    final ad = await _loadAd();
    if (ad == null) {
      await taskFuture;
      if (taskError != null) {
        Error.throwWithStackTrace(taskError!, taskStack!);
      }
      return null;
    }

    final earned = await _showAd(ad);
    await taskFuture;

    if (taskError != null) {
      Error.throwWithStackTrace(taskError!, taskStack!);
    }
    if (!earned) return null;
    return taskResult;
  }
}
