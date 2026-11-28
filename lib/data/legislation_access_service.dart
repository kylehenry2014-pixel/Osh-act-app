import 'package:flutter/material.dart';

import 'ad_service.dart';
import 'subscription_repository.dart';

/// Shared advertisement gate for legislation entry points.
class LegislationAccessService {
  LegislationAccessService._();

  static final instance = LegislationAccessService._();

  static const _featureKey = 'act_section_open';

  bool _requestActive = false;

  bool _canContinue(BuildContext context) {
    return context.mounted &&
        ModalRoute.of(context)?.isCurrent == true &&
        TickerMode.of(context);
  }

  void _showMessage(BuildContext context, String message) {
    if (!_canContinue(context)) return;

    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> open({
    required BuildContext context,
    required Future<void> Function() onOpen,
  }) async {
    if (_requestActive || !_canContinue(context)) return;

    _requestActive = true;

    try {
      if (!SubscriptionRepository.instance.isPro) {
        final adCount = await AdService.instance
            .nextRequiredAdCount(_featureKey);

        if (!context.mounted) return;
        if (!_canContinue(context)) return;

        if (!SubscriptionRepository.instance.isPro) {
          if (AdService.instance.isBusy) {
            _showMessage(
              context,
              'Another advertisement is active. Please wait.',
            );
            return;
          }

          final confirmed = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Watch an ad to continue'),
              content: Text(
                adCount == 1
                    ? 'Watch a short ad to open this section.'
                    : 'Watch $adCount ads to open this section.',
              ),
              actions: [
                TextButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.of(dialogContext).pop(true),
                  child: const Text('Watch'),
                ),
              ],
            ),
          );

          if (!context.mounted) return;
          if (!_canContinue(context) || confirmed != true) {
            return;
          }

          if (!SubscriptionRepository.instance.isPro) {
            final earned =
                await AdService.instance.watchAds(adCount);

            if (!context.mounted) return;
            if (!_canContinue(context)) return;

            if (!earned) {
              _showMessage(
                context,
                'The advertisement was unavailable or incomplete. '
                'Please try again.',
              );
              return;
            }

            await AdService.instance.recordUnlockedRequest(
              _featureKey,
            );
          }
        }
      }

      if (!context.mounted) return;
      if (!_canContinue(context)) return;

      await onOpen();
    } catch (error) {
      debugPrint(
        'Legislation access failed: ${error.runtimeType}',
      );

      if (!context.mounted) return;

      _showMessage(
        context,
        'Unable to open this section. Please try again.',
      );
    } finally {
      _requestActive = false;
    }
  }
}