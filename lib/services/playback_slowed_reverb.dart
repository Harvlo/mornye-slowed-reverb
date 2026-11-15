import 'package:flutter/foundation.dart';
import 'package:mornye/models/slowed_reverb_settings.dart';

/// Shared by every playback deck, including AutoMix's incoming deck.
///
/// The Darwin player multiplies whatever transport rate it was given by
/// [SlowedReverbSettings.rate] while the effect is on. Dart keeps sending the
/// transport rate unchanged so AutoMix's beat matching still sees the rate it
/// requested.
final playbackSlowedReverb = ValueNotifier<SlowedReverbSettings>(
  const SlowedReverbSettings(),
);

/// A native reverb failure. Speed can still be applied when this is set.
final playbackSlowedReverbError = ValueNotifier<String?>(null);

final _errors = <String, String>{};

void reportSlowedReverbError(String playerId, String? error) {
  if (error == null) {
    _errors.remove(playerId);
  } else {
    _errors[playerId] = error;
  }
  playbackSlowedReverbError.value = _errors.isEmpty
      ? null
      : _errors.values.first;
}
