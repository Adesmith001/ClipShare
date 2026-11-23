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

bool isDirectImage(Uri? url) =>
    isHttpsLink(url) &&
    RegExp(r'\.(?:jpe?g|png|webp)$').hasMatch(url!.path.toLowerCase());

Uri? extractMediaLink(String text) {
  final whole = Uri.tryParse(text.trim());
  bool supported(Uri? url) =>
      isSocialVideo(url) || isDirectVideo(url) || isDirectImage(url);
  if (!RegExp(r'\s').hasMatch(text.trim()) && supported(whole)) return whole;
  for (final match in RegExp(
    r'''https://[^\s<>"']+''',
    caseSensitive: false,
  ).allMatches(text)) {
    final url = Uri.tryParse(
      match.group(0)!.replaceFirst(RegExp(r'[.,!?)\]}]+$'), ''),
    );
    if (supported(url)) return url;
  }
  return null;
}

typedef MediaItem = ({Uri url, int slot, String? position});
typedef ResolvedMedia = ({Uri source, List<MediaItem> items, String? title});

class InstagramSignInRequired implements Exception {
  const InstagramSignInRequired();
}

class TikTokResolverUnavailable implements Exception {
  const TikTokResolverUnavailable();
}

List<MediaItem> _single(Uri url) => [(url: url, slot: 0, position: null)];

final _pinPath = RegExp(r'^/pin/(?:[\w-]+--)?([0-9]+)/?$');
final _postPath = RegExp(r'^/(?:i/web|[^/]+)/status/([0-9]+)(?:/|$)');
final _videoId = RegExp(r'^[A-Za-z0-9_-]{11}$');
final _instagramPath = RegExp(r'^/(?:p|reels?|tv)/([\w-]+)/?$');
final _tiktokPath = RegExp(r'^/@[\w.-]+/video/([0-9]+)/?$');
final _tiktokMobilePath = RegExp(r'^/v/([0-9]+)\.html/?$');
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

String? tikTokVideoId(Uri url) =>
    const {'tiktok.com', 'www.tiktok.com', 'm.tiktok.com'}.contains(url.host)
    ? (_tiktokPath.firstMatch(url.path) ??
              _tiktokMobilePath.firstMatch(url.path))
          ?.group(1)
    : null;

bool isTikTokLink(Uri? url) {
  if (!isHttpsLink(url)) return false;
  if (tikTokVideoId(url!) != null) return true;
  if (const {'vm.tiktok.com', 'vt.tiktok.com'}.contains(url.host)) {
    return RegExp(r'^/[\w-]+/?$').hasMatch(url.path);
  }
  return const {
        'tiktok.com',
        'www.tiktok.com',
        'm.tiktok.com',
      }.contains(url.host) &&
      RegExp(r'^/t/[\w-]+/?$').hasMatch(url.path);
}

bool isTikTokMedia(Uri? url) {
  if (!isHttpsLink(url)) return false;
  final host = url!.host;
  if (const {'tikwm.com', 'www.tikwm.com'}.contains(host)) {
    return url.path.startsWith('/video/');
  }
  return const [
        'tiktokcdn.com',
        'tiktokcdn-us.com',
        'tiktokcdn-eu.com',
        'tiktokv.com',
      ].any((domain) => host == domain || host.endsWith('.$domain')) &&
      url.path.contains('/video/');
}

bool isSocialVideo(Uri? url) =>
    isHttpsLink(url) &&
    (_pinId(url!) != null ||
        (url.host == 'pin.it' && url.pathSegments.length == 1) ||
        _xPostId(url) != null ||
        _youtubeId(url) != null ||
        _instagramCode(url) != null ||
        isTikTokLink(url));

// Match pending/retry metadata before the native queue learns a short-link alias.
String mediaSourceKey(Uri? url) {
  if (url == null) return '';
  final tiktok = tikTokVideoId(url);
  if (tiktok != null) return 'tiktok:$tiktok';
  if (isTikTokLink(url)) {
    return '${url.host}:${url.path.replaceAll(RegExp(r'/$'), '')}';
  }
  final youtube = _youtubeId(url);
  if (youtube != null) return 'youtube:$youtube';
  final post = _xPostId(url);
  if (post != null) return 'x:$post';
  final pin = _pinId(url);
  if (pin != null) return 'pinterest:$pin';
  final instagram = _instagramCode(url);
  if (instagram != null) return 'instagram:$instagram';
  if (url.host == 'pin.it' && url.pathSegments.length == 1) {
    return 'pin.it:${url.pathSegments.single}';
  }
  return url.removeFragment().toString();
}

const _timeout = Duration(seconds: 12);

Future<ResolvedMedia> resolveSocialVideo(Uri url) async {
  if (!isSocialVideo(url)) throw const FormatException('Unsupported post.');
  final youtubeId = _youtubeId(url);
  if (youtubeId != null) return _resolveYouTube(youtubeId);
  final client = HttpClient()..connectionTimeout = _timeout;
  try {
    if (isTikTokLink(url)) return await _resolveTikTok(client, url);
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
      final post = html == null
          ? null
          : _instagramPagePost(html, instagramCode);
      final items = _instagramItems(post);
      if (items.isEmpty) {
        throw const FormatException('Instagram media unavailable.');
      }
      return (
        source: source,
        items: items,
        title: _title(_field(_field(post, 'caption'), 'text')),
      );
    }
    final postId = _xPostId(url);
    if (postId != null) {
      final endpoint = Uri.https('cdn.syndication.twimg.com', '/tweet-result', {
        'id': postId,
        'lang': 'en',
        'token': '1',
      });
      final post = await _requestJson(client, endpoint);
      final items = xMedia(post);
      if (items.isEmpty) throw const FormatException('No media on this post.');
      return (
        source: Uri.https('x.com', '/i/web/status/$postId'),
        items: items,
        title: _title(_field(post, 'text')),
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
    final post = await _requestJson(
      client,
      endpoint,
      headers: {'X-Pinterest-PWS-Handler': 'www/[username].js'},
    );
    final data = _field(_field(post, 'resource_response'), 'data');
    final images = _field(data, 'images');
    final media =
        pinterestMp4(post) ??
        (_field(data, 'videos') == null &&
                _field(data, 'story_pin_data') == null &&
                images is Map
            ? _largestImage(
                images.values,
                (uri) => uri.host.endsWith('.pinimg.com'),
              )
            : null);
    if (media == null) {
      throw const FormatException('No supported media on this pin.');
    }
    return (
      source: Uri.https('www.pinterest.com', '/pin/$id/'),
      items: _single(media),
      title:
          _title(_field(data, 'title')) ?? _title(_field(data, 'grid_title')),
    );
  } finally {
    client.close(force: true);
  }
}

Future<ResolvedMedia> _resolveTikTok(HttpClient client, Uri url) async {
  final requestedId = tikTokVideoId(url);
  final source = requestedId == null
      ? Uri(scheme: 'https', host: url.host, path: url.path)
      : Uri.https('www.tiktok.com', '/@_/video/$requestedId');
  // TikTok alone uses the public resolver. Send the post link without tracking
  // parameters; provider sessions and cookies are never sent to this service.
  final response = await _requestJson(
    client,
    Uri.https('www.tikwm.com', '/api/', {'url': source.toString(), 'hd': '1'}),
    headers: {'Accept': 'application/json', 'User-Agent': 'ClipShare/0.2'},
  );
  if (_field(response, 'code') != 0) throw const TikTokResolverUnavailable();
  final data = _field(response, 'data');
  final id = _field(data, 'id');
  final images = _field(data, 'images');
  if (id is! String ||
      !RegExp(r'^[0-9]+$').hasMatch(id) ||
      (requestedId != null && requestedId != id) ||
      (images is List && images.isNotEmpty)) {
    throw const FormatException('TikTok video unavailable.');
  }
  for (final key in ['hdplay', 'play', 'wmplay']) {
    final value = _field(data, key);
    final candidate = value is String && value.isNotEmpty
        ? Uri.tryParse(value)
        : null;
    final media = candidate == null
        ? null
        : Uri.https('www.tikwm.com', '/').resolveUri(candidate);
    if (isTikTokMedia(media)) {
      return (
        source: Uri.https('www.tiktok.com', '/@_/video/$id'),
        items: _single(media!),
        title: _title(_field(data, 'title')),
      );
    }
  }
  throw const FormatException('No supported TikTok video.');
}

Future<ResolvedMedia> _resolveYouTube(String id) async {
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
    String? title;
    try {
      final video = await youtube.videos
          .get(id)
          .timeout(const Duration(seconds: 4));
      title = _title(video.title);
    } on Exception {
      // Media already resolved and can still be downloaded.
    }
    return (
      source: Uri.https('www.youtube.com', '/watch', {'v': id}),
      items: _single(best.url),
      title: title,
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
  final redirect = response.headers.value(HttpHeaders.locationHeader);
  if (endpoint.host == 'www.instagram.com' &&
      response.statusCode >= 300 &&
      response.statusCode < 400 &&
      redirect != null &&
      endpoint.resolve(redirect).path.startsWith('/accounts/login')) {
    throw const InstagramSignInRequired();
  }
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

Uri? instagramMp4(String html, String code) =>
    _instagramVideo(_instagramPagePost(html, code));

List<MediaItem> instagramMedia(String html, String code) =>
    _instagramItems(_instagramPagePost(html, code));

List<MediaItem> _instagramItems(Object? post) {
  final slides = _field(post, 'carousel_media');
  if (slides is! List || slides.isEmpty) {
    if (_field(post, 'media_type') == 8) return [];
    final media = _instagramVideo(post) ?? _instagramPhoto(post);
    return media == null ? [] : _single(media);
  }
  return [
    for (final (index, slide) in slides.indexed)
      if ((_instagramVideo(slide) ?? _instagramPhoto(slide)) case final Uri url)
        (url: url, slot: index, position: '${index + 1}/${slides.length}'),
  ];
}

Uri? _instagramPhoto(Object? post) => _field(post, 'media_type') == 1
    ? _largestImage(
        _field(_field(post, 'image_versions2'), 'candidates'),
        _instagramCdn,
      )
    : null;

Object? _instagramPagePost(String html, String code) {
  for (final script in _jsonScript.allMatches(html)) {
    final text = script.group(1)!;
    if (!text.contains('"xig_polaris_media"')) continue;
    try {
      final post = _instagramPost(jsonDecode(text), code, 0);
      if (post != null) return post;
    } on FormatException {
      continue;
    }
  }
  return null;
}

bool _instagramCdn(Uri uri) =>
    uri.host.endsWith('.cdninstagram.com') || uri.host.endsWith('.fbcdn.net');

Uri? _instagramVideo(Object? post) {
  final videos = _field(post, 'video_versions');
  if (videos is List) {
    Uri? selected;
    num bestPixels = -1;
    for (final video in videos) {
      final value = _field(video, 'url');
      final url = value is String ? Uri.tryParse(value) : null;
      if (!isDirectVideo(url) || !_instagramCdn(url!)) {
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
    return selected;
  }
  return null;
}

List<MediaItem> xMedia(Object? post) {
  final details = _field(post, 'mediaDetails');
  if (details is! List) return [];
  final urls = [for (final item in details) _xVideo(item) ?? _xPhoto(item)];
  // Prior versions saved only the first playable video, or the first photo.
  final firstVideo = urls.indexWhere(isDirectVideo);
  final legacy = firstVideo >= 0
      ? firstVideo
      : urls.indexWhere((url) => url != null);
  return [
    for (final (index, url) in urls.indexed)
      if (url != null)
        (
          url: url,
          slot: index == legacy ? 0 : index + 1,
          position: urls.length > 1 ? '${index + 1}/${urls.length}' : null,
        ),
  ];
}

Uri? _xPhoto(Object? item) {
  if (_field(item, 'type') != 'photo') return null;
  final value = _field(item, 'media_url_https');
  final url = value is String ? Uri.tryParse(value) : null;
  if (!isDirectImage(url) || url!.host != 'pbs.twimg.com') return null;
  return url.replace(queryParameters: {...url.queryParameters, 'name': 'orig'});
}

Uri? _largestImage(Object? values, bool Function(Uri) isCdn) {
  if (values is! Iterable) return null;
  Uri? selected;
  num bestPixels = -1;
  for (final item in values) {
    final value = _field(item, 'url');
    final url = value is String ? Uri.tryParse(value) : null;
    if (!isDirectImage(url) || !isCdn(url!)) continue;
    final width = _field(item, 'width');
    final height = _field(item, 'height');
    final pixels = width is num && height is num ? width * height : 0;
    if (pixels > bestPixels) {
      bestPixels = pixels;
      selected = url;
    }
  }
  return selected;
}

String? _title(Object? value) {
  if (value is! String) return null;
  final text = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (text.isEmpty) return null;
  return String.fromCharCodes(text.runes.take(180));
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
    final url = _xVideo(item);
    if (url != null) return url;
  }
  return null;
}

Uri? _xVideo(Object? item) {
  final variants = _field(_field(item, 'video_info'), 'variants');
  if (variants is! List) return null;
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
  return selected;
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
