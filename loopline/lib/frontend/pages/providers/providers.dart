import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class ProviderException implements Exception {
  final String message;
  ProviderException(this.message);

  @override
  String toString() => message;
}

/// rates[from][to] = units of `to` received for 1 unit of `from`.
class RateSnapshot {
  final String source;
  final DateTime fetchedAt;
  final Map<String, Map<String, double>> rates;

  const RateSnapshot(this.source, this.fetchedAt, this.rates);
}

abstract class RateProvider {
  String get id;
  String get label;
  bool get realtime;
  String get note;
  List<String> get defaultAssets;
  Duration get cacheTtl;
  Future<RateSnapshot> fetch();
}

/// OKX spot order-book tickers: real-time best bid/ask, no API key.
///  - selling BASE for QUOTE pays the bid  => rate BASE->QUOTE = bid
///  - buying  BASE with QUOTE pays the ask => rate QUOTE->BASE = 1 / ask
/// Using bid/ask (not mid price) is what makes the arbitrage check honest.
class OkxProvider implements RateProvider {
  final http.Client _client;
  OkxProvider(this._client);

  @override
  String get id => 'okx';
  @override
  String get label => 'OKX spot';
  @override
  bool get realtime => true;
  @override
  String get note => 'live best bid/ask';
  @override
  List<String> get defaultAssets =>
      ['USDT', 'USDC', 'BTC', 'ETH', 'SOL', 'XRP', 'DOGE', 'LTC'];
  @override
  Duration get cacheTtl => const Duration(seconds: 2);

  @override
  Future<RateSnapshot> fetch() async {
    // Override with: OKX_BASE_URL=https://your-proxy-or-mirror dart run bin/server.dart
    final base = Platform.environment['OKX_BASE_URL'] ?? 'https://www.okx.com';
    final http.Response res;
    try {
      res = await _client
          .get(Uri.parse('$base/api/v5/market/tickers?instType=SPOT'))
          .timeout(const Duration(seconds: 6));
    } on TimeoutException {
      throw ProviderException(
          'This server could not reach $base within 6s (network, VPN or ISP block?)');
    } on SocketException catch (e) {
      throw ProviderException('Cannot connect to $base: ${e.message}');
    }
    if (res.statusCode != 200) {
      throw ProviderException('OKX returned HTTP ${res.statusCode}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (body['code'] != '0') {
      throw ProviderException('OKX error: ${body['msg']}');
    }

    final rates = <String, Map<String, double>>{};
    for (final item in body['data'] as List) {
      final t = item as Map<String, dynamic>;
      final parts = (t['instId'] as String).split('-');
      if (parts.length != 2) continue;

      final bid = double.tryParse('${t['bidPx']}');
      final ask = double.tryParse('${t['askPx']}');
      if (bid == null || ask == null || bid <= 0 || ask <= 0) continue;

      final base = parts[0], quote = parts[1];
      (rates[base] ??= {})[quote] = bid;
      (rates[quote] ??= {})[base] = 1 / ask;
    }
    return RateSnapshot(id, DateTime.now().toUtc(), rates);
  }
}

/// ECB reference rates via Frankfurter. Published once per working day, so
/// this is NOT real-time and is internally consistent (cross rates from one
/// USD base), meaning it should show no arbitrage. Useful as a control case.
class EcbProvider implements RateProvider {
  final http.Client _client;
  EcbProvider(this._client);

  @override
  String get id => 'ecb';
  @override
  String get label => 'ECB reference';
  @override
  bool get realtime => false;
  @override
  String get note => 'daily reference rates, not real-time';
  @override
  List<String> get defaultAssets =>
      ['USD', 'EUR', 'GBP', 'INR', 'JPY', 'CHF', 'AUD', 'CAD'];
  @override
  Duration get cacheTtl => const Duration(minutes: 10);

  @override
  Future<RateSnapshot> fetch() async {
    final http.Response res;
    try {
      res = await _client
          .get(Uri.parse('https://api.frankfurter.dev/v1/latest?base=USD'))
          .timeout(const Duration(seconds: 8));
    } on TimeoutException {
      throw ProviderException('Frankfurter did not respond within 8s');
    } on SocketException catch (e) {
      throw ProviderException('Cannot connect to Frankfurter: ${e.message}');
    }
    if (res.statusCode != 200) {
      throw ProviderException('Frankfurter returned HTTP ${res.statusCode}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final usd = <String, double>{'USD': 1.0};
    (body['rates'] as Map<String, dynamic>)
        .forEach((k, v) => usd[k] = (v as num).toDouble());

    final rates = <String, Map<String, double>>{};
    for (final a in usd.keys) {
      rates[a] = {
        for (final b in usd.keys)
          if (a != b) b: usd[b]! / usd[a]!,
      };
    }
    return RateSnapshot(id, DateTime.now().toUtc(), rates);
  }
}

/// Per-source cache; concurrent requests share one upstream call.
class SnapshotCache {
  final Map<String, RateSnapshot> _snapshots = {};
  final Map<String, Future<RateSnapshot>> _inflight = {};

  Future<RateSnapshot> get(RateProvider p) async {
    final cached = _snapshots[p.id];
    if (cached != null &&
        DateTime.now().toUtc().difference(cached.fetchedAt) < p.cacheTtl) {
      return cached;
    }
    return _inflight[p.id] ??= p.fetch().then((snap) {
      _snapshots[p.id] = snap;
      return snap;
      // NOTE: the braces matter. `() => _inflight.remove(id)` returns the very
      // future whenComplete() is building, so it waited on itself forever and
      // every request hung (the bug behind the 504s).
    }).whenComplete(() {
      _inflight.remove(p.id);
    });
  }
}

class _LiveTick {
  final double price;
  final DateTime time;
  const _LiveTick(this.price, this.time);
}

/// Finnhub forex WebSocket: wss://ws.finnhub.io, OANDA symbols like
/// OANDA:EUR_USD. Pushes {"type":"trade","data":[{p,s,t,...}]} on every
/// tick. No fixed interval -- liquid pairs tick constantly, thin pairs can
/// go quiet, and forex closes entirely on weekends. This class keeps an
/// in-memory last-tick table and reconnects with backoff; fetch() just
/// reads that table and drops anything older than [maxTickAge].
class FinnhubProvider implements RateProvider {
  final String apiKey;

  /// OANDA pairs without the exchange prefix, e.g. 'EUR_USD'. Only the
  /// listed direction is subscribed -- the reverse edge is derived as 1/p
  /// rather than opening a second subscription for it.
  final List<String> pairs;

  final Map<String, _LiveTick> _ticks = {};
  WebSocketChannel? _channel;
  StreamSubscription? _sub;
  Timer? _reconnectTimer;
  Timer? _watchdog;
  int _backoffSeconds = 1;
  DateTime? _lastMessageAt;
  bool _disposed = false;

  /// A tick older than this is treated as stale and excluded from the
  /// graph -- it no longer reflects a tradeable price.
  static const maxTickAge = Duration(seconds: 15);

  /// If NO message at all (not even on an unrelated pair) has arrived in
  /// this long, the socket itself is considered dead, not just quiet.
  static const connectionTimeout = Duration(seconds: 45);

  FinnhubProvider({required this.apiKey, required this.pairs}) {
    _connect();
    // Belt-and-braces: some dead sockets don't fire onDone/onError.
    _watchdog = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_lastMessageAt == null) return;
      if (DateTime.now().toUtc().difference(_lastMessageAt!) >
          connectionTimeout) {
        _scheduleReconnect();
      }
    });
  }

  @override
  String get id => 'finnhub';
  @override
  String get label => 'Finnhub forex';
  @override
  bool get realtime => true;
  @override
  String get note =>
      connected ? 'live tick stream (OANDA via Finnhub)' : 'reconnecting…';
  @override
  List<String> get defaultAssets => _currenciesFromPairs(pairs);
  @override
  Duration get cacheTtl => Duration.zero; // in-memory read, no need to cache

  bool get connected =>
      _lastMessageAt != null &&
      DateTime.now().toUtc().difference(_lastMessageAt!) < connectionTimeout;

  void _connect() {
    if (_disposed) return;
    final uri = Uri.parse('wss://ws.finnhub.io?token=$apiKey');
    // Don't print the token.
    print('[finnhub] connecting to wss://ws.finnhub.io');
    try {
      _channel = IOWebSocketChannel.connect(uri);
    } catch (e, st) {
      print('[finnhub] connect() threw: $e');
      print(st);
      _scheduleReconnect();
      return;
    }
    // ready completes only once the WebSocket handshake actually succeeds --
    // IOWebSocketChannel.connect() returning does NOT mean connected yet.
    _channel!.ready.then((_) {
      print('[finnhub] handshake OK, subscribing to ${pairs.length} pairs');
      for (final pair in pairs) {
        _channel!.sink
            .add(jsonEncode({'type': 'subscribe', 'symbol': 'OANDA:$pair'}));
      }
      _backoffSeconds = 1; // reset only once a connection truly succeeds
    }).catchError((e, st) {
      print('[finnhub] handshake FAILED: $e');
      _scheduleReconnect();
    });
    _sub = _channel!.stream.listen(
      _onMessage,
      onError: (e) {
        print('[finnhub] stream error: $e');
        _scheduleReconnect();
      },
      onDone: () {
        print('[finnhub] stream closed (code=${_channel?.closeCode}, reason=${_channel?.closeReason})');
        _scheduleReconnect();
      },
      cancelOnError: true,
    );
  }

  void _onMessage(dynamic raw) {
    if (_lastMessageAt == null) print('[finnhub] first message received');
    _lastMessageAt = DateTime.now().toUtc();

    final Map<String, dynamic> msg;
    try {
      msg = jsonDecode(raw as String) as Map<String, dynamic>;
    } catch (_) {
      return; // ping/malformed frame -- ignore, connection still counts as alive
    }
    if (msg['type'] != 'trade') return;
    final data = msg['data'];
    if (data is! List) return;

    for (final entry in data) {
      final t = entry as Map<String, dynamic>;
      final symbol = t['s'] as String?;
      final price = (t['p'] as num?)?.toDouble();
      if (symbol == null || price == null || price <= 0) continue;

      final pair = symbol.startsWith('OANDA:') ? symbol.substring(6) : symbol;
      final tsMs = t['t'] as num?;
      final time = tsMs != null
          ? DateTime.fromMillisecondsSinceEpoch(tsMs.toInt(), isUtc: true)
          : DateTime.now().toUtc();
      _ticks[pair] = _LiveTick(price, time);
    }
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _sub?.cancel();
    _channel = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: _backoffSeconds), _connect);
    _backoffSeconds = (_backoffSeconds * 2).clamp(1, 30);
  }

  List<String> _currenciesFromPairs(List<String> pairs) {
    final set = <String>{};
    for (final p in pairs) {
      final parts = p.split('_');
      if (parts.length == 2) set.addAll(parts);
    }
    final list = set.toList()..sort();
    return list;
  }

  @override
  Future<RateSnapshot> fetch() async {
    final now = DateTime.now().toUtc();

    if (!connected) {
      throw ProviderException(
          'Finnhub WebSocket is not connected (reconnecting) -- no live ticks available right now');
    }

    final rates = <String, Map<String, double>>{};
    var freshCount = 0;
    for (final e in _ticks.entries) {
      if (now.difference(e.value.time) > maxTickAge) continue; // stale tick
      final parts = e.key.split('_');
      if (parts.length != 2) continue;
      final base = parts[0], quote = parts[1];
      final price = e.value.price;
      (rates[base] ??= {})[quote] = price;
      (rates[quote] ??= {})[base] = 1 / price; // derived reciprocal edge
      freshCount++;
    }

    if (freshCount == 0) {
      throw ProviderException(
          'Connected to Finnhub but every subscribed pair is stale (older than ${maxTickAge.inSeconds}s) -- market may be closed');
    }
    return RateSnapshot(id, now, rates);
  }

  void dispose() {
    _disposed = true;
    _watchdog?.cancel();
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
  }
}