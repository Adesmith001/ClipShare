import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:clipshare/library.dart';
import 'package:clipshare/social_video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'recognizes TikTok posts and short shares without accepting lookalikes',
    () {
      for (final text in [
        'https://www.tiktok.com/@creator/video/6742501081818877190',
        'https://m.tiktok.com/v/6742501081818877190.html',
        'https://vm.tiktok.com/ZExample/',
        'https://vt.tiktok.com/ZExample/',
        'https://www.tiktok.com/t/ZExample/',
      ]) {
        expect(isSocialVideo(Uri.parse(text)), isTrue, reason: text);
        expect(
          extractMediaLink('Watch this $text')?.host,
          Uri.parse(text).host,
        );
        expect(mediaPlatform({'url': text}), 'TikTok');
      }
      for (final text in [
        'https://www.tiktok.com/@creator',
        'https://www.tiktok.com/@creator/live',
        'https://www.tiktok.com/@creator/photo/123',
        'https://www.tiktok.com.evil.test/@creator/video/123',
        'https://vm.tiktok.com.evil.test/ZExample/',
        'https://name:secret@vm.tiktok.com/ZExample/',
        'http://vm.tiktok.com/ZExample/',
      ]) {
        expect(isSocialVideo(Uri.parse(text)), isFalse, reason: text);
      }
    },
  );

  test('resolves TikTok through the service with a stable source and signed video URL', () async {
    Uri? requested;
    final response = {
      'code': 0,
      'data': {
        'id': '6742501081818877190',
        'title': ' A public   video ',
        'hdplay': 'https://v16.tiktokcdn-us.com/video/clip/?signature=example',
        'play': 'https://v19.tiktokcdn.com/video/normal/',
      },
    };
    final resolved = await HttpOverrides.runZoned(
      () => resolveSocialVideo(
        Uri.parse(
          'https://www.tiktok.com/@creator/video/6742501081818877190?tracking=private',
        ),
      ),
      createHttpClient: (_) => _Client(response, (url) => requested = url),
    );
    expect(requested?.host, 'www.tikwm.com');
    expect(
      requested?.queryParameters['url'],
      'https://www.tiktok.com/@_/video/6742501081818877190',
    );
    expect(requested.toString(), isNot(contains('private')));
    expect(mediaSourceKey(resolved.source), 'tiktok:6742501081818877190');
    expect(resolved.items.single.url.host, 'v16.tiktokcdn-us.com');
    expect(resolved.items.single.url.queryParameters['signature'], 'example');
    expect(resolved.title, 'A public video');
  });

  test(
    'short links use the resolved id and fall back to the standard video',
    () async {
      final resolved = await HttpOverrides.runZoned(
        () => resolveSocialVideo(Uri.parse('https://vm.tiktok.com/ZExample/')),
        createHttpClient: (_) => _Client({
          'code': 0,
          'data': {
            'id': '6742501081818877190',
            'hdplay': 'http://v16.tiktokcdn.com/insecure',
            'play': '/video/media/play/6742501081818877190.mp4',
          },
        }, (_) {}),
      );
      expect(resolved.source.path, '/@_/video/6742501081818877190');
      expect(resolved.items.single.url.host, 'www.tikwm.com');
    },
  );

  test(
    'rejects service errors photos unrelated ids and untrusted media',
    () async {
      for (final response in [
        {'code': -1, 'msg': 'unavailable'},
        {
          'code': 0,
          'data': {
            'id': '123',
            'play': 'https://v16.tiktokcdn.com/video/clip/',
          },
        },
        {
          'code': 0,
          'data': {
            'id': '6742501081818877190',
            'images': ['photo'],
            'play': 'https://v16.tiktokcdn.com/audio/file/',
          },
        },
        {
          'code': 0,
          'data': {
            'id': '6742501081818877190',
            'play': 'https://v16.tiktokcdn.com.evil.test/video/clip/',
          },
        },
        {
          'code': 0,
          'data': {
            'id': '6742501081818877190',
            'play': 'https://www.tikwm.com/api/',
          },
        },
      ]) {
        await expectLater(
          HttpOverrides.runZoned(
            () => resolveSocialVideo(
              Uri.parse(
                'https://www.tiktok.com/@creator/video/6742501081818877190',
              ),
            ),
            createHttpClient: (_) => _Client(response, (_) {}),
          ),
          throwsA(isA<Exception>()),
        );
      }
    },
  );
}

class _Headers extends Fake implements HttpHeaders {
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  String? value(String name) => null;
}

class _Client extends Fake implements HttpClient {
  _Client(this.response, this.onRequest);
  final Object response;
  final void Function(Uri) onRequest;
  @override
  set connectionTimeout(Duration? value) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    onRequest(url);
    return _Request(response);
  }

  @override
  void close({bool force = false}) {}
}

class _Request extends Fake implements HttpClientRequest {
  _Request(this.response);
  final Object response;
  @override
  final headers = _Headers();
  @override
  set followRedirects(bool value) {}
  @override
  Future<HttpClientResponse> close() async => _Response(response);
}

class _Response extends Fake implements HttpClientResponse {
  _Response(this.response);
  final Object response;
  @override
  bool get isBroadcast => false;
  @override
  int get statusCode => 200;
  @override
  final headers = _Headers();
  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream.value(utf8.encode(jsonEncode(response))).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );
}
