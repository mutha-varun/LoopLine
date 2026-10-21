import 'package:flutter/material.dart';
import 'package:loopline/backend/arbitrage.dart';
import 'package:loopline/backend/detector.dart';

class ResultsScreen extends StatefulWidget {
  final ArbitrageDetector detector;
  final List<Arbitrage> results;
 
  const ResultsScreen({
    super.key,
    required this.detector,
    required this.results,
  });
 
  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}
 
class _ResultsScreenState extends State<ResultsScreen> {
  final _amountController = TextEditingController(text: '1000');
 
  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }
 
  double get _startAmount => double.tryParse(_amountController.text) ?? 0;
 
  /// Money after each hop of the loop, starting from [start].
  List<double> _walk(Arbitrage o, double start) {
    final amounts = [start];
    var a = start;
    for (var i = 0; i < o.path.length - 1; i++) {
      a = a *
          widget.detector.rates[o.path[i]]![o.path[i + 1]]! *
          (1 - widget.detector.fee);
      amounts.add(a);
    }
    return amounts;
  }
 
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = widget.results;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Results'),
        backgroundColor: Colors.transparent,
      ),
      body: results.isEmpty
          ? _emptyState(theme)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                Text(
                  '${results.length} arbitrage '
                  '${results.length == 1 ? 'loop' : 'loops'} found',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Starting amount',
                    helperText: 'In the first currency of each loop',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 16),
                for (final o in results) _opportunityCard(theme, o),
              ],
            ),
    );
  }
 
  Widget _emptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.balance, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text('No arbitrage found', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Every loop multiplies to 1 or less, so the rates are consistent '
              '(no negative cycle in the graph).',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
 
  Widget _opportunityCard(ThemeData theme, Arbitrage o) {
    final start = _startAmount;
    final amounts = _walk(o, start);
    final gain = amounts.last - start;
    final green = theme.colorScheme.primary;
 
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: const Color(0xFF161B22),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var i = 0; i < o.path.length; i++) ...[
                        Chip(
                          label: Text(o.path[i]),
                          visualDensity: VisualDensity.compact,
                        ),
                        if (i < o.path.length - 1)
                          Icon(Icons.arrow_forward,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: green.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '+${o.profitPercent.toStringAsFixed(3)}%',
                    style: TextStyle(color: green, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < o.path.length - 1; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${o.path[i]} → ${o.path[i + 1]}  '
                        '×${widget.detector.rates[o.path[i]]![o.path[i + 1]]!.toStringAsPrecision(6)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                    Text(
                      '${amounts[i + 1].toStringAsFixed(2)} ${o.path[i + 1]}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            const Divider(height: 24),
            Text(
              start > 0
                  ? 'Start ${start.toStringAsFixed(2)} ${o.path.first} → '
                      'end ${amounts.last.toStringAsFixed(2)} ${o.path.first} '
                      '(${gain >= 0 ? '+' : ''}${gain.toStringAsFixed(2)})'
                  : 'Enter a starting amount to simulate this loop',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
 