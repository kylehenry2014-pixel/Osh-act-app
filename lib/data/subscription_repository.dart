import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

class SubscriptionRepository {
  static final SubscriptionRepository instance = SubscriptionRepository._();
  SubscriptionRepository._();

  static const String monthlyProductId = 'ohs_act_remove_ads_monthly';
  static const Set<String> productIds = {monthlyProductId};

  final ValueNotifier<bool> isProNotifier = ValueNotifier<bool>(false);
  bool get isPro => isProNotifier.value;

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
    if (Firebase.apps.isEmpty) return;
    try {
      await _ensureSignedIn();
      final uid = _auth.currentUser!.uid;

      _entitlementSub?.cancel();
      _entitlementSub = _firestore
          .collection('subscriptions')
          .doc(uid)
          .snapshots()
          .listen((doc) {
        isProNotifier.value = _isActiveEntitlement(doc.data());
      });

      _purchaseSub?.cancel();
      _purchaseSub =
          _iap.purchaseStream.listen(_onPurchaseUpdate, onError: (_) {});
    } catch (_) {
      // Leave isProNotifier at its safe default (false) on any failure.
    }
  }

  bool _isActiveEntitlement(Map<String, dynamic>? data) {
    if (data == null) return false;
    if (data['isActive'] != true) return false;
    final expiresAt = data['expiresAt'];
    if (expiresAt is Timestamp && expiresAt.toDate().isBefore(DateTime.now())) {
      return false;
    }
    return true;
  }

  Future<List<ProductDetails>> queryProducts() async {
    if (Firebase.apps.isEmpty) return [];
    final available = await _iap.isAvailable();
    if (!available) return [];
    final response = await _iap.queryProductDetails(productIds);
    return response.productDetails;
  }

  Future<void> buy(ProductDetails product) async {
    final purchaseParam = PurchaseParam(productDetails: product);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  Future<void> restorePurchases() async {
    await _iap.restorePurchases();
  }

  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        await _verifyAndGrant(purchase);
      }
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }

  Future<void> _verifyAndGrant(PurchaseDetails purchase) async {
    try {
      final callable = _functions.httpsCallable('verifyPurchase');
      await callable.call<Map<String, dynamic>>({
        'productId': purchase.productID,
        'purchaseToken': purchase.verificationData.serverVerificationData,
        'platform': 'android',
      });
    } catch (_) {
      // Swallow - the Firestore listener is the source of truth.
    }
  }

  void dispose() {
    _entitlementSub?.cancel();
    _purchaseSub?.cancel();
  }
}
