import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../core/app_state.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../data/repo.dart';
import '../widgets/common.dart';
import 'devices.dart';
import 'home.dart';
import 'order.dart';

class DeviceDetailScreen extends StatelessWidget {
  const DeviceDetailScreen({super.key, required this.deviceId});
  final String deviceId;

  @override
  Widget build(BuildContext context) {
    return DbBuilder<Rec?>(
      load: () => Repo.device(deviceId),
      builder: (context, d) {
        if (d == null || d['deleted_at'] != null) {
          return Scaffold(appBar: AppBar(), body: EmptyState(icon: Icons.search_off, message: tr('الجهاز مش موجود', 'Device not found')));
        }
        return DefaultTabController(
          length: 5,
          child: Scaffold(
            appBar: AppBar(
              title: Text(s(d['name'])),
              actions: [
                if (Db.i.canWrite)
                  IconButton(
                    tooltip: tr('تعديل', 'Edit'),
                    icon: const Icon(Icons.edit),
                    onPressed: () => push(context, DeviceFormScreen(deviceId: deviceId)),
                  ),
                if (Db.i.canApprove)
                  IconButton(
                    tooltip: tr('حذف', 'Delete'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      if (await confirm(context, tr('تحذف الجهاز ده؟ السجل بيفضل محفوظ في التاريخ.', 'Delete this device? Its history is kept.'))) {
                        await Db.i.softDelete('devices', deviceId);
                        if (context.mounted) Navigator.pop(context);
                      }
                    },
                  ),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(96),
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: [
                      Expanded(
                        child: Text('${s(d['asset_code'])}${s(d['location']).isEmpty ? '' : ' · ${s(d['location'])}'}',
                            style: const TextStyle(color: Colors.white70)),
                      ),
                      StatusChip(deviceStatus(s(d['status']))),
                    ]),
                  ),
                  TabBar(
                    isScrollable: true,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white60,
                    indicatorColor: Brand.tealDark,
                    tabs: [
                      Tab(text: tr('نظرة عامة', 'Overview')),
                      Tab(text: tr('سجل الصيانة', 'History')),
                      Tab(text: tr('الوقائية', 'Preventive')),
                      Tab(text: tr('قطع الغيار', 'Parts')),
                      Tab(text: tr('المستندات', 'Documents')),
                    ],
                  ),
                ]),
              ),
            ),
            floatingActionButton: Db.i.canWrite
                ? FloatingActionButton.extended(
                    backgroundColor: Brand.teal,
                    foregroundColor: Colors.white,
                    icon: const Icon(Icons.add),
                    label: Text(tr('أمر صيانة جديد', 'New work order')),
                    onPressed: () => startNewOrder(context, deviceId),
                  )
                : null,
            body: TabBarView(children: [
              _Overview(d),
              _History(deviceId),
              _Preventive(deviceId),
              _Parts(deviceId),
              _Docs(deviceId),
            ]),
          ),
        );
      },
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview(this.d);
  final Rec d;
  Widget _row(String k, String v) => ListTile(dense: true, title: Text(k, style: const TextStyle(color: Colors.grey)), subtitle: Text(v.isEmpty ? '—' : v, style: const TextStyle(fontSize: 16)));

  @override
  Widget build(BuildContext context) {
    final photo = s(d['photo_path']);
    return ListView(padding: const EdgeInsets.only(bottom: 100), children: [
      if (photo.isNotEmpty && File(photo).existsSync())
        Padding(padding: const EdgeInsets.all(16), child: ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(File(photo), height: 180, fit: BoxFit.cover))),
      _row(tr('الشركة المصنعة', 'Manufacturer'), s(d['manufacturer'])),
      _row(tr('الموديل', 'Model'), s(d['model'])),
      _row(tr('الرقم التسلسلي', 'Serial'), s(d['serial'])),
      _row(tr('تاريخ التركيب', 'Install date'), fmtDate(d['install_date'] as String?)),
      _row(tr('ملاحظات', 'Notes'), s(d['notes'])),
      if (Db.i.canWrite)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: DropdownButtonFormField<String>(
            value: s(d['status']),
            decoration: deco(tr('تغيير حالة الجهاز', 'Change device status')),
            items: [for (final st in ['working', 'stopped', 'under_repair']) DropdownMenuItem(value: st, child: Text(deviceStatus(st).label))],
            onChanged: (v) {
              if (v != null) Db.i.update('devices', s(d['id']), {'status': v});
            },
          ),
        ),
      Padding(padding: const EdgeInsets.all(16), child: SyncBadge(d['sync_status'])),
      _NotesBlock(entity: 'devices', id: s(d['id'])),
    ]);
  }
}

/// ملاحظات الفريق: كل ملاحظة بتاريخها.
class _NotesBlock extends StatelessWidget {
  const _NotesBlock({required this.entity, required this.id});
  final String entity, id;
  @override
  Widget build(BuildContext context) {
    return DbBuilder<List<Rec>>(
      load: () => Repo.notes(entity, id),
      builder: (context, list) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Text(tr('الملاحظات', 'Notes'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            if (Db.i.canWrite)
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(tr('ملاحظة', 'Add note')),
                onPressed: () async {
                  final t = await askText(context, tr('ملاحظة جديدة', 'New note'), maxLines: 3, helper: noPatientDataHint);
                  if (t != null && t.isNotEmpty) await Repo.addNote(entity, id, t);
                },
              ),
          ]),
        ),
        for (final n in list)
          ListTile(dense: true, title: Text(s(n['body'])), subtitle: Text(fmtDateTime(s(n['created_at'])))),
      ]),
    );
  }
}

class _History extends StatelessWidget {
  const _History(this.deviceId);
  final String deviceId;
  @override
  Widget build(BuildContext context) {
    return DbBuilder<List<Rec>>(
      load: () => Repo.orders(deviceId: deviceId),
      builder: (context, list) => list.isEmpty
          ? EmptyState(icon: Icons.history, message: tr('مفيش أوامر صيانة للجهاز ده لسه', 'No work orders for this device yet'))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: list.length,
              itemBuilder: (_, k) => orderCard(context, list[k], showDevice: false),
            ),
    );
  }
}

Widget orderCard(BuildContext context, Rec o, {bool showDevice = true}) => Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        title: Text(showDevice ? '${orderTypeLabel(s(o['type']))} — ${s(o['device_name'])}' : orderTypeLabel(s(o['type']))),
        subtitle: Text('${fmtDate(s(o['created_at']))} · ${priorityLabel(s(o['priority']))}'
            '${s(o['description']).isEmpty ? '' : '\n${s(o['description'])}'}', maxLines: 3, overflow: TextOverflow.ellipsis),
        isThreeLine: s(o['description']).isNotEmpty,
        trailing: StatusChip(orderStatus(s(o['status']))),
        onTap: () => push(context, OrderScreen(orderId: s(o['id']))),
      ),
    );

class _Preventive extends StatelessWidget {
  const _Preventive(this.deviceId);
  final String deviceId;

  Future<void> _add(BuildContext context) async {
    final title = TextEditingController();
    final period = TextEditingController();
    final ref = TextEditingController();
    String? due;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(tr('خطة وقائية جديدة', 'New preventive plan')),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: title, decoration: deco(tr('اسم الإجراء', 'Task name'))),
              const SizedBox(height: 10),
              TextField(
                controller: period,
                keyboardType: TextInputType.number,
                decoration: deco(tr('الفترة (بالأيام)', 'Interval (days)'),
                    helper: tr('انت اللي بتحددها حسب دليل الشركة', 'You set it per the manufacturer manual')),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.event),
                label: Text('${tr('تاريخ الاستحقاق القادم', 'Next due date')}: ${due ?? '—'}'),
                onPressed: () async {
                  final d = await pickDate(ctx, initial: due);
                  if (d != null) setS(() => due = d);
                },
              ),
              const SizedBox(height: 10),
              TextField(controller: ref, decoration: deco(tr('مرجع الخطة (اسم الدليل أو الإجراء)', 'Reference (manual or procedure)'))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: () async {
                if (title.text.trim().isEmpty) return;
                await Db.i.insert('pm_plans', {
                  'device_id': deviceId,
                  'title': title.text.trim(),
                  'period_days': int.tryParse(period.text.trim()),
                  'next_due': due,
                  'reference': ref.text.trim(),
                });
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: Text(tr('حفظ', 'Save')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      DbBuilder<List<Rec>>(
        load: () => Repo.pmForDevice(deviceId),
        builder: (context, list) => list.isEmpty
            ? EmptyState(icon: Icons.event_repeat, message: tr('مفيش خطط وقائية. ضيف أول خطة.', 'No preventive plans. Add the first one.'))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 160),
                itemCount: list.length,
                itemBuilder: (_, k) {
                  final p = list[k];
                  final due = s(p['next_due']);
                  final late = due.isNotEmpty && due.compareTo(Repo.today()) <= 0;
                  return Card(
                    child: ListTile(
                      leading: Icon(Icons.event_repeat, color: late ? Brand.amber : null),
                      title: Text(s(p['title'])),
                      subtitle: Text(
                          '${tr('القادم', 'Next')}: ${due.isEmpty ? '—' : due}${late ? ' (${tr('مستحقة', 'due')})' : ''}\n'
                          '${tr('آخر تنفيذ', 'Last done')}: ${s(p['last_done']).isEmpty ? '—' : s(p['last_done'])}'
                          '${s(p['reference']).isEmpty ? '' : '\n${tr('المرجع', 'Ref')}: ${s(p['reference'])}'}'),
                      isThreeLine: true,
                      trailing: Db.i.canWrite
                          ? IconButton(
                              tooltip: tr('تم التنفيذ', 'Mark done'),
                              icon: const Icon(Icons.check_circle_outline),
                              onPressed: () async {
                                if (await confirm(context, tr('سجّل إن الوقائية دي اتنفذت النهارده؟', 'Record this preventive task as done today?'))) {
                                  await Repo.markPmDone(s(p['id']));
                                }
                              },
                            )
                          : null,
                    ),
                  );
                },
              ),
      ),
      if (Db.i.canWrite)
        Positioned(
          bottom: 80,
          left: 16,
          child: FloatingActionButton.small(
            heroTag: 'pm',
            tooltip: tr('خطة وقائية', 'Add plan'),
            onPressed: () => _add(context),
            child: const Icon(Icons.add),
          ),
        ),
    ]);
  }
}

class _Parts extends StatelessWidget {
  const _Parts(this.deviceId);
  final String deviceId;
  @override
  Widget build(BuildContext context) {
    return DbBuilder<List<Rec>>(
      load: () => Repo.partsForDevice(deviceId),
      builder: (context, list) => list.isEmpty
          ? EmptyState(icon: Icons.settings, message: tr('مفيش قطع غيار اتستخدمت على الجهاز ده', 'No spare parts used on this device'))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: list.length,
              itemBuilder: (_, k) => ListTile(
                title: Text(s(list[k]['part_name'])),
                subtitle: Text('${s(list[k]['part_number'])} · ${fmtDate(s(list[k]['order_date']))}'),
                trailing: Text('× ${s(list[k]['quantity'])}'),
              ),
            ),
    );
  }
}

const docKinds = ['manual', 'service', 'calibration', 'photo'];
String docKindLabel(String k) {
  switch (k) {
    case 'manual':
      return tr('دليل تشغيل', 'Operation manual');
    case 'service':
      return tr('دليل صيانة', 'Service manual');
    case 'calibration':
      return tr('تقرير معايرة', 'Calibration report');
    default:
      return tr('صورة', 'Photo');
  }
}

Future<void> addAttachment(BuildContext context, {String? deviceId, String? orderId}) async {
  String kind = 'manual';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        title: Text(tr('نوع الملف', 'File type')),
        content: DropdownButtonFormField<String>(
          value: kind,
          items: [for (final k in docKinds) DropdownMenuItem(value: k, child: Text(docKindLabel(k)))],
          onChanged: (v) => setS(() => kind = v ?? 'manual'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('إلغاء', 'Cancel'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('اختار ملف', 'Pick file'))),
        ],
      ),
    ),
  );
  if (ok != true) return;
  final f = await pickAndStore();
  if (f == null) return;
  await Db.i.insert('attachments', {'device_id': deviceId, 'work_order_id': orderId, 'kind': kind, 'name': f.name, 'path': f.path});
}

class _Docs extends StatelessWidget {
  const _Docs(this.deviceId);
  final String deviceId;
  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      DbBuilder<List<Rec>>(
        load: () => Repo.attachments(deviceId: deviceId),
        builder: (context, list) => list.isEmpty
            ? EmptyState(icon: Icons.folder_open, message: tr('مفيش مستندات. ضيف دليل التشغيل أو الصيانة.', 'No documents. Add the manual or service guide.'))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 160),
                itemCount: list.length,
                itemBuilder: (_, k) => ListTile(
                  leading: const Icon(Icons.insert_drive_file),
                  title: Text(s(list[k]['name'])),
                  subtitle: Text(docKindLabel(s(list[k]['kind']))),
                  onTap: () => OpenFilex.open(s(list[k]['path'])),
                  trailing: Db.i.canWrite
                      ? IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => Db.i.softDelete('attachments', s(list[k]['id'])))
                      : null,
                ),
              ),
      ),
      if (Db.i.canWrite)
        Positioned(
          bottom: 80,
          left: 16,
          child: FloatingActionButton.small(
            heroTag: 'doc',
            tooltip: tr('إضافة مستند', 'Add document'),
            onPressed: () => addAttachment(context, deviceId: deviceId),
            child: const Icon(Icons.attach_file),
          ),
        ),
    ]);
  }
}
