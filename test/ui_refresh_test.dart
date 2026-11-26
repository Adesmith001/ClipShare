import 'package:clipshare/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const downloads = MethodChannel('clipshare/shared_links');
  const preferences = MethodChannel('clipshare/preferences');
  late Map<String, String> saved;
  setUp(() {
    saved = {};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(preferences, (call) async {
      if (call.method == 'read') return saved;
      if (call.method == 'write') {
        saved.addAll(Map<String, String>.from(call.arguments as Map));
        return true;
      }
      if (call.method == 'markTutorialSeen') {
        saved['tutorialSeen'] = 'true';
        return true;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(downloads, (call) async {
      if (call.method == 'list') {
        return [
          {
            'id': 'ig',
            'url': 'https://www.instagram.com/reel/123/',
            'title': 'At the beach',
            'folder': 'Old folder',
            'state': 'saved',
          },
          {
            'id': 'yt',
            'url': 'https://youtu.be/123',
            'title': 'A film',
            'state': 'saved',
          },
        ];
      }
      if (call.method == 'info') return {'storageBytes': 2048};
      return null;
    });
  });
  Future<void> open(WidgetTester tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(const ClipShareApp());
    await tester.pumpAndSettle();
  }

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(downloads, null);
    messenger.setMockMethodCallHandler(preferences, null);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('first launch offers the tutorial once and Settings replays it', (
    tester,
  ) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(downloads, (call) async {
      if (call.method == 'list') return <Object>[];
      return null;
    });
    await open(tester);
    expect(find.text('Step 1 - Paste your link here'), findsOneWidget);
    expect(find.byKey(const Key('mediaLink')), findsOneWidget);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 - Get a link from another app'), findsOneWidget);
    expect(find.textContaining('Pinterest'), findsNothing);
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Paste your link below'), findsOneWidget);
    expect(find.text('Next'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('mediaLink')),
      'https://example.com/test.mp4',
    );
    await tester.pumpAndSettle();
    expect(find.text('Tap the highlighted + button'), findsOneWidget);
    await tester.tap(find.text('Skip tutorial'));
    await tester.pumpAndSettle();
    expect(saved['tutorialSeen'], 'true');
    await tester.pumpWidget(const SizedBox());
    await open(tester);
    expect(find.byKey(const Key('tutorialHint')), findsNothing);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Replay tutorial'), 240);
    await tester.tap(find.text('Replay tutorial'));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 - Paste your link here'), findsOneWidget);
  });

  testWidgets('guide follows a real download through its folder and export', (
    tester,
  ) async {
    var added = false;
    var exported = false;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(downloads, (
      call,
    ) async {
      if (call.method == 'list') {
        return [
          if (added)
            {
              'id': 'guide',
              'url': 'https://example.com/tutorial.mp4',
              'state': 'saved',
              'canExport': true,
            },
        ];
      }
      if (call.method == 'add') {
        added = true;
        return true;
      }
      if (call.method == 'export') {
        exported = true;
        return true;
      }
      return null;
    });
    await open(tester);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    await tester.enterText(
      find.byKey(const Key('mediaLink')),
      'https://example.com/tutorial.mp4',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add link'));
    await tester.pumpAndSettle();
    expect(find.text('Open the highlighted folder below'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('platform:Other')));
    await tester.tap(find.byKey(const Key('platform:Other')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Export video'));
    expect(find.text('Step 4 - Save your file below'), findsOneWidget);
    await tester.tap(find.byTooltip('Export video'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to Gallery'));
    await tester.pumpAndSettle();
    expect(exported, isTrue);
    expect(find.text('Your file has been saved'), findsOneWidget);
  });

  testWidgets(
    'search stays behind the top icon and the plus stays beside the link',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const ClipShareApp());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('librarySearch')), findsNothing);
      final plus = find.byTooltip('Add link');
      expect(plus, findsOneWidget);
      expect(
        (tester.getCenter(plus).dy -
                tester.getCenter(find.byKey(const Key('mediaLink'))).dy)
            .abs(),
        lessThan(4),
      );
      await tester.tap(find.byTooltip('Search downloads'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('librarySearch')), 'beach');
      await tester.pumpAndSettle();
      expect(find.text('At the beach'), findsOneWidget);
      expect(find.text('A film'), findsNothing);
      await tester.tap(find.byTooltip('Close search'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('librarySearch')), findsNothing);
      expect(find.text('A film'), findsNothing);
    },
  );

  testWidgets('home shows only folders and media stays inside each folder', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Recent downloads'), findsNothing);
    expect(find.text('At the beach'), findsNothing);
    expect(find.text('A film'), findsNothing);
    expect(find.byTooltip('Select downloads'), findsNothing);
    await tester.tap(find.byKey(const Key('platform:Instagram')));
    await tester.pumpAndSettle();
    expect(find.text('At the beach'), findsOneWidget);
    expect(find.text('A film'), findsNothing);
  });

  testWidgets(
    'platform folders include old downloads and need no manual folders',
    (tester) async {
      await tester.pumpWidget(const ClipShareApp());
      await tester.pumpAndSettle();
      expect(find.byTooltip('Manage folders'), findsNothing);
      await tester.tap(find.byKey(const Key('platform:Instagram')));
      await tester.pumpAndSettle();
      expect(find.text('At the beach'), findsOneWidget);
      expect(find.text('A film'), findsNothing);
      expect(find.text('Old folder'), findsNothing);
      await tester.tap(find.byTooltip('All downloads'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('platform:YouTube')), findsOneWidget);
    },
  );

  testWidgets('system back returns from a platform folder', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('platform:Instagram')));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('platform:YouTube')), findsOneWidget);
  });

  testWidgets('pasting a TikTok short link after onboarding creates a folder', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    Map<Object?, Object?>? queued;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(downloads, (
      call,
    ) async {
      if (call.method == 'addResolved') {
        queued = Map<Object?, Object?>.from(call.arguments as Map);
        return true;
      }
      if (call.method == 'list') {
        return [
          if (queued != null)
            {
              'id': 'tt',
              'url': queued!['source'],
              'title': queued!['title'],
              'state': 'saved',
            },
        ];
      }
      return null;
    });
    await tester.pumpWidget(
      MaterialApp(
        home: DownloadsScreen(
          resolveMedia: (source) async {
            expect(source.host, 'vm.tiktok.com');
            return (
              source: Uri.parse(
                'https://www.tiktok.com/@_/video/6742501081818877190',
              ),
              items: [
                (
                  url: Uri.parse('https://v19.tiktokcdn-us.com/video/clip/'),
                  slot: 0,
                  position: null,
                ),
              ],
              title: 'A TikTok clip',
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip tutorial'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('mediaLink')),
      'https://vm.tiktok.com/ZExample/',
    );
    await tester.tap(find.byTooltip('Add link'));
    await tester.pumpAndSettle();
    expect(queued?['sharedSource'], 'https://vm.tiktok.com/ZExample/');
    expect(find.byKey(const Key('platform:TikTok')), findsOneWidget);
    expect(find.text('A TikTok clip'), findsNothing);
    await tester.tap(find.byKey(const Key('platform:TikTok')));
    await tester.pumpAndSettle();
    expect(find.text('A TikTok clip'), findsOneWidget);
    expect(find.byTooltip('Play video'), findsOneWidget);
  });

  testWidgets('failed preference writes keep the current theme', (
    tester,
  ) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      preferences,
      (call) async {
        if (call.method == 'read') return saved;
        throw PlatformException(code: 'storage_unavailable');
      },
    );
    await open(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Appearance'))).brightness,
      Brightness.light,
    );
    expect(
      find.text('Couldn’t save settings. Please try again.'),
      findsOneWidget,
    );
    expect(saved, isEmpty);
  });

  testWidgets('settings persist theme filter and sort across relaunch', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await open(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.text('Appearance'))).brightness,
      Brightness.dark,
    );
    await tester.tap(find.text('Videos'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Oldest first'));
    await tester.tap(find.text('Oldest first'));
    await tester.pumpAndSettle();
    expect(saved, {'theme': 'dark', 'filter': 'Videos', 'sort': 'oldest'});
    await tester.pumpWidget(const SizedBox());
    await open(tester);
    await tester.tap(find.byTooltip('Search downloads'));
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byTooltip('Settings'))).brightness,
      Brightness.dark,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Videos'))
          .selected,
      isTrue,
    );
    expect(
      tester.getTopLeft(find.text('A film')).dy,
      lessThan(tester.getTopLeft(find.text('At the beach')).dy),
    );
  });
}
