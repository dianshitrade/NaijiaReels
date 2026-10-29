// Fails if any non-comment code in lib/ contains CJK characters: the app UI
// (buttons, hints, errors, debug text) must be English only.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _cjk = RegExp(r'[\u3000-\u303f\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uff00-\uffef]');

/// Removes // and /* */ comments while keeping string literals intact.
String stripComments(String src) {
  final out = StringBuffer();
  var i = 0;
  String? quote; // ' " ''' """
  while (i < src.length) {
    if (quote != null) {
      if (src.startsWith(quote, i)) {
        out.write(quote);
        i += quote.length;
        quote = null;
        continue;
      }
      if (src[i] == r'\' && i + 1 < src.length) {
        out.write(src.substring(i, i + 2));
        i += 2;
        continue;
      }
      out.write(src[i++]);
      continue;
    }
    if (src.startsWith('//', i)) {
      while (i < src.length && src[i] != '\n') {
        i++;
      }
      continue;
    }
    if (src.startsWith('/*', i)) {
      final end = src.indexOf('*/', i + 2);
      final stop = end < 0 ? src.length : end + 2;
      out.write('\n' * '\n'.allMatches(src.substring(i, stop)).length);
      i = stop;
      continue;
    }
    for (final q in ["'''", '"""', "'", '"']) {
      if (src.startsWith(q, i)) {
        quote = q;
        break;
      }
    }
    if (quote != null) {
      out.write(quote);
      i += quote.length;
      continue;
    }
    out.write(src[i++]);
  }
  return out.toString();
}

void main() {
  test('stripComments keeps strings, drops comments', () {
    expect(_cjk.hasMatch(stripComments("// \u4e2d\u6587\nvar a = 1; /* \u4e2d */")), isFalse);
    expect(_cjk.hasMatch(stripComments("var s = 'a // \u4e2d';")), isTrue);
  });

  test('no CJK in non-comment code under lib/', () {
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final lines = stripComments(f.readAsStringSync()).split('\n');
      for (var n = 0; n < lines.length; n++) {
        if (_cjk.hasMatch(lines[n])) bad.add('${f.path}:${n + 1}: ${lines[n].trim()}');
      }
    }
    expect(bad, isEmpty, reason: 'CJK text found in app/lib code:\n${bad.join('\n')}');
  });
}
