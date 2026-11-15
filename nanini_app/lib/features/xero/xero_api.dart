import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../suppliers/suppliers_models.dart';
import 'xero_export.dart';

/// The hub straight to Xero through Xero's API, instead of the CSV files:
/// the same sales invoices and bills (built by xero_export.dart), sent as
/// drafts to approve in Xero.
///
/// Sign-in: Xero's OAuth 2 with PKCE for a desktop app -- no client secret.
/// The Xero app (developer.xero.com > My Apps > New app, "Mobile or desktop
/// app", redirect URI [kXeroRedirect]) gives the client ID; the sign-in runs
/// in the browser and comes back to this PC on [kXeroRedirect]. The tokens
/// are kept on this PC only (its local settings), never in the database.

const kXeroRedirectPort = 8749;
const kXeroRedirect = 'http://localhost:$kXeroRedirectPort/callback';

/// Xero's scopes: the granular ones (apps made from 2026), else the broad
/// ones of older apps -- the sign-in tries the second when Xero refuses the first.
const kXeroScopeSets = [
  'openid profile email offline_access accounting.invoices accounting.contacts accounting.settings.read',
  'openid profile email offline_access accounting.transactions accounting.contacts accounting.settings.read',
];

const _authorizeUrl = 'https://login.xero.com/identity/connect/authorize';
const _tokenUrl = 'https://identity.xero.com/connect/token';
const _api = 'https://api.xero.com';

class XeroProblem implements Exception {
  XeroProblem(this.message);
  final String message;
  @override
  String toString() => message;
}

/// This PC's link to one Xero organisation.
class XeroConnection {
  XeroConnection({
    required this.clientId,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.tenantId,
    required this.tenantName,
  });
  final String clientId;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String tenantId;
  final String tenantName;

  XeroConnection withTokens(String access, String refresh, DateTime expires) => XeroConnection(
      clientId: clientId, accessToken: access, refreshToken: refresh, expiresAt: expires, tenantId: tenantId, tenantName: tenantName);

  Map<String, dynamic> toJson() => {
        'client_id': clientId,
        'access_token': accessToken,
        'refresh_token': refreshToken,
        'expires_at': expiresAt.toUtc().toIso8601String(),
        'tenant_id': tenantId,
        'tenant_name': tenantName,
      };

  factory XeroConnection.fromJson(Map<String, dynamic> j) => XeroConnection(
        clientId: j['client_id'] as String,
        accessToken: j['access_token'] as String,
        refreshToken: j['refresh_token'] as String,
        expiresAt: DateTime.parse(j['expires_at'] as String),
        tenantId: j['tenant_id'] as String,
        tenantName: j['tenant_name'] as String? ?? 'Xero',
      );
}

/// Where the connection is kept: this PC's local settings (tests: in memory).
class XeroStore {
  static const _key = 'xero_connection';
  static const _clientKey = 'xero_client_id';

  Future<XeroConnection?> load() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_key);
    if (s == null) return null;
    try {
      return XeroConnection.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(XeroConnection c) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode(c.toJson()));
    await p.setString(_clientKey, c.clientId);
  }

  Future<void> clear() async => (await SharedPreferences.getInstance()).remove(_key);

  /// The client ID used last (to sign in again without typing it).
  Future<String?> lastClientId() async => (await SharedPreferences.getInstance()).getString(_clientKey);
}

class MemoryXeroStore extends XeroStore {
  XeroConnection? connection;
  String? clientId;
  @override
  Future<XeroConnection?> load() async => connection;
  @override
  Future<void> save(XeroConnection c) async {
    connection = c;
    clientId = c.clientId;
  }

  @override
  Future<void> clear() async => connection = null;
  @override
  Future<String?> lastClientId() async => clientId;
}

/// PKCE: a random code verifier and its S256 challenge.
String xeroCodeVerifier([Random? random]) {
  final r = random ?? Random.secure();
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
  return List.generate(64, (_) => chars[r.nextInt(chars.length)]).join();
}

String xeroCodeChallenge(String verifier) => base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes).replaceAll('=', '');

Uri xeroAuthorizeUri({required String clientId, required String scopes, required String challenge, required String state}) =>
    Uri.parse(_authorizeUrl).replace(queryParameters: {
      'response_type': 'code',
      'client_id': clientId,
      'redirect_uri': kXeroRedirect,
      'scope': scopes,
      'state': state,
      'code_challenge': challenge,
      'code_challenge_method': 'S256',
    });

/// One document to send: [key] says which document it is in Xero
/// (type|contact|number), to leave out one Xero already has.
class XeroDraft {
  XeroDraft({required this.id, required this.label, required this.endpoint, required this.key, required this.total, required this.json});

  /// The hub's document (sales report / supplier document) it comes from.
  final String id;
  final String label;

  /// 'Invoices' or 'CreditNotes'.
  final String endpoint;
  final String key;
  final double total;
  final Map<String, dynamic> json;
}

/// What Xero said about one draft: accepted, or why not.
class XeroResult {
  XeroResult(this.draft, this.error);
  final XeroDraft draft;
  final String? error;
  bool get ok => error == null;
}

String xeroKey(String type, String contact, String number) =>
    '$type|${contact.trim().toLowerCase()}|${number.trim().toUpperCase()}';

double _r(double v) => (v * 100).roundToDouble() / 100;

String _taxType(Map<String, String> taxTypes, String name) {
  final t = taxTypes[name];
  if (t == null) throw XeroProblem('Xero has no tax rate "$name" (Accounting > Advanced > Tax rates).');
  return t;
}

/// The tax rate names [drafts] need that Xero doesn't have.
Set<String> xeroMissingTaxRates(Iterable<String> names, Map<String, String> taxTypes) => {for (final n in names) if (!taxTypes.containsKey(n)) n};

/// A supplier's invoice as a Xero bill (ACCPAY), or its credit note
/// (ACCPAYCREDIT, amounts positive): a draft, tax exclusive, a line per item
/// against its account as in the bills CSV; lines without an account on
/// [fallbackAccount].
XeroDraft xeroBillDraft(XeroBill b, Map<String, String> taxTypes, {String fallbackAccount = kXeroSuspense}) {
  final credit = b.total < 0;
  final sign = credit ? -1 : 1;
  final lines = [
    for (final l in b.lines)
      for (final (description, excl, account, taxName, tax) in xeroBillLineParts(
          l,
          (l.description ?? '').trim().isNotEmpty ? l.description!.trim() : docKindLabel(b.doc.kind),
          (l.account ?? '').isNotEmpty ? l.account! : fallbackAccount))
        {
          'Description': description,
          'Quantity': 1,
          'UnitAmount': _r(sign * excl),
          'AccountCode': account,
          'TaxType': _taxType(taxTypes, taxName),
          'TaxAmount': ?(tax == null ? null : _r(sign * tax)),
        },
  ];
  final contact = b.supplier.name.trim();
  final type = credit ? 'ACCPAYCREDIT' : 'ACCPAY';
  return XeroDraft(
    id: b.doc.id,
    label: '${b.number} (${b.supplier.name})',
    endpoint: credit ? 'CreditNotes' : 'Invoices',
    key: xeroKey(type, contact, b.number),
    total: b.total,
    json: {
      'Type': type,
      'Contact': {'Name': contact},
      'Date': b.doc.date,
      if (!credit) 'DueDate': b.dueDate,
      if (credit) 'CreditNoteNumber': b.number else 'InvoiceNumber': b.number,
      'LineAmountTypes': 'Exclusive',
      'Status': 'DRAFT',
      'CurrencyCode': 'ZAR',
      'LineItems': lines,
    },
  );
}

/// An account sale as a Xero sales invoice (ACCREC) at nett, as in the
/// sales invoices CSV: a draft, tax exclusive; a credit note if its total is
/// below nil.
XeroDraft xeroInvoiceDraft(XeroInvoice inv, Map<String, String> taxTypes) {
  final credit = inv.total < 0;
  final sign = credit ? -1 : 1;
  final type = credit ? 'ACCRECCREDIT' : 'ACCREC';
  return XeroDraft(
    id: inv.report.id!,
    label: '${inv.number} (${inv.contact})',
    endpoint: credit ? 'CreditNotes' : 'Invoices',
    key: xeroKey(type, inv.contact, inv.number),
    total: inv.total,
    json: {
      'Type': type,
      'Contact': {'Name': inv.contact},
      'Date': inv.report.reportDate,
      if (!credit) 'DueDate': inv.dueDate,
      if (credit) 'CreditNoteNumber': inv.number else 'InvoiceNumber': inv.number,
      'Reference': inv.reference,
      'LineAmountTypes': 'Exclusive',
      'Status': 'DRAFT',
      'CurrencyCode': 'ZAR',
      'LineItems': [
        for (final l in inv.lines)
          {
            'Description': l.description,
            'Quantity': 1,
            'UnitAmount': _r(sign * l.amount),
            'AccountCode': l.account,
            'TaxType': _taxType(taxTypes, l.taxType),
            'TaxAmount': ?(l.tax == null ? null : _r(sign * l.tax!)),
          },
      ],
    },
  );
}

/// Talks to Xero for one organisation, signing in again with the refresh token when needed.
class XeroApi {
  XeroApi({http.Client? client, XeroStore? store, Future<bool> Function(Uri)? openBrowser, this.wait = _sleep})
      : _http = client ?? http.Client(),
        store = store ?? XeroStore(),
        _open = openBrowser ?? ((u) => launchUrl(u, mode: LaunchMode.externalApplication));

  final http.Client _http;
  final XeroStore store;
  final Future<bool> Function(Uri) _open;

  /// Waiting when Xero asks to slow down (tests: no wait).
  final Future<void> Function(Duration) wait;
  static Future<void> _sleep(Duration d) => Future<void>.delayed(d);

  XeroConnection? _conn;

  /// Signing in is only done on the PC (the browser comes back to this PC).
  static bool get canSignIn => !Platform.isAndroid && !Platform.isIOS;

  Future<XeroConnection?> connection() async => _conn ??= await store.load();

  Future<void> disconnect() async {
    _conn = null;
    await store.clear();
  }

  /// Signs in to Xero in the browser and picks the organisation (the one
  /// named Nanini if there are several).
  Future<XeroConnection> connect(String clientId, {Duration timeout = const Duration(minutes: 5)}) async {
    clientId = clientId.trim();
    if (clientId.isEmpty) throw XeroProblem('The client ID of the Xero app is needed (developer.xero.com > My Apps).');
    for (final (i, scopes) in kXeroScopeSets.indexed) {
      final verifier = xeroCodeVerifier();
      final state = xeroCodeVerifier().substring(0, 24);
      final back = await _signInInBrowser(xeroAuthorizeUri(clientId: clientId, scopes: scopes, challenge: xeroCodeChallenge(verifier), state: state), timeout);
      if (back['error'] == 'invalid_scope' && i < kXeroScopeSets.length - 1) continue;
      if (back['error'] != null) throw XeroProblem('Xero said: ${back['error_description'] ?? back['error']}');
      if (back['state'] != state) throw XeroProblem('The sign-in came back from somewhere else -- try again.');
      final code = back['code'];
      if (code == null) throw XeroProblem('Xero gave no sign-in code -- try again.');
      final tokens = await _token({
        'grant_type': 'authorization_code',
        'client_id': clientId,
        'code': code,
        'redirect_uri': kXeroRedirect,
        'code_verifier': verifier,
      });
      final r = await _http.get(Uri.parse('$_api/connections'), headers: {'Authorization': 'Bearer ${tokens.access}', 'Accept': 'application/json'});
      if (r.statusCode != 200) throw XeroProblem('Could not read the Xero organisations (${r.statusCode}).');
      final orgs = [for (final o in jsonDecode(r.body) as List) if ((o['tenantType'] ?? 'ORGANISATION') == 'ORGANISATION') o as Map<String, dynamic>];
      if (orgs.isEmpty) throw XeroProblem('No Xero organisation was allowed -- tick Nanini when Xero asks.');
      final org = orgs.firstWhere((o) => '${o['tenantName']}'.toLowerCase().contains('nanini'), orElse: () => orgs.first);
      final c = XeroConnection(
        clientId: clientId,
        accessToken: tokens.access,
        refreshToken: tokens.refresh,
        expiresAt: tokens.expires,
        tenantId: org['tenantId'] as String,
        tenantName: org['tenantName'] as String? ?? 'Xero',
      );
      await store.save(c);
      return _conn = c;
    }
    throw XeroProblem('Xero refused the sign-in.');
  }

  /// Opens the sign-in page and waits for Xero to come back to this PC: the
  /// query of the redirect (code and state, or error).
  Future<Map<String, String>> _signInInBrowser(Uri url, Duration timeout) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, kXeroRedirectPort);
    try {
      final got = Completer<Map<String, String>>();
      server.listen((req) async {
        if (req.uri.path != '/callback') {
          req.response.statusCode = 404;
          await req.response.close();
          return;
        }
        final q = req.uri.queryParameters;
        req.response.headers.contentType = ContentType.html;
        req.response.write('<html><body style="font-family:sans-serif;padding:32px">'
            '<h2>${q.containsKey('code') ? 'Signed in to Xero' : 'Not signed in'}</h2>'
            '<p>You can close this window and go back to the Nanini hub.</p></body></html>');
        await req.response.close();
        if (!got.isCompleted) got.complete(q);
      });
      if (!await _open(url)) throw XeroProblem('Could not open the browser for the Xero sign-in.');
      return await got.future.timeout(timeout, onTimeout: () => throw XeroProblem('The Xero sign-in took too long -- try again.'));
    } finally {
      await server.close(force: true);
    }
  }

  Future<({String access, String refresh, DateTime expires})> _token(Map<String, String> form) async {
    final r = await _http.post(Uri.parse(_tokenUrl), headers: {'Content-Type': 'application/x-www-form-urlencoded'}, body: form);
    if (r.statusCode != 200) {
      String why = '${r.statusCode}';
      try {
        why = '${(jsonDecode(r.body) as Map)['error'] ?? why}';
      } catch (_) {}
      if (why == 'invalid_grant') throw XeroProblem('The Xero sign-in has expired -- connect to Xero again.');
      throw XeroProblem('Xero refused the sign-in ($why).');
    }
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    return (
      access: j['access_token'] as String,
      refresh: j['refresh_token'] as String,
      expires: DateTime.now().toUtc().add(Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 1800)),
    );
  }

  Future<XeroConnection> _fresh({bool force = false}) async {
    final c = await connection();
    if (c == null) throw XeroProblem('Not connected to Xero yet.');
    if (!force && c.expiresAt.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 1)))) return c;
    final t = await _token({'grant_type': 'refresh_token', 'client_id': c.clientId, 'refresh_token': c.refreshToken});
    final n = c.withTokens(t.access, t.refresh, t.expires);
    await store.save(n);
    return _conn = n;
  }

  /// A call to Xero's accounting API; the JSON it returns.
  Future<Map<String, dynamic>> call(String method, String path, {Map<String, String>? query, Object? body}) async {
    var c = await _fresh();
    for (var attempt = 0;; attempt++) {
      final uri = Uri.parse('$_api/api.xro/2.0/$path').replace(queryParameters: query);
      final headers = {
        'Authorization': 'Bearer ${c.accessToken}',
        'xero-tenant-id': c.tenantId,
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json',
      };
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      final r = await http.Response.fromStream(await _http.send(req));
      if (r.statusCode == 401 && attempt == 0) {
        c = await _fresh(force: true);
        continue;
      }
      if (r.statusCode == 429 && attempt < 3) {
        final s = int.tryParse(r.headers['retry-after'] ?? '') ?? 5;
        await wait(Duration(seconds: s.clamp(1, 60)));
        continue;
      }
      // Validation errors come back as 400 with each document's errors in the body.
      if (r.statusCode == 200 || (r.statusCode == 400 && r.body.trimLeft().startsWith('{'))) {
        final j = jsonDecode(r.body) as Map<String, dynamic>;
        if (r.statusCode == 200 || j.containsKey('Elements') || j.containsKey('Invoices') || j.containsKey('CreditNotes')) return j;
        throw XeroProblem('Xero: ${j['Message'] ?? j['Detail'] ?? r.statusCode}');
      }
      if (r.statusCode == 403) throw XeroProblem('Xero didn\'t allow this (403) -- connect to Xero again and allow all it asks.');
      throw XeroProblem('Xero answered ${r.statusCode}${r.body.length < 300 ? ': ${r.body}' : ''}');
    }
  }

  /// Xero's tax rates: name -> tax type code (the CSV used the names).
  Future<Map<String, String>> taxTypes() async {
    final j = await call('GET', 'TaxRates');
    return {
      for (final t in (j['TaxRates'] as List? ?? const []))
        if ((t['Status'] ?? 'ACTIVE') == 'ACTIVE') '${t['Name']}': '${t['TaxType']}',
    };
  }

  /// The invoices, bills and credit notes Xero has from [from] (yyyy-MM-dd)
  /// on, not deleted or voided, as [xeroKey]s.
  Future<Set<String>> existingKeys(String from) async {
    final d = from.split('-').map(int.parse).toList();
    final where = 'Date>=DateTime(${d[0]},${d[1]},${d[2]})';
    final out = <String>{};
    for (final (endpoint, numberField) in [('Invoices', 'InvoiceNumber'), ('CreditNotes', 'CreditNoteNumber')]) {
      for (var page = 1;; page++) {
        final j = await call('GET', endpoint, query: {'where': where, 'page': '$page', 'pageSize': '500', if (endpoint == 'Invoices') 'summaryOnly': 'true'});
        final list = (j[endpoint] as List?) ?? const [];
        for (final x in list) {
          final status = '${x['Status']}';
          if (status == 'DELETED' || status == 'VOIDED') continue;
          out.add(xeroKey('${x['Type']}', '${x['Contact']?['Name'] ?? ''}', '${x[numberField] ?? ''}'));
        }
        // Xero gives at least 100 a page (500 asked; some endpoints keep to 100).
        if (list.length < 100) break;
      }
    }
    return out;
  }

  /// Sends [drafts] (50 at a time); what Xero said about each.
  Future<List<XeroResult>> send(List<XeroDraft> drafts) async {
    final out = <XeroResult>[];
    for (final endpoint in ['Invoices', 'CreditNotes']) {
      final these = [for (final d in drafts) if (d.endpoint == endpoint) d];
      for (var i = 0; i < these.length; i += 50) {
        final part = these.sublist(i, min(i + 50, these.length));
        final j = await call('PUT', endpoint, query: {'summarizeErrors': 'false'}, body: {endpoint: [for (final d in part) d.json]});
        final back = (j[endpoint] as List?) ?? (j['Elements'] as List?) ?? const [];
        for (final (k, d) in part.indexed) {
          final x = k < back.length ? back[k] as Map<String, dynamic> : const <String, dynamic>{};
          final errors = [for (final e in (x['ValidationErrors'] as List? ?? const [])) '${e['Message']}'];
          final failed = x.isEmpty || x['StatusAttributeString'] == 'ERROR' || errors.isNotEmpty;
          out.add(XeroResult(d, failed ? (errors.isEmpty ? 'not accepted' : errors.join('; ')) : null));
        }
      }
    }
    return out;
  }
}
