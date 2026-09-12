import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/business_event.dart';
import '../models/capture_result.dart';
import '../models/daily_record.dart';
import '../models/dashboard.dart';
import '../models/money_movement.dart';
import '../models/session.dart';
import '../models/zalo_user.dart';
import 'api_client.dart';
import 'format.dart';
import 'taxbridge_api.dart';

/// Mock đọc `assets/fixtures/*.json` (copy từ contract), state in-memory tối thiểu.
/// Dashboard tính từ events + movements như backend nên số khớp `dashboard.json`.
class FakeTaxBridgeApi implements TaxBridgeApi {
  final List<Map<String, dynamic>> _events = [];
  final List<Map<String, dynamic>> _movements = [];
  final List<Map<String, dynamic>> _records = [];
  bool _loaded = false;
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
    return CaptureResult(
      captureId: _id('cap'),
      status: 'DONE',
      resultType: 'EVENT',
      resultId: e['eventId'] as String,
    );
  }

  @override
  Future<CaptureResult> captureFile(String type, String path) async {
    await _delay();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final file = path.split('/').last;
    final hasDemo =
        file.startsWith('sale_voice') ||
        file.startsWith('receipt') ||
        file.startsWith('transfer_');
    final asset = hasDemo ? 'asset://demo/$file' : null;

    if (type == 'IMAGE_TRANSFER') {
      final base = await _json(
        file.contains('deposit')
            ? 'money_movement_unmatched'
            : 'money_movement',
      );
      final m = {
        ...base,
        'movementId': _id('mov'),
        'occurredAt': _now(),
        'evidenceUrl': asset,
        'candidates': _candidatesFor((base['amount'] as num).toInt()),
      };
      _movements.insert(0, m);
      return CaptureResult(
        captureId: _id('cap'),
        status: 'DONE',
        resultType: 'MONEY_MOVEMENT',
        resultId: m['movementId'] as String,
      );
    }

    late Map<String, dynamic> e;
    if (type == 'IMAGE_RECEIPT') {
      // Phiếu bao bì 220k tiền mặt (ev_002 trong fixture) ở trạng thái DRAFT.
      e = {
        ..._events.firstWhere((x) => x['eventId'] == 'ev_002'),
        'status': 'DRAFT',
        'evidenceText': null,
        'confidence': 0.89,
      };
    } else {
      e = {
        ...await _json('event'),
        'captureType': 'AUDIO',
        'evidenceText': 'Bán cho chị Lan 3 hộp collagen, tổng 450 nghìn, khách chuyển khoản.',
      };
    }
    e = {
      ...e,
      'eventId': _id('ev'),
      'status': 'DRAFT',
      'occurredAt': _now(),
      'evidenceUrl': asset,
    };
    _events.insert(0, e);
    return CaptureResult(
      captureId: _id('cap'),
      status: 'DONE',
      resultType: 'EVENT',
      resultId: e['eventId'] as String,
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
    _resolveWarnings(id);
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
    _resolveWarnings(id);
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
    if (m['status'] == 'UNMATCHED') {
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
    _resolveWarnings(id);
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
    _resolveWarnings(id);
    return MoneyMovement.fromJson(m);
  }

  // ---- dashboard / close day ----

  Map<String, int> _summary() {
    int sum(bool Function(Map<String, dynamic>) f) =>
        _events.where(f).fold(0, (a, e) => a + (e['amount'] as num).toInt());
    final revenue = sum(
      (e) => e['type'] == 'SALE' && e['status'] == 'CONFIRMED',
    );
    final collected = sum(
      (e) =>
          e['type'] == 'SALE' &&
          e['status'] == 'CONFIRMED' &&
          e['paymentStatus'] == 'PAID',
    );
    return {
      'revenue': revenue,
      'expense': sum(
        (e) => e['type'] == 'PURCHASE' && e['status'] == 'CONFIRMED',
      ),
      'collected': collected,
      'receivable': revenue - collected,
    };
  }

  @override
  Future<Dashboard> dashboard(String date) async {
    await _delay();
    return Dashboard.fromJson({
      'date': date,
      ..._summary(),
      'bankIn': _movements
          .where((m) => m['direction'] == 'IN')
          .fold(0, (a, m) => a + (m['amount'] as num).toInt()),
      'draftCount': _events.where((e) => e['status'] == 'DRAFT').length,
      'unmatchedMoneyCount': _movements
          .where((m) => m['status'] == 'UNMATCHED')
          .length,
    });
  }

  @override
  Future<DailyRecord> closeDay(String date) async {
    await _delay();
    final old = _records.where((r) => r['date'] == date).firstOrNull;
    final resolved = ((old?['warnings'] as List?) ?? const [])
        .cast<Map<String, dynamic>>()
        .where((w) => w['status'] == 'RESOLVED')
        .toList();
    final open = <Map<String, dynamic>>[
      for (final m in _movements.where((m) => m['status'] == 'UNMATCHED'))
        {
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
      for (final e in _events.where((e) => e['status'] == 'DRAFT'))
        {
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
    ];
    final warnings = [...open, ...resolved];
    final rec = {
      'date': date,
      'summary': _summary(),
      'warningCount': open.length,
      'warnings': warnings,
      'closedAt': old?['closedAt'] ?? _now(),
      'updatedAt': _now(),
    };
    _records.removeWhere((r) => r['date'] == date);
    _records.add(rec);
    _records.sort(
      (a, b) => (b['date'] as String).compareTo(a['date'] as String),
    );
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

  /// Warning OPEN trỏ tới [resourceId] → RESOLVED; recompute summary record mới nhất.
  void _resolveWarnings(String resourceId) {
    for (final r in _records) {
      var touched = false;
      for (final w in (r['warnings'] as List).cast<Map<String, dynamic>>()) {
        if (w['resourceId'] == resourceId && w['status'] == 'OPEN') {
          w['status'] = 'RESOLVED';
          w['resolvedAt'] = _now();
          touched = true;
        }
      }
      if (touched) {
        r['warningCount'] = (r['warnings'] as List)
            .where((w) => (w as Map)['status'] == 'OPEN')
            .length;
        r['summary'] = _summary();
        r['updatedAt'] = _now();
      }
    }
  }
}
