import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mornye/l10n/l10n.dart';
import 'package:mornye/models/slowed_reverb_settings.dart';
import 'package:mornye/providers/slowed_reverb_provider.dart';
import 'package:mornye/services/playback_slowed_reverb.dart';
import 'package:mornye/theme/mornye_theme.dart';
import 'package:mornye/widgets/app_bottom_sheet.dart';
import 'package:mornye/widgets/app_icon.dart';
import 'package:mornye/widgets/app_slider.dart';
import 'package:mornye/widgets/expressive_icon_button.dart';
import 'package:mornye/widgets/slider_value_header.dart';

/// The effect is applied by the Darwin AVPlayer fork. Android, Windows and
/// Linux keep ordinary playback, so the control is not shown there.
bool get slowedReverbSupported {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS || TargetPlatform.macOS => true,
    _ => false,
  };
}

/// System output button (AirPlay on iOS, the route picker on Android).
bool get playerFooterShowsSystemOutput {
  if (kIsWeb) return false;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android || TargetPlatform.iOS => true,
    _ => false,
  };
}

/// How wide one Now Playing footer control should be.
///
/// Lyrics, shuffle, repeat, slowed + reverb and the output button share the
/// row. They stay at [max] until a narrow phone, then shrink together, and
/// never go below the 48 dp touch target.
double playerFooterSegmentWidth({
  required double available,
  required int slots,
  required double connectedGap,
  double max = 56,
  double min = 48,
}) {
  if (slots <= 0 || !available.isFinite || available <= 0) return max;
  final natural = max * slots + connectedGap;
  if (natural <= available) return max;
  final fitted = (available - connectedGap) / slots;
  if (fitted < min) return min;
  if (fitted > max) return max;
  return fitted;
}

/// One tap toggles slowed + reverb. A long press opens the speed and reverb
/// sliders, which preview on the song that is already playing.
class SlowedReverbButton extends ConsumerWidget {
  const SlowedReverbButton({super.key, this.width = 56, this.onSheetChanged});

  final double width;
  final ValueChanged<bool>? onSheetChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!slowedReverbSupported) return const SizedBox.shrink();
    final enabled = ref.watch(
      slowedReverbProvider.select((settings) => settings.enabled),
    );
    final l10n = context.l10n;
    final tooltip = enabled ? l10n.slowedReverbOn : l10n.slowedReverb;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      toggled: enabled,
      hint: l10n.slowedReverbTuneHint,
      child: context.isMornye
          ? IconButton(
              tooltip: tooltip,
              isSelected: enabled,
              color: scheme.onSurface,
              style: IconButton.styleFrom(
                backgroundColor: enabled
                    ? scheme.onSurface.withValues(alpha: 0.16)
                    : Colors.transparent,
              ),
              icon: const AppIcon(Icons.waves),
              onPressed: () => _toggle(ref, enabled),
              onLongPress: () => _openSheet(context),
            )
          : ExpressiveIconButton(
              tooltip: tooltip,
              selected: enabled,
              width: width,
              foregroundColor: enabled
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
              backgroundColor: enabled
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHigh,
              icon: const AppIcon(Icons.waves),
              onPressed: () => _toggle(ref, enabled),
              onLongPress: () => _openSheet(context),
            ),
    );
  }

  void _toggle(WidgetRef ref, bool enabled) {
    ref.read(slowedReverbProvider.notifier).setEnabled(!enabled);
  }

  Future<void> _openSheet(BuildContext context) async {
    onSheetChanged?.call(true);
    await showAppBottomSheet<void>(
      context: context,
      title: context.l10n.slowedReverbTune,
      builder: (context) => const SlowedReverbSheet(),
    );
    onSheetChanged?.call(false);
  }
}

class SlowedReverbSheet extends ConsumerWidget {
  const SlowedReverbSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(slowedReverbProvider);
    final notifier = ref.read(slowedReverbProvider.notifier);
    final l10n = context.l10n;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.slowedReverbDescription,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final preset in SlowedReverbPreset.values)
                ChoiceChip(
                  label: Text(_presetLabel(l10n, preset)),
                  selected: settings.matches(preset),
                  onSelected: (_) => notifier.applyPreset(preset),
                ),
            ],
          ),
        ),
        _slider(
          context,
          title: l10n.slowedReverbSpeed,
          valueLabel: '${settings.rate.toStringAsFixed(2)}×',
          value: settings.rate,
          min: 0.7,
          max: 1,
          divisions: 30,
          onChanged: notifier.setRate,
        ),
        _slider(
          context,
          title: l10n.slowedReverbMix,
          valueLabel: '${(settings.mix * 100).round()}%',
          value: settings.mix,
          min: 0,
          max: 1,
          divisions: 100,
          onChanged: notifier.setMix,
        ),
        _slider(
          context,
          title: l10n.slowedReverbRoom,
          valueLabel: '${(settings.room * 100).round()}%',
          value: settings.room,
          min: 0,
          max: 1,
          divisions: 100,
          onChanged: notifier.setRoom,
        ),
        ValueListenableBuilder<String?>(
          valueListenable: playbackSlowedReverbError,
          builder: (context, error, _) {
            if (error == null) return const SizedBox(height: 8);
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                error,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  String _presetLabel(AppLocalizations l10n, SlowedReverbPreset preset) =>
      switch (preset) {
        SlowedReverbPreset.light => l10n.slowedReverbPresetLight,
        SlowedReverbPreset.classic => l10n.slowedReverbPresetClassic,
        SlowedReverbPreset.heavy => l10n.slowedReverbPresetHeavy,
      };

  Widget _slider(
    BuildContext context, {
    required String title,
    required String valueLabel,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SliderValueHeader(title: title, value: valueLabel),
          AppSlider(
            value: value.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: divisions,
            semanticLabel: '$title: $valueLabel',
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
