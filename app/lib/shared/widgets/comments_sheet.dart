import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../core/network/api_response.dart';
import '../../data/mock/mock_api.dart';
import '../../data/models.dart';

/// Bottom sheet for GET/POST /episodes/{id}/comments + comment likes.
/// Shared by the Home feed and the player page.
Future<void> showCommentsSheet(BuildContext context,
    {required String episodeId, required int commentCount, ValueChanged<int>? onPosted}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (_) => CommentsSheet(episodeId: episodeId, commentCount: commentCount, onPosted: onPosted),
  );
}

String timeAgo(DateTime t, {DateTime? now}) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

class CommentsSheet extends ConsumerStatefulWidget {
  const CommentsSheet({super.key, required this.episodeId, required this.commentCount, this.onPosted});
  final String episodeId;
  final int commentCount;
  final ValueChanged<int>? onPosted;
  @override
  ConsumerState<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends ConsumerState<CommentsSheet> {
  String _sort = 'hot';
  List<Comment>? _items;
  bool _hasMore = false;
  int _page = 1;
  bool _sending = false;
  String? _error;
  late int _count = widget.commentCount;
  final _ctrl = TextEditingController();

  MockApi get _api => ref.read(mockApiProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    final page = more ? _page + 1 : 1;
    final r = await _api.comments(widget.episodeId, sort: _sort, page: page);
    if (!mounted) return;
    setState(() {
      _page = page;
      _hasMore = r.hasMore;
      _items = more ? [...?_items, ...r.items] : r.items;
    });
  }

  Future<void> _send() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final c = await _api.postComment(widget.episodeId, _ctrl.text);
      _ctrl.clear();
      setState(() {
        _items = [c, ...?_items];
        _count++;
      });
      widget.onPosted?.call(_count);
    } on ApiException catch (e) {
      setState(() => _error = commentErrorMessage(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _like(int i) async {
    final c = _items![i];
    final on = !c.liked;
    setState(() => _items![i] = c.copyWith(liked: on, likeCount: c.likeCount + (on ? 1 : -1))); // optimistic
    try {
      final r = await _api.setCommentLiked(c.id, on);
      if (mounted) setState(() => _items![i] = c.copyWith(liked: r.liked, likeCount: r.likeCount));
    } on ApiException {
      if (mounted) setState(() => _items![i] = c);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.sizeOf(context).height;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SizedBox(
          key: const ValueKey('comments-sheet'),
          height: h * .62,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
              child: Row(children: [
                Text('${compactCount(_count)} comments',
                    key: const ValueKey('comments-count'),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                const Spacer(),
                for (final s in const [('hot', 'Hot'), ('new', 'New')])
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ChoiceChip(
                      key: ValueKey('comments-sort-${s.$1}'),
                      label: Text(s.$2),
                      selected: _sort == s.$1,
                      onSelected: (_) {
                        setState(() => _sort = s.$1);
                        _load();
                      },
                    ),
                  ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop()),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: _items == null
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : _items!.isEmpty
                      ? const Center(
                          child: Text('No comments yet. Be the first!', style: TextStyle(color: Colors.white60)))
                      : ListView.builder(
                          itemCount: _items!.length + (_hasMore ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == _items!.length) {
                              _load(more: true);
                              return const Padding(
                                  padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()));
                            }
                            final c = _items![i];
                            return ListTile(
                              key: ValueKey('comment-${c.id}'),
                              leading: CircleAvatar(
                                backgroundColor: AppColors.surfaceHigh,
                                foregroundImage: c.user.avatarUrl == null
                                    ? null
                                    : ResizeImage(NetworkImage(c.user.avatarUrl!), width: 96),
                                onForegroundImageError: c.user.avatarUrl == null ? null : (_, __) {},
                                child: Text(c.user.nickname.isEmpty ? '?' : c.user.nickname[0]),
                              ),
                              title: Text('${c.user.nickname} · ${timeAgo(c.createdAt)}',
                                  style: const TextStyle(fontSize: 13, color: Colors.white60)),
                              subtitle: Text(c.text, style: const TextStyle(fontSize: 15, color: Colors.white)),
                              trailing: GestureDetector(
                                key: ValueKey('comment-like-${c.id}'),
                                onTap: () => _like(i),
                                child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(c.liked ? Icons.favorite : Icons.favorite_border,
                                      size: 20, color: c.liked ? AppColors.primary : Colors.white60),
                                  Text(compactCount(c.likeCount), style: const TextStyle(fontSize: 12)),
                                ]),
                              ),
                            );
                          },
                        ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(_error!,
                    key: const ValueKey('comment-error'), style: const TextStyle(color: Colors.redAccent)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 6, 10),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('comment-input'),
                    controller: _ctrl,
                    maxLines: 3,
                    minLines: 1,
                    decoration: const InputDecoration(hintText: 'Add a comment…', isDense: true),
                  ),
                ),
                IconButton(
                  key: const ValueKey('comment-send'),
                  icon: const Icon(Icons.send, color: AppColors.primary),
                  onPressed: _sending ? null : _send,
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
