import 'dart:async';

import 'package:clipshare/main.dart';
import 'package:clipshare/social_video.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const channel = MethodChannel('clipshare/shared_links');
  late List<Map<String, Object>> entries;
  late List<MethodCall> actions;

  setUp(() {
    entries = [
      {
        'id': '1',
        'url': 'https://example.com/sunrise.mp4?secret=hidden',
        'title': 'Morning walk',
        'state': 'saved',
        'folder': 'Travel',
        'canExport': true,
      },
      {
        'id': '2',
        'url': 'https://example.org/meal.jpg',
        'title': 'Dinner ideas',
        'state': 'failed',
        'folder': '',
        'isImage': true,
        'canRetry': true,
      },
    ];
    actions = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'list') return entries;
          if (call.method == 'folders') return ['Travel'];
          if (call.method == 'reconcile') return true;
          if (call.method == 'info') {
            return {
              'version': '0.2.0',
              'build': '9',
              'os': 'Android test',
              'storageBytes': 2048,
            };
          }
          actions.add(call);
          if (call.method == 'delete') {
            entries.removeWhere((e) => e['id'] == call.arguments);
          }
          if (call.method == 'move') {
            final args = call.arguments as Map;
            for (final e in entries.where(
              (e) => (args['ids'] as List).contains(e['id']),
            )) {
              e['folder'] = args['folder'] as String;
            }
          }
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  Future<void> open(WidgetTester tester, {Widget? child}) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.resetPhysicalSize();
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(child ?? const ClipShareApp());
    await tester.pumpAndSettle();
  }

  testWidgets('search matches titles and sources without matching URL tokens', (
    tester,
  ) async {
    await open(tester);
    await tester.enterText(find.byKey(const Key('librarySearch')), 'MORNING');
    await tester.pumpAndSettle();
    expect(find.text('Morning walk'), findsOneWidget);
    expect(find.text('Dinner ideas'), findsNothing);
    await tester.enterText(
      find.byKey(const Key('librarySearch')),
      'example.org',
    );
    await tester.pumpAndSettle();
    expect(find.text('Dinner ideas'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('librarySearch')), 'hidden');
    await tester.pumpAndSettle();
    expect(find.text('No matching downloads'), findsOneWidget);
  });

  testWidgets('folder filter combines with media filter', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('folderFilter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Travel').last);
    await tester.pumpAndSettle();
    expect(find.text('Morning walk'), findsOneWidget);
    expect(find.text('Dinner ideas'), findsNothing);
    await tester.tap(find.text('Photos'));
    await tester.pumpAndSettle();
    expect(find.text('No matching downloads'), findsOneWidget);
  });

  testWidgets('batch retry only retries eligible selected entries', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Select downloads'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select all visible'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('batchActions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Retry / download'));
    await tester.pumpAndSettle();
    expect(actions.where((c) => c.method == 'retry').map((c) => c.arguments), [
      '2',
    ]);
    expect(find.textContaining('1 completed'), findsOneWidget);
  });

  testWidgets(
    'batch delete requires confirmation and removes selected files only',
    (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Select downloads'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('select:1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('batchActions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete selected'));
      await tester.pumpAndSettle();
      expect(actions.where((c) => c.method == 'delete'), isEmpty);
      expect(find.textContaining('Exported copies'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(
        actions.where((c) => c.method == 'delete').map((c) => c.arguments),
        ['1'],
      );
      expect(find.text('Dinner ideas'), findsOneWidget);
    },
  );

  testWidgets('selected entries can move to a folder', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Select downloads'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('select:2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('batchActions')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to folder'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Travel').last);
    await tester.pumpAndSettle();
    final move = actions.singleWhere((c) => c.method == 'move');
    expect(move.arguments, {
      'ids': ['2'],
      'folder': 'Travel',
    });
  });

  testWidgets(
    'help shows build and sanitized feedback without private URL data',
    (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Help and feedback'));
      await tester.pumpAndSettle();
      expect(find.textContaining('0.2.0'), findsWidgets);
      expect(find.text('Copy diagnostic report'), findsOneWidget);
      expect(find.textContaining('secret=hidden'), findsNothing);
    },
  );

  testWidgets('large text on a narrow screen has no layout exception', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: const ClipShareApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('folder creation rejects duplicates before writing', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('Manage folders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New folder'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Folder name'),
      ' travel ',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('That folder name is already in use.'), findsOneWidget);
    expect(actions.where((c) => c.method == 'createFolder'), isEmpty);
    await tester.enterText(
      find.widgetWithText(TextField, 'Folder name'),
      'Recipes',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      actions.singleWhere((c) => c.method == 'createFolder').arguments,
      'Recipes',
    );
  });

  testWidgets('dismissing deletion keeps all local entries', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Export video'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete download'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep'));
    await tester.pumpAndSettle();
    expect(actions.where((c) => c.method == 'delete'), isEmpty);
    expect(find.text('Morning walk'), findsOneWidget);
  });

  testWidgets('unavailable library can be refreshed without a restart', (
    tester,
  ) async {
    var first = true;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      if (call.method == 'list') {
        if (first) {
          first = false;
          throw PlatformException(code: 'shared_links_unavailable');
        }
        return entries;
      }
      if (call.method == 'folders') return ['Travel'];
      return null;
    });
    await open(tester);
    expect(find.text('Downloads are unavailable.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Morning walk'), findsOneWidget);
    expect(find.text('Downloads are unavailable.'), findsNothing);
  });

  testWidgets(
    'batch continues after failure and defers refresh and repeat submission',
    (tester) async {
      final firstExport = Completer<bool>();
      var lists = 0;
      entries[1]['state'] = 'saved';
      entries[1]['canExport'] = true;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'list') {
          lists++;
          return entries;
        }
        if (call.method == 'folders') return ['Travel'];
        if (call.method == 'export') {
          actions.add(call);
          if (call.arguments == '1') return firstExport.future;
          return true;
        }
        return null;
      });
      await open(tester);
      await tester.tap(find.byTooltip('Select downloads'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Select all visible'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('batchActions')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to Gallery'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Updating downloads…'), findsOneWidget);
      expect(
        tester
            .widget<PopupMenuButton<String>>(
              find.byKey(const Key('batchActions')),
            )
            .enabled,
        isFalse,
      );
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('changed'),
        ),
        (_) {},
      );
      await tester.pump();
      expect(lists, 1);
      firstExport.completeError(PlatformException(code: 'storage_full'));
      await tester.pumpAndSettle();
      expect(
        actions.where((c) => c.method == 'export').map((c) => c.arguments),
        ['1', '2'],
      );
      expect(lists, 2);
      expect(
        find.textContaining('1 completed · 1 failed · 0 skipped'),
        findsOneWidget,
      );
      expect(find.textContaining('Free some device storage'), findsOneWidget);
    },
  );

  testWidgets(
    'pending resolution shows progress and reports this attempt error',
    (tester) async {
      final resolved = Completer<ResolvedMedia>();
      entries[1] = {
        'id': '2',
        'url': 'https://x.com/name/status/123',
        'state': 'pending',
      };
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'list') return entries;
        if (call.method == 'folders') return ['Travel'];
        if (call.method == 'export') {
          throw PlatformException(code: 'network_error');
        }
        if (call.method == 'addResolved') {
          throw PlatformException(code: 'storage_full');
        }
        return null;
      });
      await open(
        tester,
        child: MaterialApp(
          home: DownloadsScreen(resolveMedia: (_) => resolved.future),
        ),
      );
      await tester.tap(find.byTooltip('Export video'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to Gallery'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Download media'));
      await tester.pump();
      expect(find.text('Resolving link…'), findsOneWidget);
      resolved.complete((
        source: Uri.parse('https://x.com/i/web/status/123'),
        title: 'Post',
        items: [
          (
            url: Uri.parse('https://video.twimg.com/clip.mp4'),
            slot: 0,
            position: null,
          ),
        ],
      ));
      await tester.pumpAndSettle();
      expect(find.textContaining('Free some device storage'), findsOneWidget);
      expect(find.text('Resolving link…'), findsNothing);
    },
  );

  testWidgets('wide library accommodates failed entries with enlarged text', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    entries[0]['title'] =
        'A very long title from a shared social post that needs two lines';
    entries[0]['state'] = 'failed';
    entries[0]['error'] = 'source_unavailable';
    entries[0]['canRetry'] = true;
    await tester.binding.setSurfaceSize(const Size(900, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.2)),
        child: const ClipShareApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'every resolved carousel slide keeps the pending Unfiled choice',
    (tester) async {
      entries[0]['url'] = 'https://x.com/i/web/status/123';
      entries[0]['folder'] = 'Travel';
      entries[1] = {
        'id': '2',
        'url': 'https://twitter.com/name/status/123?s=20',
        'state': 'pending',
        'folder': '',
      };
      await open(
        tester,
        child: MaterialApp(
          home: DownloadsScreen(
            resolveMedia: (_) async => (
              source: Uri.parse('https://x.com/i/web/status/123'),
              title: 'Carousel',
              items: [
                (
                  url: Uri.parse('https://video.twimg.com/one.mp4'),
                  slot: 0,
                  position: '1/2',
                ),
                (
                  url: Uri.parse('https://video.twimg.com/two.mp4'),
                  slot: 1,
                  position: '2/2',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Download media'));
      await tester.pumpAndSettle();
      final queued = actions.where((c) => c.method == 'addResolved').toList();
      expect(queued, hasLength(2));
      expect(queued.map((c) => (c.arguments as Map)['folder']), ['', '']);
    },
  );

  testWidgets('pasting an equivalent post keeps the existing pending folder', (
    tester,
  ) async {
    entries[1] = {
      'id': '2',
      'url': 'https://twitter.com/name/status/123?s=20',
      'state': 'pending',
      'folder': 'Travel',
    };
    await open(
      tester,
      child: MaterialApp(
        home: DownloadsScreen(
          resolveMedia: (_) async => (
            source: Uri.parse('https://x.com/i/web/status/123'),
            title: null,
            items: [
              (
                url: Uri.parse('https://video.twimg.com/one.mp4'),
                slot: 0,
                position: null,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.enterText(
      find.byKey(const Key('mediaLink')),
      'https://x.com/another/status/123',
    );
    await tester.tap(find.text('Add link'));
    await tester.pumpAndSettle();
    final args =
        actions.singleWhere((c) => c.method == 'addResolved').arguments as Map;
    expect(args['folder'], 'Travel');
    expect(args['sharedSource'], 'https://x.com/another/status/123');
  });
}
