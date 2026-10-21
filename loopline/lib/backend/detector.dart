import 'dart:math';

import 'package:loopline/backend/arbitrage.dart';
import 'package:loopline/backend/model/edge.dart';

class ArbitrageDetector {
  final List<String> currencies;
 
  /// rates[from][to] = units of `to` received for 1 unit of `from`.
  final Map<String, Map<String, double>> rates;
 
  /// Optional per-trade fee as a fraction (0.001 = 0.1%).
  final double fee;
 
  ArbitrageDetector({
    required this.currencies,
    required this.rates,
    this.fee = 0.0,
  });
 
  /// Builds the detector from a square matrix (matrix[i][j] = rate i -> j).
  factory ArbitrageDetector.fromMatrix(
    List<String> currencies,
    List<List<double>> matrix, {
    double fee = 0.0,
  }) {
    final rates = <String, Map<String, double>>{};
    for (var i = 0; i < currencies.length; i++) {
      rates[currencies[i]] = {
        for (var j = 0; j < currencies.length; j++)
          if (i != j) currencies[j]: matrix[i][j],
      };
    }
    return ArbitrageDetector(currencies: currencies, rates: rates, fee: fee);
  }
 
  double _effectiveRate(String from, String to) =>
      rates[from]![to]! * (1 - fee);
 
  List<Edge> _buildEdges(Map<String, int> index) {
    final edges = <Edge>[];
    rates.forEach((from, targets) {
      targets.forEach((to, rate) {
        final u = index[from];
        final v = index[to];
        if (u == null || v == null || u == v || rate <= 0) return;
        edges.add(Edge(u, v, -log(rate * (1 - fee))));
      });
    });
    return edges;
  }
 
  /// Returns one arbitrage loop, or null if none exists.
  Arbitrage? detect() {
    final n = currencies.length;
    if (n < 2) return null;
 
    final index = {for (var i = 0; i < n; i++) currencies[i]: i};
    final edges = _buildEdges(index);
 
    // All distances start at 0 = virtual source connected to every node,
    // so a negative cycle anywhere in the graph is found.
    final dist = List<double>.filled(n, 0);
    final pred = List<int>.filled(n, -1);
    const eps = 1e-7; // ignore float-noise loops (< ~0.00001%)
 
    var lastRelaxed = -1;
    for (var pass = 0; pass < n; pass++) {
      lastRelaxed = -1;
      for (final e in edges) {
        if (dist[e.from] + e.weight < dist[e.to] - eps) {
          dist[e.to] = dist[e.from] + e.weight;
          pred[e.to] = e.from;
          lastRelaxed = e.to;
        }
      }
      if (lastRelaxed == -1) return null; // converged -> no negative cycle
    }
 
    // Relaxation still happening on pass n => negative cycle reachable.
    // Step back n times to guarantee we are inside the cycle.
    var x = lastRelaxed;
    for (var i = 0; i < n; i++) {
      x = pred[x];
    }
 
    final loop = <int>[];
    var cur = x;
    do {
      loop.add(cur);
      cur = pred[cur];
    } while (cur != x);
    loop.add(x);
 
    final ordered = loop.reversed.map((i) => currencies[i]).toList();
 
    var profit = 1.0;
    for (var i = 0; i < ordered.length - 1; i++) {
      profit *= _effectiveRate(ordered[i], ordered[i + 1]);
    }
    return Arbitrage(ordered, profit);
  }
 
  /// Finds every distinct opportunity by removing one edge of each found
  /// loop and re-running detection (bounded by [limit]).
  List<Arbitrage> detectAll({int limit = 10}) {
    final working = <String, Map<String, double>>{
      for (final e in rates.entries) e.key: Map.of(e.value),
    };
    final found = <Arbitrage>[];
    final seen = <String>{};
 
    for (var i = 0; i < limit; i++) {
      final opp = ArbitrageDetector(
        currencies: currencies,
        rates: working,
        fee: fee,
      ).detect();
      if (opp == null) break;
 
      final key = _canonicalKey(opp.path);
      if (seen.add(key)) found.add(opp);
 
      // Break the loop by dropping its first edge, then search again.
      working[opp.path[0]]?.remove(opp.path[1]);
    }
    return found;
  }
 
  String _canonicalKey(List<String> path) {
    final body = path.sublist(0, path.length - 1);
    final start = body.indexOf(body.reduce((a, b) => a.compareTo(b) < 0 ? a : b));
    final rotated = [...body.sublist(start), ...body.sublist(0, start)];
    return rotated.join('>');
  }
 
  /// Best 3-currency loops even when unprofitable. Shows how close a live
  /// market is to arbitrage (result is usually slightly below 0%).
  List<Arbitrage> closestLoops({int limit = 5}) {
    final out = <Arbitrage>[];
    final n = currencies.length;
    final keep = (1 - fee) * (1 - fee) * (1 - fee);
    for (var i = 0; i < n; i++) {
      for (var j = i + 1; j < n; j++) {
        for (var k = i + 1; k < n; k++) {
          if (k == j) continue;
          final a = currencies[i], b = currencies[j], c = currencies[k];
          final ab = rates[a]?[b], bc = rates[b]?[c], ca = rates[c]?[a];
          if (ab == null || bc == null || ca == null) continue;
          out.add(Arbitrage([a, b, c, a], ab * bc * ca * keep));
        }
      }
    }
    out.sort((x, y) => y.profitFactor.compareTo(x.profitFactor));
    return out.take(limit).toList();
  }
}
 