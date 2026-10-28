import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naija_reels/app/env.dart';
import 'package:naija_reels/core/network/api_response.dart';
import 'package:naija_reels/shared/widgets/brand_logo.dart';

void main() {
  test('env default points to Prism mock', () {
    expect(Env.apiRoot, 'http://10.0.2.2:4010/api/v1');
  });

  test('ApiResponse parses envelope', () {
    final r = ApiResponse<int>.fromJson(
        {'code': 0, 'message': 'ok', 'data': 5}, (d) => d as int);
    expect(r.isSuccess, isTrue);
    expect(r.data, 5);
  });

  testWidgets('BrandLogo renders', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BrandLogo()));
    expect(find.byType(RichText), findsWidgets);
  });
}
