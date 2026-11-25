import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Handles rewarded advertisement access across the application.
///
/// Server-side feature quotas remain enforced by Cloud Functions.
class AdService {
  AdService._();

  static final AdService instance = AdService._();

  static const String _rewardedAdUnitId =
      'ca-app-pub-5123635284859515/2402128555';

  static const String _testRewardedAdUnitId =
      'ca-app-pub-3940256099942544/5224354917';

  static const bool _useTestAds = false;

  static String get _adUnitId =>
      _useTestAds ? _testRewardedAdUnitId : _rewardedAdUnitId;

  static const _initialisationTimeout = Duration(seconds: 15);
  static const _loadTimeout = Duration(seconds: 20);
  static const _showTimeout = Duration(seconds: 180);
  static const _cacheLifetime = Duration(minutes: 45);

  bool _initialised = false;
  bool _watchingAds = false;
  bool _presentationActive = false;

  Future<void>? _initialising;
  Future<void>? _preloading;

  RewardedAd? _cachedAd;
  DateTime? _cachedAt;

  bool get isBusy => _watchingAds || _presentationActive;

  Future<void> init() async {
    if (_initialised) return;

    final pending = _initialising;

    if (pending != null) {
      await pending.timeout(_initialisationTimeout);
      return;
    }

    final operation = _initialiseSdk();

    _initialising = operation;

    unawaited(operation.then<void>(
      (_) {
        if (identical(_initialising, operation)) {
          _initialising = null;
        }
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_initialising, operation)) {
          _initialising = null;
        }
      },
    ));

    await operation.timeout(_initialisationTimeout);
  }

  Future<void> _initialiseSdk() async {
    await MobileAds.instance.initialize();
    _initialised = true;
  }

  Future<int> nextRequiredAdCount(String featureKey) async {
    return 1;
  }

  Future<void> recordUnlockedRequest(String featureKey) async {}

  Future<void> _disposeAd(RewardedAd ad) async {
    try {
      await ad.dispose();
    } catch (_) {
      debugPrint('Rewarded advertisement disposal failed.');
    }
  }

  Future<RewardedAd?> _loadAd() async {
    try {
      await init();
    } catch (_) {
      debugPrint('Advertisement SDK unavailable.');
      return null;
    }

    final completer = Completer<RewardedAd?>();

    final timer = Timer(_loadTimeout, () {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    });

    Future<void> requestAd() async {
      try {
        await RewardedAd.load(
          adUnitId: _adUnitId,
          request: const AdRequest(),
          rewardedAdLoadCallback: RewardedAdLoadCallback(
            onAdLoaded: (ad) {
              if (completer.isCompleted) {
                unawaited(_disposeAd(ad));
                return;
              }

              completer.complete(ad);
            },
            onAdFailedToLoad: (error) {
              debugPrint(
                'Rewarded advertisement load failed: ${error.code}',
              );

              if (!completer.isCompleted) {
                completer.complete(null);
              }
            },
          ),
        );
      } catch (_) {
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      }
    }

    unawaited(requestAd());

    try {
      return await completer.future;
    } finally {
      timer.cancel();
    }
  }

  bool get _cacheValid {
    final loadedAt = _cachedAt;

    if (_cachedAd == null || loadedAt == null) {
      return false;
    }

    final age = DateTime.now().difference(loadedAt);

    return !age.isNegative && age < _cacheLifetime;
  }

  Future<void> _clearCache() async {
    final ad = _cachedAd;

    _cachedAd = null;
    _cachedAt = null;

    if (ad != null) {
      await _disposeAd(ad);
    }
  }

  Future<void> preload() async {
    if (_cacheValid || isBusy) return;

    final pending = _preloading;

    if (pending != null) {
      await pending;
      return;
    }

    final operation = _preloadOnce();

    _preloading = operation;

    try {
      await operation;
    } finally {
      if (identical(_preloading, operation)) {
        _preloading = null;
      }
    }
  }

  Future<void> _preloadOnce() async {
    try {
      await _clearCache();

      final ad = await _loadAd();

      if (ad == null) return;

      _cachedAd = ad;
      _cachedAt = DateTime.now();
    } catch (_) {
      debugPrint('Advertisement preload unavailable.');
    }
  }

  Future<RewardedAd?> _takeAd() async {
    final pending = _preloading;

    if (pending != null) {
      await pending;
    }

    if (_cacheValid) {
      final ad = _cachedAd;

      _cachedAd = null;
      _cachedAt = null;

      return ad;
    }

    await _clearCache();

    return _loadAd();
  }

  Future<bool> _showAd(RewardedAd ad) async {
    if (_presentationActive) {
      await _disposeAd(ad);
      return false;
    }

    _presentationActive = true;

    final completer = Completer<bool>();

    var rewardEarned = false;
    var closed = false;

    void finish(bool earned) {
      if (closed) return;

      closed = true;
      _presentationActive = false;

      unawaited(_disposeAd(ad));

      if (!completer.isCompleted) {
        completer.complete(earned);
      }
    }

    final timer = Timer(_showTimeout, () {
      if (!completer.isCompleted) {
        debugPrint('Advertisement presentation timed out.');
        completer.complete(false);
      }

      // Keep the presentation lock until the SDK confirms
      // dismissal or failure. Never open another fullscreen
      // advertisement over a potentially active one.
    });

    Future<void> present() async {
      try {
        ad.fullScreenContentCallback = FullScreenContentCallback(
          onAdDismissedFullScreenContent: (_) {
            finish(rewardEarned);
          },
          onAdFailedToShowFullScreenContent: (_, error) {
            debugPrint(
              'Rewarded advertisement show failed: ${error.code}',
            );

            finish(false);
          },
        );

        await ad.show(
          onUserEarnedReward: (_, reward) {
            if (!closed && !completer.isCompleted) {
              rewardEarned = true;
            }
          },
        );
      } catch (_) {
        finish(false);
      }
    }

    unawaited(present());

    try {
      return await completer.future;
    } finally {
      timer.cancel();
    }
  }

  Future<bool> watchAds(int count) async {
    if (count <= 0 || isBusy) return false;

    _watchingAds = true;

    try {
      for (var i = 0; i < count; i++) {
        final ad = await _takeAd();

        if (ad == null) return false;

        final earned = await _showAd(ad);

        if (!earned) return false;
      }

      return true;
    } catch (_) {
      debugPrint('Rewarded advertisement unavailable.');
      return false;
    } finally {
      _watchingAds = false;

      if (!_presentationActive) {
        unawaited(preload());
      }
    }
  }

  Future<T?> runWithAd<T>({
    required bool isPro,
    required Future<T> Function() task,
  }) async {
    if (isPro) {
      return task();
    }

    final earned = await watchAds(1);

    if (!earned) return null;

    // Execute the requested operation only after the
    // advertisement reward has been earned.
    return task();
  }
}