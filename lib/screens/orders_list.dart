import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../data/db.dart';
import '../data/repo.dart';
import '../widgets/common.dart';
import 'device_detail.dart';
import 'home.dart';

/// قائمة أوامر الصيانة مع فلتر.
class OrdersListScreen extends StatefulWidget {
  const OrdersListScreen({super.key, required this.title, this.filter = 'all'});
  final String title;
  final String filter;
  @override
  State<OrdersListScreen> createState() => _OrdersListScreenState();
}

class _OrdersListScreenState extends State<OrdersListScreen> {
  late String _f = widget.filter;

  @override
  Widget build(BuildContext context) {
    final filters = {
      'all': tr('الكل', 'All'),
      'open': tr('مفتوحة', 'Open'),
      'pending': tr('في انتظار الاعتماد', 'Waiting approval'),
      'closed': tr('مغلقة', 'Closed'),
    };
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
            for (final e in filters.entries)
              Padding(
                padding: const EdgeInsets.all(6),
                child: ChoiceChip(label: Text(e.value), selected: _f == e.key, onSelected: (_) => setState(() => _f = e.key)),
              ),
          ]),
        ),
        Expanded(
          child: DbBuilder<List<Rec>>(
            key: ValueKey(_f),
            load: () => Repo.orders(filter: _f),
            builder: (context, list) => list.isEmpty
                ? EmptyState(icon: Icons.assignment_outlined, message: tr('مفيش أوامر هنا', 'No orders here'))
                : ListView.builder(padding: const EdgeInsets.only(bottom: 40), itemCount: list.length, itemBuilder: (_, k) => orderCard(context, list[k])),
          ),
        ),
      ]),
    );
  }
}

/// الوقائية المستحقة.
class PmDueScreen extends StatelessWidget {
  const PmDueScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('وقائية مستحقة', 'Preventive due'))),
      body: DbBuilder<List<Rec>>(
        load: Repo.pmDue,
        builder: (context, list) => list.isEmpty
            ? EmptyState(icon: Icons.event_available, message: tr('مفيش وقائية مستحقة', 'No preventive tasks due'))
            : ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, k) => ListTile(
                  leading: const Icon(Icons.event_busy),
                  title: Text('${s(list[k]['title'])} — ${s(list[k]['device_name'])}'),
                  subtitle: Text('${tr('الاستحقاق', 'Due')}: ${s(list[k]['next_due'])}'),
                  onTap: () => push(context, DeviceDetailScreen(deviceId: s(list[k]['device_id']))),
                ),
              ),
      ),
    );
  }
}
