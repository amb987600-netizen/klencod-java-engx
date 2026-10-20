import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../data/repo.dart';
import '../widgets/common.dart';
import 'calendar.dart';
import 'devices.dart';
import 'home.dart';
import 'order.dart';

/// الإطار الأساسي: تنقل سفلي + زر "أمر صيانة جديد".
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _i = 0;

  void goTo(int i) => setState(() => _i = i);

  Future<void> newOrder() async {
    final devices = await Repo.devices();
    if (!mounted) return;
    if (devices.isEmpty) {
      toast(context, tr('ضيف جهاز الأول عشان تعمل أمر صيانة', 'Add a device first'));
      goTo(1);
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .7,
        builder: (ctx, sc) => Column(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(tr('اختار الجهاز', 'Choose the device'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: ListView.builder(
              controller: sc,
              itemCount: devices.length,
              itemBuilder: (_, k) => ListTile(
                title: Text(s(devices[k]['name'])),
                subtitle: Text(s(devices[k]['asset_code'])),
                onTap: () => Navigator.pop(ctx, s(devices[k]['id'])),
              ),
            ),
          ),
        ]),
      ),
    );
    if (picked == null || !mounted) return;
    await startNewOrder(context, picked);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(onGoTo: goTo),
      const DevicesScreen(),
      const CalendarScreen(),
      const AssistantScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _i, children: pages),
      floatingActionButton: Db.i.canWrite
          ? FloatingActionButton.extended(
              backgroundColor: Brand.teal,
              foregroundColor: Colors.white,
              onPressed: newOrder,
              icon: const Icon(Icons.add),
              label: Text(tr('أمر صيانة جديد', 'New work order')),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _i,
        onDestinationSelected: goTo,
        destinations: [
          NavigationDestination(icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: tr('الرئيسية', 'Home')),
          NavigationDestination(icon: const Icon(Icons.devices_other_outlined), selectedIcon: const Icon(Icons.devices_other), label: tr('الأجهزة', 'Devices')),
          NavigationDestination(icon: const Icon(Icons.calendar_month_outlined), selectedIcon: const Icon(Icons.calendar_month), label: tr('التقويم', 'Calendar')),
          NavigationDestination(icon: const Icon(Icons.smart_toy_outlined), selectedIcon: const Icon(Icons.smart_toy), label: tr('المساعد', 'Assistant')),
        ],
      ),
    );
  }
}

/// المساعد الذكي: مكانه محجوز دلوقتي وهيتنفذ في مرحلة لاحقة.
class AssistantScreen extends StatelessWidget {
  const AssistantScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('المساعد', 'Assistant'))),
      body: EmptyState(
        icon: Icons.smart_toy,
        message: tr(
            'المساعد الذكي جاي في مرحلة لاحقة. هيجاوب من المستندات اللي ترفعها وسجل الصيانة بس، ويكتب المصدر، ولو مش لاقي إجابة هيقول "مش لاقيها".',
            'The smart assistant is coming later. It will answer only from your uploaded documents and maintenance history, cite sources, and say "not found" when unsure.'),
      ),
    );
  }
}
