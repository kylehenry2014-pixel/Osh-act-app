
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import '../data/subscription_repository.dart';
import '../theme/app_theme.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  List<ProductDetails> _products = [];
  bool _loading = true;
  bool _purchasing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await SubscriptionRepository.instance.queryProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _loading = false;
        if (products.isEmpty) {
          _error =
              'Subscriptions aren\'t available yet. Please try again later.';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load subscription options. Please try again later.';
      });
    }
  }

  Future<void> _buy(ProductDetails product) async {
    setState(() {
      _purchasing = true;
      _error = null;
    });
    try {
      await SubscriptionRepository.instance.buy(product);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error =
              'Something went wrong starting the purchase. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  Future<void> _restore() async {
    setState(() {
      _purchasing = true;
      _error = null;
    });
    try {
      await SubscriptionRepository.instance.restorePurchases();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not restore purchases. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _purchasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        title: Text('Remove Ads', style: AppText.headline(size: 18)),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      body: ValueListenableBuilder<bool>(
        valueListenable: SubscriptionRepository.instance.isProNotifier,
        builder: (context, isPro, _) {
          if (isPro) return _AlreadySubscribed();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.workspace_premium_outlined,
                    size: 40, color: AppColors.amberDeep),
                const SizedBox(height: 16),
                Text('Skip the ads', style: AppText.headline(size: 22)),
                const SizedBox(height: 10),
                Text(
                  'Get unlimited access to the Safety Chat Bot, Checklists, and '
                  'Certificate Reminders - no ads to watch, ever.',
                  style: AppText.body(size: 15, color: AppColors.steel),
                ),
                const SizedBox(height: 28),
                if (_loading) ...[
                  const Center(
                      child: CircularProgressIndicator(
                          color: AppColors.amberDeep)),
                ] else ...[
                  for (final product in _products)
                    _PlanCard(
                      product: product,
                      enabled: !_purchasing,
                      onTap: () => _buy(product),
                    ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!,
                      style: AppText.label(size: 12, color: AppColors.red)),
                ],
                const SizedBox(height: 20),
                Center(
                  child: TextButton(
                    onPressed: _purchasing ? null : _restore,
                    child: Text(
                      'Restore purchases',
                      style: AppText.label(size: 12, color: AppColors.steel),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final ProductDetails product;
  final bool enabled;
  final VoidCallback onTap;

  const _PlanCard(
      {required this.product, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.paperRaised,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(product.title,
                        style: AppText.headline(
                            size: 16, weight: FontWeight.w600)),
                    const SizedBox(height: 3),
                    Text(product.description, style: AppText.label(size: 11)),
                  ],
                ),
              ),
              Text(
                product.price,
                style: AppText.headline(size: 16, weight: FontWeight.w700)
                    .copyWith(color: AppColors.amberDeep),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlreadySubscribed extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline, size: 44, color: AppColors.green),
            const SizedBox(height: 16),
            Text('You\'re subscribed', style: AppText.headline(size: 18)),
            const SizedBox(height: 8),
            Text(
              'Ads are removed across the Safety Chat Bot, Checklists, and '
              'Certificate Reminders.',
              textAlign: TextAlign.center,
              style: AppText.body(size: 14, color: AppColors.steel),
            ),
          ],
        ),
      ),
    );
  }
}
