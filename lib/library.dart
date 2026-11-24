import 'social_video.dart';

typedef DownloadEntry = Map<Object?, Object?>;

String mediaSource(DownloadEntry entry) {
  final host =
      Uri.tryParse(entry['url'] as String? ?? '')?.host
          .replaceFirst(RegExp(r'^(www|m|mobile)\.'), '') ??
      '';
  return switch (host) {
    'youtube.com' || 'youtu.be' => 'YouTube',
    'pinterest.com' || 'pin.it' => 'Pinterest',
    'twitter.com' || 'x.com' => 'X',
    'instagram.com' => 'Instagram',
    'tiktok.com' || 'vm.tiktok.com' || 'vt.tiktok.com' => 'TikTok',
    _ => host,
  };
}

bool mediaIsImage(DownloadEntry entry) =>
    entry['isImage'] == true ||
    isDirectImage(Uri.tryParse(entry['url'] as String? ?? ''));

String mediaPlatform(DownloadEntry entry) {
  final source = mediaSource(entry);
  return const {
        'Instagram',
        'X',
        'YouTube',
        'Pinterest',
        'TikTok',
      }.contains(source)
      ? source
      : 'Other';
}

String mediaTitle(DownloadEntry entry) {
  if (entry['title'] case final String title when title.isNotEmpty) {
    return title;
  }
  final url = Uri.tryParse(entry['url'] as String? ?? '');
  if ((isDirectImage(url) || isDirectVideo(url)) &&
      url!.pathSegments.isNotEmpty) {
    final name = url.pathSegments.last
        .replaceFirst(RegExp(r'\.[^.]+$'), '')
        .replaceAll(RegExp(r'[_-]+'), ' ');
    if (name.isNotEmpty) return name;
  }
  final source = mediaSource(entry);
  return source.isEmpty ? 'Shared link' : '$source post';
}

List<DownloadEntry> filterDownloads(
  List<DownloadEntry> entries, {
  String query = '',
  String type = 'All',
  String? folder,
  String? platform,
}) {
  final words = query
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty);
  return entries.where((entry) {
    if (platform != null && mediaPlatform(entry) != platform) return false;
    if (folder != null && (entry['folder'] as String? ?? '') != folder) {
      return false;
    }
    if (type == 'Photos' && !mediaIsImage(entry)) return false;
    if (type == 'Videos' &&
        (mediaIsImage(entry) || entry['state'] == 'pending')) {
      return false;
    }
    final url = Uri.tryParse(entry['url'] as String? ?? '');
    final text =
        '${mediaTitle(entry)} ${mediaSource(entry)} ${url?.host ?? ''} ${url?.path ?? ''}'
            .toLowerCase();
    return words.every(text.contains);
  }).toList();
}

bool canApply(String action, DownloadEntry entry) => switch (action) {
  'delete' || 'move' => true,
  'cancel' => entry['state'] == 'downloading' && entry['canCancel'] == true,
  'export' => entry['state'] == 'saved' && entry['canExport'] == true,
  'retry' =>
    entry['canRetry'] == true ||
        (entry['state'] == 'pending' &&
            (isSocialVideo(Uri.tryParse(entry['url'] as String? ?? '')) ||
                isDirectImage(Uri.tryParse(entry['url'] as String? ?? '')) ||
                isDirectVideo(Uri.tryParse(entry['url'] as String? ?? '')))),
  _ => false,
};

String downloadErrorMessage(String? code) => switch (code) {
  'tiktok_unavailable' => 'TikTok couldn’t be resolved. Try again shortly, or copy a fresh public video link.',
  'photos_denied' => 'Allow Photos access in Settings, or save to Files.',
  'network' ||
  'network_error' ||
  'offline' ||
  'connection' => 'Check your connection, then retry.',
  'timeout' => 'The request timed out. Check your connection and retry.',
  'disk_full' ||
  'storage_full' ||
  'insufficient_space' => 'Free some device storage, then retry.',
  'authentication' || 'sign_in_required' =>
    'This provider requires sign-in. See Help for supported sign-in options.',
  'unavailable' ||
  'source_unavailable' ||
  'http_error' ||
  'not_found' ||
  'http_404' =>
    'The media is unavailable. Check that the post is still accessible.',
  'unsupported' ||
  'invalid_media' ||
  'cannot_decode' => 'The response is not a supported photo or video.',
  'interrupted' ||
  'cannot_resume' ||
  'download_missing' ||
  'missing_task' => 'The transfer was interrupted. Retry to download it again.',
  'file_missing' ||
  'missing_file' => 'The local file is missing. Retry to download it again.',
  'folder_exists' => 'A folder with that name already exists.',
  'waiting_for_wifi' => 'Waiting for Wi-Fi.',
  'waiting_for_network' => 'Waiting for a network connection.',
  'waiting_to_retry' => 'The device is waiting to retry this transfer.',
  'download_paused' =>
    'The device has paused this transfer. Check your connection.',
  'server_error' => 'The provider is temporarily unavailable. Try again later.',
  'storage_unavailable' || 'file_error' =>
    'The device could not access local storage. Check storage and retry.',
  'too_many_redirects' =>
    'The media link redirected too many times. Try sharing the original post.',
  'invalid_folder' ||
  'invalid_argument' => 'Check the name or selection and try again.',
  _ => 'Couldn’t complete that action. Refresh Downloads and try again.',
};

String formatBytes(num bytes) {
  if (bytes < 1024) return '${bytes.round()} B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
