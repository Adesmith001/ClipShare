import 'dart:convert';
import 'dart:io';

bool isHttpsLink(Uri? url) =>
    url != null &&
    url.scheme == 'https' &&
    url.host.isNotEmpty &&
    url.userInfo.isEmpty;

bool isDirectVideo(Uri? url) =>
    isHttpsLink(url) && url!.path.toLowerCase().endsWith('.mp4');

final _pinPath = RegExp(r'^/pin/(?:[\w-]+--)?([0-9]+)/?$');
final _postPath = RegExp(r'^/(?:i/web|[^/]+)/status/([0-9]+)(?:/|$)');

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
        _xPostId(url) != null);

const _timeout = Duration(seconds: 12);

Future<({Uri source, Uri media})> resolveSocialVideo(Uri url) async {
  if (!isSocialVideo(url)) throw const FormatException('Unsupported post.');
  final client = HttpClient()..connectionTimeout = _timeout;
  try {
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

Future<Object?> _requestJson(
  HttpClient client,
  Uri endpoint, {
  Map<String, String> headers = const {},
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
    if (text.length > 2 * 1024 * 1024) {
      throw const FormatException('Provider response too large.');
    }
  });
  return jsonDecode(text.toString());
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
