import 'package:clipshare/social_video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('recognizes public Pin URLs and exact short-link hosts', () {
    expect(
      isSocialVideo(Uri.parse('https://www.pinterest.com/pin/video--123/')),
      isTrue,
    );
    expect(isSocialVideo(Uri.parse('https://pin.it/Ab123')), isTrue);
    expect(isSocialVideo(Uri.parse('https://x.com/name/status/123')), isTrue);
    expect(
      isSocialVideo(Uri.parse('https://x.com.example/name/status/123')),
      isFalse,
    );
    expect(isSocialVideo(Uri.parse('https://pin.it.example/Ab123')), isFalse);
    expect(
      isSocialVideo(Uri.parse('https://www.pinterest.com/search/')),
      isFalse,
    );
  });

  test('selects the largest HTTPS MP4 from the Pinterest CDN', () {
    final media = pinterestMp4({
      'resource_response': {
        'data': {
          'videos': {
            'video_list': {
              'low': {
                'url': 'https://v1.pinimg.com/low.mp4',
                'width': 360,
                'height': 640,
              },
              'stream': {'url': 'https://v1.pinimg.com/high.m3u8'},
              'foreign': {
                'url': 'https://example.com/high.mp4',
                'width': 4096,
                'height': 4096,
              },
              'high': {
                'url': 'https://v1.pinimg.com/high.mp4?signature=example',
                'width': 720,
                'height': 1280,
              },
            },
          },
        },
      },
    });
    expect(
      media.toString(),
      'https://v1.pinimg.com/high.mp4?signature=example',
    );
    expect(pinterestMp4({'resource_response': {}}), isNull);
  });

  test('selects the highest bitrate MP4 for the first video in an X post', () {
    final media = xMp4({
      'mediaDetails': [
        {
          'video_info': {
            'variants': [
              {'url': 'https://video.twimg.com/low.mp4', 'bitrate': 100},
              {'url': 'https://video.twimg.com/high.mp4', 'bitrate': 200},
              {'url': 'https://video.twimg.com/high.m3u8', 'bitrate': 300},
            ],
          },
        },
      ],
    });
    expect(media.toString(), 'https://video.twimg.com/high.mp4');
    expect(xMp4({}), isNull);
  });
}
