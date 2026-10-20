import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/app_state.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../data/repo.dart';
import '../widgets/common.dart';

class _Ev {
  final String date; // yyyy-MM-dd
  final String title;
  final String kind; // pm / reminder / order
  final String? id;
  _Ev(this.date, this.title, this.kind, [this.id]);
}

String _localDate(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : dateStr(d.toLocal());
}

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});
  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  String _mode = 'month';
  DateTime _day = DateTime.now();

  Future<List<_Ev>> _load() async {
    final ev = <_Ev>[];
    for (final p in await Repo.pmAll()) {
      ev.add(_Ev(s(p['next_due']), '${tr('وقائية', 'PM')}: ${s(p['title'])} — ${s(p['device_name'])}', 'pm'));
    }
    for (final r in await Repo.reminders()) {
      ev.add(_Ev(_localDate(s(r['remind_at'])), s(r['title']), 'reminder', s(r['id'])));
    }
    for (final o in await Repo.orders(filter: 'open')) {
      ev.add(_Ev(_localDate(s(o['created_at'])), '${orderTypeLabel(s(o['type']))}: ${s(o['device_name'])}', 'order'));
    }
    return ev;
  }

  Future<void> _addReminder() async {
    final t = TextEditingController();
    var when = DateTime(_day.year, _day.month, _day.day, 9);
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: Text(tr('تذكير جديد', 'New reminder')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: t, decoration: deco(tr('العنوان', 'Title'))),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.event),
              label: Text(DateFormat('yyyy/MM/dd  HH:mm').format(when)),
              onPressed: () async {
                final d = await showDatePicker(context: ctx, initialDate: when, firstDate: DateTime(2000), lastDate: DateTime(2100));
                if (d == null || !ctx.mounted) return;
                final tm = await showTimePicker(context: ctx, initialTime: TimeOfDay.fromDateTime(when));
                setS(() => when = DateTime(d.year, d.month, d.day, tm?.hour ?? when.hour, tm?.minute ?? when.minute));
              },
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(tr('إلغاء', 'Cancel'))),
            FilledButton(
              onPressed: () async {
                if (t.text.trim().isEmpty) return;
                await Db.i.insert('reminders', {'title': t.text.trim(), 'remind_at': when.toUtc().toIso8601String()});
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
    return Scaffold(
      appBar: AppBar(title: Text(tr('التقويم', 'Calendar'))),
      floatingActionButton: Db.i.canWrite
          ? Padding(
              padding: const EdgeInsets.only(bottom: 72),
              child: FloatingActionButton(heroTag: 'rem', tooltip: tr('تذكير', 'Reminder'), onPressed: _addReminder, child: const Icon(Icons.add_alarm)),
            )
          : null,
      body: DbBuilder<List<_Ev>>(
        load: _load,
        builder: (context, events) {
          List<_Ev> on(DateTime d) => events.where((e) => e.date == dateStr(d)).toList();
          return ListView(padding: const EdgeInsets.only(bottom: 160), children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'day', label: Text(tr('يوم', 'Day'))),
                  ButtonSegment(value: 'week', label: Text(tr('أسبوع', 'Week'))),
                  ButtonSegment(value: 'month', label: Text(tr('شهر', 'Month'))),
                ],
                selected: {_mode},
                onSelectionChanged: (v) => setState(() => _mode = v.first),
              ),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => setState(() => _day = _shift(-1))),
              Text(_mode == 'month' ? DateFormat('yyyy / MM').format(_day) : DateFormat('yyyy/MM/dd').format(_day),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => setState(() => _day = _shift(1))),
              TextButton(onPressed: () => setState(() => _day = DateTime.now()), child: Text(tr('النهارده', 'Today'))),
            ]),
            if (_mode == 'month') _monthGrid(events),
            if (_mode == 'week') ..._weekList(on),
            if (_mode != 'week') ..._dayList(on(_day)),
          ]);
        },
      ),
    );
  }

  DateTime _shift(int dir) {
    switch (_mode) {
      case 'month':
        return DateTime(_day.year, _day.month + dir, 1);
      case 'week':
        return _day.add(Duration(days: 7 * dir));
      default:
        return _day.add(Duration(days: dir));
    }
  }

  Widget _monthGrid(List<_Ev> events) {
    final first = DateTime(_day.year, _day.month, 1);
    final days = DateUtils.getDaysInMonth(_day.year, _day.month);
    final lead = first.weekday % 7; // الأحد = 0
    final names = [tr('أحد', 'Sun'), tr('اثنين', 'Mon'), tr('ثلاثاء', 'Tue'), tr('أربعاء', 'Wed'), tr('خميس', 'Thu'), tr('جمعة', 'Fri'), tr('سبت', 'Sat')];
    final cells = <Widget>[for (final x in names) Center(child: Text(x, style: const TextStyle(fontSize: 11, color: Colors.grey)))];
    for (var k = 0; k < lead; k++) {
      cells.add(const SizedBox());
    }
    for (var d = 1; d <= days; d++) {
      final date = DateTime(_day.year, _day.month, d);
      final has = events.any((e) => e.date == dateStr(date));
      final sel = DateUtils.isSameDay(date, _day);
      cells.add(InkWell(
        onTap: () => setState(() => _day = date),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: sel ? Brand.teal : null, borderRadius: BorderRadius.circular(8)),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('$d', style: TextStyle(color: sel ? Colors.white : null, fontWeight: DateUtils.isSameDay(date, DateTime.now()) ? FontWeight.bold : null)),
            Icon(Icons.circle, size: 6, color: has ? (sel ? Colors.white : Brand.amber) : Colors.transparent),
          ]),
        ),
      ));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: GridView.count(crossAxisCount: 7, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), childAspectRatio: 1.1, children: cells),
    );
  }

  List<Widget> _weekList(List<_Ev> Function(DateTime) on) {
    final start = _day.subtract(Duration(days: _day.weekday % 7));
    final out = <Widget>[];
    for (var k = 0; k < 7; k++) {
      final d = start.add(Duration(days: k));
      out.add(SectionTitle(DateFormat('EEEE yyyy/MM/dd', AppState.i.lang).format(d)));
      final ev = on(d);
      out.addAll(ev.isEmpty ? [Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('—', style: const TextStyle(color: Colors.grey)))] : _dayList(ev));
    }
    return out;
  }

  List<Widget> _dayList(List<_Ev> ev) {
    if (ev.isEmpty) {
      return [Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(tr('مفيش مواعيد في اليوم ده', 'Nothing scheduled this day'))))];
    }
    return [
      for (final e in ev)
        ListTile(
          leading: Icon(e.kind == 'pm' ? Icons.event_repeat : (e.kind == 'order' ? Icons.assignment : Icons.alarm), color: e.kind == 'pm' ? Brand.amber : Brand.teal),
          title: Text(e.title),
          trailing: e.kind == 'reminder' && Db.i.canWrite
              ? IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => Db.i.softDelete('reminders', e.id!))
              : null,
        ),
    ];
  }
}
