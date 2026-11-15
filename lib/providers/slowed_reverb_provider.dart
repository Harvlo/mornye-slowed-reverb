import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mornye/models/slowed_reverb_settings.dart';
import 'package:mornye/services/playback_slowed_reverb.dart';

final slowedReverbProvider =
    NotifierProvider<SlowedReverbController, SlowedReverbSettings>(
      SlowedReverbController.new,
    );

class SlowedReverbController extends Notifier<SlowedReverbSettings> {
  static const storageKey = 'playback_slowed_reverb_v1';
  int _revision = 0;
  bool _disposed = false;
  SlowedReverbSettings? _pending;
  bool _saving = false;
  Timer? _saveTimer;
  late Future<void> _loading;

  /// Completes after the saved settings have been read, or the read failed.
  Future<void> get loaded => _loading;

  @override
  SlowedReverbSettings build() {
    ref.onDispose(() {
      _disposed = true;
      _saveTimer?.cancel();
      if (!_saving && _pending != null) unawaited(_save());
    });
    _loading = _load();
    return const SlowedReverbSettings();
  }

  Future<void> _load() async {
    final revision = _revision;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (_disposed || raw == null || revision != _revision) return;
      final data = jsonDecode(raw);
      if (data is! Map) return;
      final settings = SlowedReverbSettings.fromJson(
        Map<String, dynamic>.from(data),
      );
      if (_disposed || revision != _revision) return;
      state = settings;
      playbackSlowedReverb.value = settings;
    } catch (_) {
      // Keep the classic defaults. Playback does not depend on the old file.
    }
  }

  void setEnabled(bool enabled) => _commit(state.copyWith(enabled: enabled));

  /// Slider edits turn the effect on so the playing song previews them.
  void setRate(double rate) =>
      _commit(state.copyWith(enabled: true, rate: rate));

  void setMix(double mix) => _commit(state.copyWith(enabled: true, mix: mix));

  void setRoom(double room) =>
      _commit(state.copyWith(enabled: true, room: room));

  void applyPreset(SlowedReverbPreset preset) =>
      _commit(preset.settings(enabled: true));

  /// Writes any pending change immediately. Tests use this instead of waiting
  /// out the save timer.
  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _save();
  }

  void _commit(SlowedReverbSettings settings) {
    final next = SlowedReverbSettings(
      enabled: settings.enabled,
      rate: settings.rate,
      mix: settings.mix,
      room: settings.room,
    );
    _revision++;
    state = next;
    playbackSlowedReverb.value = next;
    _pending = next;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), () {
      if (!_saving) unawaited(_save());
    });
  }

  Future<void> _save() async {
    _saving = true;
    try {
      await _loading;
      final prefs = await SharedPreferences.getInstance();
      while (_pending != null) {
        final value = jsonEncode(_pending!.toJson());
        _pending = null;
        if (!await prefs.setString(storageKey, value)) {
          throw StateError('Write failed');
        }
      }
    } catch (_) {
      if (!_disposed) {
        playbackSlowedReverbError.value ??=
            'Could not save slowed + reverb settings.';
      }
    } finally {
      _saving = false;
    }
  }
}
