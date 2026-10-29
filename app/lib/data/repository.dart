import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_client.dart';
import 'models.dart';

Map<String, dynamic> _m(Object? d) => d as Map<String, dynamic>;

class Repository {
  Repository(this._api);
  final ApiClient _api;

  Future<HomeData> home() =>
      _api.get('/home', decode: (d) => HomeData.fromJson(_m(d)));

  Future<List<Drama>> dramas({int page = 1, int size = 20}) => _api.get(
        '/dramas',
        query: {'page': page, 'size': size},
        decode: (d) => ((_m(d)['items'] as List?) ?? const [])
            .map((e) => Drama.fromJson(_m(e)))
            .toList(),
      );

  Future<Drama> drama(String id) =>
      _api.get('/dramas/$id', decode: (d) => Drama.fromJson(_m(d)));

  Future<PlayInfo> play(String episodeId) => _api.get(
      '/episodes/$episodeId/play', decode: (d) => PlayInfo.fromJson(_m(d)));

  Future<UnlockResult> unlockWithCoins(String episodeId) => _api.post(
      '/episodes/$episodeId/unlock',
      body: {'method': 'coin'},
      decode: (d) => UnlockResult.fromJson(_m(d)));

  Future<Wallet> wallet() =>
      _api.get('/wallet', decode: (d) => Wallet.fromJson(_m(d)));
}

final repositoryProvider =
    Provider<Repository>((ref) => Repository(ref.watch(apiClientProvider)));

final homeProvider =
    FutureProvider.autoDispose<HomeData>((ref) => ref.watch(repositoryProvider).home());

final dramaListProvider = FutureProvider.autoDispose<List<Drama>>(
    (ref) => ref.watch(repositoryProvider).dramas());

final dramaDetailProvider = FutureProvider.autoDispose.family<Drama, String>(
    (ref, id) => ref.watch(repositoryProvider).drama(id));

final walletProvider =
    FutureProvider<Wallet>((ref) => ref.watch(repositoryProvider).wallet());
