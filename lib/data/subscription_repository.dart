import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Temporary: while true, the Remove Ads card always shows on the More screen
/// and the subscription screen explains why products could not be loaded.
/// Set to false once the paywall works, to restore the normal behaviour.
const bool kShowPaywallDiagnostics = true;

class SubscriptionRepository {
  static final SubscriptionRepository instance = SubscriptionRepository._();
  SubscriptionRepository._();

  static const String monthlyProductId = 'ohs_act_remove_ads_monthly';
  static const Set<String> productIds = {monthlyProductId};

  final ValueNotifier<bool> isProNotifier = ValueNotifier<bool>(false);
  DateTime? _entitlementExpiry;
  Timer? _expiryTimer;

  bool get isPro =>
      isProNotifier.value &&
      (_entitlementExpiry?.isAfter(DateTime.now()) ?? false);

  void _clearEntitlement() {
    _expiryTimer?.cancel();
    _expiryTimer = null;
    _entitlementExpiry = null;
    isProNotifier.value = false;
  }

  void _applyEntitlement(Map<String, dynamic>? data) {
    _expiryTimer?.cancel();

    if (!_isActiveEntitlement(data)) {
      _clearEntitlement();
      return;
    }

    final expiry = (data!['expiresAt'] as Timestamp).toDate();

    _entitlementExpiry = expiry;

    final remaining = expiry.difference(DateTime.now());

    if (remaining <= Duration.zero) {
      _clearEntitlement();
      return;
    }

    isProNotifier.value = true;

    _expiryTimer = Timer(remaining, _clearEntitlement);
  }

  FirebaseAuth get _auth => FirebaseAuth.instance;
  FirebaseFunctions get _functions => FirebaseFunctions.instance;
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  InAppPurchase get _iap => InAppPurchase.instance;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _entitlementSub;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  Future<void> _ensureSignedIn() async {
    if (_auth.currentUser == null) {
      await _auth.signInAnonymously();
    }
  }

  Future<void> init() async {
    try {
      await _purchaseSub?.cancel();

      _purchaseSub = _iap.purchaseStream.listen(
        _onPurchaseUpdate,
        onError: (Object error) {
          debugPrint('Purchase stream error: $error');
        },
      );
    } catch (error) {
      debugPrint('Purchase listener error: $error');
    }

    if (Firebase.apps.isEmpty) return;

    try {
      await _ensureSignedIn();
      final uid = _auth.currentUser!.uid;

      await _entitlementSub?.cancel();
      _clearEntitlement();

      _entitlementSub = _firestore
          .collection('subscriptions')
          .doc(uid)
          .snapshots()
          .listen((doc) {
        _applyEntitlement(doc.data());
      }, onError: (Object error) {
        _clearEntitlement();
        debugPrint('Subscription entitlement unavailable.');
      });


    } catch (_) {
      _clearEntitlement();
    }
  }

  bool _isActiveEntitlement(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (data['isActive'] != true) return false;
    final expiresAt = data['expiresAt'];

    // Missing or invalid expiry information must never
    // grant a paid entitlement.
    if (expiresAt is! Timestamp) return false;

    return expiresAt.toDate().isAfter(DateTime.now());
  }

  /// A short, human-readable reason for the last empty product query. Only
  /// shown on screen while kShowPaywallDiagnostics is true.
  String? lastQueryDiagnostic;

  Future<List<ProductDetails>>? _inFlightQuery;

  /// Calls made while a query is already running share that one query.
  Future<List<ProductDetails>> queryProducts() {
    return _inFlightQuery ??=
        _queryProductsOnce().whenComplete(() => _inFlightQuery = null);
  }

  Future<List<ProductDetails>> _queryProductsOnce() async {
    lastQueryDiagnostic = null;
    var stage = 'connecting to Play billing';
    try {

      final available = await _iap.isAvailable().timeout(const Duration(seconds: 15));
      if (!available) {
        lastQueryDiagnostic =
            'Google Play Billing is not available. Is the app installed from Google Play, and is the Play Store up to date?';
        return [];
      }
      stage = 'loading the product from Play';
      final response = await _iap.queryProductDetails(productIds).timeout(const Duration(seconds: 45));
      final error = response.error;
      if (error != null) {
        lastQueryDiagnostic =
            'Play returned an error: ' + error.code + ' - ' + error.message;
      } else if (response.notFoundIDs.isNotEmpty) {
        lastQueryDiagnostic = 'Play did not find these product IDs: ' +
            response.notFoundIDs.join(', ') +
            ' (check the ID, and that the subscription and its base plan are Active).';
      } else if (response.productDetails.isEmpty) {
        lastQueryDiagnostic = 'Play returned no products.';
      }
      return response.productDetails;
    } catch (e) {
      lastQueryDiagnostic = 'Error while ' + stage + ': ' + e.toString();
      return [];
    }
  }

  Future<void> buy(ProductDetails product) async {
    if (Firebase.apps.isEmpty) {
      throw StateError('Purchase verification is unavailable.');
    }

    await _ensureSignedIn().timeout(const Duration(seconds: 20));

    final purchaseParam = PurchaseParam(productDetails: product);
    final launched = await _iap.buyNonConsumable(
      purchaseParam: purchaseParam,
    );

    if (!launched) {
      throw StateError('Google Play could not start the purchase.');
    }
  }

  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        final verified = await _verifyAndGrant(purchase);
        // Acknowledge only after the server confirms the purchase with Google.
        if (verified && purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
      } else if ((purchase.status == PurchaseStatus.error || purchase.status == PurchaseStatus.canceled) && purchase.pendingCompletePurchase) {
        // Error or canceled purchases must still be completed.
        await _iap.completePurchase(purchase);
      }
    }
  }

  Future<bool> _verifyAndGrant(PurchaseDetails purchase) async {
    try {
      if (Firebase.apps.isEmpty) return false;

      await _ensureSignedIn().timeout(const Duration(seconds: 20));

      final callable = _functions.httpsCallable('verifyPurchase');
      await callable.call<Map<String, dynamic>>({
        'productId': purchase.productID,
        'purchaseToken': purchase.verificationData.serverVerificationData,
        'platform': 'android',
      });
      return true;
    } catch (_) {
      // Verification failed (rejected or network). Leave the purchase
      // unacknowledged so it is delivered again and retried on the next launch.
      return false;
    }
  }

  void dispose() {
    _clearEntitlement();
    _entitlementSub?.cancel();
    _purchaseSub?.cancel();
  }
}
