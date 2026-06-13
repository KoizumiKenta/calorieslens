import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../storage/app_database.dart';

/// The heart of offline-first: every local write appends a mutation here;
/// the SyncEngine drains FIFO when online. Server idempotency (client_uuid
/// on diary entries, Idempotency-Key elsewhere) makes retries safe.
class MutationQueue {
  MutationQueue(this._db);

  final AppDatabase _db;
  static const _uuid = Uuid();
  static const maxAttempts = 8;

  Future<void> enqueue({
    required String entity, // diary_entry | water | weight | exercise | favorite | template | profile
    required String op, // create | update | delete
    required Map<String, dynamic> payload,
  }) async {
    await _db.into(_db.mutations).insert(
          MutationsCompanion.insert(
            id: _uuid.v7(),
            entity: entity,
            op: op,
            payload: jsonEncode(payload),
            createdAt: DateTime.now().toUtc(),
          ),
        );
  }

  /// Pending mutations in commit order. Diary creates are batched by the
  /// SyncEngine into one POST /v1/diary/entries call (max 50 per batch).
  Future<List<Mutation>> pending({int limit = 100}) =>
      (_db.select(_db.mutations)
            ..where((m) => m.attempts.isSmallerThanValue(maxAttempts))
            ..orderBy([(m) => OrderingTerm.asc(m.createdAt)])
            ..limit(limit))
          .get();

  Future<void> markSynced(Iterable<String> ids) =>
      (_db.delete(_db.mutations)..where((m) => m.id.isIn(ids))).go();

  /// Transient failure: increment attempts; the SyncEngine applies
  /// exponential backoff per mutation. After [maxAttempts] the mutation
  /// surfaces in the "sync issues" sheet instead of retrying forever —
  /// data is never silently dropped.
  Future<void> markFailed(String id) async {
    await _db.customUpdate(
      'UPDATE mutations SET attempts = attempts + 1, last_attempt_at = ? WHERE id = ?',
      variables: [
        Variable(DateTime.now().toUtc().toIso8601String()),
        Variable(id),
      ],
      updates: {_db.mutations},
    );
  }

  Stream<int> watchPendingCount() {
    final count = _db.mutations.id.count();
    return (_db.selectOnly(_db.mutations)..addColumns([count]))
        .map((row) => row.read(count) ?? 0)
        .watchSingle();
  }
}
