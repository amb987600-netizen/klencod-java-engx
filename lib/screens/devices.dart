import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/app_state.dart';
import '../core/theme.dart';
import '../data/db.dart';
import '../data/repo.dart';
import '../widgets/common.dart';
import 'device_detail.dart';
import 'home.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key, this.initialFilter = 'all', this.standalone = false});
  final String initialFilter;
  final bool standalone;
  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late String _filter = widget.initialFilter;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filters = {
      'all': tr('الكل', 'All'),
      'needs': tr('محتاج صيانة', 'Needs service'),
      'repair': tr('تحت الإصلاح', 'Under repair'),
      'pm': tr('صيانة قادمة', 'Upcoming PM'),
    };
    return Scaffold(
      appBar: AppBar(title: Text(tr('الأجهزة', 'Devices'))),
      floatingActionButton: Db.i.canWrite && !widget.standalone
          ? Padding(
              padding: const EdgeInsets.only(bottom: 72),
              child: FloatingActionButton(
                heroTag: 'addDevice',
                tooltip: tr('إضافة جهاز', 'Add device'),
                onPressed: () => push(context, const DeviceFormScreen()),
                child: const Icon(Icons.add),
              ),
            )
          : null,
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: InputDecoration(
              hintText: tr('ابحث بالاسم أو الكود أو السيريال', 'Search by name, code or serial'),
              prefixIcon: const Icon(Icons.search),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        SizedBox(
          height: 48,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final e in filters.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: _filter == e.key,
                    onSelected: (_) => setState(() => _filter = e.key),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: DbBuilder<List<Rec>>(
            key: ValueKey('$_filter|$_q'),
            load: () => Repo.devices(search: _q, filter: _filter),
            builder: (context, list) {
              if (list.isEmpty) {
                return EmptyState(
                  icon: Icons.devices_other,
                  message: _q.isNotEmpty || _filter != 'all'
                      ? tr('مفيش أجهزة مطابقة', 'No matching devices')
                      : tr('لسه مضفتش أجهزة. دوس + وضيف أول جهاز.', 'No devices yet. Tap + to add your first.'),
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 160),
                itemCount: list.length,
                itemBuilder: (_, k) => _DeviceCard(list[k]),
              );
            },
          ),
        ),
      ]),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard(this.d);
  final Rec d;
  @override
  Widget build(BuildContext context) {
    final photo = s(d['photo_path']);
    return Card(
      child: ListTile(
        leading: photo.isNotEmpty && File(photo).existsSync()
            ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(photo), width: 48, height: 48, fit: BoxFit.cover))
            : const CircleAvatar(child: Icon(Icons.medical_services)),
        title: Text(s(d['name']), style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([s(d['asset_code']), s(d['location'])].where((e) => e.isNotEmpty).join(' · ')),
        trailing: StatusChip(deviceStatus(s(d['status']))),
        onTap: () => push(context, DeviceDetailScreen(deviceId: s(d['id']))),
      ),
    );
  }
}

/// إضافة / تعديل جهاز.
class DeviceFormScreen extends StatefulWidget {
  const DeviceFormScreen({super.key, this.deviceId});
  final String? deviceId;
  @override
  State<DeviceFormScreen> createState() => _DeviceFormScreenState();
}

class _DeviceFormScreenState extends State<DeviceFormScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _maker = TextEditingController();
  final _model = TextEditingController();
  final _serial = TextEditingController();
  final _code = TextEditingController();
  final _loc = TextEditingController();
  final _notes = TextEditingController();
  String _status = 'working';
  String? _install;
  String? _photo;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (widget.deviceId != null) {
      final d = await Repo.device(widget.deviceId!);
      if (d != null) {
        _name.text = s(d['name']);
        _maker.text = s(d['manufacturer']);
        _model.text = s(d['model']);
        _serial.text = s(d['serial']);
        _code.text = s(d['asset_code']);
        _loc.text = s(d['location']);
        _notes.text = s(d['notes']);
        _status = s(d['status']);
        _install = d['install_date'] as String?;
        _photo = d['photo_path'] as String?;
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final code = _code.text.trim();
    if (await Repo.assetCodeTaken(code, exceptId: widget.deviceId)) {
      if (mounted) toast(context, tr('الكود ده مستخدم لجهاز تاني', 'This code is used by another device'));
      return;
    }
    final v = <String, Object?>{
      'name': _name.text.trim(),
      'manufacturer': _maker.text.trim(),
      'model': _model.text.trim(),
      'serial': _serial.text.trim(),
      'asset_code': code,
      'location': _loc.text.trim(),
      'status': _status,
      'install_date': _install,
      'photo_path': _photo,
      'notes': _notes.text.trim(),
    };
    try {
      if (widget.deviceId == null) {
        v['domain'] = 'medical';
        await Db.i.insert('devices', v);
      } else {
        await Db.i.update('devices', widget.deviceId!, v);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final edit = widget.deviceId != null;
    return Scaffold(
      appBar: AppBar(title: Text(edit ? tr('تعديل جهاز', 'Edit device') : tr('إضافة جهاز', 'Add device'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                _f(_name, tr('اسم الجهاز', 'Device name'), required: true),
                _f(_maker, tr('الشركة المصنعة', 'Manufacturer')),
                _f(_model, tr('الموديل', 'Model')),
                _f(_serial, tr('الرقم التسلسلي', 'Serial number')),
                _f(_code, tr('الكود الداخلي (فريد)', 'Asset code (unique)'), required: true),
                _f(_loc, tr('المكان / القسم', 'Location / department')),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<String>(
                    value: _status,
                    decoration: deco(tr('الحالة', 'Status')),
                    items: [
                      for (final st in ['working', 'stopped', 'under_repair'])
                        DropdownMenuItem(value: st, child: Text(deviceStatus(st).label)),
                    ],
                    onChanged: (v) => setState(() => _status = v ?? 'working'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event),
                    label: Text('${tr('تاريخ التركيب', 'Install date')}: ${_install ?? '—'}'),
                    onPressed: () async {
                      final d = await pickDate(context, initial: _install);
                      if (d != null) setState(() => _install = d);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.photo),
                    label: Text(_photo == null ? tr('إضافة صورة (اختياري)', 'Add photo (optional)') : tr('تغيير الصورة', 'Change photo')),
                    onPressed: () async {
                      final r = await pickAndStore(type: FileType.image);
                      if (r != null) setState(() => _photo = r.path);
                    },
                  ),
                ),
                _f(_notes, tr('ملاحظات', 'Notes'), lines: 3, helper: noPatientDataHint),
                const SizedBox(height: 8),
                FilledButton(onPressed: _save, child: Text(tr('حفظ', 'Save'))),
              ]),
            ),
    );
  }

  Widget _f(TextEditingController c, String label, {bool required = false, int lines = 1, String? helper}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          maxLines: lines,
          decoration: deco(label, helper: helper),
          validator: required ? (v) => (v == null || v.trim().isEmpty) ? tr('الخانة دي مطلوبة', 'Required') : null : null,
        ),
      );
}
