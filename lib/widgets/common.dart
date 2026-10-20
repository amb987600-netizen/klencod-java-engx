import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/app_state.dart';
import '../core/theme.dart';
import '../data/db.dart';

/// بيعرض بيانات من قاعدة البيانات وبيحدّث نفسه لوحده لما أي حاجة تتغير.
class DbBuilder<T> extends StatefulWidget {
  const DbBuilder({super.key, required this.load, required this.builder});
  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;

  @override
  State<DbBuilder<T>> createState() => _DbBuilderState<T>();
}

class _DbBuilderState<T> extends State<DbBuilder<T>> {
  T? _data;
  bool _loaded = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    Db.i.version.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    Db.i.version.removeListener(_reload);
    super.dispose();
  }

  @override
  void didUpdateWidget(DbBuilder<T> old) {
    super.didUpdateWidget(old);
    _reload();
  }

  Future<void> _reload() async {
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loaded = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && !_loaded) return Center(child: Text('$_error'));
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return widget.builder(context, _data as T);
  }
}

InputDecoration deco(String label, {String? helper, Widget? suffix}) => InputDecoration(
      labelText: label,
      helperText: helper,
      helperMaxLines: 2,
      border: const OutlineInputBorder(),
      suffixIcon: suffix,
    );

/// تحذير بيظهر تحت خانات النص الحر.
String get noPatientDataHint => tr('ممنوع كتابة بيانات مرضى هنا', 'Do not enter any patient data here');

void toast(BuildContext c, String m) =>
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

String fmtDate(String? v) {
  if (v == null || v.isEmpty) return '—';
  final d = DateTime.tryParse(v);
  if (d == null) return v;
  return DateFormat('yyyy/MM/dd').format(d.toLocal());
}

String fmtDateTime(String? v) {
  if (v == null || v.isEmpty) return '—';
  final d = DateTime.tryParse(v);
  if (d == null) return v;
  return DateFormat('yyyy/MM/dd  HH:mm').format(d.toLocal());
}

Future<String?> askText(BuildContext context, String title,
    {String initial = '', String? hint, int maxLines = 1, String? helper}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, maxLines: maxLines, decoration: deco(hint ?? '', helper: helper)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('إلغاء', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: Text(tr('حفظ', 'Save'))),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String message, {String? okLabel}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('لأ', 'No'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(okLabel ?? tr('أيوه', 'Yes'))),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> pickDate(BuildContext context, {String? initial}) async {
  final init = DateTime.tryParse(initial ?? '') ?? DateTime.now();
  final d = await showDatePicker(
    context: context,
    initialDate: init,
    firstDate: DateTime(2000),
    lastDate: DateTime(2100),
  );
  return d == null ? null : dateStr(d);
}

/// بيختار ملف وينسخه لمكان التطبيق الخاص.
Future<({String name, String path})?> pickAndStore({FileType type = FileType.any}) async {
  final res = await FilePicker.platform.pickFiles(type: type);
  if (res == null || res.files.isEmpty || res.files.single.path == null) return null;
  final f = res.files.single;
  final dir = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'engx_files'));
  await dir.create(recursive: true);
  final dest = p.join(dir.path, '${newId()}_${f.name}');
  await File(f.path!).copy(dest);
  return (name: f.name, path: dest);
}

// ---------- الحالات ----------

class StatusInfo {
  final String ar, en;
  final Color color;
  final IconData icon;
  const StatusInfo(this.ar, this.en, this.color, this.icon);
  String get label => tr(ar, en);
}

StatusInfo deviceStatus(String st) {
  switch (st) {
    case 'stopped':
      return const StatusInfo('متوقف', 'Stopped', Brand.red, Icons.cancel);
    case 'under_repair':
      return const StatusInfo('تحت الصيانة', 'Under repair', Brand.amber, Icons.build);
    default:
      return const StatusInfo('يعمل', 'Working', Brand.green, Icons.check_circle);
  }
}

StatusInfo orderStatus(String st) {
  switch (st) {
    case 'open':
      return const StatusInfo('مفتوح', 'Open', Brand.amber, Icons.folder_open);
    case 'in_progress':
      return const StatusInfo('قيد التنفيذ', 'In progress', Brand.amber, Icons.build);
    case 'pending_approval':
      return const StatusInfo('في انتظار الاعتماد', 'Waiting approval', Brand.teal, Icons.hourglass_top);
    case 'closed':
      return const StatusInfo('مغلق', 'Closed', Brand.green, Icons.lock);
    default:
      return const StatusInfo('مسودة', 'Draft', Colors.grey, Icons.edit_note);
  }
}

String priorityLabel(String p) {
  switch (p) {
    case 'high':
      return tr('عالية', 'High');
    case 'low':
      return tr('عادية', 'Low');
    default:
      return tr('متوسطة', 'Medium');
  }
}

Color priorityColor(String p) => p == 'high' ? Brand.red : (p == 'low' ? Colors.grey : Brand.amber);

String orderTypeLabel(String t) {
  switch (t) {
    case 'preventive':
      return tr('وقائية', 'Preventive');
    case 'calibration':
      return tr('معايرة', 'Calibration');
    default:
      return tr('عطل', 'Fault');
  }
}

String roleLabel(String r) {
  switch (r) {
    case 'admin':
      return tr('مدير', 'Admin');
    case 'technician':
      return tr('فني', 'Technician');
    case 'viewer':
      return tr('مشاهد', 'Viewer');
    default:
      return tr('مالك', 'Owner');
  }
}

/// الحالة بتتميز باللون والنص مع بعض مش باللون بس.
class StatusChip extends StatelessWidget {
  const StatusChip(this.info, {super.key});
  final StatusInfo info;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: info.color.withOpacity(.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: info.color.withOpacity(.6)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(info.icon, size: 14, color: info.color),
        const SizedBox(width: 4),
        Text(info.label, style: TextStyle(fontSize: 12, color: info.color, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

/// حالة المزامنة: محفوظ على الجهاز / في انتظار المزامنة / تمت المزامنة
class SyncBadge extends StatelessWidget {
  const SyncBadge(this.status, {super.key});
  final Object? status;

  @override
  Widget build(BuildContext context) {
    String t;
    IconData ic;
    if (status == 'synced') {
      t = tr('تمت المزامنة', 'Synced');
      ic = Icons.cloud_done;
    } else if (AppState.i.syncEnabled) {
      t = tr('في انتظار المزامنة', 'Waiting to sync');
      ic = Icons.cloud_upload;
    } else {
      t = tr('محفوظ على الجهاز', 'Saved on device');
      ic = Icons.phone_android;
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(ic, size: 13, color: Colors.grey),
      const SizedBox(width: 3),
      Text(t, style: const TextStyle(fontSize: 11, color: Colors.grey)),
    ]);
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 56, color: Colors.grey),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ]),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      );
}

/// رسالة خطأ مفهومة بدل نص تقني.
String friendlyError(Object e) {
  final m = e.toString();
  if (e is ClosedOrderException) {
    return tr('الأمر ده مغلق ومينفعش يتعدل. ضيف ملاحظة تصحيح بدل كده.', 'This order is closed and cannot be edited. Add a correction note instead.');
  }
  if (m.contains('checklist_incomplete')) return tr('لازم تأكد كل بنود قائمة التحقق الأول.', 'Confirm every checklist item first.');
  if (m.contains('not_enough_stock')) return tr('الكمية المطلوبة أكبر من المتاح في المخزون.', 'Requested quantity is more than the stock.');
  if (m.contains('self_approval')) return tr('مينفعش تعتمد أمر انت اللي طلبت إغلاقه في فريق.', 'You cannot approve your own closure request in a team.');
  if (m.contains('not_allowed') || m.contains('read_only')) return tr('مفيش صلاحية للإجراء ده.', 'You do not have permission for this action.');
  return tr('حصلت مشكلة: $m', 'Something went wrong: $m');
}
