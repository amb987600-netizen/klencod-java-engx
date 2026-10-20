import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/app_state.dart';
import '../core/theme.dart';
import '../data/repo.dart';
import '../widgets/common.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  Future<void> _export(BuildContext context, Map<String, Object> d) async {
    // الخط العربي بيتحمل من الإنترنت مرة واحدة؛ لو مفيش نت بنكتب التقرير بالإنجليزي.
    pw.Font? font;
    var ar = AppState.i.isAr;
    if (ar) {
      try {
        font = await PdfGoogleFonts.notoNaskhArabicRegular();
      } catch (_) {
        ar = false;
        if (context.mounted) toast(context, tr('مفيش إنترنت لتحميل الخط العربي، التقرير هيتصدّر بالإنجليزي.', 'No internet for the Arabic font; exporting in English.'));
      }
    }
    String t(String a, String e) => ar ? a : e;
    final faults = d['faults'] as List<MapEntry<String, int>>;
    final doc = pw.Document(theme: font == null ? null : pw.ThemeData.withFont(base: font, bold: font));
    doc.addPage(pw.Page(
      textDirection: ar ? pw.TextDirection.rtl : pw.TextDirection.ltr,
      build: (_) => pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('EngX - ${t('تقرير الصيانة', 'Maintenance report')}', style: const pw.TextStyle(fontSize: 22)),
        pw.Text(Repo.today()),
        pw.SizedBox(height: 16),
        pw.Text(t('الأعطال حسب الشهر', 'Faults by month')),
        pw.TableHelper.fromTextArray(
          headers: [t('الشهر', 'Month'), t('العدد', 'Count')],
          data: [for (final f in faults) [f.key, '${f.value}']],
          headerStyle: pw.TextStyle(color: PdfColors.white),
          headerDecoration: const pw.BoxDecoration(color: PdfColors.teal),
        ),
        pw.SizedBox(height: 16),
        pw.Text(t('جاهزية الأجهزة', 'Device readiness')),
        pw.Bullet(text: '${t('الإجمالي', 'Total')}: ${d['total']}'),
        pw.Bullet(text: '${t('يعمل', 'Working')}: ${d['working']}'),
        pw.Bullet(text: '${t('متوقف', 'Stopped')}: ${d['stopped']}'),
        pw.Bullet(text: '${t('تحت الصيانة', 'Under repair')}: ${d['repair']}'),
        pw.SizedBox(height: 16),
        pw.Text('${t('متوسط زمن الإصلاح (ساعة)', 'Average repair time (hours)')}: ${(d['avgHours'] as double).toStringAsFixed(1)}'),
        pw.Text('${t('تكلفة قطع الغيار', 'Spare parts cost')}: ${(d['partsCost'] as double).toStringAsFixed(2)}'),
      ]),
    ));
    await Printing.sharePdf(bytes: await doc.save(), filename: 'engx_report.pdf');
  }

  @override
  Widget build(BuildContext context) {
    return DbBuilder<Map<String, Object>>(
      load: Repo.reportData,
      builder: (context, d) {
        final faults = d['faults'] as List<MapEntry<String, int>>;
        final maxV = faults.fold<int>(1, (m, e) => e.value > m ? e.value : m);
        final total = d['total'] as int;
        return Scaffold(
          appBar: AppBar(
            title: Text(tr('التقارير', 'Reports')),
            actions: [IconButton(tooltip: tr('تصدير PDF', 'Export PDF'), icon: const Icon(Icons.picture_as_pdf), onPressed: () => _export(context, d))],
          ),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Text(tr('الأعطال حسب الشهر', 'Faults by month'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                for (final f in faults)
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Text('${f.value}'),
                      Container(
                        height: 100.0 * f.value / maxV + 2,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(color: Brand.red, borderRadius: BorderRadius.circular(4)),
                      ),
                      const SizedBox(height: 4),
                      Text(f.key.substring(5), style: const TextStyle(fontSize: 11)),
                    ]),
                  ),
              ]),
            ),
            SectionTitle(tr('جاهزية الأجهزة', 'Device readiness')),
            if (total == 0)
              Text(tr('مفيش أجهزة لسه', 'No devices yet'))
            else ...[
              _bar(tr('يعمل', 'Working'), d['working'] as int, total, Brand.green),
              _bar(tr('تحت الصيانة', 'Under repair'), d['repair'] as int, total, Brand.amber),
              _bar(tr('متوقف', 'Stopped'), d['stopped'] as int, total, Brand.red),
            ],
            SectionTitle(tr('زمن الإصلاح', 'Repair time')),
            Card(
              child: ListTile(
                leading: const Icon(Icons.timer),
                title: Text((d['repairCount'] as int) == 0 ? tr('مفيش أوامر مغلقة لسه', 'No closed orders yet') : '${(d['avgHours'] as double).toStringAsFixed(1)} ${tr('ساعة (متوسط)', 'hours (average)')}'),
                subtitle: Text('${tr('عدد الأوامر المحسوبة', 'Orders counted')}: ${d['repairCount']}'),
              ),
            ),
            SectionTitle(tr('تكلفة قطع الغيار', 'Spare parts cost')),
            Card(
              child: ListTile(
                leading: const Icon(Icons.payments),
                title: Text((d['partsCost'] as double).toStringAsFixed(2)),
                subtitle: Text(tr('من أسعار الشراء اللي انت دخلتها', 'Based on the purchase prices you entered')),
              ),
            ),
          ]),
        );
      },
    );
  }

  Widget _bar(String label, int v, int total, Color c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(width: 90, child: Text(label)),
          Expanded(child: LinearProgressIndicator(value: v / total, minHeight: 14, color: c, backgroundColor: c.withOpacity(.15))),
          const SizedBox(width: 8),
          Text('$v'),
        ]),
      );
}
