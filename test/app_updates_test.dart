import 'dart:io';

import 'package:clipshare/app_updates.dart';
import 'package:clipshare/release_notes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every shipped build has matching release notes', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version: (\S+)\+(\d+)$',
      multiLine: true,
    ).firstMatch(pubspec)!;
    final notes = releases[version[2]];
    expect(notes?.version, version[1]);
    expect(notes?.features, isNotEmpty);
  });

  test('iOS requires a matching, compatible, newer build', () {
    const bundle = 'com.adesmith001.clipshare.beta';
    const feed = {
      bundle: {
        'testflight': {'minimumBuild': 15, 'minimumOS': '16.5'},
      },
    };
    const install = <String, Object?>{
      'bundleId': bundle,
      'distribution': 'testflight',
      'build': 14,
      'osVersion': '17.0.1',
    };
    expect(AppUpdates.iosUpdateFor(install, feed)?.store, 'TestFlight');
    expect(AppUpdates.iosUpdateFor({...install, 'build': 15}, feed), isNull);
    expect(
      AppUpdates.iosUpdateFor({...install, 'osVersion': '16.4.1'}, feed),
      isNull,
    );
    expect(
      AppUpdates.iosUpdateFor({...install, 'distribution': 'appStore'}, feed),
      isNull,
    );
    expect(
      AppUpdates.iosUpdateFor({...install, 'bundleId': 'another.app'}, feed),
      isNull,
    );
    expect(
      AppUpdates.iosUpdateFor(install, {
        bundle: {
          'testflight': {'minimumBuild': 15},
        },
      }),
      isNull,
    );
  });
}
