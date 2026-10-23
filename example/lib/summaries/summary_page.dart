import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'summary_api.dart';

const _accent = Color(0xFF818CF8);
const _surface = Color(0xFF18181B);
const _muted = Color(0xFFA1A1AA);
const _sections = {
  'activity': 'Activity',
  'sleep': 'Sleep',
  'workouts': 'Workouts',
  'vitals': 'Vitals',
};

class SummaryPage extends StatefulWidget {
  const SummaryPage({super.key, this.api = const SummaryApi(), this.today});

  final SummaryApi api;
  final DateTime? today;

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  String _section = 'activity';
  int _days = 7;
  late DateTime _end;
  Map<String, dynamic>? _response;
  List<Map<String, dynamic>> _rows = [];
  String? _cursor;
  String? _error;
  bool _loading = true;
  bool _loadingMore = false;
  int _generation = 0;

  DateTime get _today {
    final now = widget.today ?? DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime get _start => DateTime(_end.year, _end.month, _end.day - _days + 1);

  @override
  void initState() {
    super.initState();
    _end = _today;
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_loadingMore || _cursor == null)) return;
    final generation = ++_generation;
    final requestedCursor = more ? _cursor : null;
    setState(() {
      _error = null;
      _loadingMore = more;
      _loading = !more;
      if (!more) {
        _response = null;
        _rows = [];
        _cursor = null;
      }
    });
    try {
      final response = await widget.api.fetch(
        _section,
        _section == 'vitals'
            ? {}
            : {
                'start_date': dayKey(_start),
                'end_date': dayKey(_end),
                'limit': '100',
                if (requestedCursor != null) 'cursor': requestedCursor,
              },
      );
      if (!mounted || generation != _generation) return;
      final pagination = object(response?['pagination']);
      final next = pagination['next_cursor'] as String?;
      if (pagination['has_more'] == true &&
          (next == null || next == requestedCursor)) {
        throw const FormatException('Invalid summary pagination');
      }
      setState(() {
        _response = response;
        _rows = [..._rows, ...summaryRows(response)];
        _cursor = pagination['has_more'] == true ? next : null;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = error is PlatformException && error.code == '401'
            ? 'Your session expired. Return to sync and reconnect your account.'
            : 'Could not load your summary. Check your connection and try again.';
      });
    }
  }

  void _select(String section) {
    if (section == _section) return;
    setState(() => _section = section);
    _load();
  }

  void _shift(int direction) {
    final next = DateTime(_end.year, _end.month, _end.day + direction * _days);
    setState(() => _end = next.isAfter(_today) ? _today : next);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your health', style: TextStyle(fontSize: 24)),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              const Text(
                'A closer look at your synced health data.',
                style: TextStyle(color: _muted),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _sections.entries
                    .map(
                      (entry) => ChoiceChip(
                        label: Text(entry.value),
                        selected: _section == entry.key,
                        showCheckmark: false,
                        selectedColor: _accent.withValues(alpha: 0.25),
                        onSelected: (_) => _select(entry.key),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 20),
              if (_section != 'vitals') ...[
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 7, label: Text('7 days')),
                    ButtonSegment(value: 30, label: Text('30 days')),
                  ],
                  selected: {_days},
                  onSelectionChanged: (values) {
                    setState(() => _days = values.first);
                    _load();
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      tooltip: 'Previous period',
                      onPressed: () => _shift(-1),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Expanded(
                      child: Text(
                        '${dayKey(_start)} – ${dayKey(_end)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Next period',
                      onPressed: _end.isBefore(_today) ? () => _shift(1) : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                  ],
                ),
              ] else
                const Text(
                  'Latest measurements · 7-day baseline',
                  style: TextStyle(color: _muted),
                ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else ...[
                if (_error != null)
                  _panel(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_error!, style: const TextStyle(color: _muted)),
                        TextButton(
                          onPressed: () =>
                              _load(more: _rows.isNotEmpty && _cursor != null),
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                if (_error == null || _rows.isNotEmpty) ...[
                  if ((_section == 'vitals' && _response == null) ||
                      (_section != 'vitals' && _rows.isEmpty))
                    _empty()
                  else
                    ..._content(),
                ],
                if (_cursor != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: OutlinedButton(
                      onPressed: _loadingMore ? null : () => _load(more: true),
                      child: Text(_loadingMore ? 'Loading…' : 'Load more'),
                    ),
                  ),
              ],
              const SizedBox(height: 24),
              const Text(
                'Pull down to refresh. New uploads appear after the server finishes processing them. A dash means no measurement was reported.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty() => _panel(
    Column(
      children: [
        const Icon(Icons.insights_outlined, color: _accent, size: 36),
        const SizedBox(height: 12),
        Text(
          'No ${_sections[_section]!.toLowerCase()} data yet',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          _section == 'vitals'
              ? 'Measurements appear here when they are available in Apple Health and have synced.'
              : 'Try another period, or return to sync to upload your Apple Health data.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted),
        ),
      ],
    ),
  );

  List<Widget> _content() => switch (_section) {
    'activity' => _activity(),
    'sleep' => _sleep(),
    'workouts' => _workouts(),
    _ => _vitals(),
  };

  List<Widget> _activity() => [
    _metrics([
      (
        'Steps',
        amount(total(_rows.map((row) => row['steps']))),
        'reported total',
      ),
      (
        'Distance',
        amount(
          total(_rows.map((row) => row['distance_meters'])),
          decimals: 1,
          divisor: 1000,
        ),
        'km',
      ),
      (
        'Active energy',
        amount(total(_rows.map((row) => row['active_calories_kcal']))),
        'kcal',
      ),
      (
        'Heart rate',
        amount(
          average(_rows.map((row) => object(row['heart_rate'])['avg_bpm'])),
        ),
        'bpm · daily mean',
      ),
    ]),
    const SizedBox(height: 20),
    _heading('Daily movement'),
    ..._sortedRows().map(
      (row) => _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(
              row['date'].toString(),
              '${amount(row['steps'])} steps',
              bold: true,
            ),
            const SizedBox(height: 8),
            _row(
              'Distance',
              '${amount(row['distance_meters'], decimals: 2, divisor: 1000)} km',
            ),
            _row(
              'Active energy',
              '${amount(row['active_calories_kcal'])} kcal',
            ),
            _row('Total energy', '${amount(row['total_calories_kcal'])} kcal'),
            _row(
              'Average heart rate',
              '${amount(object(row['heart_rate'])['avg_bpm'])} bpm',
            ),
            _source(row),
          ],
        ),
      ),
    ),
  ];

  List<Widget> _sleep() => [
    _metrics([
      (
        'Average sleep',
        durationMinutes(average(_rows.map((row) => row['duration_minutes']))),
        'per recorded night',
      ),
      (
        'Sleep efficiency',
        amount(
          average(_rows.map((row) => row['efficiency_percent'])),
          decimals: 1,
        ),
        '% · reported nights',
      ),
    ]),
    const SizedBox(height: 20),
    _heading('Your nights'),
    ..._sortedRows().map((row) {
      final stages = object(row['stages']);
      return _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row(
              row['date'].toString(),
              durationMinutes(row['duration_minutes']),
              bold: true,
            ),
            const SizedBox(height: 12),
            _row('Deep', durationMinutes(stages['deep_minutes'])),
            _row('REM', durationMinutes(stages['rem_minutes'])),
            _row('Light', durationMinutes(stages['light_minutes'])),
            _row('Awake', durationMinutes(stages['awake_minutes'])),
            if (number(row['nap_duration_minutes']) != null)
              _row('Naps', durationMinutes(row['nap_duration_minutes'])),
            _row(
              'Overnight heart rate',
              '${amount(row['avg_heart_rate_bpm'])} bpm',
            ),
            _row(
              'Overnight HRV (SDNN)',
              '${amount(row['avg_hrv_sdnn_ms'], decimals: 1)} ms',
            ),
            _source(row),
          ],
        ),
      );
    }),
  ];

  List<Widget> _workouts() => [
    _heading('${_rows.length} loaded sessions'),
    ..._sortedRows(field: 'start_time').map(
      (row) => _panel(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (row['name'] ?? row['type'] ?? 'Workout').toString().replaceAll(
                '_',
                ' ',
              ),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              _workoutDate(row),
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _row(
              'Duration',
              durationMinutes(
                number(row['duration_seconds']) == null
                    ? null
                    : number(row['duration_seconds'])! / 60,
              ),
            ),
            _row(
              'Distance',
              '${amount(row['distance_meters'], decimals: 2, divisor: 1000)} km',
            ),
            _row('Energy', '${amount(row['calories_kcal'])} kcal'),
            _row(
              'Average heart rate',
              '${amount(row['avg_heart_rate_bpm'])} bpm',
            ),
            _row('Elevation gain', '${amount(row['elevation_gain_meters'])} m'),
            _source(row),
          ],
        ),
      ),
    ),
  ];

  List<Widget> _vitals() {
    final body = object(_response?['slow_changing']);
    final averaged = object(_response?['averaged']);
    return [
      _metrics([
        (
          'Resting heart rate',
          amount(averaged['resting_heart_rate_bpm']),
          'bpm · 7-day average',
        ),
        (
          'HRV · SDNN',
          amount(averaged['avg_hrv_sdnn_ms'], decimals: 1),
          'ms · 7-day average',
        ),
        (
          'HRV · RMSSD',
          amount(averaged['avg_hrv_rmssd_ms'], decimals: 1),
          'ms · 7-day average',
        ),
        (
          'Weight',
          amount(body['weight_kg'], decimals: 1),
          'kg · latest measurement',
        ),
      ]),
      const SizedBox(height: 16),
      _panel(
        Column(
          children: [
            _row('Height', '${amount(body['height_cm'], decimals: 1)} cm'),
            _row(
              'Body fat',
              '${amount(body['body_fat_percent'], decimals: 1)} %',
            ),
            _row(
              'Lean body mass',
              '${amount(body['muscle_mass_kg'], decimals: 1)} kg',
            ),
            _row('BMI', amount(body['bmi'], decimals: 1)),
          ],
        ),
      ),
      const SizedBox(height: 8),
      const Text(
        'SDNN and RMSSD are different HRV measurements and are shown separately. No recovery score is estimated.',
        style: TextStyle(color: _muted, fontSize: 12),
      ),
    ];
  }

  List<Map<String, dynamic>> _sortedRows({String field = 'date'}) => [..._rows]
    ..sort(
      (a, b) =>
          (b[field] ?? '').toString().compareTo((a[field] ?? '').toString()),
    );

  String _workoutDate(Map<String, dynamic> row) {
    final utc = DateTime.tryParse(row['start_time']?.toString() ?? '')?.toUtc();
    if (utc == null) return 'Time unavailable';
    final offset = row['zone_offset']?.toString();
    final match = RegExp(r'^([+-])(\d{2}):(\d{2})$').firstMatch(offset ?? '');
    final adjusted = match == null
        ? utc
        : utc.add(
            Duration(
              minutes:
                  (int.parse(match[2]!) * 60 + int.parse(match[3]!)) *
                  (match[1] == '-' ? -1 : 1),
            ),
          );
    return '${dayKey(adjusted)} · ${adjusted.hour.toString().padLeft(2, '0')}:${adjusted.minute.toString().padLeft(2, '0')} ${match == null ? 'UTC' : 'UTC$offset'}';
  }

  Widget _heading(String title) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      title,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
    ),
  );

  Widget _source(Map<String, dynamic> row) {
    final source = object(row['source']);
    final label =
        source['source'] ?? source['provider'] ?? 'Synced health data';
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        label.toString(),
        style: const TextStyle(color: _muted, fontSize: 11),
      ),
    );
  }

  Widget _metrics(List<(String, String, String)> values) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 600
          ? 4
          : constraints.maxWidth < 310
          ? 1
          : 2;
      final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: values
            .map(
              (metric) => SizedBox(
                width: width,
                child: _panel(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        metric.$1,
                        style: const TextStyle(color: _muted, fontSize: 12),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        metric.$2,
                        style: const TextStyle(
                          fontSize: 27,
                          fontWeight: FontWeight.w600,
                          color: _accent,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        metric.$3,
                        style: const TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                  margin: false,
                ),
              ),
            )
            .toList(),
      );
    },
  );

  Widget _panel(Widget child, {bool margin = true}) => Container(
    padding: const EdgeInsets.all(16),
    margin: margin ? const EdgeInsets.only(bottom: 12) : null,
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFF27272A)),
    ),
    child: child,
  );

  Widget _row(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: bold ? Colors.white : _muted,
              fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ],
    ),
  );
}
