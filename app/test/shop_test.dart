import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naija_reels/app/theme.dart';
import 'package:naija_reels/core/network/api_response.dart';
import 'package:naija_reels/data/mock/mock_api.dart';
import 'package:naija_reels/data/models.dart';
import 'package:naija_reels/data/repository.dart';
import 'package:naija_reels/features/shop/shop_page.dart';

class _NoRepo implements Repository {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  test('formatNaira uses ₦ from kobo', () {
    expect(formatNaira(150000), '₦1,500');
    expect(formatNaira(2999900), '₦29,999');
    expect(formatNaira(49950), '₦499.50');
  });

  test('countdown text', () {
    final n = DateTime(2026, 1, 1);
    expect(countdownText(n.add(const Duration(hours: 5, minutes: 3, seconds: 9)), n), '05:03:09');
    expect(countdownText(n.subtract(const Duration(seconds: 1)), n), '00:00:00');
  });

  test('mock packages follow contract and prices are obvious placeholders', () async {
    final api = MockApi(_NoRepo());
    final l = await api.shopPackages();
    expect(l.where((p) => p.tag == 'first_recharge'), hasLength(1));
    expect(l.where((p) => p.tag == 'limited' && p.endsAt != null), isNotEmpty);
    expect(l.where((p) => p.isVip && p.tag == null && p.vipDays != null), isNotEmpty);
    expect(l.where((p) => !p.isVip && p.tag == null), hasLength(4));
    for (final p in l) {
      expect((p.amountKobo ~/ 100) % 100, 99, reason: '${p.id} placeholder price');
      expect(p.playProductId, isNotNull);
    }
  });

  test('POST /orders then poll GET /orders/{id} until paid; first recharge disappears', () async {
    final api = MockApi(_NoRepo())..pollsUntilPaid = 2;
    final o = await api.createOrder('pk_coins_1000', couponId: 'cp_n200_off');
    expect(o.status, 'pending');
    expect(o.discountKobo, 20000);
    expect(o.amountKobo, 149900 - 20000);
    expect((await api.getOrder(o.id)).status, 'pending');
    expect((await api.getOrder(o.id)).status, 'paid');
    expect((await api.shopPackages()).any((p) => p.tag == 'first_recharge'), isFalse);
    expect(await api.coupons(), isEmpty);
    final b = await api.buyAndPoll('pk_vip_week', interval: Duration.zero);
    expect(b.status, 'paid');
  });

  test('coupon not applicable -> 42202, unknown product -> 40401', () async {
    final api = MockApi(_NoRepo());
    expect(() => api.createOrder('pk_coins_500', couponId: 'cp_n200_off'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', 42202)));
    expect(() => api.createOrder('nope'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 40401)));
    expect((await api.coupons()).single.id, 'cp_n200_off');
    expect((await api.coupons(status: 'used')).single.id, 'cp_bonus_100');
  });

  testWidgets('Shop page renders quick row, offers with countdown, two-column packs', (t) async {
    await t.binding.setSurfaceSize(const Size(400, 2000));
    final api = MockApi(_NoRepo())..pollsUntilPaid = 1;
    await t.pumpWidget(ProviderScope(
      overrides: [mockApiProvider.overrideWithValue(api)],
      child: MaterialApp(theme: AppTheme.dark, home: const ShopPage(pollInterval: Duration.zero)),
    ));
    await t.pump();
    await t.pump();
    for (final l in ['My orders', 'Coupons', 'Wallet', 'Coin packs', 'VIP passes']) {
      expect(find.text(l), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('countdown-pk_coins_first')), findsOneWidget);
    expect(find.byKey(const ValueKey('countdown-pk_vip_week')), findsOneWidget);
    expect(find.byKey(const ValueKey('shop-placeholder-note')), findsOneWidget);
    expect(find.text('₦1,499'), findsOneWidget);
    final a = t.getRect(find.byKey(const ValueKey('pack-pk_coins_500')));
    final b = t.getRect(find.byKey(const ValueKey('pack-pk_coins_1000')));
    expect(a.top, b.top);
    expect(b.left, greaterThan(a.right));
    expect(t.widget<Text>(find.text('₦1,499')).style?.color, AppColors.gold);

    await t.tap(find.byKey(const ValueKey('buy-pk_coins_first')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 10));
    await t.pump(const Duration(milliseconds: 10));
    expect(find.textContaining('coins added'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });
}
