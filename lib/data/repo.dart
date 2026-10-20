import 'package:sqflite/sqflite.dart';
import '../core/app_state.dart';
import 'db.dart';

typedef Rec = Map<String, Object?>;

/// كل الاستعلامات وقواعد الشغل (زي الإغلاق على مرحلتين) في مكان واحد.
class Repo {
  static Database get _d => Db.i.raw;
  static const openStatuses = "('draft','open','in_progress','pending_approval')";

  static String today() => dateStr(DateTime.now());
  static String plusDays(int days) => dateStr(DateTime.now().add(Duration(days: days)));

  static Future<int> _count(String sql, [List<Object?> a = const []]) async =>
      Sqflite.firstIntValue(await _d.rawQuery(sql, a)) ?? 0;

  // ---------- الأجهزة ----------

  static Future<List<Rec>> devices({String search = '', String filter = 'all'}) {
    final where = <String>['d.deleted_at IS NULL'];
    final args = <Object?>[];
    if (search.trim().isNotEmpty) {
      where.add('(d.name LIKE ? OR d.asset_code LIKE ? OR d.serial LIKE ?)');
      final q = '%${search.trim()}%';
      args.addAll([q, q, q]);
    }
    switch (filter) {
      case 'attention':
        where.add("d.status IN ('stopped','under_repair')");
        break;
      case 'needs':
        where.add("d.status = 'stopped'");
        break;
      case 'repair':
        where.add("d.status = 'under_repair'");
        break;
      case 'pm':
        where.add(
            "EXISTS (SELECT 1 FROM pm_plans p WHERE p.device_id = d.id AND p.deleted_at IS NULL AND p.next_due IS NOT NULL AND p.next_due <= ?)");
        args.add(plusDays(30));
        break;
    }
    return _d.rawQuery('SELECT d.* FROM devices d WHERE ${where.join(' AND ')} ORDER BY d.name COLLATE NOCASE', args);
  }

  static Future<Rec?> device(String id) async {
    final r = await _d.query('devices', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : r.first;
  }

  static Future<bool> assetCodeTaken(String code, {String? exceptId}) async {
    final r = await _d.query('devices',
        columns: ['id'],
        where: 'asset_code = ? AND deleted_at IS NULL AND workspace_id = ?',
        whereArgs: [code, Db.i.workspaceId]);
    return r.any((e) => e['id'] != exceptId);
  }

  // ---------- أوامر الصيانة ----------

  static Future<Rec?> order(String id) async {
    final r = await _d.query('work_orders', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : r.first;
  }

  /// filter: open / pending / closed / all
  static Future<List<Rec>> orders({String filter = 'all', String? deviceId}) {
    final where = <String>['w.deleted_at IS NULL'];
    final args = <Object?>[];
    if (deviceId != null) {
      where.add('w.device_id = ?');
      args.add(deviceId);
    }
    switch (filter) {
      case 'open':
        where.add("w.status IN $openStatuses");
        break;
      case 'pending':
        where.add("w.status = 'pending_approval'");
        break;
      case 'closed':
        where.add("w.status = 'closed'");
        break;
    }
    return _d.rawQuery(
        'SELECT w.*, d.name AS device_name, d.asset_code AS asset_code FROM work_orders w LEFT JOIN devices d ON d.id = w.device_id WHERE ${where.join(' AND ')} ORDER BY w.created_at DESC',
        args);
  }

  static Future<String> createOrder({required String deviceId, required String type}) {
    return Db.i.tx((t) async {
      final id = await Db.i.insert('work_orders', {
        'device_id': deviceId,
        'type': type,
        'priority': 'medium',
        'status': 'draft',
        'assigned_to': Db.i.userId,
        'domain': 'medical',
        'discovered_at': nowIso(),
      }, txn: t);
      final defaults = [
        tr('اختبار السلامة الكهربائية حسب إجراء المستشفى', 'Electrical safety test per hospital procedure'),
        tr('اختبار الأداء حسب دليل الشركة', 'Performance test per manufacturer manual'),
        tr('تسجيل القياسات بعد الإصلاح', 'Record post-repair measurements'),
      ];
      for (var k = 0; k < defaults.length; k++) {
        await Db.i.insert('closure_items', {'work_order_id': id, 'label': defaults[k], 'checked': 0, 'sort': k}, txn: t);
      }
      return id;
    });
  }

  static Future<void> setOrderStatus(String id, String status) => Db.i.update('work_orders', id, {'status': status});

  /// لما الفني يبدأ التنفيذ: الأمر "قيد التنفيذ" والجهاز (لو عطل) "تحت الصيانة".
  static Future<void> startWork(String orderId) {
    return Db.i.tx((t) async {
      final o = (await t.query('work_orders', where: 'id = ?', whereArgs: [orderId])).first;
      final changes = <String, Object?>{'status': 'in_progress'};
      if (o['started_at'] == null) changes['started_at'] = nowIso();
      await Db.i.update('work_orders', orderId, changes, txn: t);
      if (o['type'] == 'fault') {
        await Db.i.update('devices', s(o['device_id']), {'status': 'under_repair'}, txn: t);
      }
    });
  }

  static Future<List<Rec>> checklist(String orderId) => _d.query('closure_items',
      where: 'work_order_id = ? AND deleted_at IS NULL', whereArgs: [orderId], orderBy: 'sort, created_at');

  static Future<void> setChecked(String itemId, bool v) => Db.i.update('closure_items', itemId, {
        'checked': v ? 1 : 0,
        'confirmed_by': v ? Db.i.userId : null,
        'confirmed_at': v ? nowIso() : null,
      });

  /// الفني بيطلب الاعتماد: لازم كل بنود قائمة التحقق تكون متأكدة.
  static Future<void> requestClosure(String orderId) {
    return Db.i.tx((t) async {
      final items = await t.query('closure_items', where: 'work_order_id = ? AND deleted_at IS NULL', whereArgs: [orderId]);
      if (items.isEmpty || items.any((e) => e['checked'] != 1)) throw StateError('checklist_incomplete');
      final o = (await t.query('work_orders', where: 'id = ?', whereArgs: [orderId])).first;
      await Db.i.update('work_orders', orderId, {
        'status': 'pending_approval',
        'closure_requested_by': Db.i.userId,
        'closure_requested_at': nowIso(),
        'finished_at': o['finished_at'] ?? nowIso(),
      }, txn: t);
    });
  }

  /// الإغلاق النهائي: Owner أو Admin بس.
  static Future<void> approveClosure(String orderId) {
    if (!Db.i.canApprove) throw PermissionException('not_allowed');
    return Db.i.tx((t) async {
      final o = (await t.query('work_orders', where: 'id = ?', whereArgs: [orderId])).first;
      if (o['status'] != 'pending_approval') throw StateError('not_pending');
      if (o['closure_requested_by'] == Db.i.userId && Db.i.workspaceType != 'personal') {
        throw PermissionException('self_approval');
      }
      await Db.i.update('work_orders', orderId, {
        'status': 'closed',
        'approved_by': Db.i.userId,
        'approved_at': nowIso(),
      }, txn: t);
    });
  }

  static Future<void> returnToTech(String orderId, String note) {
    if (!Db.i.canApprove) throw PermissionException('not_allowed');
    return Db.i.tx((t) async {
      await Db.i.update('work_orders', orderId, {'status': 'in_progress', 'return_note': note}, txn: t);
      await Db.i.insert('notes', {'entity': 'work_orders', 'entity_id': orderId, 'body': note}, txn: t);
    });
  }

  /// أمر مغلق: التصحيح بيتم بإضافة ملاحظة جديدة بس.
  static Future<void> addNote(String entity, String id, String body) =>
      Db.i.insert('notes', {'entity': entity, 'entity_id': id, 'body': body});

  static Future<List<Rec>> notes(String entity, String id) => _d.query('notes',
      where: 'entity = ? AND entity_id = ? AND deleted_at IS NULL', whereArgs: [entity, id], orderBy: 'created_at DESC');

  // ---------- المخزون ----------

  static Future<List<Rec>> parts({bool lowOnly = false}) => _d.query('spare_parts',
      where: lowOnly ? 'deleted_at IS NULL AND quantity <= min_quantity' : 'deleted_at IS NULL',
      orderBy: 'name COLLATE NOCASE');

  static Future<List<Rec>> partsForOrder(String orderId) => _d.rawQuery(
      'SELECT u.*, s.name AS part_name, s.part_number AS part_number FROM part_usage u JOIN spare_parts s ON s.id = u.part_id WHERE u.work_order_id = ? AND u.deleted_at IS NULL ORDER BY u.created_at',
      [orderId]);

  static Future<List<Rec>> partsForDevice(String deviceId) => _d.rawQuery(
      'SELECT u.*, s.name AS part_name, s.part_number AS part_number, w.created_at AS order_date FROM part_usage u JOIN spare_parts s ON s.id = u.part_id JOIN work_orders w ON w.id = u.work_order_id WHERE w.device_id = ? AND u.deleted_at IS NULL ORDER BY u.created_at DESC',
      [deviceId]);

  /// استخدام قطعة: بتنقص من المخزون وبتتربط بالأمر في نفس الوقت.
  static Future<void> usePart(String orderId, String partId, int qty) {
    return Db.i.tx((t) async {
      final r = await t.query('spare_parts', where: 'id = ? AND deleted_at IS NULL', whereArgs: [partId]);
      if (r.isEmpty) throw StateError('part_not_found');
      final stock = n(r.first['quantity']);
      if (qty <= 0 || qty > stock) throw StateError('not_enough_stock');
      await Db.i.insert('part_usage', {'work_order_id': orderId, 'part_id': partId, 'quantity': qty}, txn: t);
      await Db.i.update('spare_parts', partId, {'quantity': stock - qty}, txn: t);
    });
  }

  static Future<void> removePartUsage(String usageId) {
    return Db.i.tx((t) async {
      final u = (await t.query('part_usage', where: 'id = ?', whereArgs: [usageId])).first;
      final part = (await t.query('spare_parts', where: 'id = ?', whereArgs: [u['part_id']])).first;
      await Db.i.softDelete('part_usage', usageId, txn: t);
      await Db.i.update('spare_parts', s(u['part_id']), {'quantity': n(part['quantity']) + n(u['quantity'])}, txn: t);
    });
  }

  // ---------- الوقائية والتقويم ----------

  static Future<List<Rec>> pmForDevice(String deviceId) => _d.query('pm_plans',
      where: 'device_id = ? AND deleted_at IS NULL', whereArgs: [deviceId], orderBy: 'next_due');

  static Future<List<Rec>> pmAll() => _d.rawQuery(
      'SELECT p.*, d.name AS device_name FROM pm_plans p JOIN devices d ON d.id = p.device_id WHERE p.deleted_at IS NULL AND d.deleted_at IS NULL AND p.next_due IS NOT NULL ORDER BY p.next_due');

  static Future<List<Rec>> pmDue() => _d.rawQuery(
      'SELECT p.*, d.name AS device_name FROM pm_plans p JOIN devices d ON d.id = p.device_id WHERE p.deleted_at IS NULL AND d.deleted_at IS NULL AND p.next_due IS NOT NULL AND p.next_due <= ? ORDER BY p.next_due',
      [today()]);

  /// تم تنفيذ الوقائية: آخر تنفيذ = النهاردة، والقادم = النهاردة + الفترة (اللي المستخدم دخلها).
  static Future<void> markPmDone(String planId) async {
    final r = await _d.query('pm_plans', where: 'id = ?', whereArgs: [planId]);
    if (r.isEmpty) return;
    final days = n(r.first['period_days']);
    await Db.i.update('pm_plans', planId, {
      'last_done': today(),
      if (days > 0) 'next_due': plusDays(days),
    });
  }

  static Future<List<Rec>> reminders() =>
      _d.query('reminders', where: 'deleted_at IS NULL', orderBy: 'remind_at');

  // ---------- المرفقات ----------

  static Future<List<Rec>> attachments({String? deviceId, String? orderId}) => _d.query('attachments',
      where: 'deleted_at IS NULL AND ${deviceId != null ? 'device_id = ?' : 'work_order_id = ?'}',
      whereArgs: [deviceId ?? orderId],
      orderBy: 'created_at DESC');

  // ---------- الرئيسية ----------

  static Future<Map<String, int>> dashboardCounts() async => {
        'open': await _count("SELECT COUNT(*) FROM work_orders WHERE deleted_at IS NULL AND status IN $openStatuses"),
        'pm': await _count(
            'SELECT COUNT(*) FROM pm_plans WHERE deleted_at IS NULL AND next_due IS NOT NULL AND next_due <= ?', [today()]),
        'devices':
            await _count("SELECT COUNT(*) FROM devices WHERE deleted_at IS NULL AND status IN ('stopped','under_repair')"),
        'parts': await _count('SELECT COUNT(*) FROM spare_parts WHERE deleted_at IS NULL AND quantity <= min_quantity'),
      };

  static Future<int> pendingSyncCount() => _count("SELECT COUNT(*) FROM sync_queue WHERE status = 'pending'");

  // ---------- التقارير ----------

  static Future<Map<String, Object>> reportData() async {
    final now = DateTime.now();
    final months = <String>[];
    for (var k = 5; k >= 0; k--) {
      final d = DateTime(now.year, now.month - k, 1);
      months.add('${d.year}-${d.month.toString().padLeft(2, '0')}');
    }
    final rows = await _d.rawQuery(
        "SELECT substr(created_at,1,7) AS m, COUNT(*) AS c FROM work_orders WHERE deleted_at IS NULL AND type = 'fault' GROUP BY m");
    final byMonth = {for (final r in rows) s(r['m']): n(r['c'])};
    final faults = [for (final m in months) MapEntry(m, byMonth[m] ?? 0)];

    final total = await _count('SELECT COUNT(*) FROM devices WHERE deleted_at IS NULL');
    final working = await _count("SELECT COUNT(*) FROM devices WHERE deleted_at IS NULL AND status = 'working'");
    final stopped = await _count("SELECT COUNT(*) FROM devices WHERE deleted_at IS NULL AND status = 'stopped'");
    final repair = await _count("SELECT COUNT(*) FROM devices WHERE deleted_at IS NULL AND status = 'under_repair'");

    final closed = await _d.rawQuery(
        "SELECT started_at, finished_at FROM work_orders WHERE deleted_at IS NULL AND status = 'closed' AND started_at IS NOT NULL AND finished_at IS NOT NULL");
    var hours = 0.0;
    var cnt = 0;
    for (final r in closed) {
      final a = DateTime.tryParse(s(r['started_at']));
      final b = DateTime.tryParse(s(r['finished_at']));
      if (a != null && b != null && !b.isBefore(a)) {
        hours += b.difference(a).inMinutes / 60.0;
        cnt++;
      }
    }
    final costRow = await _d.rawQuery(
        'SELECT COALESCE(SUM(u.quantity * COALESCE(s.purchase_price, 0)), 0) AS total FROM part_usage u JOIN spare_parts s ON s.id = u.part_id WHERE u.deleted_at IS NULL');
    final cost = (costRow.first['total'] as num?)?.toDouble() ?? 0.0;

    return {
      'faults': faults,
      'total': total,
      'working': working,
      'stopped': stopped,
      'repair': repair,
      'avgHours': cnt == 0 ? 0.0 : hours / cnt,
      'repairCount': cnt,
      'partsCost': cost,
    };
  }
}
