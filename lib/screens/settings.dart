import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../core/app_state.dart';
import '../data/db.dart';
import '../data/repo.dart';
import '../widgets/common.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final st = AppState.i;
    return ListenableBuilder(
      listenable: st,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: Text(tr('الإعدادات', 'Settings'))),
        body: ListView(children: [
          SectionTitle2x(tr('الشكل', 'Appearance')),
          ListTile(
            title: Text(tr('اللغة', 'Language')),
            trailing: SegmentedButton<String>(
              segments: const [ButtonSegment(value: 'ar', label: Text('عربي')), ButtonSegment(value: 'en', label: Text('EN'))],
              selected: {st.lang},
              onSelectionChanged: (v) => st.setLang(v.first),
            ),
          ),
          ListTile(
            title: Text(tr('الوضع', 'Mode')),
            trailing: SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.light, icon: const Icon(Icons.light_mode), label: Text(tr('فاتح', 'Light'))),
                ButtonSegment(value: ThemeMode.dark, icon: const Icon(Icons.dark_mode), label: Text(tr('داكن', 'Dark'))),
              ],
              selected: {st.themeMode == ThemeMode.dark ? ThemeMode.dark : ThemeMode.light},
              onSelectionChanged: (v) => st.setTheme(v.first),
            ),
          ),
          SectionTitle2x(tr('البيانات والمزامنة', 'Data and sync')),
          SwitchListTile(
            title: Text(tr('المزامنة السحابية', 'Cloud sync')),
            subtitle: Text(tr('مقفولة افتراضيًا. التطبيق بيشتغل محليًا بالكامل. لو سياسة المستشفى بتمنع رفع البيانات سيبها مقفولة.',
                'Off by default. The app works fully on your device. Keep it off if hospital policy forbids uploading data.')),
            value: st.syncEnabled,
            onChanged: (v) => st.setSync(v),
          ),
          if (st.syncEnabled)
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(tr('ربط الحساب السحابي لسه مش متفعّل في الإصدار ده', 'Cloud account link is not enabled in this build yet')),
              subtitle: Text(tr('التغييرات بتتجمّع في طابور وهتتبعت لما الربط يتفعّل.', 'Changes are queued and will be sent once the link is enabled.')),
            ),
          ListTile(
            leading: const Icon(Icons.sync),
            title: Text(tr('عمليات في انتظار المزامنة', 'Changes waiting to sync')),
            trailing: DbBuilder<int>(load: Repo.pendingSyncCount, builder: (_, n) => Text('$n')),
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: Text(tr('إيه اللي بيتخزن فين؟', 'What is stored where?')),
            subtitle: Text(tr(
                'كل بياناتك (الأجهزة، الأوامر، المخزون، الملفات) على جهازك بس. مفيش حاجة بتتبعت لأي سيرفر. ممنوع تدخل بيانات مرضى.',
                'All your data (devices, orders, inventory, files) is stored only on this device. Nothing is sent to any server. Never enter patient data.')),
          ),
          ListTile(
            leading: const Icon(Icons.backup),
            title: Text(tr('نسخة احتياطية', 'Backup')),
            subtitle: Text(tr('احفظ نسخة من قاعدة البيانات في مجلد تختاره', 'Save a copy of the database to a folder you choose')),
            onTap: () => _backup(context),
          ),
          SectionTitle2x(tr('الفريق', 'Team')),
          ListTile(
            leading: const Icon(Icons.groups),
            title: Text(tr('الفريق والأدوار', 'Team and roles')),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TeamScreen())),
          ),
          SectionTitle2x(tr('الحساب', 'Account')),
          ListTile(
            leading: const Icon(Icons.person),
            title: Text(st.userName.isEmpty ? tr('بدون اسم', 'No name') : st.userName),
            subtitle: Text(roleLabel(Db.i.role)),
            trailing: const Icon(Icons.edit),
            onTap: () async {
              final t = await askText(context, tr('اسمك', 'Your name'), initial: st.userName);
              if (t != null && t.isNotEmpty) {
                await st.setUserName(t);
                await Db.i.raw.update('members', {'user_name': t}, where: 'id = ?', whereArgs: [Db.i.memberId]);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(tr('تسجيل الخروج', 'Sign out')),
            subtitle: Text(tr('بيرجعك لشاشة الترحيب. بياناتك على الجهاز بتفضل زي ما هي.', 'Returns to the welcome screen. Your data stays on the device.')),
            onTap: () async {
              if (await confirm(context, tr('تسجيل الخروج؟', 'Sign out?'))) {
                await st.signOut();
                if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              }
            },
          ),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Future<void> _backup(BuildContext context) async {
    try {
      final dir = await FilePicker.platform.getDirectoryPath();
      if (dir == null) return;
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      await File(Db.i.path).copy(p.join(dir, 'engx_backup_$stamp.db'));
      if (context.mounted) toast(context, tr('اتحفظت النسخة الاحتياطية', 'Backup saved'));
    } catch (e) {
      if (context.mounted) toast(context, friendlyError(e));
    }
  }
}

class SectionTitle2x extends StatelessWidget {
  const SectionTitle2x(this.t, {super.key});
  final String t;
  @override
  Widget build(BuildContext context) => SectionTitle(t);
}

/// الفريق: دلوقتي المساحة شخصية والمالك هو العضو الوحيد.
class TeamScreen extends StatelessWidget {
  const TeamScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('الفريق والأدوار', 'Team and roles'))),
      body: DbBuilder<List<Rec>>(
        load: () async => Db.i.raw.query('members', where: 'workspace_id = ? AND deleted_at IS NULL', whereArgs: [Db.i.workspaceId]),
        builder: (context, list) => ListView(children: [
          for (final m in list)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(s(m['user_name']).isEmpty ? tr('أنا', 'Me') : s(m['user_name'])),
              subtitle: Text(roleLabel(s(m['role']))),
              trailing: StatusChip(StatusInfo('نشط', 'Active', const Color(0xFF2E9E6B), Icons.check_circle)),
            ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              tr('دعوة أعضاء وإسناد الأوامر بيحتاجوا ربط سحابي (مرحلة الفريق). قاعدة البيانات والأدوار والصلاحيات جاهزة من دلوقتي: مالك، مدير، فني، مشاهد.',
                  'Inviting members and assigning orders need the cloud link (team phase). The database, roles and permissions are already in place: Owner, Admin, Technician, Viewer.'),
              style: const TextStyle(color: Colors.grey),
            ),
          ),
        ]),
      ),
    );
  }
}
