import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:naija_reels/app/theme.dart';
import 'package:naija_reels/core/network/api_response.dart';
import 'package:naija_reels/data/mock/mock_api.dart';
import 'package:naija_reels/data/models.dart';
import 'package:naija_reels/data/repository.dart';
import 'package:naija_reels/features/rewards/rewards_page.dart';

class _NoRepo implements Repository {
  @override
  Future<List<Drama>> dramas({int page = 1, int size = 20}) async => const [
        Drama(id: 'dr_mama', title: 'Mama-in-Law Wahala', coverUrl: '', tags: [], episodeCount: 6),
      ];
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

void main() {
  test('summary follows contract example', () async {
    final api = MockApi(_NoRepo());
    final s = await api.rewardsSummary(now: DateTime.utc(2026, 10, 30, 3));
    expect(s.balanceCoins, 245);
    expect(s.cashKobo, 0);
    expect(s.newbie7Day, hasLength(7));
    expect(s.newbie7Day![2].taskId, 'newbie:3');
    expect(s.checkin7Day[3].taskId, 'checkin:2026-10-30');
    expect(s.checkinStreak, 3);
    expect(s.bingeStreak!.taskId, 'binge:2026-10-30');
    expect(s.bingeStreak!.status, 'in_progress');
    expect(s.dramaCompletion.single.status, 'claimable');
    expect(s.dramaCompletion.single.title, 'Finish Mama-in-Law Wahala');
    expect(s.dramaCompletion.single.target, 6);
    expect(s.chests.map((c) => c.status), ['unlocking', 'locked']);
  });

  test('claim credits balance; repeat claim returns 40903', () async {
    final api = MockApi(_NoRepo());
    final now = DateTime.utc(2026, 10, 30, 3);
    await api.rewardsSummary(now: now);
    final r = await api.claimReward('checkin:2026-10-30');
    expect(r, {'taskId': 'checkin:2026-10-30', 'rewardCoins': 15, 'balanceCoins': 260});
    expect(() => api.claimReward('checkin:2026-10-30'),
        throwsA(isA<ApiException>().having((e) => e.code, 'code', kErrAlreadyClaimed)));
    expect(() => api.claimReward('bogus'), throwsA(isA<ApiException>().having((e) => e.code, 'code', 40401)));
    final s = await api.rewardsSummary(now: now);
    expect(s.checkin7Day[3].status, 'claimed');
    expect(s.todayChecked, isTrue);
    expect(s.balanceCoins, 260);
  });

  testWidgets('Rewards page: sections in order, gold balances, claim and 40903 shown as claimed', (t) async {
    await t.binding.setSurfaceSize(const Size(420, 2200));
    final api = MockApi(_NoRepo());
    await t.pumpWidget(ProviderScope(
      overrides: [mockApiProvider.overrideWithValue(api)],
      child: MaterialApp(theme: AppTheme.dark, home: const RewardsPage()),
    ));
    await t.pump();
    await t.pump();
    final order = [
      'rewards-balances',
      'rewards-newbie',
      'rewards-checkin',
      'rewards-binge',
      'rewards-complete',
      'rewards-chests'
    ];
    final tops = [for (final k in order) t.getRect(find.byKey(ValueKey(k))).top];
    expect(tops, [...tops]..sort());
    expect(find.text('245'), findsOneWidget);
    expect(find.text('₦0'), findsOneWidget);
    expect(t.widget<Text>(find.byKey(const ValueKey('rewards-coins'))).style?.color, AppColors.gold);
    expect(find.textContaining('Withdraw'), findsNothing);
    expect(find.textContaining('Oya, claim am!'), findsWidgets);

    await t.tap(find.byKey(const ValueKey('claim-complete:dr_mama')));
    await t.pump();
    await t.pump();
    expect(find.text('345'), findsOneWidget);

    // Backend says already claimed (40903): UI shows Claimed, no error.
    await api.claimReward('newbie:3');
    await t.tap(find.byKey(const ValueKey('claim-newbie:3')));
    await t.pump();
    await t.pump();
    expect(find.textContaining('Could not claim'), findsNothing);
    expect(find.byKey(const ValueKey('claim-newbie:3')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
