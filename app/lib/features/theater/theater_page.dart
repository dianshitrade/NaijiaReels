import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../data/mock/mock_api.dart';
import '../../data/models.dart';
import '../../shared/widgets/ankara_pattern.dart';
import '../../shared/widgets/cover_image.dart';

/// Genre chips: label → contract `genre` ('' = all).
const kTheaterGenres = <(String, String)>[
  ('Explore', ''),
  ('Nollywood', 'nollywood'),
  ('Comedy', 'comedy'),
  ('Romance', 'romance'),
  ('Family', 'family'),
  ('Drama', 'drama'),
];

const kEagleAsset = 'android/app/src/main/res/mipmap-xhdpi/ic_launcher_round.png';

String _cap(String t) => t.isEmpty ? t : t[0].toUpperCase() + t.substring(1);

/// Theater: search + eagle avatar, genres, quick actions, two-column covers.
class TheaterPage extends ConsumerStatefulWidget {
  const TheaterPage({super.key});
  @override
  ConsumerState<TheaterPage> createState() => _TheaterPageState();
}

class _TheaterPageState extends ConsumerState<TheaterPage> {
  int _genre = 0;
  String _sort = 'hot';
  String _status = '';

  String get _key => '$_sort|${kTheaterGenres[_genre].$2}|$_status';

  Future<void> _filter() async {
    var sort = _sort;
    var status = _status;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Filter', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            const Text('Sort by', style: TextStyle(color: Colors.white70)),
            Wrap(spacing: 8, children: [
              for (final s in const [('hot', 'Most popular'), ('new', 'Newest')])
                ChoiceChip(label: Text(s.$2), selected: sort == s.$1, onSelected: (_) => set(() => sort = s.$1)),
            ]),
            const SizedBox(height: 12),
            const Text('Status', style: TextStyle(color: Colors.white70)),
            Wrap(spacing: 8, children: [
              for (final s in const [('', 'All'), ('ongoing', 'Ongoing'), ('completed', 'Completed')])
                ChoiceChip(
                    key: ValueKey('filter-status-${s.$1}'),
                    label: Text(s.$2),
                    selected: status == s.$1,
                    onSelected: (_) => set(() => status = s.$1)),
            ]),
            const SizedBox(height: 16),
            SizedBox(
                width: double.infinity,
                child: FilledButton(
                    key: const ValueKey('filter-apply'),
                    onPressed: () => Navigator.of(ctx).pop(true),
                    child: const Text('Show dramas'))),
          ]),
        ),
      ),
    );
    if (ok == true) {
      setState(() {
        _sort = sort;
        _status = status;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(theaterDramasProvider(_key));
    final top = MediaQuery.paddingOf(context).top;
    final cardW = (MediaQuery.sizeOf(context).width - 36) / 2;
    final decodeW = (cardW * MediaQuery.devicePixelRatioOf(context)).round();
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(theaterDramasProvider(_key)),
        child: CustomScrollView(
          key: const ValueKey('theater-scroll'),
          slivers: [
            SliverToBoxAdapter(
              child: Stack(children: [
                const Positioned.fill(child: TextilePattern(opacity: .06)),
                Padding(
                  padding: EdgeInsets.fromLTRB(12, top + 10, 12, 0),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: GestureDetector(
                          key: const ValueKey('theater-search'),
                          onTap: () => context.push(Routes.dramas),
                          child: Container(
                            height: 44,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            decoration:
                                BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(22)),
                            child: const Row(children: [
                              Icon(Icons.search, color: Colors.white60),
                              SizedBox(width: 8),
                              Expanded(
                                  child: Text('Wetin you dey watch?',
                                      style: TextStyle(color: Colors.white54, fontSize: 15))),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        key: const ValueKey('theater-avatar'),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle, border: Border.all(color: AppColors.primary, width: 2)),
                        child: ClipOval(child: Image.asset(kEagleAsset, cacheWidth: 132, fit: BoxFit.cover)),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 34,
                      child: ListView(scrollDirection: Axis.horizontal, children: [
                        for (var i = 0; i < kTheaterGenres.length; i++)
                          GestureDetector(
                            key: ValueKey('genre-${kTheaterGenres[i].$1}'),
                            onTap: () => setState(() => _genre = i),
                            child: Padding(
                              padding: const EdgeInsets.only(right: 18),
                              child: Column(children: [
                                Text(kTheaterGenres[i].$1,
                                    style: TextStyle(
                                        fontSize: i == _genre ? 19 : 16.5,
                                        fontWeight: i == _genre ? FontWeight.w800 : FontWeight.w500,
                                        color: i == _genre ? Colors.white : Colors.white60)),
                                const SizedBox(height: 3),
                                Container(
                                    width: 16, height: 3, color: i == _genre ? AppColors.primary : Colors.transparent),
                              ]),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      _Quick(
                          key: const ValueKey('quick-filter'),
                          icon: Icons.filter_alt,
                          color: const Color(0xFF7C5CFF),
                          label: 'Filter',
                          active: _status.isNotEmpty,
                          onTap: _filter),
                      _Quick(
                          key: const ValueKey('quick-charts'),
                          icon: Icons.local_fire_department,
                          color: AppColors.gold,
                          label: 'Charts',
                          onTap: () =>
                              Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ChartsPage()))),
                      _Quick(
                          key: const ValueKey('quick-new'),
                          icon: Icons.fiber_new,
                          color: AppColors.primary,
                          label: 'New',
                          active: _sort == 'new',
                          onTap: () => setState(() => _sort = _sort == 'new' ? 'hot' : 'new')),
                      _Quick(
                          key: const ValueKey('quick-coming-soon'),
                          icon: Icons.event_available,
                          color: const Color(0xFFFF8A3D),
                          label: 'Coming soon',
                          onTap: () => Navigator.of(context)
                              .push(MaterialPageRoute<void>(builder: (_) => const ComingSoonPage()))),
                    ]),
                    const SizedBox(height: 12),
                  ]),
                ),
              ]),
            ),
            ...list.when(
              loading: () => [
                const SliverFillRemaining(
                    hasScrollBody: false, child: Center(child: CircularProgressIndicator(color: AppColors.primary))),
              ],
              error: (e, _) => [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: TextButton(
                        onPressed: () => ref.invalidate(theaterDramasProvider(_key)),
                        child: const Text('Could not load dramas. Tap to retry.')),
                  ),
                ),
              ],
              data: (items) => [
                if (items.isEmpty)
                  const SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                          child:
                              Text('No dramas match yet. Try another genre.', style: TextStyle(color: Colors.white70))))
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    sliver: SliverGrid(
                      key: const ValueKey('theater-grid'),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.52),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) => TheaterCard(drama: items[i], decodeWidth: decodeW),
                        childCount: items.length,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Quick extends StatelessWidget {
  const _Quick(
      {super.key,
      required this.icon,
      required this.color,
      required this.label,
      required this.onTap,
      this.active = false});
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
  final bool active;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 42,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: AppColors.surfaceHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: active ? AppColors.primary : Colors.transparent),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
              child: Icon(icon, size: 16, color: Colors.white),
            ),
            const SizedBox(width: 5),
            Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          ]),
        ),
      ),
    );
  }
}

class DramaBadge extends StatelessWidget {
  const DramaBadge(this.badge, {super.key});
  final String badge;
  @override
  Widget build(BuildContext context) {
    final hot = badge == 'hot';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: hot ? AppColors.primary : AppColors.gold,
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomRight: Radius.circular(10)),
      ),
      child: Text(hot ? 'Hot' : 'New',
          style: TextStyle(color: hot ? Colors.white : Colors.black, fontSize: 12, fontWeight: FontWeight.w800)),
    );
  }
}

/// Two-column portrait cover card.
class TheaterCard extends StatelessWidget {
  const TheaterCard({super.key, required this.drama, this.decodeWidth});
  final Drama drama;
  final int? decodeWidth;
  @override
  Widget build(BuildContext context) {
    final d = drama;
    return GestureDetector(
      key: ValueKey('theater-card-${d.id}'),
      onTap: () => context.push(Routes.dramaDetail(d.id)),
      child: Container(
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Stack(children: [
            CoverImage(d.coverUrl,
                title: d.title, radius: 0, aspectRatio: 3 / 4, decodeWidth: decodeWidth, showFallbackTitle: false),
            if (d.badge != null) Positioned(left: 0, top: 0, child: DramaBadge(d.badge!)),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(8, 18, 8, 6),
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0xAA000000)])),
                child: Row(children: [
                  const Icon(Icons.local_fire_department, size: 15, color: Colors.white),
                  const SizedBox(width: 3),
                  Text('${compactCount(d.heatCount ?? 0)} heat',
                      style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Text(d.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, height: 1.25)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
            child: Wrap(spacing: 5, runSpacing: 4, children: [
              for (final t in d.tags.take(3))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: AppColors.surfaceHigh, borderRadius: BorderRadius.circular(4)),
                  child: Text(_cap(t), style: const TextStyle(fontSize: 11.5, color: Colors.white70)),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Charts: GET /charts?type=hot|trending|new|completed.
class ChartsPage extends ConsumerWidget {
  const ChartsPage({super.key});
  static const _types = [('hot', 'Hot'), ('trending', 'Trending'), ('new', 'New'), ('completed', 'Completed')];
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: _types.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Charts', style: TextStyle(fontWeight: FontWeight.w800)),
          bottom: TabBar(indicatorColor: AppColors.primary, tabs: [for (final t in _types) Tab(text: t.$2)]),
        ),
        body: TabBarView(children: [for (final t in _types) _ChartList(type: t.$1)]),
      ),
    );
  }
}

class _ChartList extends ConsumerWidget {
  const _ChartList({required this.type});
  final String type;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ref.watch(chartsProvider(type)).when(
          loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
          error: (e, _) => Center(
              child:
                  TextButton(onPressed: () => ref.invalidate(chartsProvider(type)), child: const Text('Tap to retry'))),
          data: (items) => items.isEmpty
              ? const Center(child: Text('Nothing on this chart yet.', style: TextStyle(color: Colors.white70)))
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final c = items[i];
                    final ch = c.rankChange;
                    return InkWell(
                      key: ValueKey('chart-${c.drama.id}'),
                      onTap: () => context.push(Routes.dramaDetail(c.drama.id)),
                      child: Row(children: [
                        SizedBox(
                          width: 34,
                          child: Text('${c.rank}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900,
                                  color: c.rank <= 3 ? AppColors.gold : Colors.white60)),
                        ),
                        SizedBox(
                            width: 72,
                            child: CoverImage(c.drama.coverUrl,
                                title: c.drama.title, radius: 8, decodeWidth: (72 * dpr).round())),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(c.drama.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Text(c.drama.tags.map(_cap).join(' · '),
                                style: const TextStyle(color: Colors.white60, fontSize: 13)),
                            const SizedBox(height: 4),
                            Text('${compactCount(c.drama.heatCount ?? 0)} heat',
                                style: const TextStyle(color: AppColors.gold, fontSize: 13)),
                          ]),
                        ),
                        SizedBox(
                          width: 44,
                          child: ch == null
                              ? const Text('NEW',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800, fontSize: 12))
                              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Icon(ch > 0 ? Icons.arrow_drop_up : (ch < 0 ? Icons.arrow_drop_down : Icons.remove),
                                      color: ch > 0 ? AppColors.primary : (ch < 0 ? Colors.redAccent : Colors.white54)),
                                  if (ch != 0) Text('${ch.abs()}', style: const TextStyle(fontSize: 13)),
                                ]),
                        ),
                      ]),
                    );
                  },
                ),
        );
  }
}

/// Coming soon: GET /dramas/coming-soon + POST/DELETE /dramas/{id}/reminder.
class ComingSoonPage extends ConsumerStatefulWidget {
  const ComingSoonPage({super.key});
  @override
  ConsumerState<ComingSoonPage> createState() => _ComingSoonPageState();
}

class _ComingSoonPageState extends ConsumerState<ComingSoonPage> {
  final Map<String, bool> _on = {};
  final Map<String, int> _count = {};

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  String _date(DateTime d) {
    final l = d.toLocal();
    return '${l.day} ${_months[l.month - 1]} · ${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }

  void _toggle(ComingSoonDrama c) {
    final now = !(_on[c.drama.id] ?? c.reminderSet);
    final before = _count[c.drama.id] ?? c.reminderCount;
    setState(() {
      _on[c.drama.id] = now;
      _count[c.drama.id] = before + (now ? 1 : -1);
    });
    ref
        .read(mockApiProvider)
        .setReminder(c.drama.id, now, countBefore: before, releaseAt: c.releaseAt); // optimistic, idempotent
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 1),
        content: Text(now ? 'We go remind you when ${c.drama.title} drops.' : 'Reminder removed')));
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Coming soon', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ref.watch(comingSoonProvider).when(
            loading: () => const Center(child: CircularProgressIndicator(color: AppColors.primary)),
            error: (e, _) => Center(
                child:
                    TextButton(onPressed: () => ref.invalidate(comingSoonProvider), child: const Text('Tap to retry'))),
            data: (items) => items.isEmpty
                ? const Center(
                    key: ValueKey('coming-soon-empty'),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.movie_filter_outlined, size: 56, color: AppColors.primary),
                      SizedBox(height: 12),
                      Text('New dramas coming soon', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    ]))
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 14),
                    itemBuilder: (_, i) {
                      final c = items[i];
                      final on = _on[c.drama.id] ?? c.reminderSet;
                      final n = _count[c.drama.id] ?? c.reminderCount;
                      return Row(
                          key: ValueKey('coming-${c.drama.id}'),
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                                width: 96,
                                child: CoverImage(c.drama.coverUrl,
                                    title: c.drama.title, radius: 10, decodeWidth: (96 * dpr).round())),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(c.drama.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                Text('Premieres ${_date(c.releaseAt)}',
                                    style: const TextStyle(
                                        color: AppColors.gold, fontSize: 13, fontWeight: FontWeight.w600)),
                                const SizedBox(height: 4),
                                Text(c.drama.description ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white70)),
                                const SizedBox(height: 4),
                                Text(
                                    [
                                      if (c.drama.plannedEpisodes > 0) '${c.drama.plannedEpisodes} EPs',
                                      '${compactCount(n)} want to watch'
                                    ].join(' · '),
                                    key: ValueKey('coming-count-${c.drama.id}'),
                                    style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
                                const SizedBox(height: 8),
                                on
                                    ? OutlinedButton.icon(
                                        key: ValueKey('remind-${c.drama.id}'),
                                        onPressed: () => _toggle(c),
                                        icon: const Icon(Icons.notifications_active, size: 18),
                                        label: const Text('Reminder set'))
                                    : FilledButton.icon(
                                        key: ValueKey('remind-${c.drama.id}'),
                                        onPressed: () => _toggle(c),
                                        icon: const Icon(Icons.notifications_none, size: 18),
                                        label: const Text('Remind me')),
                              ]),
                            ),
                          ]);
                    },
                  ),
          ),
    );
  }
}
