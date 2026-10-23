import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_wearables_health_sdk_example/summaries/summary_api.dart';
import 'package:open_wearables_health_sdk_example/summaries/summary_page.dart';

class FakeApi extends SummaryApi {
  FakeApi(this.handler);
  final Future<Map<String, dynamic>?> Function(String, Map<String, String>)
  handler;
  final List<(String, Map<String, String>)> requests = [];

  @override
  Future<Map<String, dynamic>?> fetch(
    String section,
    Map<String, String> query,
  ) {
    requests.add((section, query));
    return handler(section, query);
  }
}

Map<String, dynamic> page(List<Map<String, dynamic>> rows, {String? cursor}) =>
    {
      'data': rows,
      'pagination': {'has_more': cursor != null, 'next_cursor': cursor},
    };

Future<void> mount(WidgetTester tester, SummaryApi api) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: SummaryPage(api: api, today: DateTime(2026, 10, 23)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('missing values stay missing and zero measurements stay zero', () {
    expect(total([null, null]), isNull);
    expect(average([null, 10, 20]), 15);
    expect(amount(0), '0');
    expect(amount(null), '—');
    expect(durationMinutes(450), '7h 30m');
    expect(dayKey(DateTime(2026, 1, 2)), '2026-01-02');
  });

  testWidgets('activity renders reported values and changes the date range', (
    tester,
  ) async {
    final api = FakeApi(
      (_, _) async => page([
        {'date': '2026-10-23', 'steps': 8432, 'distance_meters': 6240.5},
      ]),
    );
    await mount(tester, api);
    expect(find.text('8432'), findsOneWidget);
    expect(api.requests.single.$2['start_date'], '2026-10-17');
    expect(api.requests.single.$2['end_date'], '2026-10-23');
    await tester.tap(find.text('30 days'));
    await tester.pumpAndSettle();
    expect(api.requests.last.$2['start_date'], '2026-09-24');
    expect(tester.takeException(), isNull);
  });

  testWidgets('sleep renders stages and keeps missing measurements distinct', (
    tester,
  ) async {
    final api = FakeApi(
      (section, _) async => section == 'sleep'
          ? page([
              {
                'date': '2026-10-23',
                'duration_minutes': 450,
                'stages': {'deep_minutes': 70},
              },
            ])
          : page([]),
    );
    await mount(tester, api);
    await tester.tap(find.text('Sleep'));
    await tester.pumpAndSettle();
    expect(find.text('7h 30m'), findsWidgets);
    expect(find.text('1h 10m'), findsOneWidget);
    expect(find.text('Deep'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('vitals uses its own baseline without a date range', (
    tester,
  ) async {
    final api = FakeApi(
      (section, _) async => section == 'vitals'
          ? {
              'slow_changing': {'weight_kg': 72.5},
              'averaged': {'avg_hrv_sdnn_ms': 45.2},
            }
          : page([]),
    );
    await mount(tester, api);
    await tester.tap(find.text('Vitals'));
    await tester.pumpAndSettle();
    expect(api.requests.last.$2, isEmpty);
    expect(find.text('45.2'), findsOneWidget);
    expect(find.text('72.5'), findsOneWidget);
    expect(find.text('30 days'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pagination appends sessions and sends the returned cursor', (
    tester,
  ) async {
    final api = FakeApi(
      (section, query) async => section == 'workouts'
          ? page([
              {
                'name': query['cursor'] == null
                    ? 'Morning run'
                    : 'Evening walk',
              },
            ], cursor: query['cursor'] == null ? 'page-2' : null)
          : page([]),
    );
    await mount(tester, api);
    await tester.tap(find.text('Workouts'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Load more'), 200);
    await tester.tap(find.text('Load more'));
    await tester.pumpAndSettle();
    expect(api.requests.last.$2['cursor'], 'page-2');
    expect(find.text('2 loaded sessions'), findsOneWidget);
    expect(find.text('Evening walk'), findsOneWidget);
    expect(find.text('Load more'), findsNothing);
  });

  testWidgets('expired session has an actionable error', (tester) async {
    final api = FakeApi((_, _) async => throw PlatformException(code: '401'));
    await mount(tester, api);
    expect(find.textContaining('Your session expired'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a late response cannot overwrite the selected page', (
    tester,
  ) async {
    final slow = Completer<Map<String, dynamic>?>();
    final api = FakeApi(
      (section, _) =>
          section == 'activity' ? slow.future : Future.value(page([])),
    );
    await tester.pumpWidget(MaterialApp(home: SummaryPage(api: api)));
    await tester.pump();
    await tester.tap(find.text('Sleep'));
    await tester.pumpAndSettle();
    slow.complete(
      page([
        {'date': '2026-10-23', 'steps': 99999},
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('No sleep data yet'), findsOneWidget);
    expect(find.text('99999'), findsNothing);
  });
}
