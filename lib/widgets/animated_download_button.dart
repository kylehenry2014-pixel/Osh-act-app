import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum _DownloadState { idle, loading, success }

/// A reusable button that morphs between a download icon, a spinner, and a
/// checkmark as [onDownload] runs - used for any "save this file" action
/// (checklists, investigations, toolbox talks, legal appointments) so the
/// person gets clear feedback instead of the button just sitting there.
///
/// If [onDownload] throws, the button quietly returns to its idle state -
/// show any error message from the caller's side (e.g. a SnackBar) rather
/// than from here, since this widget only owns the icon/spinner/checkmark
/// visual, not error UI.
class AnimatedDownloadButton extends StatefulWidget {
  final Future<void> Function() onDownload;
  final String idleLabel;
  final IconData idleIcon;

  const AnimatedDownloadButton({
    super.key,
    required this.onDownload,
    this.idleLabel = 'Save',
    this.idleIcon = Icons.download_outlined,
  });

  @override
  State<AnimatedDownloadButton> createState() => _AnimatedDownloadButtonState();
}

class _AnimatedDownloadButtonState extends State<AnimatedDownloadButton> {
  _DownloadState _state = _DownloadState.idle;

  Future<void> _handleTap() async {
    if (_state != _DownloadState.idle) return;
    setState(() => _state = _DownloadState.loading);
    try {
      await widget.onDownload();
      if (!mounted) return;
      setState(() => _state = _DownloadState.success);
      await Future.delayed(const Duration(milliseconds: 1200));
    } catch (_) {
      // Caller is responsible for surfacing the error (e.g. a SnackBar);
      // this widget just resets back to idle so the person can retry.
    } finally {
      if (mounted) setState(() => _state = _DownloadState.idle);
    }
  }

  Widget _iconFor(_DownloadState state) {
    switch (state) {
      case _DownloadState.idle:
        return Icon(widget.idleIcon,
            key: const ValueKey('idle'), size: 20, color: AppColors.amberDeep);
      case _DownloadState.loading:
        return SizedBox(
          key: const ValueKey('loading'),
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
              strokeWidth: 2.2, color: AppColors.amberDeep),
        );
      case _DownloadState.success:
        return const Icon(Icons.check_circle,
            key: ValueKey('success'), size: 20, color: AppColors.green);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (_state) {
      _DownloadState.idle => widget.idleLabel,
      _DownloadState.loading => 'Saving...',
      _DownloadState.success => 'Saved',
    };

    return InkWell(
      onTap: _handleTap,
      borderRadius: BorderRadius.circular(2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.line),
          borderRadius: BorderRadius.circular(2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, animation) =>
                  ScaleTransition(scale: animation, child: child),
              child: _iconFor(_state),
            ),
            const SizedBox(width: 8),
            Text(label, style: AppText.label(size: 12, color: AppColors.ink)),
          ],
        ),
      ),
    );
  }
}
