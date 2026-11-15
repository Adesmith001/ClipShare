import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart';

bool isHttpsLink(Uri? url) =>
    url != null &&
    url.scheme == 'https' &&
    url.host.isNotEmpty &&
    url.userInfo.isEmpty;

bool isDirectVideo(Uri? url) =>
    isHttpsLink(url) && url!.path.toLowerCase().endsWith('.mp4');

final _pinPath = RegExp(r'^/pin/(?:[\w-]+--)?([0-9]+)/?$');
final _postPath = RegExp(r'^/(?:i/web|[^/]+)/status/([0-9]+)(?:/|$)');
final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
final _instagramPath = RegExp(r'^/(?:p|reels?|tv)/([\w-]+)/?$');
final _jsonScript = RegExp(
  r'<script\b[^>]*\btype="application/json"[^>]*>(.*?)</script>',
  dotAll: true,
);

String? _instagramCode(Uri url) =>
    const {
      'instagram.com',
      'www.instagram.com',
      'm.instagram.com',
    }.contains(url.host)
    ? _instagramPath.firstMatch(url.path)?.group(1)
    : null;

String? _youtubeId(Uri url) {
  final parts = url.pathSegments;
  final id = switch (url.host) {
    'youtu.be' when parts.length == 1 => parts.first,
    'youtube.com' || 'www.youtube.com' || 'm.youtube.com' => switch (parts) {
      ['watch'] => url.queryParameters['v'],
      ['shorts' || 'live', final String id] => id,
      _ => null,
    },
    _ => null,
  };
  return id != null && _videoId.hasMatch(id) ? id : null;
}

String? _xPostId(Uri url) {
  const hosts = {
    'x.com',
    'www.x.com',
    'mobile.x.com',
    'twitter.com',
    'www.twitter.com',
    'mobile.twitter.com',
  };
  return hosts.contains(url.host)
      ? _postPath.firstMatch(url.path)?.group(1)
      : null;
}

String? _pinId(Uri url) {
  final host = url.host;
  if (host != 'pinterest.com' && !host.endsWith('.pinterest.com')) return null;
  return _pinPath.firstMatch(url.path)?.group(1);
}

bool isSocialVideo(Uri? url) =>
    isHttpsLink(url) &&
    (_pinId(url!) != null ||
        (url.host == 'pin.it' && url.pathSegments.length == 1) ||
        _xPostId(url) != null ||
        _youtubeId(url) != null ||
        _instagramCode(url) != null);

const _timeout = Duration(seconds: 12);

Future<({Uri source, Uri media})> resolveSocialVideo(Uri url) async {
  if (!isSocialVideo(url)) throw const FormatException('Unsupported post.');
  final youtubeId = _youtubeId(url);
  if (youtubeId != null) return _resolveYouTube(youtubeId);
  final client = HttpClient()..connectionTimeout = _timeout;
  try {
    final instagramCode = _instagramCode(url);
    if (instagramCode != null) {
      final source = Uri.https('www.instagram.com', '/p/$instagramCode');
      final html = await _requestText(
        client,
        source,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
              '(KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36',
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          'Accept-Language': 'en-us,en;q=0.5',
          'Sec-Fetch-Mode': 'navigate',
        },
      );
      final media = html == null ? null : instagramMp4(html, instagramCode);
      if (media == null) {
        throw const FormatException('Instagram video unavailable.');
      }
      return (source: source, media: media);
    }
    final postId = _xPostId(url);
    if (postId != null) {
      final endpoint = Uri.https('cdn.syndication.twimg.com', '/tweet-result', {
        'id': postId,
        'lang': 'en',
        'token': '1',
      });
      final media = xMp4(await _requestJson(client, endpoint));
      if (media == null) throw const FormatException('No MP4 on this post.');
      return (
        source: Uri.https('x.com', '/i/web/status/$postId'),
        media: media,
      );
    }
    var id = _pinId(url);
    var redirect = url;
    for (var i = 0; id == null && i < 3 && redirect.host == 'pin.it'; i++) {
      final request = await client.getUrl(redirect).timeout(_timeout);
      request.followRedirects = false;
      final response = await request.close().timeout(_timeout);
      final location = response.headers.value(HttpHeaders.locationHeader);
      if (response.statusCode < 300 ||
          response.statusCode >= 400 ||
          location == null) {
        break;
      }
      redirect = redirect.resolve(location);
      if (!isHttpsLink(redirect)) break;
      id = _pinId(redirect);
    }
    if (id == null) throw const FormatException('Unrecognized Pinterest pin.');

    final endpoint = Uri.https(
      'www.pinterest.com',
      '/resource/PinResource/get/',
      {
        'data': jsonEncode({
          'options': {'id': id, 'field_set_key': 'detailed'},
        }),
      },
    );
    final media = pinterestMp4(
      await _requestJson(
        client,
        endpoint,
        headers: {'X-Pinterest-PWS-Handler': 'www/[username].js'},
      ),
    );
    if (media == null) throw const FormatException('No MP4 on this pin.');
    return (source: Uri.https('www.pinterest.com', '/pin/$id/'), media: media);
  } finally {
    client.close(force: true);
  }
}

Future<({Uri source, Uri media})> _resolveYouTube(String id) async {
  final youtube = YoutubeExplode();
  try {
    final manifest = await youtube.videos.streams
        .getManifest(id)
        .timeout(const Duration(seconds: 25));
    final muxed = manifest.muxed.where((stream) {
      final url = stream.url;
      return stream.container.name == 'mp4' &&
          isHttpsLink(url) &&
          url.host.endsWith('.googlevideo.com') &&
          url.path == '/videoplayback' &&
          url.queryParameters['mime'] == 'video/mp4';
    });
    if (muxed.isEmpty) {
      throw const FormatException('No combined YouTube MP4 available.');
    }
    final best = muxed.reduce(
      (a, b) => a.bitrate.bitsPerSecond >= b.bitrate.bitsPerSecond ? a : b,
    );
    return (
      source: Uri.https('www.youtube.com', '/watch', {'v': id}),
      media: best.url,
    );
  } on VideoUnavailableException {
    throw const FormatException('YouTube video unavailable.');
  } finally {
    youtube.close();
  }
}

Future<Object?> _requestJson(
  HttpClient client,
  Uri endpoint, {
  Map<String, String> headers = const {},
}) async {
  final text = await _requestText(client, endpoint, headers: headers);
  return text == null ? null : jsonDecode(text);
}

Future<String?> _requestText(
  HttpClient client,
  Uri endpoint, {
  required Map<String, String> headers,
}) async {
  final request = await client.getUrl(endpoint).timeout(_timeout);
  request.followRedirects = false;
  headers.forEach(request.headers.set);
  final response = await request.close().timeout(_timeout);
  if (response.statusCode == HttpStatus.notFound) return null;
  if (response.statusCode != HttpStatus.ok) {
    throw HttpException('Provider returned HTTP ${response.statusCode}.');
  }
  final text = StringBuffer();
  await utf8.decoder.bind(response).timeout(_timeout).forEach((chunk) {
    text.write(chunk);
    if (text.length > 4 * 1024 * 1024) {
      throw const FormatException('Provider response too large.');
    }
  });
  return text.toString();
}

Uri? instagramMp4(String html, String code) {
  for (final script in _jsonScript.allMatches(html)) {
    final text = script.group(1)!;
    if (!text.contains('"xig_polaris_media"')) continue;
    try {
      final post = _instagramPost(jsonDecode(text), code, 0);
      final videos = _field(post, 'video_versions');
      if (videos is List) {
        Uri? selected;
        num bestPixels = -1;
        for (final video in videos) {
          final value = _field(video, 'url');
          final url = value is String ? Uri.tryParse(value) : null;
          if (!isDirectVideo(url) ||
              !(url!.host.endsWith('.cdninstagram.com') ||
                  url.host.endsWith('.fbcdn.net'))) {
            continue;
          }
          final width = _field(video, 'width');
          final height = _field(video, 'height');
          final pixels = width is num && height is num ? width * height : 0;
          if (pixels > bestPixels) {
            selected = url;
            bestPixels = pixels;
          }
        }
        if (selected != null) return selected;
      }
    } on FormatException {
      continue;
    }
  }
  return null;
}

Object? _instagramPost(Object? value, String code, int depth) {
  if (depth == 32) return null;
  final media = _field(
    _field(value, 'xig_polaris_media'),
    'if_not_gated_logged_out',
  );
  if (_field(media, 'code') == code) return media;
  final children = switch (value) {
    Map() => value.values,
    List() => value,
    _ => const <Object?>[],
  };
  for (final child in children) {
    final match = _instagramPost(child, code, depth + 1);
    if (match != null) return match;
  }
  return null;
}

Uri? xMp4(Object? json) {
  final details = _field(json, 'mediaDetails');
  if (details is! List) return null;
  for (final item in details) {
    final variants = _field(_field(item, 'video_info'), 'variants');
    if (variants is! List) continue;
    Uri? selected;
    num bestBitrate = -1;
    for (final variant in variants) {
      final value = _field(variant, 'url');
      final url = value is String ? Uri.tryParse(value) : null;
      if (!isDirectVideo(url) || url!.host != 'video.twimg.com') continue;
      final valueBitrate = _field(variant, 'bitrate');
      final bitrate = valueBitrate is num ? valueBitrate : 0;
      if (bitrate > bestBitrate) {
        selected = url;
        bestBitrate = bitrate;
      }
    }
    if (selected != null) return selected;
  }
  return null;
}

Uri? pinterestMp4(Object? json) {
  final data = _field(_field(json, 'resource_response'), 'data');
  final videos = _field(_field(data, 'videos'), 'video_list');
  if (videos is! Map) return null;
  Uri? selected;
  num bestPixels = -1;
  for (final video in videos.values) {
    final value = _field(video, 'url');
    final url = value is String ? Uri.tryParse(value) : null;
    if (!isDirectVideo(url) || !url!.host.endsWith('.pinimg.com')) continue;
    final width = _field(video, 'width');
    final height = _field(video, 'height');
    final pixels = width is num && height is num ? width * height : 0;
    if (pixels > bestPixels) {
      selected = url;
      bestPixels = pixels;
    }
  }
  return selected;
}

Object? _field(Object? value, String key) => value is Map ? value[key] : null;
