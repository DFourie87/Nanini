import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:nanini_app/features/sales/sales_customers_models.dart';
import 'package:nanini_app/features/sales/sales_models.dart';
import 'package:nanini_app/features/suppliers/suppliers_models.dart';
import 'package:nanini_app/features/xero/xero_api.dart';
import 'package:nanini_app/features/xero/xero_export.dart';

const taxTypes = {
  kZeroRated: 'ZERORATEDOUTPUT',
  kStandardSales: 'OUTPUT',
  kStandardPurchases: 'INPUT',
  kNoVat: 'NONE',
  kCapitalPurchases: 'CAPEXINPUT',
};

XeroConnection conn({DateTime? expires}) => XeroConnection(
      clientId: 'client',
      accessToken: 'old-access',
      refreshToken: 'refresh-1',
      expiresAt: expires ?? DateTime.now().toUtc().add(const Duration(minutes: 20)),
      tenantId: 'tenant-1',
      tenantName: 'Nanini Boerdery',
    );

List<XeroBill> bills() {
  final omnia = Supplier(id: 's1', name: 'Omnia ', category: '3740 - Fertilizer');
  final docs = [
    SupplierDoc(id: 'd1', supplierId: 's1', kind: SupplierDocKind.invoice, date: '2026-09-10', amount: 1150, reference: 'IN1', vatAmount: 150),
    SupplierDoc(id: 'd2', supplierId: 's1', kind: SupplierDocKind.creditNote, date: '2026-09-12', amount: 115, reference: 'CN1', vatAmount: 15),
  ];
  final lines = [
    DocLine(id: 'l1', docId: 'd1', lineNo: 1, description: 'Fertilizer 2:3:4', excl: 600, vat: 90),
    DocLine(id: 'l2', docId: 'd1', lineNo: 2, description: 'Transport', excl: 400, vat: 60, glAccount: '4800/000'),
  ];
  return xeroBills(purchasesFor([SupplierAccount(omnia, docs, const [])], lines, const [], '2026-09-01', '2026-09-30'));
}

void main() {
  test('PKCE: the challenge is the base64url SHA-256 of the verifier, no padding', () {
    // As Python's hashlib + urlsafe_b64encode work it out.
    expect(xeroCodeChallenge('dBjftJeZ4CVP-mB92K27uhbUJU1p1r7wW1gFWFOEjXk'), 'bwWFMyPfdG9qreDhH2lmftFx_dFeLDalzcT1gb_j68g');
    final v = xeroCodeVerifier();
    expect(v.length, 64);
    final u = xeroAuthorizeUri(clientId: 'abc', scopes: kXeroScopeSets.first, challenge: 'ch', state: 'st');
    expect((u.host, u.queryParameters['redirect_uri'], u.queryParameters['code_challenge_method']), ('login.xero.com', kXeroRedirect, 'S256'));
  });

  test('a supplier invoice as a draft bill, a credit note as an ACCPAYCREDIT with its amounts positive', () {
    final b = bills();
    final bill = xeroBillDraft(b[0], taxTypes);
    expect((bill.endpoint, bill.key, bill.total), ('Invoices', 'ACCPAY|omnia|IN1', 1150.0));
    expect(bill.json['Status'], 'DRAFT');
    expect(bill.json['Contact'], {'Name': 'Omnia'});
    expect(bill.json['InvoiceNumber'], 'IN1');
    expect(bill.json['LineAmountTypes'], 'Exclusive');
    expect([for (final l in bill.json['LineItems'] as List) (l['UnitAmount'], l['AccountCode'], l['TaxType'], l['TaxAmount'])],
        [(600.0, '3740/000', 'INPUT', 90.0), (400.0, '4800/000', 'INPUT', 60.0)]);
    final cn = xeroBillDraft(b[1], taxTypes);
    expect((cn.endpoint, cn.key, cn.json['Type'], cn.json['CreditNoteNumber']), ('CreditNotes', 'ACCPAYCREDIT|omnia|CN1', 'ACCPAYCREDIT', 'CN1'));
    expect(cn.json.containsKey('DueDate'), isFalse);
    final l = (cn.json['LineItems'] as List).single;
    expect((l['UnitAmount'], l['TaxAmount']), (100.0, 15.0));
    // A tax rate Xero doesn't have: said, not sent wrong.
    expect(() => xeroBillDraft(b[0], const {kNoVat: 'NONE'}), throwsA(isA<XeroProblem>()));
  });

  test('an account sale as a draft sales invoice at nett', () {
    final r = SalesReport(id: 'r1', category: 'potatoes', agent: 'Botha Roodt', reportNumber: '15060', reportDate: '2026-10-28',
        grossTotal: 1000, commissionBeforeVat: 100, vat: 15, nettAmount: 885);
    final inv = xeroInvoices(reports: [r], lineItems: const {}, deductions: const {
      'r1': [XeroDeduction(reportId: 'r1', ord: 1, label: 'AGENT COMMISSION', amount: 100, vat: 15)],
    }, customers: [Customer(id: 'c1', name: 'Botha Roodt Johannesburg', agent: 'Botha Roodt')]).single;
    final d = xeroInvoiceDraft(inv, taxTypes);
    expect((d.id, d.endpoint, d.key, d.total), ('r1', 'Invoices', 'ACCREC|botha roodt johannesburg|15060', 885.0));
    expect((d.json['Reference'], d.json['Date'], d.json['Status']), ('Account sale 15060', '2026-10-28', 'DRAFT'));
    expect([for (final l in d.json['LineItems'] as List) (l['UnitAmount'], l['AccountCode'], l['TaxType'], l['TaxAmount'])],
        [(1000.0, '1000/800', 'ZERORATEDOUTPUT', null), (-100.0, '3490/000', 'INPUT', -15.0)]);
  });

  test('calls Xero with the organisation, signs in again when the access token is old, and keeps the new refresh token', () async {
    final store = MemoryXeroStore()..connection = conn(expires: DateTime.now().toUtc().subtract(const Duration(minutes: 1)));
    final seen = <http.BaseRequest>[];
    final client = MockClient((req) async {
      seen.add(req);
      if (req.url.host == 'identity.xero.com') {
        expect(req.bodyFields['grant_type'], 'refresh_token');
        expect(req.bodyFields['refresh_token'], 'refresh-1');
        return http.Response(jsonEncode({'access_token': 'new-access', 'refresh_token': 'refresh-2', 'expires_in': 1800}), 200);
      }
      expect(req.headers['Authorization'], 'Bearer new-access');
      expect(req.headers['xero-tenant-id'], 'tenant-1');
      return http.Response(jsonEncode({
        'TaxRates': [
          {'Name': kStandardPurchases, 'TaxType': 'INPUT', 'Status': 'ACTIVE'},
          {'Name': 'Old rate', 'TaxType': 'OLD', 'Status': 'DELETED'},
        ]
      }), 200);
    });
    final api = XeroApi(client: client, store: store, wait: (_) async {});
    expect(await api.taxTypes(), {kStandardPurchases: 'INPUT'});
    expect(store.connection!.refreshToken, 'refresh-2');
    expect(seen.length, 2);
  });

  test('what Xero already has (not voided or deleted) is known by type, contact and number', () async {
    final client = MockClient((req) async {
      final path = req.url.path;
      expect(req.url.queryParameters['where'], 'Date>=DateTime(2026,8,29)');
      if (path.endsWith('/Invoices')) {
        return http.Response(jsonEncode({
          'Invoices': [
            {'Type': 'ACCPAY', 'InvoiceNumber': 'ACC394402', 'Contact': {'Name': 'Noord Tranvaal Boere'}, 'Status': 'AUTHORISED'},
            {'Type': 'ACCPAY', 'InvoiceNumber': 'ACC122-71622', 'Contact': {'Name': 'Noord Tranvaal Boere'}, 'Status': 'DELETED'},
          ]
        }), 200);
      }
      return http.Response(jsonEncode({
        'CreditNotes': [
          {'Type': 'ACCPAYCREDIT', 'CreditNoteNumber': 'BKAH151353', 'Contact': {'Name': 'VKB'}, 'Status': 'PAID'},
        ]
      }), 200);
    });
    final api = XeroApi(client: client, store: MemoryXeroStore()..connection = conn(), wait: (_) async {});
    expect(await api.existingKeys(kXeroFrom), {'ACCPAY|noord tranvaal boere|ACC394402', 'ACCPAYCREDIT|vkb|BKAH151353'});
  });

  test('sends drafts and says per document what Xero refused; waits when Xero asks to slow down', () async {
    var calls = 0;
    var waited = 0;
    final client = MockClient((req) async {
      calls++;
      if (calls == 1) return http.Response('', 429, headers: {'retry-after': '2'});
      expect(req.method, 'PUT');
      expect(req.url.queryParameters['summarizeErrors'], 'false');
      final sent = (jsonDecode(req.body) as Map)['Invoices'] as List;
      expect(sent.length, 1);
      return http.Response(jsonEncode({
        'Invoices': [
          {'StatusAttributeString': 'ERROR', 'ValidationErrors': [{'Message': 'Account code \'9999/000\' is not a valid code'}]},
        ]
      }), 400);
    });
    final api = XeroApi(client: client, store: MemoryXeroStore()..connection = conn(), wait: (d) async => waited += d.inSeconds);
    final b = xeroBillDraft(bills()[0], taxTypes);
    final results = await api.send([b]);
    expect(waited, 2);
    expect(results.single.ok, isFalse);
    expect(results.single.error, contains('9999/000'));
  });
}
