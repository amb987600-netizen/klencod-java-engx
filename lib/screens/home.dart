import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../data/repo.dart';
import '../widgets/common.dart';
import 'device_detail.dart';
import 'devices.dart';
import 'inventory.dart';
import 'order.dart';
import 'orders_list.dart';
import 'reports.dart';
import 'settings.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.onGoTo});
  final void Function(int) onGoTo;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.i,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(tr('أهلًا ${AppState.i.userName}', 'Hello ${AppState.i.userName}')),
          actions: [
            IconButton(
              tooltip: tr('بحث', 'Search'),
              icon: const Icon(Icons.search),
              onPressed: () => onGoTo(1),
            ),
            IconButton(
              tooltip: tr('التنبيهات', 'Alerts'),
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AlertsScreen())),
            ),
          ],
        ),
        body: DbBuilder<_HomeData>(
          load: () async => _HomeData(
            await Repo.dashboardCounts(),
            await Repo.pmDue(),
            await Repo.orders(filter: 'open'),
            await Repo.pendingSyncCount(),
          ),
          builder: (context, d) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            children: [
              _statusBar(d),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.7,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: [
                  _stat(context, tr('أوامر مفتوحة', 'Open orders'), d.counts['open']!, Brand.teal, Icons.assignment,
                      () => push(context, OrdersListScreen(title: tr('أوامر مفتوحة', 'Open orders'), filter: 'open'))),
                  _stat(context, tr('وقائية مستحقة', 'Preventive due'), d.counts['pm']!, Brand.amber, Icons.event_busy,
                      () => push(context, const PmDueScreen())),
                  _stat(context, tr('أجهزة محتاجة متابعة', 'Devices needing attention'), d.counts['devices']!, Brand.red,
                      Icons.warning_amber, () => push(context, const DevicesScreen(initialFilter: 'attention', standalone: true))),
                  _stat(context, tr('قطع مطلوبة', 'Parts to reorder'), d.counts['parts']!, Brand.amber, Icons.inventory_2,
                      () => push(context, const InventoryScreen(lowOnly: true))),
                ],
              ),
              SectionTitle(tr('مهام النهارده', "Today's tasks")),
              ..._tasks(context, d),
              SectionTitle(tr('الأقسام', 'Sections')),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                children: [
                  _tile(context, Icons.devices_other, tr('أجهزة', 'Devices'), () => onGoTo(1)),
                  _tile(context, Icons.build, tr('صيانة', 'Maintenance'),
                      () => push(context, OrdersListScreen(title: tr('الصيانة', 'Maintenance'), filter: 'all'))),
                  _tile(context, Icons.calendar_month, tr('تقويم', 'Calendar'), () => onGoTo(2)),
                  _tile(context, Icons.inventory_2, tr('مخزون', 'Inventory'), () => push(context, const InventoryScreen())),
                  _tile(context, Icons.bar_chart, tr('تقارير', 'Reports'), () => push(context, const ReportsScreen())),
                  _tile(context, Icons.settings, tr('إعدادات', 'Settings'), () => push(context, const SettingsScreen())),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusBar(_HomeData d) {
    final local = !AppState.i.syncEnabled;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Brand.teal.withOpacity(.12), borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Icon(local ? Icons.phone_android : Icons.cloud_sync, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            local
                ? tr('شغال على جهازك بدون إنترنت', 'Working on your device, offline')
                : tr('${d.pendingSync} عملية في انتظار المزامنة', '${d.pendingSync} changes waiting to sync'),
          ),
        ),
      ]),
    );
  }

  List<Widget> _tasks(BuildContext context, _HomeData d) {
    final w = <Widget>[];
    for (final p in d.pm) {
      final overdue = s(p['next_due']).compareTo(Repo.today()) < 0;
      w.add(Card(
        child: ListTile(
          leading: Icon(Icons.event_busy, color: Brand.amber),
          title: Text('${s(p['title'])} — ${s(p['device_name'])}'),
          subtitle: Text('${overdue ? tr('متأخرة', 'Overdue') : tr('النهارده', 'Today')} · ${fmtDate(s(p['next_due']))}'),
          onTap: () async {
            final dev = await Repo.device(s(p['device_id']));
            if (dev != null && context.mounted) push(context, DeviceDetailScreen(deviceId: s(dev['id'])));
          },
        ),
      ));
    }
    for (final o in d.orders.take(8)) {
      w.add(Card(
        child: ListTile(
          leading: const Icon(Icons.assignment, color: Brand.teal),
          title: Text('${orderTypeLabel(s(o['type']))} — ${s(o['device_name'])}'),
          subtitle: Text(s(o['description']).isEmpty ? orderStatus(s(o['status'])).label : s(o['description']),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          trailing: StatusChip(orderStatus(s(o['status']))),
          onTap: () => push(context, OrderScreen(orderId: s(o['id']))),
        ),
      ));
    }
    if (w.isEmpty) {
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(tr('مفيش مهام. دوس "أمر صيانة جديد" أو ضيف جهاز عشان تبدأ.',
                'No tasks. Tap "New work order" or add a device to begin.')),
          ),
        )
      ];
    }
    return w;
  }

  Widget _stat(BuildContext c, String label, int v, Color color, IconData icon, VoidCallback onTap) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Row(children: [
              Icon(icon, color: color, size: 20),
              const Spacer(),
              Text('$v', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
            ]),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
          ]),
        ),
      ),
    );
  }

  Widget _tile(BuildContext c, IconData icon, String label, VoidCallback onTap) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 30, color: Theme.of(c).colorScheme.primary),
          const SizedBox(height: 6),
          Text(label),
        ]),
      ),
    );
  }
}

class _HomeData {
  final Map<String, int> counts;
  final List<Rec> pm;
  final List<Rec> orders;
  final int pendingSync;
  _HomeData(this.counts, this.pm, this.orders, this.pendingSync);
}

Future<T?> push<T>(BuildContext c, Widget w) => Navigator.push<T>(c, MaterialPageRoute(builder: (_) => w));

/// التنبيهات: وقائية مستحقة + قطع تحت الحد الأدنى + أوامر في انتظار الاعتماد.
class AlertsScreen extends StatelessWidget {
  const AlertsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('التنبيهات', 'Alerts'))),
      body: DbBuilder<List<Widget>>(
        load: () async {
          final w = <Widget>[];
          for (final p in await Repo.pmDue()) {
            w.add(ListTile(
              leading: const Icon(Icons.event_busy, color: Brand.amber),
              title: Text(tr('صيانة وقائية مستحقة', 'Preventive maintenance due')),
              subtitle: Text('${s(p['title'])} — ${s(p['device_name'])}'),
            ));
          }
          for (final p in await Repo.parts(lowOnly: true)) {
            w.add(ListTile(
              leading: const Icon(Icons.inventory_2, color: Brand.amber),
              title: Text(tr('قطعة وصلت للحد الأدنى', 'Part at minimum level')),
              subtitle: Text('${s(p['name'])} — ${tr('المتاح', 'in stock')}: ${s(p['quantity'])}'),
            ));
          }
          if (Db.i.canApprove) {
            for (final o in await Repo.orders(filter: 'pending')) {
              w.add(ListTile(
                leading: const Icon(Icons.hourglass_top, color: Brand.teal),
                title: Text(tr('أمر في انتظار الاعتماد', 'Order waiting approval')),
                subtitle: Text(s(o['device_name'])),
                onTap: () => push(context, OrderScreen(orderId: s(o['id']))),
              ));
            }
          }
          return w;
        },
        builder: (c, w) => w.isEmpty
            ? EmptyState(icon: Icons.notifications_none, message: tr('مفيش تنبيهات دلوقتي', 'No alerts right now'))
            : ListView(children: w),
      ),
    );
  }
}
