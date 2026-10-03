import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/widgets/nanini_app_bar.dart';
import '../../theme/nanini_theme.dart';
import 'suppliers_account_screen.dart';
import 'suppliers_data.dart';
import 'suppliers_overview_screen.dart';
import 'suppliers_period.dart';
import 'suppliers_recon_screen.dart';

/// Everything about one supplier on one page: what's due, documents to
/// check, uploading invoices and statements, the account for a period
/// (opening + invoices - payments = amount due) with its lines, the
/// statements checked, and its details.
class SupplierScreen extends StatefulWidget {
  const SupplierScreen({super.key, required this.data, required this.supplierId});
  final SuppliersData data;
  final String supplierId;

  @override
  State<SupplierScreen> createState() => _SupplierScreenState();
}

class _SupplierScreenState extends State<SupplierScreen> {
  SupplierPeriod period = SupplierPeriod.taxYearToDate(DateTime.now());

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.data,
      builder: (context, _) {
        final a = widget.data.accounts.where((x) => x.supplier.id == widget.supplierId).firstOrNull;
        return Scaffold(
          appBar: NaniniAppBar(title: a?.supplier.name ?? 'Supplier'),
          body: a == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(a.due < -0.005 ? 'In credit' : 'Amount due', style: Theme.of(context).textTheme.titleMedium),
                                  if ((a.supplier.accountNo ?? '').isNotEmpty)
                                    Text('Our account ${a.supplier.accountNo}', style: const TextStyle(color: NaniniColors.muted)),
                                ],
                              ),
                            ),
                            Text(
                              a.due < -0.005 ? '-${fmtRCents(-a.due)}' : fmtRCents(a.due),
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: a.due > 0.005 ? NaniniColors.red : a.due < -0.005 ? NaniniColors.green : NaniniColors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (a.hiddenByOpening > 0)
                      Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: NaniniColors.amber)),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'The opening balance (${fmtRCents(a.supplier.openingBalance)}) is dated ${fmtDateDisplay(a.supplier.openingDate)}: '
                                '${a.hiddenByOpening} invoice(s) and payment(s) before that date are left out. '
                                'Most suppliers start on 1 March (the tax year) -- change its date.',
                                style: const TextStyle(color: NaniniColors.amber, fontWeight: FontWeight.w600),
                              ),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(onPressed: () => editSupplier(context, widget.data, s: a.supplier), child: const Text('Change details')),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ...supplierWorkSections(context, widget.data, a),
                    const SizedBox(height: 16),
                    Text('Account', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 6),
                    SupplierAccountSection(data: widget.data, account: a, period: period, onPeriod: (p) => setState(() => period = p)),
                    const SizedBox(height: 16),
                    Card(
                      child: ExpansionTile(
                        title: const Text('Details -- payable, banking, contact'),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
                        children: supplierDetailsSection(context, widget.data, a),
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }
}
