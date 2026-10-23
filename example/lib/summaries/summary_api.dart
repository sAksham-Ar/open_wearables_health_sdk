import 'dart:convert';

import 'package:open_wearables_health_sdk/open_wearables_health_sdk.dart';

class SummaryApi {
  const SummaryApi();

  Future<Map<String, dynamic>?> fetch(
    String section,
    Map<String, String> query,
  ) async {
    final result = jsonDecode(
      await OpenWearablesHealthSdk.fetchSummary(section: section, query: query),
    );
    if (result == null) return null;
    if (result is! Map<String, dynamic>) {
      throw const FormatException('Unexpected summary response');
    }
    return result;
  }
}

String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

double? number(dynamic value) =>
    value is num && value.isFinite ? value.toDouble() : null;

Map<String, dynamic> object(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : {};

List<Map<String, dynamic>> summaryRows(Map<String, dynamic>? response) =>
    (response?['data'] as List? ?? [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();

double? average(Iterable<dynamic> values) {
  final valid = values.map(number).whereType<double>().toList();
  return valid.isEmpty ? null : valid.reduce((a, b) => a + b) / valid.length;
}

double? total(Iterable<dynamic> values) {
  final valid = values.map(number).whereType<double>().toList();
  return valid.isEmpty ? null : valid.reduce((a, b) => a + b);
}

String amount(dynamic value, {int decimals = 0, double divisor = 1}) {
  final parsed = number(value);
  return parsed == null ? '—' : (parsed / divisor).toStringAsFixed(decimals);
}

String durationMinutes(dynamic value) {
  final minutes = number(value)?.round();
  if (minutes == null) return '—';
  return '${minutes ~/ 60}h ${(minutes % 60).toString().padLeft(2, '0')}m';
}
