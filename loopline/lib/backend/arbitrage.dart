class Arbitrage {
  
  final List<String> path;
 
  final double profitFactor;
 
  const Arbitrage(this.path, this.profitFactor);
 
  double get profitPercent => (profitFactor - 1) * 100;
 
  @override
  String toString() =>
      '${path.join(' -> ')}  (+${profitPercent.toStringAsFixed(4)}%)';

}