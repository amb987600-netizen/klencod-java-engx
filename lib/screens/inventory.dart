import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../data/repo.dart';
import '../widgets/common.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key, this.lowOnly = false});
  final bool lowOnly;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(lowOnly ? tr('قطع مطلوبة', 'Parts to reorder') : tr('المخزون', 'Inventory'))),
      floatingActionButton: Db.i.canWrite && !lowOnly
          ? FloatingActionButton.extended(
              backgroundColor: Brand.teal,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: Text(tr('إضافة قطعة', 'Add part')),
              onPressed: () => editPart(context),
            )
          : null,
      body: DbBuilder<List<Rec>>(
        load: () => Repo.parts(lowOnly: lowOnly),
        builder: (context, list) => list.isEmpty
            ? EmptyState(
                icon: Icons.inventory_2_outlined,
                message: lowOnly ? tr('مفيش قطع تحت الحد الأدنى', 'No parts below minimum') : tr('المخزون فاضي. ضيف أول قطعة غيار.', 'Inventory is empty. Add your first part.'))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                itemCount: list.length,
                itemBuilder: (_, k) => _PartCard(list[k]),
              ),
      ),
    );
  }
}

class _PartCard extends StatelessWidget {
  const _PartCard(this.p);
  final Rec p;
  @override
  Widget build(BuildContext context) {
    final q = n(p['quantity']);
    final min = n(p['min_quantity']);
    final low = q <= min;
    final ratio = min <= 0 ? (q > 0 ? 1.0 : 0.0) : (q / (min * 2)).clamp(0.0, 1.0);
    return Card(
      child: InkWell(
        onTap: Db.i.canWrite ? () => editPart(context, part: p) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(s(p['name']), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
              if (low) StatusChip(StatusInfo('تحت الحد الأدنى', 'Low stock', Brand.amber, Icons.warning_amber)),
            ]),
            if (s(p['part_number']).isNotEmpty) Text(s(p['part_number']), style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 8),
            LinearProgressIndicator(value: ratio, minHeight: 8, color: low ? Brand.amber : Brand.green, backgroundColor: Colors.grey.withOpacity(.25)),
            const SizedBox(height: 6),
            Row(children: [
              Text('${tr('المتاح', 'In stock')}: $q  ·  ${tr('الحد الأدنى', 'Min')}: $min'),
              const Spacer(),
              if (low && Db.i.canWrite)
                TextButton(
                  onPressed: () async {
                    await Db.i.insert('reminders', {
                      'title': '${tr('طلب توفير', 'Reorder')}: ${s(p['name'])}',
                      'remind_at': DateTime.now().toUtc().toIso8601String(),
                    });
                    if (context.mounted) toast(context, tr('اتضاف طلب التوفير في التقويم', 'Reorder request added to the calendar'));
                  },
                  child: Text(tr('طلب توفير', 'Request reorder')),
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

Future<void> editPart(BuildContext context, {Rec? part}) async {
  final name = TextEditingController(text: s(part?['name']));
  final num = TextEditingController(text: s(part?['part_number']));
  final qty = TextEditingController(text: part == null ? '0' : s(part['quantity']));
  final min = TextEditingController(text: part == null ? '0' : s(part['min_quantity']));
  final price = TextEditingController(text: part?['purchase_price'] == null ? '' : s(part!['purchase_price']));
  final sup = TextEditingController(text: s(part?['supplier']));
  final loc = TextEditingController(text: s(part?['location']));
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(part == null ? tr('قطعة جديدة', 'New part') : tr('تعديل قطعة', 'Edit part')),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final e in [
            (name, tr('الاسم', 'Name'), false),
            (num, tr('رقم القطعة', 'Part number'), false),
            (qty, tr('الكمية', 'Quantity'), true),
            (min, tr('الحد الأدنى', 'Minimum'), true),
            (price, tr('سعر الشراء (اختياري)', 'Purchase price (optional)'), true),
            (sup, tr('المورد', 'Supplier'), false),
            (loc, tr('مكان التخزين', 'Storage location'), false),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: TextField(controller: e.$1, keyboardType: e.$3 ? TextInputType.number : null, decoration: deco(e.$2)),
            ),
        ]),
      ),
      actions: [
        if (part != null && Db.i.canApprove)
          TextButton(
            onPressed: () async {
              await Db.i.softDelete('spare_parts', s(part['id']));
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(tr('حذف', 'Delete'), style: const TextStyle(color: Brand.red)),
          ),
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('إلغاء', 'Cancel'))),
        FilledButton(
          onPressed: () async {
            if (name.text.trim().isEmpty) return;
            final v = <String, Object?>{
              'name': name.text.trim(),
              'part_number': num.text.trim(),
              'quantity': int.tryParse(qty.text.trim()) ?? 0,
              'min_quantity': int.tryParse(min.text.trim()) ?? 0,
              'purchase_price': double.tryParse(price.text.trim()),
              'supplier': sup.text.trim(),
              'location': loc.text.trim(),
            };
            if (part == null) {
              await Db.i.insert('spare_parts', v);
            } else {
              await Db.i.update('spare_parts', s(part['id']), v);
            }
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: Text(tr('حفظ', 'Save')),
        ),
      ],
    ),
  );
}
