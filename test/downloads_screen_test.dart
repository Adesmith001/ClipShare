import 'package:clipshare/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('shows a photo title and exports the saved image', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    const channel = MethodChannel('clipshare/shared_links');
    final messenger = tester.binding.defaultBinaryMessenger;
    Object? exported;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'saveToPhotos') {
        exported = call.arguments;
        return true;
      }
      if (call.method != 'list') return null;
      return [
        {
          'id': 'photo',
          'url': 'https://www.pinterest.com/pin/123/',
          'title': 'A quiet morning',
          'isImage': true,
          'canExport': true,
          'state': 'saved',
        },
      ];
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });
    await tester.pumpWidget(const ClipShareApp());
    await tester.pumpAndSettle();
    expect(find.text('A quiet morning'), findsOneWidget);
    expect(find.text('Pinterest'), findsOneWidget);
    expect(find.byTooltip('View image'), findsOneWidget);
    await tester.tap(find.byTooltip('Export image'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save to Photos'));
    await tester.pumpAndSettle();
    expect(exported, 'photo');
  });

  testWidgets('submits a pasted URL and refreshes the queue', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    const channel = MethodChannel('clipshare/shared_links');
    final messenger = tester.binding.defaultBinaryMessenger;
    const url = 'https://example.com/video.mp4?token=example';
    String? queued;
    messenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'add') {
        queued = call.arguments as String;
        return null;
      }
      return queued == null
          ? []
          : [
              {
                'id': '1',
                'url': queued,
                'state': 'downloading',
                'progress': 0.5,
                'canCancel': true,
              },
            ];
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      debugDefaultTargetPlatformOverride = null;
    });

    await tester.pumpWidget(const ClipShareApp());
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('mediaLink')), url);
    await tester.tap(find.text('Add link'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(queued, url);
    expect(find.text('Downloading · 50%'), findsOneWidget);
    expect(find.byTooltip('Cancel download'), findsOneWidget);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('only saved downloads can be played on $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      await tester.binding.setSurfaceSize(const Size(430, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const channel = MethodChannel('clipshare/shared_links');
      final messenger = tester.binding.defaultBinaryMessenger;
      Object? played;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'play') {
          played = call.arguments;
          return null;
        }
        return [
          {
            'id': 'pending-id',
            'url': 'https://example.com/post',
            'state': 'pending',
          },
          {
            'id': 'transfer-id',
            'url': 'https://example.com/transfer.mp4',
            'state': 'downloading',
          },
          {
            'id': 'failed-id',
            'url': 'https://example.com/failed.mp4',
            'state': 'failed',
          },
          {
            'id': 'saved-id',
            'url': 'https://example.com/video.mp4',
            'state': 'saved',
          },
        ];
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        debugDefaultTargetPlatformOverride = null;
      });

      await tester.pumpWidget(const ClipShareApp());
      await tester.pumpAndSettle();

      expect(find.text('Pending download'), findsOneWidget);
      expect(find.text('Downloading'), findsOneWidget);
      expect(find.text('Download failed'), findsOneWidget);
      expect(find.text('Saved'), findsOneWidget);
      final play = find.byTooltip('Play video');
      expect(play, findsOneWidget);
      await tester.ensureVisible(play);
      await tester.tap(play);
      await tester.pumpAndSettle();
      expect(played, 'saved-id');
    });
  }
}
