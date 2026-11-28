import 'package:flutter/material.dart';
import '../theme/app_icons.dart';
import '../theme/appearance_controller.dart';

class AppearanceSelector extends StatelessWidget {
  const AppearanceSelector({super.key});

  Future<void> _select(
    BuildContext context,
    ThemeMode mode,
  ) async {
    final saved =
        await AppearanceController.instance.setMode(mode);

    if (!saved && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save appearance. Please try again.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final appearance = AppearanceController.instance;

    return ListenableBuilder(
      listenable: appearance,
      builder: (context, _) {
        final enabled =
            appearance.isLoaded && !appearance.isSaving;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF3B3E35),
                Color(0xFF252820),
                Color(0xFF171916),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: const Color(0xFFDA9B2A),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(
                children: [
                  Icon(
                    AppIcons.paletteOutlined,
                    color: Color(0xFFFFE4A0),
                    size: 28,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Appearance',
                          style: TextStyle(
                            color: Color(0xFFF7F3E6),
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Personalise your experience',
                          style: TextStyle(
                            color: Color(0xFFC5C6BB),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _option(
                context,
                mode: ThemeMode.light,
                selected: appearance.mode,
                enabled: enabled,
                icon: AppIcons.lightModeOutlined,
                title: 'Light',
                subtitle: 'Classic cream and gold',
              ),
              const SizedBox(height: 8),
              _option(
                context,
                mode: ThemeMode.dark,
                selected: appearance.mode,
                enabled: enabled,
                icon: AppIcons.darkModeOutlined,
                title: 'Dark',
                subtitle: 'Premium charcoal and gold',
              ),
              const SizedBox(height: 12),
              Text(
                appearance.isSaving
                    ? 'Saving appearance...'
                    : !appearance.isLoaded
                        ? 'Loading appearance...'
                        : 'Your preference is saved automatically.',
                style: const TextStyle(
                  color: Color(0xFFC5C6BB),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _option(
    BuildContext context, {
    required ThemeMode mode,
    required ThemeMode selected,
    required bool enabled,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final active = selected == mode;
    final radius = BorderRadius.circular(12);

    return Semantics(
      selected: active,
      button: true,
      enabled: enabled,
      child: Material(
        color: active
            ? const Color(0xFF49402A)
            : const Color(0xFF30332C),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
            color: active
                ? const Color(0xFFDA9B2A)
                : const Color(0xFF55594E),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled
              ? () => _select(context, mode)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: const Color(0xFFFFE4A0),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFFF7F3E6),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: Color(0xFFC5C6BB),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  active
                      ? AppIcons.checkCircle
                      : AppIcons.radioButtonUnchecked,
                  color: active
                      ? const Color(0xFFDA9B2A)
                      : const Color(0xFF85897D),
                  size: 21,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}