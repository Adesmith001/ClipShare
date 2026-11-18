import 'package:clipshare/library.dart';
import 'package:clipshare/library_help.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'search combines words, source, type and folder without reading tokens',
    () {
      final entries = <DownloadEntry>[
        {
          'id': '1',
          'url': 'https://x.com/person/status/123?token=private',
          'title': 'City morning walk',
          'folder': 'Travel',
          'state': 'saved',
        },
        {
          'id': '2',
          'url': 'https://example.com/morning.jpg',
          'folder': '',
          'isImage': true,
          'state': 'saved',
        },
      ];
      expect(
        filterDownloads(
          entries,
          query: 'morning CITY',
          folder: 'Travel',
          type: 'Videos',
        ).map((e) => e['id']),
        ['1'],
      );
      expect(filterDownloads(entries, query: 'private'), isEmpty);
      expect(
        filterDownloads(
          entries,
          folder: '',
          type: 'Photos',
        ).map((e) => e['id']),
        ['2'],
      );
    },
  );

  test('batch eligibility excludes inapplicable states', () {
    expect(canApply('retry', {'state': 'saved', 'canRetry': false}), isFalse);
    expect(
      canApply('cancel', {'state': 'downloading', 'canCancel': false}),
      isFalse,
    );
    expect(canApply('export', {'state': 'failed', 'canExport': true}), isFalse);
    expect(canApply('delete', {'state': 'pending'}), isTrue);
    expect(
      canApply('retry', {
        'state': 'pending',
        'url': 'https://example.com/post',
      }),
      isFalse,
    );
  });

  test(
    'diagnostics excludes titles, folder names, URLs and arbitrary error text',
    () {
      final report = diagnosticReport(
        {'version': '0.2.0', 'build': '9'},
        [
          {
            'url': 'https://secret.example/private?token=123',
            'title': 'Private title',
            'folder': 'Private folder',
            'state': 'failed',
            'error': 'network_error',
          },
          {'state': 'failed', 'error': 'https://secret.example/'},
        ],
      );
      expect(report, contains('network_error'));
      expect(report, contains('Entries: 2'));
      expect(report, isNot(contains('secret.example')));
      expect(report, isNot(contains('Private title')));
      expect(report, isNot(contains('Private folder')));
    },
  );
}
