import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../app/theme.dart';
import '../../core/network/api_response.dart';
import '../../data/mock/mock_api.dart';
import '../../data/models.dart';
import '../../shared/widgets/cover_image.dart';
import '../inbox/inbox_page.dart';
import '../profile/profile_page.dart';

/// "EP x/N" label; N is always [Drama.plannedEpisodes] (never invented).
String epProgress(int episodeNo, Drama d) {
  final n = d.plannedEpisodes;
  return n > 0 ? 'EP $episodeNo/$n' : 'EP $episodeNo';
}

/// Me tab (reference 5_me): header, counters, entry cards and library tabs.
class MePage extends ConsumerStatefulWidget {
  const MePage({super.key, this.active = true, this.onOpenShop, this.onOpenRewards});
  final bool active;
  final VoidCallback? onOpenShop;
  final VoidCallback? onOpenRewards;
  @override
  ConsumerState<MePage> createState() => _MePageState();
}

class _MePageState extends ConsumerState<MePage> with SingleTickerProviderStateMixin {
  static const tabs = ['Works', 'History', 'Saved', 'Liked', 'Reminders'];
  late final TabController _tabs = TabController(length: tabs.length, initialIndex: 1, vsync: this);
  String _status = 'all';

  @override
  void didUpdateWidget(covariant MePage old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _refresh();
  }

  void _refresh() {
    ref.invalidate(meProvider);
    ref.invalidate(meHistoryProvider);
    ref.invalidate(meSavedProvider);
    ref.invalidate(meLikedProvider);
    ref.invalidate(meRemindersProvider);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _editProfile(MeProfile me) async {
    final ctl = TextEditingController(text: me.nickname);
    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Edit profile'),
        content: TextField(
          key: const ValueKey('me-nickname-field'),
          controller: ctl,
          maxLength: 24,
          decoration: const InputDecoration(labelText: 'Nickname'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancel')),
          FilledButton(
              key: const ValueKey('me-nickname-save'),
              onPressed: () => Navigator.pop(c, ctl.text),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null || !mounted) return;
    try {
      await ref.read(mockApiProvider).updateMe(nickname: name);
      ref.invalidate(meProvider);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.code == 40001 ? 'Nickname must be 2-24 characters' : e.message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            key: const ValueKey('me-inbox'),
            tooltip: 'Inbox',
            icon: const Icon(Icons.mail_outline),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const InboxPage())),
          ),
          PopupMenuButton<String>(
            key: const ValueKey('me-menu'),
            icon: const Icon(Icons.menu),
            onSelected: (v) {
              if (v == 'account') {
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfilePage()));
              } else if (v == 'settings') {
                context.push(Routes.settings);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'account', child: Text('Account & wallet')),
              PopupMenuItem(value: 'settings', child: Text('Settings')),
            ],
          ),
        ],
      ),
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverToBoxAdapter(
            child: me.when(
              data: (m) => _Header(me: m, onEdit: () => _editProfile(m)),
              loading: () => const SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
              error: (e, _) => SizedBox(height: 80, child: Center(child: Text('Could not load profile: $e'))),
            ),
          ),
          SliverToBoxAdapter(child: _EntryCards(onShop: widget.onOpenShop, onRewards: widget.onOpenRewards)),
          SliverPersistentHeader(pinned: true, delegate: _TabBarDelegate(_tabs, tabs)),
        ],
        body: TabBarView(controller: _tabs, children: [
          const _Empty(key: ValueKey('me-works'), icon: Icons.video_library_outlined, text: 'No works yet'),
          _historyTab(),
          _savedTab(),
          _likedTab(),
          _remindersTab(),
        ]),
      ),
    );
  }

  Widget _historyTab() {
    final h = ref.watch(meHistoryProvider(_status));
    const labels = {'all': 'All', 'finished': 'Finished', 'in_progress': 'In progress'};
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
        child: Row(children: [
          for (final e in labels.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                key: ValueKey('me-history-${e.key}'),
                label: Text(e.value),
                selected: _status == e.key,
                selectedColor: AppColors.primary.withValues(alpha: .25),
                onSelected: (_) => setState(() => _status = e.key),
              ),
            ),
        ]),
      ),
      Expanded(
        child: _async(h, (items) {
          if (items.isEmpty) {
            return const _Empty(icon: Icons.history, text: 'Nothing here yet. Start watching!');
          }
          return _Grid(key: const ValueKey('me-grid-history'), children: [
            for (final it in items)
              _CoverTile(
                key: ValueKey('me-history-item-${it.drama.id}'),
                drama: it.drama,
                caption: epProgress(it.lastEpisodeNo, it.drama),
                badge: it.lastSeasonNumber > 1 ? 'S${it.lastSeasonNumber}' : null,
                onTap: () => context.push(Routes.play(it.drama.id, _indexOf(it))),
              ),
          ]);
        }),
      ),
    ]);
  }

  int _indexOf(MeHistoryItem it) => it.lastEpisodeNo > 0 && it.lastSeasonNumber == 1 ? it.lastEpisodeNo - 1 : 0;

  Widget _savedTab() => _async(ref.watch(meSavedProvider), (items) {
        if (items.isEmpty) return const _Empty(icon: Icons.bookmark_border, text: 'No saved dramas');
        return _Grid(key: const ValueKey('me-grid-saved'), children: [
          for (final s in items)
            _CoverTile(
              drama: s.drama,
              caption: s.lastEpisodeNo != null
                  ? epProgress(s.lastEpisodeNo!, s.drama)
                  : (s.drama.plannedEpisodes > 0 ? '${s.drama.plannedEpisodes} EPs' : ''),
              onTap: () => context.push(Routes.dramaDetail(s.drama.id)),
            ),
        ]);
      });

  Widget _likedTab() => _async(ref.watch(meLikedProvider), (items) {
        if (items.isEmpty) return const _Empty(icon: Icons.favorite_border, text: 'No liked episodes');
        return _Grid(key: const ValueKey('me-grid-liked'), children: [
          for (final l in items)
            _CoverTile(
              drama: l.drama,
              coverUrl: l.coverUrl,
              caption: epProgress(l.episodeNo, l.drama),
              badge: l.seasonNumber > 1 ? 'S${l.seasonNumber}' : null,
              onTap: () => context.push(Routes.dramaDetail(l.drama.id)),
            ),
        ]);
      });

  Widget _remindersTab() => _async(ref.watch(meRemindersProvider), (items) {
        if (items.isEmpty) return const _Empty(icon: Icons.notifications_none, text: 'No reminders set');
        return _Grid(key: const ValueKey('me-grid-reminders'), children: [
          for (final c in items)
            _CoverTile(
              drama: c.drama,
              caption: 'Out ${_md(c.releaseAt.toLocal())}',
              onTap: () => context.push(Routes.dramaDetail(c.drama.id)),
            ),
        ]);
      });

  static String _md(DateTime d) {
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${m[d.month - 1]} ${d.day}';
  }

  Widget _async<T>(AsyncValue<T> v, Widget Function(T) data) => v.when(
        data: data,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load: $e')),
      );
}

class _Header extends StatelessWidget {
  const _Header({required this.me, required this.onEdit});
  final MeProfile me;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final initials = me.nickname.trim().isEmpty ? '?' : me.nickname.trim()[0].toUpperCase();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          CircleAvatar(
            radius: 38,
            backgroundColor: AppColors.primary,
            backgroundImage: me.avatarUrl == null ? null : NetworkImage(me.avatarUrl!),
            child: me.avatarUrl == null
                ? Text(initials, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white))
                : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(me.nickname,
                  key: const ValueKey('me-nickname'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text('ID: ${me.id}', style: const TextStyle(color: AppColors.muted)),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          _Count(key: const ValueKey('me-following'), n: me.followingCount, label: 'Following'),
          _Count(key: const ValueKey('me-followers'), n: me.followersCount, label: 'Followers'),
          _Count(key: const ValueKey('me-likes'), n: me.likesCount, label: 'Likes'),
          const Spacer(),
          FilledButton.tonal(
            key: const ValueKey('me-edit'),
            onPressed: onEdit,
            child: const Text('Edit profile'),
          ),
        ]),
      ]),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count({super.key, required this.n, required this.label});
  final int n;
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 22),
        child: Column(children: [
          Text(compactCount(n), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      );
}

class _EntryCards extends StatelessWidget {
  const _EntryCards({this.onShop, this.onRewards});
  final VoidCallback? onShop;
  final VoidCallback? onRewards;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          Expanded(
              child: _Entry(
                  key: const ValueKey('me-entry-shop'),
                  icon: Icons.storefront,
                  title: 'Shop',
                  sub: 'Orders & coins',
                  onTap: onShop)),
          const SizedBox(width: 10),
          Expanded(
              child: _Entry(
                  key: const ValueKey('me-entry-rewards'),
                  icon: Icons.sports_esports,
                  title: 'Games & Rewards',
                  sub: 'Claim coins',
                  onTap: onRewards)),
        ]),
      );
}

class _Entry extends StatelessWidget {
  const _Entry({super.key, required this.icon, required this.title, required this.sub, this.onTap});
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surfaceHigh,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Icon(icon, color: AppColors.gold),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(sub, maxLines: 1, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ]),
              ),
            ]),
          ),
        ),
      );
}

class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  _TabBarDelegate(this.controller, this.labels);
  final TabController controller;
  final List<String> labels;
  @override
  double get minExtent => 48;
  @override
  double get maxExtent => 48;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: TabBar(
          key: const ValueKey('me-tabs'),
          controller: controller,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: AppColors.primary,
          labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          tabs: [for (final l in labels) Tab(key: ValueKey('me-tab-$l'), text: l)],
        ),
      );
  @override
  bool shouldRebuild(covariant _TabBarDelegate old) => old.controller != controller;
}

class _Grid extends StatelessWidget {
  const _Grid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => GridView.count(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        crossAxisCount: 3,
        mainAxisSpacing: 12,
        crossAxisSpacing: 10,
        childAspectRatio: .52,
        children: children,
      );
}

class _CoverTile extends StatelessWidget {
  const _CoverTile({super.key, required this.drama, required this.caption, this.coverUrl, this.badge, this.onTap});
  final Drama drama;
  final String caption;
  final String? coverUrl;
  final String? badge;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Center(
              child: Stack(children: [
                CoverImage(coverUrl ?? drama.coverUrl, title: drama.title, radius: 10, decodeWidth: 240),
                if (badge != null)
                  Positioned(
                    right: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(4)),
                      child: Text(badge!, style: const TextStyle(fontSize: 10)),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Text(drama.title,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(caption, maxLines: 1, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      );
}

class _Empty extends StatelessWidget {
  const _Empty({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 44, color: AppColors.primary),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(color: AppColors.muted)),
        ]),
      );
}
