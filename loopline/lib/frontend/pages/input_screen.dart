
import 'package:flutter/material.dart';
import 'package:loopline/backend/detector.dart';
import 'package:loopline/backend/live.dart';
import 'package:loopline/frontend/pages/result_screen.dart';

class _SampleData {
  final String id;
  final String label;
  final String description;
  final List<String> currencies;
  final Map<String, double> unitsPerUsd;
  final Map<String, double> rateOverrides;

  const _SampleData({
    required this.id,
    required this.label,
    required this.description,
    required this.currencies,
    required this.unitsPerUsd,
    this.rateOverrides = const {},
  });

  List<List<String>> get matrix => [
        for (final from in currencies)
          [
            for (final to in currencies)
              if (from == to)
                '1'
              else
                (rateOverrides['$from->$to'] ??
                        unitsPerUsd[to]! / unitsPerUsd[from]!)
                    .toStringAsPrecision(8),
          ],
      ];
}

const _sampleData = [
  _SampleData(
    id: 'fx-arbitrage',
    label: 'FX with arbitrage',
    description: 'A mispriced GBP/INR quote creates an arbitrage opportunity.',
    currencies: ['USD', 'EUR', 'GBP', 'INR'],
    unitsPerUsd: {'USD': 1.0, 'EUR': 0.92, 'GBP': 0.79, 'INR': 83.2},
    rateOverrides: {'GBP->INR': 106.5},
  ),
  _SampleData(
    id: 'fx-consistent',
    label: 'Consistent FX',
    description: 'Cross-rates all agree, so no arbitrage should be found.',
    currencies: ['USD', 'EUR', 'GBP', 'INR'],
    unitsPerUsd: {'USD': 1.0, 'EUR': 0.92, 'GBP': 0.79, 'INR': 83.2},
  ),
  _SampleData(
    id: 'crypto-arbitrage',
    label: 'Crypto with arbitrage',
    description: 'A mispriced ETH/SOL quote creates an arbitrage opportunity.',
    currencies: ['USDT', 'BTC', 'ETH', 'SOL'],
    unitsPerUsd: {
      'USDT': 1.0,
      'BTC': 0.000015,
      'ETH': 0.00027,
      'SOL': 0.0065,
    },
    rateOverrides: {'ETH->SOL': 25.5},
  ),
];

class InputScreen extends StatefulWidget {
  const InputScreen({super.key});
 
  @override
  State<InputScreen> createState() => _InputScreenState();
}
 
class _InputScreenState extends State<InputScreen> {
  List<String> currencies = ['USD', 'EUR', 'GBP', 'INR'];
  late List<List<String>> cells;
  double feePercent = 0;
  late final ValueNotifier<bool> _hasAnyRate;
 
  /// Bumped whenever the grid is rebuilt so text fields pick up new values.
  int version = 0;
 
  String source = 'ecb';
  bool loading = false;
  String? liveNote;
  String selectedSampleId = 'fx-arbitrage';
 
  @override
  void initState() {
    super.initState();
    _hasAnyRate = ValueNotifier(false);
    cells = _blankGrid(currencies.length);
    _refreshHasAnyRate();
  }

  @override
  void dispose() {
    _hasAnyRate.dispose();
    super.dispose();
  }

  void _refreshHasAnyRate() {
    final hasAnyRate = <bool>[
      for (var i = 0; i < cells.length; i++)
        for (var j = 0; j < cells[i].length; j++)
          i != j && cells[i][j].trim().isNotEmpty,
    ].any((filled) => filled);
    _hasAnyRate.value = hasAnyRate;
  }

  void _clearRates() {
    setState(() {
      for (var i = 0; i < cells.length; i++) {
        for (var j = 0; j < cells[i].length; j++) {
          if (i != j) {
            cells[i][j] = '';
          }
        }
      }
      version++;
      _refreshHasAnyRate();
    });
  }
 
  List<List<String>> _blankGrid(int n) => [
        for (var i = 0; i < n; i++)
          [for (var j = 0; j < n; j++) i == j ? '1' : ''],
      ];
 
  void _loadSample(_SampleData sample) {
    setState(() {
      currencies = [...sample.currencies];
      cells = sample.matrix;
      feePercent = 0;
      liveNote = null;
      version++;
      _refreshHasAnyRate();
    });
  }
 
  Future<void> _fetchLive() async {
    debugPrint('Fetching from: $apiBaseUrl/api/rates');
    setState(() => loading = true);
    try {
      final snap = await LiveRatesService.fetch(source: source);
      final t = snap.fetchedAt.toLocal();
      final hh = t.hour.toString().padLeft(2, '0');
      final mm = t.minute.toString().padLeft(2, '0');
      final ss = t.second.toString().padLeft(2, '0');
      setState(() {
        currencies = snap.currencies;
        cells = [
          for (final row in snap.matrix)
            [for (final v in row) v == 0 ? '' : v.toStringAsPrecision(8)],
        ];
        liveNote = '${snap.label} · $hh:$mm:$ss · ${snap.note}';
        version++;
        _refreshHasAnyRate();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not fetch rates: $e')),
      );
      print(e);
    } finally {
      if (mounted) setState(() => loading = false);
    }
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
      _refreshHasAnyRate();
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
      _refreshHasAnyRate();
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
          Text('Live rates', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ecb', label: Text('Frankfurt (ECB)')),
              ButtonSegment(value: 'okx', label: Text('Crypto (live OKX)')),
              ButtonSegment(value: 'finnhub', label: Text('Finnhub FX')),
            ],
            selected: {source},
            onSelectionChanged: (s) => setState(() => source = s.first),
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: loading ? null : _fetchLive,
            icon: loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.cloud_download_outlined),
            label: Text(loading ? 'Fetching…' : 'Fetch live rates'),
          ),
          if (liveNote != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(liveNote!,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant)),
            ),
          const SizedBox(height: 24),
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
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: ValueListenableBuilder<bool>(
              valueListenable: _hasAnyRate,
              builder: (context, hasAnyRate, _) {
                return OutlinedButton.icon(
                  onPressed: hasAnyRate ? _clearRates : null,
                  icon: const Icon(Icons.clear_all),
                  label: const Text('Clear rates'),
                );
              },
            ),
          ),
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
          Text('Sample data', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: selectedSampleId,
            decoration: const InputDecoration(
              labelText: 'Scenario',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final sample in _sampleData)
                DropdownMenuItem(
                  value: sample.id,
                  child: Text(sample.label),
                ),
            ],
            onChanged: (id) {
              if (id != null) setState(() => selectedSampleId = id);
            },
          ),
          const SizedBox(height: 6),
          Text(
            _sampleData
                .firstWhere((sample) => sample.id == selectedSampleId)
                .description,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _loadSample(
                    _sampleData.firstWhere(
                        (sample) => sample.id == selectedSampleId),
                  ),
                  icon: const Icon(Icons.science_outlined),
                  label: const Text('Load selected sample'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _detect,
                  icon: const Icon(Icons.radar, size: 22,),
                  label: const Text('Detect', style: TextStyle(fontSize: 16),),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
 
  Widget _buildMatrix(ThemeData theme) {
    const cellWidth = 105.0;
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
                          onChanged: (v) {
                            cells[i][j] = v;
                            _refreshHasAnyRate();
                          },
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
 