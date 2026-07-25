import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import '../../../core/api/luse_client.dart';
import '../../../core/api/africanfinancials_client.dart';
import '../../../core/storage/luse_store.dart';
import '../models/luse_market_snapshot.dart';
import '../models/luse_fundamentals.dart';
import '../models/luse_company_profile.dart';

final luseStoreProvider = Provider<LuseStore>((ref) => LuseStore());

final luseClientProvider = Provider<LuseClient>((ref) {
  return LuseClient(
    africanfinancialsClient: ref.read(africanfinancialsClientProvider),
  );
});

final luseEnabledProvider =
    StateNotifierProvider<LuseEnabledNotifier, bool>((ref) {
  return LuseEnabledNotifier(ref);
});

class LuseEnabledNotifier extends StateNotifier<bool> {
  LuseEnabledNotifier(this.ref) : super(false) {
    _init();
  }

  final Ref ref;

  Future<void> _init() async {
    final enabled = await ref.read(luseStoreProvider).isEnabled();
    if (mounted) state = enabled;
  }

  Future<void> toggle() async {
    state = !state;
    await ref.read(luseStoreProvider).setEnabled(state);
  }
}

final luseStocksProvider =
    FutureProvider.autoDispose<LuseMarketSnapshot>((ref) async {
  final client = ref.read(luseClientProvider);
  return client.fetchStocks();
});

final luseWatchlistProvider =
    StateNotifierProvider<LuseWatchlistNotifier, List<String>>((ref) {
  return LuseWatchlistNotifier(ref);
});

class LuseWatchlistNotifier extends StateNotifier<List<String>> {
  LuseWatchlistNotifier(this.ref) : super([]) {
    _init();
  }

  final Ref ref;

  Future<void> _init() async {
    final list = await ref.read(luseStoreProvider).getWatchlist();
    if (mounted) state = list;
  }

  Future<void> add(String symbol) async {
    state = [...state, symbol];
    await ref.read(luseStoreProvider).setWatchlist(state);
  }

  Future<void> remove(String symbol) async {
    state = state.where((s) => s != symbol).toList();
    await ref.read(luseStoreProvider).setWatchlist(state);
  }

  Future<void> toggle(String symbol) async {
    if (state.contains(symbol)) {
      await remove(symbol);
    } else {
      await add(symbol);
    }
  }
}

final luseHistoryProvider =
    FutureProvider.autoDispose<List<LuseMarketSnapshot>>((ref) async {
  final store = ref.read(luseStoreProvider);
  return store.getHistory();
});

final africanfinancialsClientProvider =
    Provider<AfricanfinancialsClient>((ref) => AfricanfinancialsClient());

final luseFundamentalsProvider =
    FutureProvider.autoDispose<List<LuseFundamentals>>((ref) async {
  final afClient = ref.read(africanfinancialsClientProvider);
  return afClient.fetchAllFundamentals();
});

final luseCompanyProfileProvider =
    FutureProvider.autoDispose.family<LuseCompanyProfile?, String>(
  (ref, symbol) async {
    final client = ref.read(africanfinancialsClientProvider);
    return client.fetchProfile(symbol);
  },
);

final luseStockHistoryProvider =
    FutureProvider.autoDispose<Map<String, List<Map<String, dynamic>>>>(
        (ref) async {
  final store = ref.read(luseStoreProvider);
  final watchlist = ref.read(luseWatchlistProvider);
  final result = <String, List<Map<String, dynamic>>>{};
  for (final symbol in watchlist) {
    result[symbol] = await store.getStockHistory(symbol);
  }
  return result;
});
