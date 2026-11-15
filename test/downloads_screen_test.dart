import 'package:clipshare/main.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('only saved iOS downloads can be played', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
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
    await tester.tap(play);
    await tester.pumpAndSettle();
    expect(played, 'saved-id');
  });
}
