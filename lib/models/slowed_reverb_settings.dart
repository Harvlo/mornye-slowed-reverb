/// Playback speed, pitch and reverb for the Darwin player.
///
/// Classic slowed + reverb lowers speed and pitch together (varispeed). The
/// numbers are the user's settings. The native player multiplies the transport
/// rate AutoMix asked for by [rate] while [enabled] is true, and keeps
/// AutoMix's own pitch-preserving rate when the effect is off.
class SlowedReverbSettings {
  const SlowedReverbSettings({
    this.enabled = false,
    this.rate = SlowedReverbPreset.classicRate,
    this.mix = SlowedReverbPreset.classicMix,
    this.room = SlowedReverbPreset.classicRoom,
  });

  /// Audible only on iOS and macOS. Other platforms keep the values and do
  /// not change playback.
  final bool enabled;

  /// Combined speed and pitch, from 0.70× to 1.00×. 0.85× is the usual
  /// slowed sound.
  final double rate;

  /// Wet/dry reverb mix, 0 (dry) to 1 (wet).
  final double mix;

  /// Room size, 0 (small, darker) to 1 (large).
  final double room;

  static double _clamp(double value, double min, double max, double fallback) {
    if (!value.isFinite) return fallback;
    if (value < min) return min;
    if (value > max) return max;
    return value;
  }

  SlowedReverbSettings copyWith({
    bool? enabled,
    double? rate,
    double? mix,
    double? room,
  }) => SlowedReverbSettings(
    enabled: enabled ?? this.enabled,
    rate: _clamp(rate ?? this.rate, 0.7, 1, this.rate),
    mix: _clamp(mix ?? this.mix, 0, 1, this.mix),
    room: _clamp(room ?? this.room, 0, 1, this.room),
  );

  /// True when the tuned values are this preset, whether or not it is on.
  bool matches(SlowedReverbPreset preset) =>
      (rate - preset.rate).abs() < 0.005 &&
      (mix - preset.mix).abs() < 0.02 &&
      (room - preset.room).abs() < 0.02;

  Map<String, Object> toJson() => {
    'version': 1,
    'enabled': enabled,
    'rate': rate,
    'mix': mix,
    'room': room,
  };

  factory SlowedReverbSettings.fromJson(Map<String, dynamic> json) {
    double read(String key, double fallback) {
      final value = json[key];
      return value is num ? _clamp(value.toDouble(), 0, 1, fallback) : fallback;
    }

    return SlowedReverbSettings(
      enabled: json['enabled'] == true,
      rate: json['rate'] is num
          ? _clamp((json['rate'] as num).toDouble(), 0.7, 1, 0.85)
          : SlowedReverbPreset.classicRate,
      mix: read('mix', SlowedReverbPreset.classicMix),
      room: read('room', SlowedReverbPreset.classicRoom),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SlowedReverbSettings &&
      other.enabled == enabled &&
      other.rate == rate &&
      other.mix == mix &&
      other.room == room;

  @override
  int get hashCode => Object.hash(enabled, rate, mix, room);
}

/// Named starting points. Custom slider positions match none of them.
enum SlowedReverbPreset {
  light(0.92, 0.22, 0.35),
  classic(classicRate, classicMix, classicRoom),
  heavy(0.72, 0.65, 0.82);

  const SlowedReverbPreset(this.rate, this.mix, this.room);

  static const classicRate = 0.85;
  static const classicMix = 0.40;
  static const classicRoom = 0.55;

  final double rate;
  final double mix;
  final double room;

  SlowedReverbSettings settings({required bool enabled}) =>
      SlowedReverbSettings(enabled: enabled, rate: rate, mix: mix, room: room);
}
