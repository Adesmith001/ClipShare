import 'package:clipshare/social_video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'extracts a supported URL from shared text and ignores unsupported links',
    () {
      expect(
        extractMediaLink('A clip https://x.com/name/status/123).')?.toString(),
        'https://x.com/name/status/123',
      );
      expect(extractMediaLink('https://example.com/read-more'), isNull);
      expect(
        extractMediaLink(
          'https://example.com/read-more https://example.com/photo.jpg',
        )?.path,
        '/photo.jpg',
      );
    },
  );
  test('resolves each Instagram carousel slide in post order', () {
    const html = '''
      <script type="application/json">
        {"xig_polaris_media":{"if_not_gated_logged_out":{
          "code":"carousel","media_type":8,"carousel_media":[
            {"media_type":1,"image_versions2":{"candidates":[
              {"url":"https://media.cdninstagram.com/one.jpg","width":800,"height":600}
            ]}},
            {"media_type":2,"video_versions":[
              {"url":"https://media.cdninstagram.com/two.mp4"}
            ]},
            {"media_type":1,"image_versions2":{"candidates":[
              {"url":"https://media.cdninstagram.com/three.webp"}
            ]}}
          ]
        }}}
      </script>
    ''';
    final slides = instagramMedia(html, 'carousel');
    expect(slides.map((slide) => slide.url.path), [
      '/one.jpg',
      '/two.mp4',
      '/three.webp',
    ]);
    expect(slides.map((slide) => slide.position), ['1/3', '2/3', '3/3']);
  });

  test(
    'keeps every X photo and reserves the legacy slot for the first photo',
    () {
      final items = xMedia({
        'mediaDetails': [
          for (var index = 1; index <= 3; index++)
            {
              'type': 'photo',
              'media_url_https': 'https://pbs.twimg.com/media/$index.jpg',
            },
        ],
      });
      expect(items.map((item) => item.url.path), [
        '/media/1.jpg',
        '/media/2.jpg',
        '/media/3.jpg',
      ]);
      expect(items.map((item) => item.position), ['1/3', '2/3', '3/3']);
      expect(items.first.slot, 0);
      expect(items.map((item) => item.slot).toSet(), hasLength(3));
    },
  );

  test('finds the requested Instagram video inside public page data', () {
    final url = Uri.parse('https://www.instagram.com/reel/abc123/');
    expect(isSocialVideo(url), isTrue);
    const html = '''
      <script type="application/json">
        {"data": {"xig_polaris_media": {"if_not_gated_logged_out": {
          "code": "abc123",
          "video_versions": [
            {"url": "https://media.example/high.mp4", "width": 9999, "height": 9999},
            {"url": "https://video.cdninstagram.com/clip.mp4"}
          ]
        }}}}
      </script>
    ''';
    expect(instagramMp4(html, 'abc123')?.host, 'video.cdninstagram.com');
    expect(instagramMp4(html, 'unrelated'), isNull);
  });

  test('recognizes YouTube video links without accepting playlists', () {
    for (final url in [
      'https://www.youtube.com/watch?v=Dpp1sIL1m5Q',
      'https://www.youtube.com/shorts/Dpp1sIL1m5Q',
      'https://youtu.be/Dpp1sIL1m5Q',
    ]) {
      expect(isSocialVideo(Uri.parse(url)), isTrue);
    }
    expect(
      isSocialVideo(Uri.parse('https://www.youtube.com/playlist?list=example')),
      isFalse,
    );
  });

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
