import 'package:flutter/material.dart';
import 'package:loopline_frontend/backend/detector.dart';
import 'package:loopline_frontend/frontend/pages/result_screen.dart';

class InputScreen extends StatefulWidget {
  const InputScreen({super.key});
 
  @override
  State<InputScreen> createState() => _InputScreenState();
}
 
class _InputScreenState extends State<InputScreen> {
  List<String> currencies = ['USD', 'EUR', 'GBP', 'INR'];
  late List<List<String>> cells;
  double feePercent = 0;
 
  /// Bumped whenever the grid is rebuilt so text fields pick up new values.
  int version = 0;
 
  @override
  void initState() {
    super.initState();
    cells = _blankGrid(currencies.length);
  }
 
  List<List<String>> _blankGrid(int n) => [
        for (var i = 0; i < n; i++)
          [for (var j = 0; j < n; j++) i == j ? '1' : ''],
      ];
 
  /// Consistent rates derived from USD prices, then GBP->INR is mispriced
  /// on purpose so exactly one edge creates the arbitrage.
  void _loadSample() {
    const usdPrice = {'USD': 1.0, 'EUR': 0.92, 'GBP': 0.79, 'INR': 83.2};
    final c = ['USD', 'EUR', 'GBP', 'INR'];
    final grid = [
      for (final a in c)
        [
          for (final b in c)
            a == b ? '1' : (usdPrice[b]! / usdPrice[a]!).toStringAsPrecision(8),
        ],
    ];
    grid[2][3] = '106.5'; // GBP -> INR quoted ~1.1% too high
    setState(() {
      currencies = c;
      cells = grid;
      feePercent = 0;
      version++;
    });
  }
 
  Future<void> _addCurrency() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add currency'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          maxLength: 5,
          decoration: const InputDecoration(hintText: 'e.g. JPY'),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Add')),
        ],
      ),
    );
    final clean = code?.trim().toUpperCase() ?? '';
    if (clean.isEmpty || currencies.contains(clean)) return;
    setState(() {
      for (final row in cells) {
        row.add('');
      }
      currencies = [...currencies, clean];
      cells.add([
        for (var j = 0; j < currencies.length; j++)
          j == currencies.length - 1 ? '1' : '',
      ]);
      version++;
    });
  }
 
  void _removeCurrency(int index) {
    if (currencies.length <= 2) return;
    setState(() {
      cells.removeAt(index);
      for (final row in cells) {
        row.removeAt(index);
      }
      currencies = [...currencies]..removeAt(index);
      version++;
    });
  }
 
  void _detect() {
    final matrix = [
      for (final row in cells)
        [for (final s in row) double.tryParse(s.trim()) ?? 0.0],
    ];
    final detector = ArbitrageDetector.fromMatrix(
      currencies,
      matrix,
      fee: feePercent / 100,
    );
    final results = detector.detectAll()
      ..sort((a, b) => b.profitFactor.compareTo(a.profitFactor));
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ResultsScreen(detector: detector, results: results),
      ),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Arbitrage Tracker'),
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text('Currencies', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (var i = 0; i < currencies.length; i++)
                InputChip(
                  label: Text(currencies[i]),
                  onDeleted:
                      currencies.length > 2 ? () => _removeCurrency(i) : null,
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
                onPressed: _addCurrency,
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text('Exchange rates', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Row = from, column = to. Cell shows how many units of the column '
            'currency you get for 1 unit of the row currency.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          _buildMatrix(theme),
          const SizedBox(height: 24),
          Text('Trading fee per conversion: ${feePercent.toStringAsFixed(2)}%',
              style: theme.textTheme.titleMedium),
          Slider(
            value: feePercent,
            min: 0,
            max: 1,
            divisions: 100,
            onChanged: (v) => setState(() => feePercent = v),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loadSample,
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Load sample'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _detect,
                  icon: const Icon(Icons.radar),
                  label: const Text('Detect'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
 
  Widget _buildMatrix(ThemeData theme) {
    const cellWidth = 92.0;
    const labelWidth = 56.0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const SizedBox(width: labelWidth),
              for (final c in currencies)
                SizedBox(
                  width: cellWidth,
                  child: Center(
                    child: Text('to $c',
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < currencies.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: Text(currencies[i],
                        style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600)),
                  ),
                  for (var j = 0; j < currencies.length; j++)
                    SizedBox(
                      width: cellWidth,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: TextFormField(
                          key: ValueKey('$version-$i-$j'),
                          initialValue: cells[i][j],
                          enabled: i != j,
                          textAlign: TextAlign.center,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 6, vertical: 10),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => cells[i][j] = v,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}