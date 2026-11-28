import 'package:flutter/material.dart';

import '../data/app_rating_service.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';

enum AppRatingAction {
  rate,
  remindLater,
  dontAskAgain,
}

class AppRatingDialog extends StatefulWidget {
  const AppRatingDialog({super.key});

  static Future<AppRatingAction?> show(
    BuildContext context,
  ) {
    return showDialog<AppRatingAction>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AppRatingDialog(),
    );
  }

  @override
  State<AppRatingDialog> createState() =>
      _AppRatingDialogState();
}

class _AppRatingDialogState
    extends State<AppRatingDialog> {
  final _service = AppRatingService.instance;

  bool _busy = false;
  String? _error;

  Future<void> _handle(
    AppRatingAction action,
  ) async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      switch (action) {
        case AppRatingAction.rate:
          final opened =
              await _service.openGooglePlay();

          if (!opened) {
            throw StateError(
              'Google Play could not be opened.',
            );
          }
          break;

        case AppRatingAction.remindLater:
          await _service.remindLater();
          break;

        case AppRatingAction.dontAskAgain:
          await _service.dontAskAgain();
          break;
      }

      if (!mounted) return;

      Navigator.of(context).pop(action);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _busy = false;
        _error =
            'Unable to complete this action. '
            'Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return PopScope(
      canPop: !_busy,
      child: Dialog(
        backgroundColor: palette.surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(
          horizontal: 24,
          vertical: 24,
        ),
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(
            color: palette.border,
          ),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 420,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    24, 30, 24, 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ExcludeSemantics(
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: List.generate(
                            5,
                            (index) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: Icon(
                                Icons.star_rounded,
                                size: 28,
                                color: palette.accent,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        'Rate our app',
                        textAlign: TextAlign.center,
                        style: AppText.headline(
                          size: 24,
                        ).copyWith(
                          color: palette.text,
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'Your feedback helps us improve '
                        'OHS Act & Regulations and build '
                        'better tools for safety professionals.',
                        textAlign: TextAlign.center,
                        style: AppText.body(
                          size: 14,
                          color: palette.secondaryText,
                        ),
                      ),
                      const SizedBox(height: 24),
                      if (_error != null) ...[
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: AppText.body(
                            size: 12,
                            color: palette.error,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: FilledButton(
                          onPressed: _busy
                              ? null
                              : () => _handle(
                                    AppRatingAction.rate,
                                  ),
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                AppColors.amber,
                            foregroundColor:
                                AppColors.ink,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(12),
                            ),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      AppIcons.starOutlineRounded,
                                      size: 21,
                                    ),
                                    const SizedBox(width: 9),
                                    Text(
                                      'Rate the App',
                                      style: AppText.headline(
                                        size: 14,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _handle(
                                  AppRatingAction.remindLater,
                                ),
                        child: Text(
                          'Remind me later',
                          style: AppText.body(
                            size: 14,
                            color: palette.text,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () => _handle(
                                  AppRatingAction.dontAskAgain,
                                ),
                        child: Text(
                          "Don't ask again",
                          style: AppText.body(
                            size: 12,
                            color: palette.secondaryText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const HazardStripe(height: 7),
              ],
            ),
          ),
        ),
      ),
    );
  }
}