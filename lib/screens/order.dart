import 'dart:async';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../core/app_state.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../data/repo.dart';
import '../widgets/common.dart';
import 'device_detail.dart';
import 'home.dart';

/// بيسأل عن نوع الأمر وبعدين يعمل أمر جديد ويفتحه.
Future<void> startNewOrder(BuildContext context, String deviceId) async {
  final type = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(tr('نوع الأمر', 'Order type'), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        for (final t in ['fault', 'preventive', 'calibration'])
          ListTile(
            leading: Icon(t == 'fault' ? Icons.build : (t == 'preventive' ? Icons.event_repeat : Icons.tune)),
            title: Text(orderTypeLabel(t)),
            onTap: () => Navigator.pop(ctx, t),
          ),
      ]),
    ),
  );
  if (type == null || !context.mounted) return;
  try {
    final id = await Repo.createOrder(deviceId: deviceId, type: type);
    if (context.mounted) push(context, OrderScreen(orderId: id));
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e));
  }
}

class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key, required this.orderId});
  final String orderId;
  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  int _step = 0;
  Rec? _o;
  Rec? _device;
  bool _loading = true;
  Timer? _debounce;

  final _desc = TextEditingController();
  final _reporter = TextEditingController();
  final _symptoms = TextEditingController();
  final _measure = TextEditingController();
  final _cause = TextEditingController();
  final _work = TextEditingController();
  final _tests = TextEditingController();
  String _priority = 'medium';

  String get _status => s(_o?['status']);
  bool get _readOnly => _status == 'closed' || _status == 'pending_approval' || !Db.i.canWrite;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final o = await Repo.order(widget.orderId);
    if (o == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    _o = o;
    _device = await Repo.device(s(o['device_id']));
    _desc.text = s(o['description']);
    _reporter.text = s(o['reported_by']);
    _symptoms.text = s(o['symptoms']);
    _measure.text = s(o['measurements']);
    _cause.text = s(o['cause']);
    _work.text = s(o['work_done']);
    _tests.text = s(o['test_results']);
    _priority = s(o['priority']).isEmpty ? 'medium' : s(o['priority']);
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _reloadOrder() async {
    _o = await Repo.order(widget.orderId);
    if (mounted) setState(() {});
  }

  void _changed() {
    if (_readOnly) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _save);
  }

  /// حفظ تلقائي كمسودة.
  Future<void> _save() async {
    if (_readOnly || _o == null) return;
    try {
      await Db.i.update('work_orders', widget.orderId, {
        'description': _desc.text.trim(),
        'reported_by': _reporter.text.trim(),
        'priority': _priority,
        'symptoms': _symptoms.text.trim(),
        'measurements': _measure.text.trim(),
        'cause': _cause.text.trim(),
        'work_done': _work.text.trim(),
        'test_results': _tests.text.trim(),
      });
      await _reloadOrder();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  Future<void> _go(int step) async {
    _debounce?.cancel();
    await _save();
    if (step > 0 && _status == 'draft' && _desc.text.trim().isNotEmpty && !_readOnly) {
      await Repo.setOrderStatus(widget.orderId, 'open');
      await _reloadOrder();
    }
    if (mounted) setState(() => _step = step);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final titles = [tr('البلاغ', 'Report'), tr('الفحص', 'Inspection'), tr('التنفيذ', 'Work'), tr('المراجعة', 'Review')];
    return PopScope(
      onPopInvokedWithResult: (didPop, result) => _save(),
      child: Scaffold(
        appBar: AppBar(
          title: Text('${orderTypeLabel(s(_o!['type']))} — ${s(_device?['name'])}'),
          actions: [Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Center(child: StatusChip(orderStatus(_status))))],
        ),
        body: Column(children: [
          if (_status == 'closed')
            Container(
              width: double.infinity,
              color: Brand.green.withOpacity(.15),
              padding: const EdgeInsets.all(10),
              child: Text(tr('الأمر ده مغلق ومينفعش يتعدل. للتصحيح ضيف ملاحظة في الآخر.', 'This order is closed and cannot be edited. Add a correction note at the bottom.')),
            ),
          if (_status == 'in_progress' && s(_o!['return_note']).isNotEmpty)
            Container(
              width: double.infinity,
              color: Brand.amber.withOpacity(.18),
              padding: const EdgeInsets.all(10),
              child: Text('${tr('اترجّع لك بملاحظة', 'Returned with note')}: ${s(_o!['return_note'])}'),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(children: [
              for (var k = 0; k < 4; k++)
                Expanded(
                  child: InkWell(
                    onTap: () => _go(k),
                    child: Column(children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: k <= _step ? Brand.teal : Colors.grey.shade400,
                        child: Text('${k + 1}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                      ),
                      const SizedBox(height: 4),
                      Text(titles[k], style: TextStyle(fontSize: 12, fontWeight: k == _step ? FontWeight.bold : FontWeight.normal)),
                    ]),
                  ),
                ),
            ]),
          ),
          Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [_stepBody()])),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(children: [
                if (_step > 0) Expanded(child: OutlinedButton(onPressed: () => _go(_step - 1), child: Text(tr('رجوع', 'Back')))),
                if (_step > 0 && _step < 3) const SizedBox(width: 12),
                if (_step < 3) Expanded(child: FilledButton(onPressed: () => _go(_step + 1), child: Text(tr('التالي', 'Next')))),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _tf(TextEditingController c, String label, {int lines = 1, bool patientWarning = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          maxLines: lines,
          readOnly: _readOnly,
          onChanged: (_) => _changed(),
          decoration: deco(label, helper: patientWarning ? noPatientDataHint : null),
        ),
      );

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _tf(_desc, tr('وصف البلاغ', 'Problem description'), lines: 4, patientWarning: true),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DropdownButtonFormField<String>(
              value: _priority,
              decoration: deco(tr('الأولوية', 'Priority')),
              items: [for (final p in ['low', 'medium', 'high']) DropdownMenuItem(value: p, child: Text(priorityLabel(p)))],
              onChanged: _readOnly ? null : (v) {
                setState(() => _priority = v ?? 'medium');
                _changed();
              },
            ),
          ),
          _tf(_reporter, tr('اللي بلّغ', 'Reported by')),
          const SectionTitle2(),
          _Attachments(orderId: widget.orderId, readOnly: _readOnly),
        ]);
      case 1:
        return Column(children: [
          _tf(_symptoms, tr('الأعراض', 'Symptoms'), lines: 3, patientWarning: true),
          _tf(_measure, tr('النتائج والقياسات (انت اللي بتدخلها)', 'Findings and measurements (you enter them)'), lines: 3, patientWarning: true),
          _tf(_cause, tr('سبب العطل', 'Root cause'), lines: 3, patientWarning: true),
        ]);
      case 2:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!_readOnly && (_status == 'draft' || _status == 'open'))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: Text(tr('ابدأ التنفيذ', 'Start work')),
                onPressed: () async {
                  await _save();
                  await Repo.startWork(widget.orderId);
                  await _reloadOrder();
                },
              ),
            ),
          if (s(_o!['started_at']).isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text('${tr('بدأ', 'Started')}: ${fmtDateTime(s(_o!['started_at']))}')),
          _tf(_work, tr('الأعمال المنفذة', 'Work performed'), lines: 4, patientWarning: true),
          _PartsUsed(orderId: widget.orderId, readOnly: _readOnly),
          const SizedBox(height: 12),
          _tf(_tests, tr('نتائج الاختبار بعد الإصلاح', 'Post-repair test results'), lines: 3, patientWarning: true),
        ]);
      default:
        return _Review(orderId: widget.orderId, order: _o!, onChanged: _reloadOrder, save: _save);
    }
  }
}

class SectionTitle2 extends StatelessWidget {
  const SectionTitle2({super.key});
  @override
  Widget build(BuildContext context) => SectionTitle(tr('المرفقات', 'Attachments'));
}

class _Attachments extends StatelessWidget {
  const _Attachments({required this.orderId, required this.readOnly});
  final String orderId;
  final bool readOnly;
  @override
  Widget build(BuildContext context) {
    return DbBuilder<List<Rec>>(
      load: () => Repo.attachments(orderId: orderId),
      builder: (context, list) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (final a in list)
          ListTile(
            dense: true,
            leading: const Icon(Icons.attach_file),
            title: Text(s(a['name'])),
            subtitle: Text(docKindLabel(s(a['kind']))),
            onTap: () => OpenFilex.open(s(a['path'])),
          ),
        if (!readOnly)
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: Text(tr('إضافة مرفق', 'Add attachment')),
            onPressed: () => addAttachment(context, orderId: orderId),
          ),
      ]),
    );
  }
}

class _PartsUsed extends StatelessWidget {
  const _PartsUsed({required this.orderId, required this.readOnly});
  final String orderId;
  final bool readOnly;

  Future<void> _add(BuildContext context) async {
    final parts = await Repo.parts();
    if (!context.mounted) return;
    if (parts.isEmpty) {
      toast(context, tr('المخزون فاضي. ضيف قطع من شاشة المخزون الأول.', 'Inventory is empty. Add parts from the Inventory screen first.'));
      return;
    }
    String? partId;
    final qty = TextEditingController(text: '1');
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(tr('قطعة غيار مستخدمة', 'Spare part used')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              isExpanded: true,
              value: partId,
              decoration: deco(tr('القطعة', 'Part')),
              items: [
                for (final p in parts)
                  DropdownMenuItem(value: s(p['id']), child: Text('${s(p['name'])} (${tr('متاح', 'stock')}: ${s(p['quantity'])})', overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setS(() => partId = v),
            ),
            const SizedBox(height: 10),
            TextField(controller: qty, keyboardType: TextInputType.number, decoration: deco(tr('الكمية', 'Quantity'))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: () async {
                if (partId == null) return;
                try {
                  await Repo.usePart(orderId, partId!, int.tryParse(qty.text.trim()) ?? 0);
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) toast(ctx, friendlyError(e));
                }
              },
              child: Text(tr('إضافة', 'Add')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DbBuilder<List<Rec>>(
      load: () => Repo.partsForOrder(orderId),
      builder: (context, list) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(tr('قطع الغيار المستخدمة', 'Spare parts used'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        for (final u in list)
          ListTile(
            dense: true,
            title: Text(s(u['part_name'])),
            subtitle: Text(s(u['part_number'])),
            leading: Text('× ${s(u['quantity'])}'),
            trailing: readOnly ? null : IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => Repo.removePartUsage(s(u['id']))),
          ),
        if (!readOnly)
          OutlinedButton.icon(icon: const Icon(Icons.add), label: Text(tr('إضافة قطعة من المخزون', 'Add part from inventory')), onPressed: () => _add(context)),
      ]),
    );
  }
}

class _Review extends StatelessWidget {
  const _Review({required this.orderId, required this.order, required this.onChanged, required this.save});
  final String orderId;
  final Rec order;
  final Future<void> Function() onChanged;
  final Future<void> Function() save;

  @override
  Widget build(BuildContext context) {
    final status = s(order['status']);
    final editable = (status != 'closed' && status != 'pending_approval') && Db.i.canWrite;
    return DbBuilder<List<Rec>>(
      load: () => Repo.checklist(orderId),
      builder: (context, items) {
        final allOk = items.isNotEmpty && items.every((e) => e['checked'] == 1);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(tr('قائمة التحقق قبل الإغلاق', 'Pre-closure checklist'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          Text(
            tr('التطبيق مبيفترضش إن الجهاز بقى آمن لمجرد تسجيل "تم الإصلاح". أكّد كل بند بنفسك.',
                'The app never assumes a device is safe just because it was marked repaired. Confirm every item yourself.'),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          for (final it in items)
            CheckboxListTile(
              value: it['checked'] == 1,
              title: Text(s(it['label'])),
              subtitle: it['checked'] == 1 ? Text('${tr('اتأكد', 'Confirmed')}: ${fmtDateTime(s(it['confirmed_at']))}') : null,
              onChanged: editable ? (v) => Repo.setChecked(s(it['id']), v ?? false) : null,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          if (editable)
            TextButton.icon(
              icon: const Icon(Icons.add),
              label: Text(tr('إضافة بند', 'Add item')),
              onPressed: () async {
                final t = await askText(context, tr('بند جديد', 'New item'), hint: tr('نص البند', 'Item text'));
                if (t != null && t.isNotEmpty) {
                  await Db.i.insert('closure_items', {'work_order_id': orderId, 'label': t, 'checked': 0, 'sort': items.length});
                }
              },
            ),
          const SizedBox(height: 12),
          if (editable)
            FilledButton.icon(
              icon: const Icon(Icons.send),
              label: Text(tr('طلب اعتماد الإغلاق', 'Request closure approval')),
              onPressed: allOk
                  ? () async {
                      try {
                        await save();
                        await Repo.requestClosure(orderId);
                        await onChanged();
                        if (context.mounted) {
                          toast(context, tr('الأمر في انتظار الاعتماد', 'Order is waiting for approval'));
                          if (Db.i.workspaceType == 'personal') {/* المالك يقدر يعتمد بنفسه */}
                        }
                      } catch (e) {
                        if (context.mounted) toast(context, friendlyError(e));
                      }
                    }
                  : null,
            ),
          if (editable && !allOk)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(tr('زر الإغلاق معطّل لحد ما كل البنود تتأكد.', 'Closure stays disabled until every item is confirmed.'),
                  style: const TextStyle(fontSize: 12, color: Brand.amber)),
            ),
          if (status == 'pending_approval') ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Brand.teal.withOpacity(.12), borderRadius: BorderRadius.circular(10)),
              child: Text(tr('في انتظار اعتماد المدير أو المالك.', 'Waiting for the Admin or Owner to approve.')),
            ),
            if (Db.i.canApprove) ...[
              const SizedBox(height: 10),
              FilledButton.icon(
                icon: const Icon(Icons.verified),
                label: Text(tr('اعتماد وإغلاق الأمر', 'Approve and close')),
                onPressed: () async {
                  if (!await confirm(context, tr('تعتمد الإغلاق؟ بعد كده الأمر مش هيتعدل.', 'Approve closure? The order cannot be edited afterwards.'))) return;
                  try {
                    await Repo.approveClosure(orderId);
                    await onChanged();
                  } catch (e) {
                    if (context.mounted) toast(context, friendlyError(e));
                  }
                },
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.undo),
                label: Text(tr('رجّعه للفني مع ملاحظة', 'Return to technician with a note')),
                onPressed: () async {
                  final t = await askText(context, tr('ملاحظة للفني', 'Note for technician'), maxLines: 3);
                  if (t == null || t.isEmpty) return;
                  try {
                    await Repo.returnToTech(orderId, t);
                    await onChanged();
                  } catch (e) {
                    if (context.mounted) toast(context, friendlyError(e));
                  }
                },
              ),
            ],
          ],
          if (status == 'closed')
            ListTile(
              leading: const Icon(Icons.verified, color: Brand.green),
              title: Text(tr('اتعتمد وأُغلق', 'Approved and closed')),
              subtitle: Text(fmtDateTime(s(order['approved_at']))),
            ),
          const Divider(height: 32),
          _NotesBlock2(orderId: orderId, closed: status == 'closed'),
          const SizedBox(height: 8),
          SyncBadge(order['sync_status']),
        ]);
      },
    );
  }
}

class _NotesBlock2 extends StatelessWidget {
  const _NotesBlock2({required this.orderId, required this.closed});
  final String orderId;
  final bool closed;
  @override
  Widget build(BuildContext context) {
    return DbBuilder<List<Rec>>(
      load: () => Repo.notes('work_orders', orderId),
      builder: (context, list) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(closed ? tr('ملاحظات التصحيح', 'Correction notes') : tr('الملاحظات', 'Notes'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        for (final n in list) ListTile(dense: true, title: Text(s(n['body'])), subtitle: Text(fmtDateTime(s(n['created_at'])))),
        if (Db.i.canWrite)
          TextButton.icon(
            icon: const Icon(Icons.add),
            label: Text(closed ? tr('إضافة ملاحظة تصحيح', 'Add correction note') : tr('إضافة ملاحظة', 'Add note')),
            onPressed: () async {
              final t = await askText(context, tr('ملاحظة', 'Note'), maxLines: 3, helper: noPatientDataHint);
              if (t != null && t.isNotEmpty) await Repo.addNote('work_orders', orderId, t);
            },
          ),
      ]),
    );
  }
}
