import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// معرّف UUID عشوائي (مفيش أرقام تسلسلية عشان المزامنة).
String newId() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

String nowIso() => DateTime.now().toUtc().toIso8601String();

String dateStr(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String s(Object? v) => (v ?? '').toString();
int n(Object? v) => (v as num?)?.toInt() ?? 0;

/// أمر الصيانة المغلق مينفعش يتعدل.
class ClosedOrderException implements Exception {
  @override
  String toString() => 'closed_order';
}

class PermissionException implements Exception {
  final String msg;
  PermissionException(this.msg);
  @override
  String toString() => msg;
}

const _common =
    "id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL, created_by TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, deleted_at TEXT, sync_status TEXT NOT NULL DEFAULT 'pending'";

const _noLog = {'audit_log', 'sync_queue', 'meta'};

/// قاعدة البيانات المحلية — هي المصدر الأساسي للبيانات.
/// كل تغيير بيتسجل في AuditLog وفي طابور المزامنة (SyncQueue) في نفس العملية.
class Db {
  Db._();
  static final Db i = Db._();

  Database? _database;
  Database get raw => _database!;
  String path = '';

  late String workspaceId;
  late String userId;
  late String memberId;
  String workspaceType = 'personal';

  /// الدور الحالي: owner / admin / technician / viewer
  String role = 'owner';

  /// بيزيد مع كل كتابة، والشاشات بتسمعه وتحدّث نفسها.
  final ValueNotifier<int> version = ValueNotifier(0);

  bool get canApprove => role == 'owner' || role == 'admin';
  bool get canWrite => role != 'viewer';

  Future<void> open({String? path}) async {
    this.path = path ?? p.join(await getDatabasesPath(), 'engx.db');
    _database = await openDatabase(
      this.path,
      version: 1,
      onConfigure: (d) async => d.execute('PRAGMA foreign_keys = ON'),
      onCreate: _create,
    );
    await _bootstrap();
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<void> _create(Database db, int v) async {
    final stmts = <String>[
      'CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)',
      'CREATE TABLE workspaces ($_common, name TEXT NOT NULL, type TEXT NOT NULL, owner_id TEXT NOT NULL)',
      'CREATE TABLE members ($_common, user_id TEXT NOT NULL, user_name TEXT, email TEXT, role TEXT NOT NULL, status TEXT NOT NULL, joined_at TEXT)',
      'CREATE TABLE invitations ($_common, email_or_code TEXT, role TEXT NOT NULL, invited_by TEXT, expires_at TEXT, status TEXT NOT NULL)',
      '''CREATE TABLE devices ($_common, domain TEXT NOT NULL DEFAULT 'medical', name TEXT NOT NULL,
         manufacturer TEXT, model TEXT, serial TEXT, asset_code TEXT NOT NULL, location TEXT,
         status TEXT NOT NULL DEFAULT 'working', install_date TEXT, photo_path TEXT, notes TEXT)''',
      "CREATE UNIQUE INDEX idx_devices_asset ON devices(workspace_id, asset_code) WHERE deleted_at IS NULL",
      'CREATE INDEX idx_devices_name ON devices(workspace_id, name)',
      '''CREATE TABLE work_orders ($_common, domain TEXT NOT NULL DEFAULT 'medical',
         device_id TEXT NOT NULL REFERENCES devices(id), type TEXT NOT NULL, priority TEXT NOT NULL DEFAULT 'medium',
         status TEXT NOT NULL DEFAULT 'draft', description TEXT, reported_by TEXT, discovered_at TEXT,
         symptoms TEXT, measurements TEXT, cause TEXT, work_done TEXT, started_at TEXT, finished_at TEXT,
         assigned_to TEXT, test_results TEXT, closure_requested_by TEXT, closure_requested_at TEXT,
         approved_by TEXT, approved_at TEXT, return_note TEXT)''',
      'CREATE INDEX idx_wo_device ON work_orders(device_id)',
      'CREATE INDEX idx_wo_status ON work_orders(workspace_id, status)',
      '''CREATE TABLE closure_items ($_common, work_order_id TEXT NOT NULL REFERENCES work_orders(id),
         label TEXT NOT NULL, checked INTEGER NOT NULL DEFAULT 0, confirmed_by TEXT, confirmed_at TEXT, sort INTEGER NOT NULL DEFAULT 0)''',
      'CREATE INDEX idx_ci_wo ON closure_items(work_order_id)',
      '''CREATE TABLE pm_plans ($_common, device_id TEXT NOT NULL REFERENCES devices(id), title TEXT NOT NULL,
         period_days INTEGER, last_done TEXT, next_due TEXT, reference TEXT)''',
      'CREATE INDEX idx_pm_due ON pm_plans(workspace_id, next_due)',
      '''CREATE TABLE spare_parts ($_common, name TEXT NOT NULL, part_number TEXT, quantity INTEGER NOT NULL DEFAULT 0,
         min_quantity INTEGER NOT NULL DEFAULT 0, purchase_price REAL, supplier TEXT, location TEXT)''',
      '''CREATE TABLE part_usage ($_common, work_order_id TEXT NOT NULL REFERENCES work_orders(id),
         part_id TEXT NOT NULL REFERENCES spare_parts(id), quantity INTEGER NOT NULL)''',
      'CREATE INDEX idx_pu_wo ON part_usage(work_order_id)',
      '''CREATE TABLE attachments ($_common, device_id TEXT, work_order_id TEXT, kind TEXT NOT NULL,
         name TEXT NOT NULL, path TEXT NOT NULL)''',
      '''CREATE TABLE reminders ($_common, title TEXT NOT NULL, remind_at TEXT NOT NULL, device_id TEXT, work_order_id TEXT)''',
      '''CREATE TABLE notes ($_common, entity TEXT NOT NULL, entity_id TEXT NOT NULL, body TEXT NOT NULL)''',
      'CREATE INDEX idx_notes_entity ON notes(entity, entity_id)',
      '''CREATE TABLE audit_log (id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL, member_id TEXT, entity TEXT NOT NULL,
         entity_id TEXT NOT NULL, action TEXT NOT NULL, old_value TEXT, new_value TEXT, at TEXT NOT NULL)''',
      '''CREATE TRIGGER audit_no_update BEFORE UPDATE ON audit_log BEGIN SELECT RAISE(ABORT, 'audit log is append-only'); END''',
      '''CREATE TRIGGER audit_no_delete BEFORE DELETE ON audit_log BEGIN SELECT RAISE(ABORT, 'audit log is append-only'); END''',
      '''CREATE TABLE sync_queue (id TEXT PRIMARY KEY, workspace_id TEXT NOT NULL, entity TEXT NOT NULL, entity_id TEXT NOT NULL,
         op TEXT NOT NULL, payload TEXT, status TEXT NOT NULL DEFAULT 'pending', attempts INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL)''',
    ];
    for (final q in stmts) {
      await db.execute(q);
    }
  }

  Map<String, Object?> _base(String id, String now) => {
        'id': id,
        'workspace_id': _wsTmp ?? workspaceId,
        'created_by': _uidTmp ?? userId,
        'created_at': now,
        'updated_at': now,
        'sync_status': 'pending',
      };
  String? _wsTmp;
  String? _uidTmp;

  Future<String?> _meta(String k) async {
    final r = await raw.query('meta', where: 'key = ?', whereArgs: [k]);
    return r.isEmpty ? null : r.first['value'] as String?;
  }

  Future<void> _bootstrap() async {
    var ws = await _meta('workspace_id');
    if (ws == null) {
      ws = newId();
      final uid = newId();
      final mid = newId();
      final now = nowIso();
      _wsTmp = ws;
      _uidTmp = uid;
      await raw.transaction((t) async {
        await t.insert('workspaces', {..._base(ws!, now), 'name': 'My workspace', 'type': 'personal', 'owner_id': uid});
        await t.insert('members', {
          ..._base(mid, now),
          'user_id': uid,
          'user_name': '',
          'role': 'owner',
          'status': 'active',
          'joined_at': now,
        });
        await t.insert('meta', {'key': 'workspace_id', 'value': ws});
        await t.insert('meta', {'key': 'user_id', 'value': uid});
        await t.insert('meta', {'key': 'member_id', 'value': mid});
      });
      _wsTmp = null;
      _uidTmp = null;
    }
    workspaceId = ws;
    userId = (await _meta('user_id'))!;
    memberId = (await _meta('member_id'))!;
    final w = await raw.query('workspaces', where: 'id = ?', whereArgs: [ws]);
    workspaceType = w.isEmpty ? 'personal' : s(w.first['type']);
    final m = await raw.query('members', where: 'id = ?', whereArgs: [memberId]);
    role = m.isEmpty ? 'owner' : s(m.first['role']);
  }

  // ---------- عمليات عامة ----------

  Future<T> _run<T>(Transaction? txn, Future<T> Function(Transaction) f) async {
    if (txn != null) return f(txn);
    final r = await raw.transaction(f);
    version.value++;
    return r;
  }

  /// عملية متعددة الخطوات في معاملة واحدة (لو حاجة فشلت كله يتلغي).
  Future<T> tx<T>(Future<T> Function(Transaction) f) => _run(null, f);

  Future<void> _log(Transaction t, String table, String id, String action, Object? oldV, Object? newV) async {
    if (_noLog.contains(table)) return;
    final now = nowIso();
    await t.insert('audit_log', {
      'id': newId(),
      'workspace_id': workspaceId,
      'member_id': userId,
      'entity': table,
      'entity_id': id,
      'action': action,
      'old_value': oldV == null ? null : jsonEncode(oldV),
      'new_value': newV == null ? null : jsonEncode(newV),
      'at': now,
    });
    await t.insert('sync_queue', {
      'id': newId(),
      'workspace_id': workspaceId,
      'entity': table,
      'entity_id': id,
      'op': action,
      'payload': newV == null ? null : jsonEncode(newV),
      'status': 'pending',
      'attempts': 0,
      'created_at': now,
    });
  }

  Future<void> _assertOrderOpen(Transaction t, Object? orderId) async {
    if (orderId == null) return;
    final r = await t.query('work_orders', columns: ['status'], where: 'id = ?', whereArgs: [orderId]);
    if (r.isNotEmpty && r.first['status'] == 'closed') throw ClosedOrderException();
  }

  void _assertCanWrite() {
    if (!canWrite) throw PermissionException('read_only');
  }

  Future<String> insert(String table, Map<String, Object?> values, {Transaction? txn}) {
    _assertCanWrite();
    return _run(txn, (t) async {
      if (table == 'part_usage' || table == 'closure_items') {
        await _assertOrderOpen(t, values['work_order_id']);
      }
      final id = newId();
      final now = nowIso();
      await t.insert(table, {...values, ..._base(id, now)});
      await _log(t, table, id, 'create', null, values);
      return id;
    });
  }

  Future<void> update(String table, String id, Map<String, Object?> changes, {Transaction? txn}) {
    _assertCanWrite();
    return _run(txn, (t) async {
      final rows = await t.query(table, where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) throw StateError('not_found');
      final old = rows.first;
      if (table == 'work_orders' && old['status'] == 'closed') throw ClosedOrderException();
      if (table == 'closure_items' || table == 'part_usage') {
        await _assertOrderOpen(t, old['work_order_id']);
      }
      final oldDiff = <String, Object?>{};
      final newDiff = <String, Object?>{};
      changes.forEach((k, v) {
        if (old[k] != v) {
          oldDiff[k] = old[k];
          newDiff[k] = v;
        }
      });
      if (newDiff.isEmpty) return;
      await t.update(table, {...newDiff, 'updated_at': nowIso(), 'sync_status': 'pending'}, where: 'id = ?', whereArgs: [id]);
      await _log(t, table, id, 'update', oldDiff, newDiff);
    });
  }

  /// حذف ناعم: السجل بيفضل موجود بس مخفي.
  Future<void> softDelete(String table, String id, {Transaction? txn}) {
    _assertCanWrite();
    return _run(txn, (t) async {
      final rows = await t.query(table, where: 'id = ?', whereArgs: [id]);
      if (rows.isEmpty) return;
      final old = rows.first;
      if (table == 'work_orders' && old['status'] == 'closed') throw ClosedOrderException();
      if (table == 'closure_items' || table == 'part_usage') {
        await _assertOrderOpen(t, old['work_order_id']);
      }
      final now = nowIso();
      await t.update(table, {'deleted_at': now, 'updated_at': now, 'sync_status': 'pending'}, where: 'id = ?', whereArgs: [id]);
      await _log(t, table, id, 'delete', null, null);
    });
  }
}
