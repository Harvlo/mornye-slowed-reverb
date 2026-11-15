import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mornye/l10n/app_localizations.dart';
import 'package:mornye/models/slowed_reverb_settings.dart';
import 'package:mornye/providers/slowed_reverb_provider.dart';
import 'package:mornye/services/music_playback_deck.dart';
import 'package:mornye/services/playback_slowed_reverb.dart';
import 'package:mornye/widgets/slowed_reverb_button.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    playbackSlowedReverb.value = const SlowedReverbSettings();
    playbackSlowedReverbError.value = null;
  });

  test('speed stays inside 0.70x to 1.00x and presets round-trip', () {
    const settings = SlowedReverbSettings();
    expect(settings.rate, 0.85);
    expect(settings.matches(SlowedReverbPreset.classic), isTrue);
    expect(settings.enabled, isFalse);

    final heavy = SlowedReverbPreset.heavy.settings(enabled: true);
    expect(heavy.rate, 0.72);
    expect(heavy.matches(SlowedReverbPreset.heavy), isTrue);
    expect(heavy.matches(SlowedReverbPreset.classic), isFalse);

    final stored = SlowedReverbSettings.fromJson({
      'enabled': true,
      'rate': 2,
      'mix': -1,
      'room': 0.2,
    });
    expect(stored.rate, 1);
    expect(stored.mix, 0);
    expect(stored.room, 0.2);
    expect(
      SlowedReverbSettings.fromJson(
        jsonDecode(jsonEncode(heavy.toJson())) as Map<String, dynamic>,
      ),
      heavy,
    );
  });

  test('footer controls shrink together on a narrow phone', () {
    expect(
      playerFooterSegmentWidth(available: 400, slots: 5, connectedGap: 2),
      56,
    );
    final narrow = playerFooterSegmentWidth(
      available: 264,
      slots: 5,
      connectedGap: 2,
    );
    expect(narrow, greaterThanOrEqualTo(48));
    expect(narrow, lessThan(56));
    expect(
      playerFooterSegmentWidth(available: 180, slots: 5, connectedGap: 2),
      48,
    );
  });

  test('settings survive a new session', () async {
    final first = ProviderContainer();
    addTearDown(first.dispose);
    await first.read(slowedReverbProvider.notifier).loaded;
    first
        .read(slowedReverbProvider.notifier)
        .applyPreset(SlowedReverbPreset.heavy);
    await first.read(slowedReverbProvider.notifier).flush();
    expect(playbackSlowedReverb.value.rate, 0.72);
    expect(playbackSlowedReverb.value.enabled, isTrue);

    final second = ProviderContainer();
    addTearDown(second.dispose);
    await second.read(slowedReverbProvider.notifier).loaded;
    expect(second.read(slowedReverbProvider).enabled, isTrue);
    expect(second.read(slowedReverbProvider).rate, 0.72);
    expect(second.read(slowedReverbProvider).mix, SlowedReverbPreset.heavy.mix);
  });

  test('iOS sends the effect and leaves the AutoMix rate unscaled', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    for (final name in [
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        calls.add(call);
        final arguments = call.arguments;
        if (call.method == 'create' && arguments is Map) {
          messenger.setMockMethodCallHandler(
            MethodChannel(
              'xyz.luan/audioplayers/events/${arguments['playerId']}',
            ),
            (_) async => null,
          );
        } else if (call.method == 'setSourceUrl' && arguments is Map) {
          final id = arguments['playerId'];
          unawaited(
            messenger.handlePlatformMessage(
              'xyz.luan/audioplayers/events/$id',
              const StandardMethodCodec().encodeSuccessEnvelope({
                'event': 'audio.onPrepared',
                'value': true,
              }),
              (_) {},
            ),
          );
        } else if (call.method == 'getDuration') {
          return 180000;
        }
        return null;
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'),
        null,
      ),
    );

    final deck = AudioplayersPlaybackDeck(
      playerId: 'slowed',
      slowedReverbAvailable: true,
    );
    await deck.setFileSource('/song.flac');
    expect(calls.where((call) => call.method == 'setSlowedReverb'), isEmpty);

    playbackSlowedReverb.value = const SlowedReverbSettings(
      enabled: true,
      rate: 0.85,
      mix: 0.4,
      room: 0.55,
    );
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final enabled = calls.lastWhere((call) => call.method == 'setSlowedReverb');
    final configuration =
        (enabled.arguments as Map)['configuration'] as Map<Object?, Object?>;
    expect(configuration['enabled'], isTrue);
    expect(configuration['rate'], 0.85);
    expect(configuration['mix'], 0.4);

    await deck.setPlaybackRate(1.04);
    final rate = calls.lastWhere((call) => call.method == 'setPlaybackRate');
    expect((rate.arguments as Map)['playbackRate'], 1.04);

    await deck.setFileSource('/next.flac');
    final again = calls.lastWhere((call) => call.method == 'setSlowedReverb');
    expect(
      ((again.arguments as Map)['configuration'] as Map)['enabled'],
      isTrue,
    );

    playbackSlowedReverb.value = const SlowedReverbSettings();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final off = calls.lastWhere((call) => call.method == 'setSlowedReverb');
    expect(
      ((off.arguments as Map)['configuration'] as Map)['enabled'],
      isFalse,
    );
    await deck.dispose();
  });

  test('Android accepts the setting and does not call the player', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    for (final name in [
      'xyz.luan/audioplayers.global',
      'xyz.luan/audioplayers.global/events',
    ]) {
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        calls.add(call.method);
        final arguments = call.arguments;
        if (call.method == 'create' && arguments is Map) {
          messenger.setMockMethodCallHandler(
            MethodChannel(
              'xyz.luan/audioplayers/events/${arguments['playerId']}',
            ),
            (_) async => null,
          );
        } else if (call.method == 'setSourceUrl' && arguments is Map) {
          final id = arguments['playerId'];
          unawaited(
            messenger.handlePlatformMessage(
              'xyz.luan/audioplayers/events/$id',
              const StandardMethodCodec().encodeSuccessEnvelope({
                'event': 'audio.onPrepared',
                'value': true,
              }),
              (_) {},
            ),
          );
        }
        return call.method == 'getDuration' ? 1000 : null;
      },
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('xyz.luan/audioplayers'),
        null,
      ),
    );
    final deck = AudioplayersPlaybackDeck(
      playerId: 'android-slowed',
      slowedReverbAvailable: false,
    );
    playbackSlowedReverb.value = SlowedReverbPreset.classic.settings(
      enabled: true,
    );
    await deck.setFileSource('/song.flac');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(calls, isNot(contains('setSlowedReverb')));
    await deck.dispose();
  });

  testWidgets('a tap toggles and a long press tunes with a live preset', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Center(child: SlowedReverbButton())),
        ),
      ),
    );
    await tester.pump();
    expect(find.byTooltip('Slowed + reverb'), findsOneWidget);

    await tester.tap(find.byTooltip('Slowed + reverb'));
    await tester.pump();
    expect(find.byTooltip('Slowed + reverb on'), findsOneWidget);
    expect(playbackSlowedReverb.value.enabled, isTrue);

    await tester.longPress(find.byTooltip('Slowed + reverb on'));
    await tester.pumpAndSettle();
    expect(find.text('Speed and pitch'), findsOneWidget);
    expect(find.text('0.85×'), findsOneWidget);

    await tester.tap(find.text('Heavy'));
    await tester.pump();
    expect(find.text('0.72×'), findsOneWidget);
    expect(playbackSlowedReverb.value.rate, 0.72);
    expect(playbackSlowedReverb.value.enabled, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Android hides the control', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: Center(child: SlowedReverbButton())),
        ),
      ),
    );
    await tester.pump();
    expect(find.byIcon(Icons.waves), findsNothing);
    expect(find.byType(SlowedReverbButton), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
