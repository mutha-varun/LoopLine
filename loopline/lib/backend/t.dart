import 'dart:io';
Future<void> main() async {
  final sw = Stopwatch()..start();
  final c = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  final r = await (await c.getUrl(Uri.parse(
      'https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml'))).close();
  print('status ${r.statusCode} in ${sw.elapsedMilliseconds}ms');
  c.close();
}