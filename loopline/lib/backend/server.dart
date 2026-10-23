import 'dart:convert';
import 'dart:io';
import 'package:dotenv/dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:loopline/backend/arbitrage.dart';
import 'package:loopline/backend/detector.dart';
import 'package:loopline/frontend/pages/providers/providers.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_cors_headers/shelf_cors_headers.dart';
import 'package:shelf_router/shelf_router.dart';

final _client = http.Client();

const _finnhubPairs = [
  'EUR_USD', 'GBP_USD', 'USD_JPY', 'USD_CHF',
  'USD_CAD', 'AUD_USD', 'NZD_USD', 'EUR_GBP',
];
final env = DotEnv()..load();
final FinnhubProvider? _finnhub = _createFinnhubProvider();

FinnhubProvider? _createFinnhubProvider() {
  final apiKey = env['FINNHUB_API']?.trim();
  if (apiKey == null || apiKey.isEmpty) return null;
  return FinnhubProvider(apiKey: apiKey, pairs: _finnhubPairs);
}

final _providers = <String, RateProvider>{
  for (final p in <RateProvider>[
    OkxProvider(_client),
    EcbProvider(_client),
    ?_finnhub,
  ])
    p.id: p,
};
final _cache = SnapshotCache();

class _ArbitrageDebounce {
  final Map<String, _ArbitrageResult> _cached = {};
  static const window = Duration(milliseconds: 300);

  _ArbitrageResult? get(String key) {
    final hit = _cached[key];
    if (hit == null) return null;
    if (DateTime.now().toUtc().difference(hit.computedAt) > window) return null;
    return hit;
  }

  void put(String key, _ArbitrageResult value) => _cached[key] = value;
}

class _ArbitrageResult {
  final DateTime computedAt;
  final Map<String, dynamic> json;
  _ArbitrageResult(this.computedAt, this.json);
}

final _arbitrageDebounce = _ArbitrageDebounce();

class _HttpError implements Exception {
  final int status;
  final String message;
  _HttpError(this.status, this.message);
}

class _Graph {
  final List<String> currencies;
  final Map<String, Map<String, double>> rates;
  _Graph(this.currencies, this.rates);
}

class _Ctx {
  final RateProvider provider;
  final RateSnapshot snapshot;
  final _Graph graph;
  _Ctx(this.provider, this.snapshot, this.graph);
}

Response _json(Object body, {int status = 200}) => Response(
      status,
      body: jsonEncode(body),
      headers: {'content-type': 'application/json'},
    );

List<String> _assets(String? raw, List<String> fallback) {
  if (raw == null || raw.trim().isEmpty) return fallback;
  return raw
      .split(',')
      .map((s) => s.trim().toUpperCase())
      .where((s) => s.isNotEmpty)
      .toSet()
      .toList();
}

_Graph _subgraph(Map<String, Map<String, double>> all, List<String> assets) {
  final currencies = <String>[
    for (final a in assets)
      if (all.containsKey(a)) a,
  ];
  final rates = <String, Map<String, double>>{
    for (final a in currencies)
      a: <String, double>{
        for (final e in all[a]!.entries)
          if (currencies.contains(e.key)) e.key: e.value,
      },
  };
  return _Graph(currencies, rates);
}

List<List<double>> _matrix(_Graph g) => [
      for (final a in g.currencies)
        [
          for (final b in g.currencies)
            a == b ? 1.0 : (g.rates[a]?[b] ?? 0.0),
        ],
    ];

Map<String, dynamic> _meta(_Ctx c) => {
      'source': c.provider.id,
      'label': c.provider.label,
      'realtime': c.provider.realtime,
      'note': c.provider.note,
      'fetchedAt': c.snapshot.fetchedAt.toIso8601String(),
      'currencies': c.graph.currencies,
    };

Map<String, dynamic> _oppJson(Arbitrage o) => {
      'path': o.path,
      'profitFactor': o.profitFactor,
      'profitPercent': o.profitPercent,
    };

Future<_Ctx> _prepare(Request req) async {
  final q = req.url.queryParameters;
  final provider = _providers[q['source'] ?? 'okx'];
  if (provider == null) {
    throw _HttpError(
        400, 'Unknown source. Use one of: ${_providers.keys.join(', ')}');
  }
  final assets = _assets(q['assets'], provider.defaultAssets);

  final snapshot = await _cache.get(provider).timeout(
        const Duration(seconds: 12),
        onTimeout: () => throw _HttpError(
            504,
            '${provider.id} returned no data within 12s. '
            'For finnhub: check the API key, that the forex market is open '
            '(closed on weekends), and the server logs.'),
      );
  final graph = _subgraph(snapshot.rates, assets);
  if (graph.currencies.length < 2) {
    throw _HttpError(400,
        'Need at least 2 assets supported by ${provider.id}. Matched: ${graph.currencies}');
  }
  return _Ctx(provider, snapshot, graph);
}

Future<Response> _rates(Request req) async {
  final c = await _prepare(req);
  return _json({..._meta(c), 'matrix': _matrix(c.graph)});
}

Future<Response> _arbitrage(Request req) async {
  final c = await _prepare(req);
  final q = req.url.queryParameters;
  final feePercent =
      (double.tryParse(q['fee'] ?? '') ?? 0.1).clamp(0.0, 5.0).toDouble();
  final minProfit = double.tryParse(q['minProfit'] ?? '') ?? 0.0;

  final debounceKey =
      '${c.provider.id}|${c.graph.currencies.join(",")}|$feePercent|$minProfit';
  final cached = _arbitrageDebounce.get(debounceKey);
  if (cached != null) return _json(cached.json);

  final detector = ArbitrageDetector(
    currencies: c.graph.currencies,
    rates: c.graph.rates,
    fee: feePercent / 100,
  );
  final opportunities = detector
      .detectAll()
      .where((o) => o.profitPercent >= minProfit)
      .toList()
    ..sort((a, b) => b.profitFactor.compareTo(a.profitFactor));

  final body = {
    ..._meta(c),
    'feePercent': feePercent,
    'matrix': _matrix(c.graph),
    'opportunities': opportunities.map(_oppJson).toList(),
    'closestLoops': detector.closestLoops(limit: 5).map(_oppJson).toList(),
  };
  _arbitrageDebounce.put(debounceKey, _ArbitrageResult(DateTime.now().toUtc(), body));
  return _json(body);
}

Middleware _errors() => (inner) => (req) async {
      try {
        return await inner(req);
      } on _HttpError catch (e) {
        return _json({'error': e.message}, status: e.status);
      } on ProviderException catch (e) {
        return _json({'error': e.message}, status: 502);
      } catch (e) {
        return _json({'error': 'Upstream request failed: $e'}, status: 502);
      }
    };

Future<void> main() async {
  final router = Router()
    ..get('/', (Request r) => _json({'status': 'ok'}))
    ..get('/health', (Request r) => _json({'status': 'ok'}))
    ..get(
        '/api/sources',
        (Request r) => _json({
              'sources': [
                for (final p in _providers.values)
                  {
                    'id': p.id,
                    'label': p.label,
                    'realtime': p.realtime,
                    'note': p.note,
                    'defaultAssets': p.defaultAssets,
                    if (p is FinnhubProvider) 'connected': p.connected,
                  },
              ],
            }))
    ..get('/api/rates', _rates)
    ..get('/api/arbitrage', _arbitrage);

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addMiddleware(_errors())
      .addHandler(router.call);

  final port = int.parse(Platform.environment['PORT'] ?? '8000');
  final server = await io.serve(handler, InternetAddress.anyIPv4, port);
  print('Arbitrage API listening on port ${server.port}');
  print('Open http://127.0.0.1:${server.port}/health  (0.0.0.0 is only the bind address; do not use it as a client URL)');
  if (_finnhub == null) {
    print('FINNHUB_API not set -- finnhub source disabled (okx/ecb still work)');
  } else {
    print('Finnhub WebSocket connecting for: ${_finnhubPairs.join(", ")}');
  }

  for (final sig in [ProcessSignal.sigint, ProcessSignal.sigterm]) {
    sig.watch().listen((_) async {
      _finnhub?.dispose();
      await server.close(force: true);
      exit(0);
    });
  }
}
