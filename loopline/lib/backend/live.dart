import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:http/http.dart' as http;

/// Where the backend runs. Override at build time:
///   flutter run --dart-define=API_URL=http://192.168.1.10:8000
/// Defaults: iOS simulator shares the Mac's network (127.0.0.1); the Android
/// emulator sees the host machine as 10.0.2.2.
String get apiBaseUrl {
  const override = String.fromEnvironment('API_URL');
  if (override.isNotEmpty) return override;
  return defaultTargetPlatform == TargetPlatform.android
      ? 'http://10.0.2.2:8000'
      : 'http://127.0.0.1:8000';
}

class LiveSnapshot {
  final String label;
  final String note;
  final bool realtime;
  final DateTime fetchedAt;
  final List<String> currencies;
  final List<List<double>> matrix;

  const LiveSnapshot({
    required this.label,
    required this.note,
    required this.realtime,
    required this.fetchedAt,
    required this.currencies,
    required this.matrix,
  });
}

class LiveRatesService {
  static Future<LiveSnapshot> fetch({required String source}) async {
    final uri = Uri.parse('$apiBaseUrl/api/rates')
        .replace(queryParameters: {'source': source});
    final http.Response res;
    try {
      res = await http.get(uri).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw Exception(
          'Server at $apiBaseUrl accepted the request but did not answer in 20s '
          '($source feed is probably not delivering data). Check the server logs.');
    } on SocketException {
      throw Exception(
          'Cannot connect to $apiBaseUrl. Is the server running '
          '(curl $apiBaseUrl/health)?');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode != 200) {
      throw Exception(body['error'] ?? 'Server error ${res.statusCode}');
    }

    return LiveSnapshot(
      label: body['label'] as String,
      note: body['note'] as String,
      realtime: body['realtime'] as bool,
      fetchedAt: DateTime.parse(body['fetchedAt'] as String),
      currencies: (body['currencies'] as List).cast<String>(),
      matrix: [
        for (final row in body['matrix'] as List)
          [for (final v in row as List) (v as num).toDouble()],
      ],
    );
  }
}