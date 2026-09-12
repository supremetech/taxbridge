import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/business_event.dart';
import '../models/capture_result.dart';
import '../models/daily_record.dart';
import '../models/dashboard.dart';
import '../models/money_movement.dart';
import '../models/pending.dart';
import '../models/report.dart';
import '../models/session.dart';
import '../models/zalo_user.dart';
import 'api_client.dart';
import 'format.dart';
import 'taxbridge_api.dart';

/// Mock đọc `assets/fixtures/*.json` (copy từ contract), state in-memory tối thiểu.
/// Dashboard / report / pending tính từ events + movements theo ngày như backend
/// nên số khớp `dashboard.json` khi xem ngày 11/09 (fixture in ngày 11/09).
class FakeTaxBridgeApi implements TaxBridgeApi {
  final List<Map<String, dynamic>> _events = [];
  final List<Map<String, dynamic>> _movements = [];
  final List<Map<String, dynamic>> _records = [];
  bool _loaded = false;
  bool _historyDone = false; // đã nhận bank_history 1 lần → lần sau trùng hết
  int _seq = 0;

  Future<Map<String, dynamic>> _json(String name) async =>
      jsonDecode(await rootBundle.loadString('assets/fixtures/$name.json'))
          as Map<String, dynamic>;

  Future<List<Map<String, dynamic>>> _jsonList(String name) async =>
      (jsonDecode(
        await rootBundle.loadString('assets/fixtures/$name.json'),
      ) as List).cast<Map<String, dynamic>>();

  Future<void> _init() async {
    if (_loaded) return;
    _events.addAll(await _jsonList('events'));
    _movements.addAll(await _jsonList('money_movements'));
    _records.addAll(await _jsonList('daily_records'));
    _loaded = true;
  }

  Future<void> _delay() async {
    await _init();
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }

  String _now() => DateTime.now().toIso8601String();
  String _id(String p) => '${p}_mock_${++_seq}';

  /// Ngày nghiệp vụ của event / movement.
  String _dayOf(Map<String, dynamic> x) {
    final d = DateTime.tryParse(x['occurredAt'] as String? ?? '');
    return d == null ? todayKey() : dateKey(d.toLocal());
  }

  Map<String, dynamic> _findEvent(String id) => _events.firstWhere(
    (e) => e['eventId'] == id,
    orElse: () => throw ApiException(404, 'NOT_FOUND', 'Không tìm thấy'),
  );

  Map<String, dynamic> _findMovement(String id) => _movements.firstWhere(
    (m) => m['movementId'] == id,
    orElse: () => throw ApiException(404, 'NOT_FOUND', 'Không tìm thấy'),
  );

  // ---- auth ----

  @override
  Future<void> health() async {}

  @override
  Future<List<ZaloUser>> unlinkedZaloUsers() async {
    await _delay();
    return (await _jsonList('zalo_users_unlinked'))
        .map(ZaloUser.fromJson)
        .toList();
  }

  @override
  Future<AppSession> register(
    String username,
    String password,
    String? zaloId,
  ) async {
    await _delay();
    final j = await _json('session');
    return AppSession.fromJson({...j, 'username': username, 'zaloId': zaloId});
  }

  @override
  Future<AppSession> login(String username, String password) async {
    await _delay();
    final j = await _json('session');
    return AppSession.fromJson({...j, 'username': username});
  }

  @override
  Future<void> logout() async {}

  // ---- capture ----

  CaptureResult _done(String type, Map<String, dynamic> x, String idKey) =>
      CaptureResult(
        captureId: _id('cap'),
        status: 'DONE',
        resultType: type,
        resultId: x[idKey] as String,
        occurredAt: DateTime.tryParse(x['occurredAt'] as String? ?? ''),
      );

  @override
  Future<CaptureResult> captureText(String text) async {
    await _delay();
    final e = {
      ...await _json('event'),
      'eventId': _id('ev'),
      'status': 'DRAFT',
      'occurredAt': _now(),
      'captureType': 'TEXT',
      'evidenceText': text,
      'evidenceUrl': null,
    };
    _events.insert(0, e);
    return _done('EVENT', e, 'eventId');
  }

  @override
  Future<CaptureResult> captureFile(String type, String path) async {
    await _delay();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final file = path.split('/').last;
    final hasDemo =
        file.startsWith('sale_voice') ||
        file.startsWith('receipt') ||
        file.startsWith('transfer_') ||
        file.startsWith('bank_history');
    final asset = hasDemo ? 'asset://demo/$file' : null;

    if (type == 'IMAGE_BANK_HISTORY') return _captureHistory(asset);

    if (type == 'IMAGE_TRANSFER') {
      final base = await _json(
        file.contains('deposit')
            ? 'money_movement_unmatched'
            : 'money_movement',
      );
      // Ảnh demo in ngày 11/09 → giữ occurredAt của fixture (Phase 2 ②).
      final m = {
        ...base,
        'movementId': _id('mov'),
        'status': 'UNMATCHED',
        'matchedEventId': null,
        'classificationType': null,
        'evidenceUrl': asset,
        'candidates': _candidatesFor((base['amount'] as num).toInt()),
      };
      _movements.insert(0, m);
      return _done('MONEY_MOVEMENT', m, 'movementId');
    }

    late Map<String, dynamic> e;
    if (type == 'IMAGE_RECEIPT') {
      // Phiếu bao bì 220k tiền mặt (ev_002 trong fixture) ở trạng thái DRAFT, ngày in 11/09.
      e = {
        ..._events.firstWhere((x) => x['eventId'] == 'ev_002'),
        'evidenceText': null,
        'confidence': 0.89,
      };
    } else {
      e = {
        ...await _json('event'),
        'captureType': 'AUDIO',
        'occurredAt': _now(),
        'evidenceText': 'Bán cho chị Lan 3 hộp collagen, tổng 450 nghìn, khách chuyển khoản.',
      };
    }
    e = {...e, 'eventId': _id('ev'), 'status': 'DRAFT', 'evidenceUrl': asset};
    _events.insert(0, e);
    return _done('EVENT', e, 'eventId');
  }

  /// Batch lịch sử CK (Phase 2 ①): lần đầu 3 movement mới + 2 dòng trùng; lần sau trùng hết.
  Future<CaptureResult> _captureHistory(String? asset) async {
    if (_historyDone) {
      return CaptureResult(
        captureId: _id('cap'),
        status: 'DONE',
        resultType: 'MONEY_MOVEMENT_BATCH',
        resultIds: const [],
        skippedCount: 5,
        occurredAt: DateTime.parse('2026-09-11T12:00:00+07:00'),
      );
    }
    _historyDone = true;
    const rows = [
      (
        'IN',
        1200000,
        'HUE 2 COLLAGEN',
        'NGUYEN THI HUE',
        '2026-09-10T12:00:00+07:00',
      ),
      ('IN', 250000, 'THAO 1HOP', 'LE THI THAO', '2026-09-11T12:00:00+07:00'),
      (
        'OUT',
        2000000,
        'TRA TIEN HANG',
        'CTY TNHH ABC',
        '2026-09-10T12:00:00+07:00',
      ),
    ];
    final ids = <String>[];
    for (final (dir, amount, memo, party, at) in rows) {
      final m = {
        'movementId': _id('mov'),
        'direction': dir,
        'amount': amount,
        'memo': memo,
        'counterparty': party,
        'occurredAt': at,
        'source': 'APP',
        'captureType': 'IMAGE_BANK_HISTORY',
        'evidenceText': null,
        'evidenceUrl': asset,
        'status': 'UNMATCHED',
        'matchedEventId': null,
        'classificationType': null,
        'candidates': dir == 'IN' ? _candidatesFor(amount) : [],
      };
      _movements.insert(0, m);
      ids.add(m['movementId'] as String);
    }
    return CaptureResult(
      captureId: _id('cap'),
      status: 'DONE',
      resultType: 'MONEY_MOVEMENT_BATCH',
      resultIds: ids,
      skippedCount: 2,
      occurredAt: DateTime.parse('2026-09-11T12:00:00+07:00'),
    );
  }

  /// Candidate = SALE CONFIRMED UNPAID cùng số tiền (mock đơn giản, tối đa 3).
  List<Map<String, dynamic>> _candidatesFor(int amount) => _events
      .where(
        (e) =>
            e['type'] == 'SALE' &&
            e['status'] == 'CONFIRMED' &&
            e['paymentStatus'] == 'UNPAID' &&
            e['amount'] == amount,
      )
      .take(3)
      .map(
        (e) => {
          'eventId': e['eventId'],
          'description': e['description'] ?? '',
          'amount': e['amount'],
          'score': 0.9,
        },
      )
      .toList();

  // ---- events ----

  @override
  Future<List<BusinessEvent>> events({String? status}) async {
    await _delay();
    return _events
        .where((e) => status == null || e['status'] == status)
        .map(BusinessEvent.fromJson)
        .toList();
  }

  @override
  Future<BusinessEvent> event(String id) async {
    await _delay();
    return BusinessEvent.fromJson(_findEvent(id));
  }

  @override
  Future<BusinessEvent> updateEvent(
    String id,
    Map<String, dynamic> patch,
  ) async {
    await _delay();
    final e = _findEvent(id);
    if (e['status'] != 'DRAFT') {
      throw ApiException(409, 'INVALID_STATE', 'Chỉ sửa được bản nháp');
    }
    e.addAll(patch);
    return BusinessEvent.fromJson(e);
  }

  @override
  Future<BusinessEvent> confirmEvent(String id) async {
    await _delay();
    final e = _findEvent(id);
    if (e['status'] != 'DRAFT') {
      throw ApiException(409, 'INVALID_STATE', 'Không phải bản nháp');
    }
    e['status'] = 'CONFIRMED';
    _syncRecords(id);
    return BusinessEvent.fromJson(e);
  }

  @override
  Future<BusinessEvent> rejectEvent(String id) async {
    await _delay();
    final e = _findEvent(id);
    if (e['status'] != 'DRAFT') {
      throw ApiException(409, 'INVALID_STATE', 'Không phải bản nháp');
    }
    e['status'] = 'REJECTED';
    _syncRecords(id);
    return BusinessEvent.fromJson(e);
  }

  // ---- movements ----

  @override
  Future<List<MoneyMovement>> movements({String? status}) async {
    await _delay();
    return _movements
        .where((m) => status == null || m['status'] == status)
        .map(MoneyMovement.fromJson)
        .toList();
  }

  @override
  Future<MoneyMovement> movement(String id) async {
    await _delay();
    final m = _findMovement(id);
    if (m['status'] == 'UNMATCHED' && m['direction'] == 'IN') {
      m['candidates'] = _candidatesFor((m['amount'] as num).toInt());
    }
    return MoneyMovement.fromJson(m);
  }

  @override
  Future<MoneyMovement> matchMovement(String id, String eventId) async {
    await _delay();
    final m = _findMovement(id);
    if (m['status'] != 'UNMATCHED') {
      throw ApiException(409, 'INVALID_STATE', 'Khoản tiền đã xử lý');
    }
    m['status'] = 'MATCHED';
    m['matchedEventId'] = eventId;
    m['candidates'] = <Map<String, dynamic>>[];
    _findEvent(eventId)['paymentStatus'] = 'PAID';
    _syncRecords(id);
    return MoneyMovement.fromJson(m);
  }

  @override
  Future<MoneyMovement> classifyMovement(String id, String type) async {
    await _delay();
    final m = _findMovement(id);
    if (m['status'] != 'UNMATCHED') {
      throw ApiException(409, 'INVALID_STATE', 'Khoản tiền đã xử lý');
    }
    m['status'] = 'CLASSIFIED';
    m['classificationType'] = type;
    m['candidates'] = <Map<String, dynamic>>[];
    _syncRecords(id);
    return MoneyMovement.fromJson(m);
  }

  // ---- dashboard / close day ----

  Iterable<Map<String, dynamic>> _eventsIn(String from, String to) =>
      _events.where((e) {
        final d = _dayOf(e);
        return d.compareTo(from) >= 0 && d.compareTo(to) <= 0;
      });

  Iterable<Map<String, dynamic>> _movementsIn(String from, String to) =>
      _movements.where((m) {
        final d = _dayOf(m);
        return d.compareTo(from) >= 0 && d.compareTo(to) <= 0;
      });

  int _sum(Iterable<Map<String, dynamic>> xs) =>
      xs.fold(0, (a, x) => a + (x['amount'] as num).toInt());

  /// 4 số như backend, trong khoảng [from, to].
  Map<String, int> _summary(String from, String to) {
    final es = _eventsIn(from, to).toList();
    final revenue = _sum(
      es.where((e) => e['type'] == 'SALE' && e['status'] == 'CONFIRMED'),
    );
    final collected = _sum(
      es.where(
        (e) =>
            e['type'] == 'SALE' &&
            e['status'] == 'CONFIRMED' &&
            e['paymentStatus'] == 'PAID',
      ),
    );
    return {
      'revenue': revenue,
      'expense': _sum(
        es.where((e) => e['type'] == 'PURCHASE' && e['status'] == 'CONFIRMED'),
      ),
      'collected': collected,
      'receivable': revenue - collected,
    };
  }

  Map<String, int> _counts(String from, String to) {
    final es = _eventsIn(from, to).toList();
    final ms = _movementsIn(from, to).toList();
    return {
      'bankIn': _sum(ms.where((m) => m['direction'] == 'IN')),
      'saleCount': es
          .where((e) => e['type'] == 'SALE' && e['status'] == 'CONFIRMED')
          .length,
      'purchaseCount': es
          .where((e) => e['type'] == 'PURCHASE' && e['status'] == 'CONFIRMED')
          .length,
      'draftCount': es.where((e) => e['status'] == 'DRAFT').length,
      'unmatchedMoneyCount': ms.where((m) => m['status'] == 'UNMATCHED').length,
    };
  }

  @override
  Future<Dashboard> dashboard(String date) async {
    await _delay();
    final c = _counts(date, date);
    return Dashboard.fromJson({
      'date': date,
      ..._summary(date, date),
      'bankIn': c['bankIn'],
      'draftCount': c['draftCount'],
      'unmatchedMoneyCount': c['unmatchedMoneyCount'],
      'pastDraftCount': _events
          .where((e) => e['status'] == 'DRAFT' && _dayOf(e).compareTo(date) < 0)
          .length,
      'pastUnmatchedCount': _movements
          .where(
            (m) => m['status'] == 'UNMATCHED' && _dayOf(m).compareTo(date) < 0,
          )
          .length,
    });
  }

  @override
  Future<DailyRecord> closeDay(String date) async {
    await _delay();
    final old = _records.where((r) => r['date'] == date).firstOrNull;
    final rec = {
      'date': date,
      'summary': _summary(date, date),
      'warningCount': 0,
      'warnings': <Map<String, dynamic>>[],
      'closedAt': old?['closedAt'] ?? _now(),
      'updatedAt': _now(),
    };
    _records.removeWhere((r) => r['date'] == date);
    _records.add(rec);
    _records.sort(
      (a, b) => (b['date'] as String).compareTo(a['date'] as String),
    );
    _syncRecord(rec, keepResolvedFrom: old);
    return DailyRecord.fromJson(rec);
  }

  @override
  Future<List<DailyRecord>> dailyRecords() async {
    await _delay();
    return _records.map(DailyRecord.fromJson).toList();
  }

  @override
  Future<DailyRecord> dailyRecord(String date) async {
    await _delay();
    final r = _records.where((r) => r['date'] == date).firstOrNull;
    if (r == null) throw ApiException(404, 'NOT_FOUND', 'Chưa đóng ngày này');
    return DailyRecord.fromJson(r);
  }

  /// Như `sync_record(date)` backend: warning OPEN cho DRAFT/UNMATCHED trong ngày,
  /// warning hết lý do → RESOLVED, recompute summary. Chỉ với record đã đóng.
  void _syncRecord(
    Map<String, dynamic> r, {
    Map<String, dynamic>? keepResolvedFrom,
  }) {
    final date = r['date'] as String;
    final prev = ((keepResolvedFrom ?? r)['warnings'] as List? ?? const [])
        .cast<Map<String, dynamic>>();
    final open = <String, Map<String, dynamic>>{
      for (final m in _movementsIn(
        date,
        date,
      ).where((m) => m['status'] == 'UNMATCHED'))
        'UNMATCHED_MONEY:${m['movementId']}': {
          'warningId': 'UNMATCHED_MONEY:${m['movementId']}',
          'type': 'UNMATCHED_MONEY',
          'status': 'OPEN',
          'resourceType': 'MONEY_MOVEMENT',
          'resourceId': m['movementId'],
          'amount': m['amount'],
          'message':
              'Khoản tiền ${vnd((m['amount'] as num).toInt())} chưa được phân loại.',
          'resolvedAt': null,
        },
      for (final e in _eventsIn(
        date,
        date,
      ).where((e) => e['status'] == 'DRAFT'))
        'DRAFT_EVENT:${e['eventId']}': {
          'warningId': 'DRAFT_EVENT:${e['eventId']}',
          'type': 'DRAFT_EVENT',
          'status': 'OPEN',
          'resourceType': 'EVENT',
          'resourceId': e['eventId'],
          'amount': e['amount'],
          'message':
              'Giao dịch ${vnd((e['amount'] as num).toInt())} chưa được xác nhận.',
          'resolvedAt': null,
        },
    };
    final warnings = <Map<String, dynamic>>[];
    for (final w in prev) {
      final id = w['warningId'] as String;
      if (open.containsKey(id)) {
        warnings.add(open.remove(id)!);
      } else if (w['status'] == 'OPEN') {
        warnings.add({...w, 'status': 'RESOLVED', 'resolvedAt': _now()});
      } else {
        warnings.add(w);
      }
    }
    warnings.addAll(open.values);
    r['warnings'] = warnings;
    r['warningCount'] = warnings.where((w) => w['status'] == 'OPEN').length;
    r['summary'] = _summary(date, date);
    r['updatedAt'] = _now();
  }

  /// Sau mutation: sync record của ngày bản ghi (nếu đã đóng).
  void _syncRecords(String resourceId) {
    final x =
        _events.where((e) => e['eventId'] == resourceId).firstOrNull ??
        _movements.where((m) => m['movementId'] == resourceId).firstOrNull;
    if (x == null) return;
    final day = _dayOf(x);
    for (final r in _records.where((r) => r['date'] == day)) {
      _syncRecord(r);
    }
  }

  // ---- Phase 2 ----

  @override
  Future<Report> report(String from, String to) async {
    await _delay();
    final days = DateTime.parse(to).difference(DateTime.parse(from)).inDays + 1;
    final dates = <String>{
      ..._eventsIn(from, to).map(_dayOf),
      ..._movementsIn(from, to).map(_dayOf),
    }.toList()..sort((a, b) => b.compareTo(a));
    final byType = <String, Map<String, int>>{};
    for (final e in _eventsIn(
      from,
      to,
    ).where((e) => e['status'] == 'CONFIRMED')) {
      final t = byType.putIfAbsent(
        e['type'] as String,
        () => {'amount': 0, 'count': 0},
      );
      t['amount'] = t['amount']! + (e['amount'] as num).toInt();
      t['count'] = t['count']! + 1;
    }
    return Report.fromJson({
      'from': from,
      'to': to,
      'days': days,
      'summary': {..._summary(from, to), ..._counts(from, to)},
      'byDay': [
        for (final d in dates) {'date': d, ..._summary(d, d), ..._counts(d, d)},
      ],
      'byType': [
        for (final t in byType.entries)
          {
            'type': t.key,
            'amount': t.value['amount'],
            'count': t.value['count'],
          },
      ],
    });
  }

  @override
  Future<Pending> pending() async {
    await _delay();
    int asc(Map<String, dynamic> a, Map<String, dynamic> b) =>
        (a['occurredAt'] as String? ?? '').compareTo(
          b['occurredAt'] as String? ?? '',
        );
    final drafts = _events.where((e) => e['status'] == 'DRAFT').toList()
      ..sort(asc);
    final unmatched =
        _movements.where((m) => m['status'] == 'UNMATCHED').toList()..sort(asc);
    final dates = <String>{
      ...drafts.map(_dayOf),
      ...unmatched.map(_dayOf),
    }.toList()..sort();
    return Pending.fromJson({
      'draftEvents': drafts,
      'unmatchedMovements': unmatched,
      'byDate': [
        for (final d in dates)
          {
            'date': d,
            'draftCount': drafts.where((e) => _dayOf(e) == d).length,
            'unmatchedCount': unmatched.where((m) => _dayOf(m) == d).length,
          },
      ],
    });
  }

  @override
  Future<ReplayResult> replayZalo(String zaloId) async {
    await _delay();
    final r = await _json('replay_result');
    // Mô phỏng message cũ → nháp `source: ZALO` để badge Giao dịch tăng.
    final base = await _json('event');
    for (var i = 0; i < ((r['replayed'] as num?)?.toInt() ?? 0); i++) {
      _events.insert(0, {
        ...base,
        'eventId': _id('ev'),
        'status': 'DRAFT',
        'occurredAt': _now(),
        'source': 'ZALO',
        'captureType': 'TEXT',
        'evidenceText': 'bán 3 hộp collagen 450 nghìn chuyển khoản',
        'evidenceUrl': null,
      });
    }
    return ReplayResult.fromJson({...r, 'zaloId': zaloId});
  }
}
