import 'package:clipshare/library.dart';
import 'package:clipshare/main.dart';
import 'package:clipshare/social_video.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('store and personal builds accept the same social and direct links', () {
    for (final link in [
      'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
      'https://x.com/person/status/123',
      'https://www.instagram.com/reel/test/',
      'https://pin.it/abc',
      'https://vm.tiktok.com/ZExample/',
    ]) {
      expect(isSocialVideo(Uri.parse(link)), isTrue, reason: link);
      expect(extractMediaLink('Shared with you: $link'), Uri.parse(link));
    }
    for (final link in [
      'https://example.com/own-video.mp4',
      'https://example.com/own-photo.jpg',
    ]) {
      expect(extractMediaLink(link), Uri.parse(link));
    }
    for (final link in [
      'http://x.com/person/status/123',
      'https://x.com.evil.test/person/status/123',
      'https://name:secret@x.com/person/status/123',
    ]) {
      expect(extractMediaLink(link), isNull);
    }
    expect(mediaPlatform({'url': 'https://x.com/person/status/123'}), 'X');
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('pasted social link reaches the download queue on $platform', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = platform;
      const channel = MethodChannel('clipshare/shared_links');
      final messenger = tester.binding.defaultBinaryMessenger;
      Map<Object?, Object?>? queued;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'addResolved') {
          queued = Map<Object?, Object?>.from(call.arguments as Map);
          return true;
        }
        if (call.method == 'list') return <Object>[];
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        debugDefaultTargetPlatformOverride = null;
      });
      const source = 'https://x.com/person/status/123';
      await tester.pumpWidget(
        MaterialApp(
          home: DownloadsScreen(
            resolveMedia: (url) async {
              expect(url.toString(), source);
              return (
                source: url,
                items: [
                  (
                    url: Uri.parse('https://example.com/video.mp4'),
                    slot: 0,
                    position: null,
                  ),
                ],
                title: 'Test video',
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('mediaLink')), source);
      await tester.tap(find.byTooltip('Add link'));
      await tester.pumpAndSettle();
      expect(queued?['source'], source);
      expect(queued?['media'], 'https://example.com/video.mp4');
      expect(
        find.text('Paste a direct HTTPS MP4, JPEG, PNG, or WebP file link.'),
        findsNothing,
      );
    });
  }
}
