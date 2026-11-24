import 'dart:io';

import 'package:clipshare/library.dart';
import 'package:clipshare/main.dart';
import 'package:clipshare/social_video.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  const enabled = bool.fromEnvironment('STORE_BETA');
  group('direct-media store beta', skip: !enabled, () {
    test(
      'rejects all social posts before opening a network connection',
      () async {
        for (final link in [
          'https://www.youtube.com/watch?v=dQw4w9WgXc',
          'https://x.com/person/status/123',
          'https://www.instagram.com/reel/test/',
          'https://pin.it/abc',
          'https://vm.tiktok.com/ZExample/',
        ]) {
          final url = Uri.parse(link);
          expect(isSocialVideo(url), isFalse, reason: link);
          expect(extractMediaLink(link), isNull);
          await expectLater(
            HttpOverrides.runZoned(
              () => resolveSocialVideo(url),
              createHttpClient: (_) =>
                  throw StateError('Social resolution attempted networking'),
            ),
            throwsFormatException,
          );
        }
        expect(
          extractMediaLink('https://example.com/own-video.mp4'),
          isNotNull,
        );
        expect(
          extractMediaLink('https://example.com/own-photo.jpg'),
          isNotNull,
        );
        expect(
          mediaPlatform({'url': 'https://example.com/own-video.mp4'}),
          'Videos',
        );
        expect(
          mediaPlatform({'url': 'https://example.com/own-photo.jpg'}),
          'Photos',
        );
      },
    );

    testWidgets('organizes direct media without advertising social providers', (
      tester,
    ) async {
      const channel = MethodChannel('clipshare/shared_links');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'list') {
          return [
            {
              'id': 'v',
              'url': 'https://example.com/own-video.mp4',
              'state': 'saved',
            },
            {
              'id': 'p',
              'url': 'https://example.com/own-photo.jpg',
              'state': 'saved',
              'isImage': true,
            },
          ];
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await tester.pumpWidget(const ClipShareApp());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('platform:Videos')), findsOneWidget);
      expect(find.byKey(const Key('platform:Photos')), findsOneWidget);
      expect(find.text('TikTok'), findsNothing);
      expect(find.text('Instagram'), findsNothing);
    });
  });
}
