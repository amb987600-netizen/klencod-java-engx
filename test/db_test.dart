import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:engx/data/db.dart';
import 'package:engx/data/repo.dart';

Future<String> _device([String code = 'D-1']) =>
    Db.i.insert('devices', {'name': 'Monitor', 'asset_code': code, 'status': 'working', 'domain': 'medical'});

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    await Db.i.close();
    await databaseFactoryFfi.deleteDatabase(inMemoryDatabasePath);
    await Db.i.open(path: inMemoryDatabasePath);
    Db.i.role = 'owner';
  });

  test('ids are UUIDs and records carry workspace + creator', () async {
    final id = await _device();
    expect(id.length, 36);
    final d = (await Repo.device(id))!;
    expect(d['workspace_id'], Db.i.workspaceId);
    expect(d['created_by'], Db.i.userId);
    expect(d['deleted_at'], isNull);
  });

  test('asset code must be unique among live devices', () async {
    final id = await _device('X');
    expect(await Repo.assetCodeTaken('X'), isTrue);
    expect(await Repo.assetCodeTaken('X', exceptId: id), isFalse);
    await expectLater(_device('X'), throwsA(anything));
    await Db.i.softDelete('devices', id);
    expect(await Repo.assetCodeTaken('X'), isFalse);
  });

  test('closure flow: checklist -> request -> approve -> locked', () async {
    final dev = await _device();
    final o = await Repo.createOrder(deviceId: dev, type: 'fault');
    final items = await Repo.checklist(o);
    expect(items.length, 3);

    await expectLater(Repo.requestClosure(o), throwsA(predicate((e) => e.toString().contains('checklist_incomplete'))));

    for (final it in items) {
      await Repo.setChecked(it['id'] as String, true);
    }
    await Repo.requestClosure(o);
    expect((await Repo.order(o))!['status'], 'pending_approval');

    await Repo.approveClosure(o);
    final closed = (await Repo.order(o))!;
    expect(closed['status'], 'closed');
    expect(closed['approved_by'], Db.i.userId);

    await expectLater(Db.i.update('work_orders', o, {'cause': 'x'}), throwsA(isA<ClosedOrderException>()));
    await expectLater(Db.i.softDelete('work_orders', o), throwsA(isA<ClosedOrderException>()));
    await expectLater(Repo.setChecked(items.first['id'] as String, false), throwsA(isA<ClosedOrderException>()));
    // التصحيح بملاحظة بيشتغل
    await Repo.addNote('work_orders', o, 'correction');
    expect((await Repo.notes('work_orders', o)).length, 1);
  });

  test('technician cannot approve; viewer cannot write', () async {
    final dev = await _device();
    final o = await Repo.createOrder(deviceId: dev, type: 'fault');
    for (final it in await Repo.checklist(o)) {
      await Repo.setChecked(it['id'] as String, true);
    }
    await Repo.requestClosure(o);
    Db.i.role = 'technician';
    expect(() => Repo.approveClosure(o), throwsA(isA<PermissionException>()));
    Db.i.role = 'viewer';
    await expectLater(Db.i.insert('devices', {'name': 'n', 'asset_code': 'Z'}), throwsA(isA<PermissionException>()));
  });

  test('spare part usage adjusts stock and blocks over-use', () async {
    final dev = await _device();
    final o = await Repo.createOrder(deviceId: dev, type: 'fault');
    final part = await Db.i.insert('spare_parts', {'name': 'Fuse', 'quantity': 5, 'min_quantity': 2});
    await Repo.usePart(o, part, 3);
    expect((await Repo.parts()).first['quantity'], 2);
    await expectLater(Repo.usePart(o, part, 3), throwsA(predicate((e) => e.toString().contains('not_enough_stock'))));
    final usage = (await Repo.partsForOrder(o)).first;
    await Repo.removePartUsage(usage['id'] as String);
    expect((await Repo.parts()).first['quantity'], 5);
  });

  test('low stock appears in dashboard counts', () async {
    await Db.i.insert('spare_parts', {'name': 'A', 'quantity': 1, 'min_quantity': 2});
    await Db.i.insert('spare_parts', {'name': 'B', 'quantity': 9, 'min_quantity': 2});
    expect((await Repo.dashboardCounts())['parts'], 1);
  });

  test('preventive plan uses the interval the user entered', () async {
    final dev = await _device();
    final id = await Db.i.insert('pm_plans', {'device_id': dev, 'title': 'Check', 'period_days': 10, 'next_due': Repo.today()});
    expect((await Repo.pmDue()).length, 1);
    await Repo.markPmDone(id);
    final p = (await Repo.pmForDevice(dev)).first;
    expect(p['last_done'], Repo.today());
    expect(p['next_due'], Repo.plusDays(10));
    expect((await Repo.pmDue()).length, 0);
  });

  test('audit log records changes and cannot be altered', () async {
    final dev = await _device();
    await Db.i.update('devices', dev, {'location': 'ICU'});
    final logs = await Db.i.raw.query('audit_log', where: 'entity_id = ?', whereArgs: [dev]);
    expect(logs.map((e) => e['action']), containsAll(['create', 'update']));
    await expectLater(Db.i.raw.update('audit_log', {'action': 'x'}), throwsA(anything));
    await expectLater(Db.i.raw.delete('audit_log'), throwsA(anything));
    final q = await Db.i.raw.query('sync_queue');
    expect(q.length, greaterThanOrEqualTo(2));
  });
}
