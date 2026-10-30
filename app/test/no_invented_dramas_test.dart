import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Real drama ids from GET https://naijareels-api.onrender.com/api/v1/dramas (2026-10-30).
const _real = {'dr_mama', 'dr_prince', 'dr_lagos'};

/// Titles that were invented in earlier mocks; they must never come back.
const _banned = [
  "Prince's Secret Bride",
  'Owambe Queens',
  'Danfo Driver Diaries',
  'Aso Rock Secrets',
  "Billionaire's Secret Wife",
  'My Village Husband is a Prince',
  'Royal Blood of Benin',
  'CEO Daddy Returns',
  'Love in Abuja',
  'Kidnapped Heiress',
  'Wedding Crasher',
  'Okada Romance',
  'Lagos Revenge',
];

void main() {
  test('every hard-coded dramaId in lib/ is a real backend drama; no invented titles', () {
    final files = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
    final idRe = RegExp(r"'(dr_[a-z0-9_]+)'");
    for (final f in files) {
      final src = f.readAsStringSync();
      for (final m in idRe.allMatches(src)) {
        final id = m.group(1)!.replaceAll(RegExp(r'_ep\d+$'), '');
        expect(_real, contains(id), reason: '${f.path}: ${m.group(1)}');
      }
      for (final b in _banned) {
        expect(src.contains(b), isFalse, reason: '${f.path}: "$b"');
      }
    }
  });
}
