import 'business_event.dart';
import 'money_movement.dart';

/// `GET /api/pending` — Phase 2 ③ (`fixtures/pending.json`).
class PendingDay {
  PendingDay({
    required this.date,
    required this.draftCount,
    required this.unmatchedCount,
  });

  final String date;
  final int draftCount;
  final int unmatchedCount;

  factory PendingDay.fromJson(Map<String, dynamic> j) => PendingDay(
    date: j['date'] as String,
    draftCount: (j['draftCount'] as num?)?.toInt() ?? 0,
    unmatchedCount: (j['unmatchedCount'] as num?)?.toInt() ?? 0,
  );
}

class Pending {
  Pending({
    required this.draftEvents,
    required this.unmatchedMovements,
    required this.byDate,
  });

  final List<BusinessEvent> draftEvents;
  final List<MoneyMovement> unmatchedMovements;
  final List<PendingDay> byDate; // cũ nhất trước

  bool get isEmpty => draftEvents.isEmpty && unmatchedMovements.isEmpty;

  factory Pending.fromJson(Map<String, dynamic> j) => Pending(
    draftEvents: ((j['draftEvents'] as List?) ?? const [])
        .map((e) => BusinessEvent.fromJson(e as Map<String, dynamic>))
        .toList(),
    unmatchedMovements: ((j['unmatchedMovements'] as List?) ?? const [])
        .map((m) => MoneyMovement.fromJson(m as Map<String, dynamic>))
        .toList(),
    byDate: ((j['byDate'] as List?) ?? const [])
        .map((d) => PendingDay.fromJson(d as Map<String, dynamic>))
        .toList(),
  );
}

/// `POST /api/zalo-users/{zaloId}/replay` (`fixtures/replay_result.json`).
class ReplayResult {
  ReplayResult({
    required this.zaloId,
    required this.replayed,
    required this.done,
    required this.failed,
    required this.skipped,
  });

  final String zaloId;
  final int replayed;
  final int done;
  final int failed;
  final int skipped;

  factory ReplayResult.fromJson(Map<String, dynamic> j) => ReplayResult(
    zaloId: j['zaloId'] as String? ?? '',
    replayed: (j['replayed'] as num?)?.toInt() ?? 0,
    done: (j['done'] as num?)?.toInt() ?? 0,
    failed: (j['failed'] as num?)?.toInt() ?? 0,
    skipped: (j['skipped'] as num?)?.toInt() ?? 0,
  );
}
