const kGuestTypes = ['local', 'international'];

String guestTypeLabel(String g) => g == 'international' ? 'International' : 'Local';

enum HuntingPaymentMethod { eft, cash }

HuntingPaymentMethod huntingPaymentMethodFromString(String? s) => s == 'eft' ? HuntingPaymentMethod.eft : HuntingPaymentMethod.cash;

/// Price for one species, for one guest type, at one farm -- looked up when
/// adding an animal to an invoice and prefilled (but still editable) there.
class HuntingPriceEntry {
  HuntingPriceEntry({required this.id, required this.farmId, required this.species, required this.guestType, required this.price});
  final String id;
  final String farmId;
  final String species;
  final String guestType; // 'local' | 'international'
  final double price;

  factory HuntingPriceEntry.fromJson(Map<String, dynamic> j) => HuntingPriceEntry(
        id: j['id'] as String,
        farmId: j['farm_id'] as String,
        species: j['species'] as String,
        guestType: j['guest_type'] as String,
        price: (j['price'] as num?)?.toDouble() ?? 0,
      );
}

/// Two flat rates per night per farm -- one for the hunter themselves, one
/// for a non-hunter (e.g. a spouse along for the trip). Not split by guest
/// type the way animal prices are (there's no international accommodation).
class HuntingAccommodationRate {
  HuntingAccommodationRate({required this.id, required this.farmId, required this.hunterRate, required this.nonHunterRate});
  final String id;
  final String farmId;
  final double hunterRate;
  final double nonHunterRate;

  factory HuntingAccommodationRate.fromJson(Map<String, dynamic> j) => HuntingAccommodationRate(
        id: j['id'] as String,
        farmId: j['farm_id'] as String,
        hunterRate: (j['hunter_rate'] as num?)?.toDouble() ?? 0,
        nonHunterRate: (j['non_hunter_rate'] as num?)?.toDouble() ?? 0,
      );
}

/// One hunter's visit -- every animal they hunt and every accommodation
/// charge for them is a line item under this, and it's the unit a single
/// invoice/breakdown is generated for. Each hunter on a shared trip gets
/// their own HuntingInvoice.
class HuntingInvoice {
  HuntingInvoice({
    required this.id,
    this.invoiceNumber,
    required this.hunterName,
    this.firstName,
    this.nickname,
    this.surname,
    this.idOrPassport,
    required this.farmId,
    required this.guestType,
    required this.paymentMethod,
    required this.visitDate,
    this.visitToDate,
    required this.createdAt,
  });
  final String id;
  final int? invoiceNumber;

  /// "First Surname" -- what prints on the invoice and permit. The parts
  /// are kept separately too; older rows (and bookings converted to an
  /// invoice) may only have this combined name.
  final String hunterName;
  final String? firstName;
  final String? nickname;
  final String? surname;
  final String? idOrPassport;
  final String farmId;
  final String guestType; // 'local' | 'international'
  final HuntingPaymentMethod paymentMethod;
  final String visitDate;
  final String? visitToDate;
  final DateTime createdAt;

  String get visitEndDate => visitToDate ?? visitDate;

  factory HuntingInvoice.fromJson(Map<String, dynamic> j) => HuntingInvoice(
        id: j['id'] as String,
        invoiceNumber: j['invoice_number'] as int?,
        hunterName: j['hunter_name'] as String,
        firstName: j['first_name'] as String?,
        nickname: j['nickname'] as String?,
        surname: j['surname'] as String?,
        idOrPassport: j['id_or_passport'] as String?,
        farmId: j['farm_id'] as String,
        guestType: j['guest_type'] as String,
        paymentMethod: huntingPaymentMethodFromString(j['payment_method'] as String?),
        visitDate: j['visit_date'] as String,
        visitToDate: j['visit_to_date'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

/// "12 Oct 2026" or "12 Oct 2026 – 15 Oct 2026" for a multi-day visit.
String visitRangeLabel(HuntingInvoice i, String Function(String?) fmt) =>
    i.visitEndDate == i.visitDate ? fmt(i.visitDate) : '${fmt(i.visitDate)} – ${fmt(i.visitEndDate)}';

/// One hunted animal -- always gets its own permit_number, since a
/// transport permit is required per animal, not per invoice. Horn length is
/// only meaningful for males, where it drives the price via
/// HuntingHornPriceBand instead of the flat HuntingPriceEntry.
class HuntingAnimalLine {
  HuntingAnimalLine({
    required this.id,
    required this.invoiceId,
    this.permitNumber,
    required this.species,
    this.sex,
    this.hornInches,
    required this.price,
    required this.huntDate,
    required this.createdAt,
  });
  final String id;
  final String invoiceId;
  final int? permitNumber;
  final String species;
  final String? sex; // 'male' | 'female'
  final double? hornInches;
  final double price;
  final String huntDate;
  final DateTime createdAt;

  factory HuntingAnimalLine.fromJson(Map<String, dynamic> j) => HuntingAnimalLine(
        id: j['id'] as String,
        invoiceId: j['invoice_id'] as String,
        permitNumber: j['permit_number'] as int?,
        species: j['species'] as String,
        sex: j['sex'] as String?,
        hornInches: (j['horn_inches'] as num?)?.toDouble(),
        price: (j['price'] as num?)?.toDouble() ?? 0,
        huntDate: j['hunt_date'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

/// A price band for male animals of one species -- price depends on horn
/// length (inches) rather than being flat like HuntingPriceEntry. maxInches
/// null means "and up" (no upper bound on this band).
class HuntingHornPriceBand {
  HuntingHornPriceBand({
    required this.id,
    required this.farmId,
    required this.species,
    required this.guestType,
    required this.minInches,
    this.maxInches,
    required this.price,
  });
  final String id;
  final String farmId;
  final String species;
  final String guestType; // 'local' | 'international'
  final double minInches;
  final double? maxInches;
  final double price;

  bool matches(double inches) => inches >= minInches && (maxInches == null || inches <= maxInches!);

  factory HuntingHornPriceBand.fromJson(Map<String, dynamic> j) => HuntingHornPriceBand(
        id: j['id'] as String,
        farmId: j['farm_id'] as String,
        species: j['species'] as String,
        guestType: j['guest_type'] as String,
        minInches: (j['min_inches'] as num?)?.toDouble() ?? 0,
        maxInches: (j['max_inches'] as num?)?.toDouble(),
        price: (j['price'] as num?)?.toDouble() ?? 0,
      );
}

/// A farm's uploaded P3 government exemption certificate -- its permit
/// number auto-fills the transport permit's blank "EXEMPTION PERMIT NUMBER"
/// line, and its expiry date drives the renewal warning shown on opening
/// the Hunting module.
class HuntingExemptionCertificate {
  HuntingExemptionCertificate({
    required this.id,
    required this.farmId,
    this.permitNumber,
    this.issueDate,
    required this.expiryDate,
    required this.createdAt,
  });
  final String id;
  final String farmId;
  final String? permitNumber;
  final String? issueDate;
  final String expiryDate;
  final DateTime createdAt;

  factory HuntingExemptionCertificate.fromJson(Map<String, dynamic> j) => HuntingExemptionCertificate(
        id: j['id'] as String,
        farmId: j['farm_id'] as String,
        permitNumber: j['permit_number'] as String?,
        issueDate: j['issue_date'] as String?,
        expiryDate: j['expiry_date'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

/// A pre-visit reservation -- tracked separately from HuntingInvoice since a
/// booking exists before anything is billed. Once the hunter arrives and the
/// visit is actually invoiced, the booking is marked converted (kept for
/// history rather than deleted) and drops out of the active list.
class HuntingBooking {
  HuntingBooking({
    required this.id,
    required this.hunterName,
    this.idOrPassport,
    required this.farmId,
    required this.guestType,
    required this.fromDate,
    required this.toDate,
    this.phone,
    this.email,
    this.notes,
    required this.converted,
    required this.createdAt,
  });
  final String id;
  final String hunterName;
  final String? idOrPassport;
  final String farmId;
  final String guestType; // 'local' | 'international'
  final String fromDate;
  final String toDate;
  final String? phone;
  final String? email;
  final String? notes;
  final bool converted;
  final DateTime createdAt;

  factory HuntingBooking.fromJson(Map<String, dynamic> j) => HuntingBooking(
        id: j['id'] as String,
        hunterName: j['hunter_name'] as String,
        idOrPassport: j['id_or_passport'] as String?,
        farmId: j['farm_id'] as String,
        guestType: j['guest_type'] as String,
        fromDate: j['from_date'] as String,
        toDate: j['to_date'] as String,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        notes: j['notes'] as String?,
        converted: j['converted'] as bool? ?? false,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

/// personType records who this charge is for -- the hunter themselves or a
/// non-hunter companion (e.g. a spouse) -- since they're billed at
/// different rates (see HuntingAccommodationRate). Both can appear as
/// separate lines under the same invoice, since the invoice covers "all of
/// [the hunter's] expenses" including a companion's stay.
class HuntingAccommodationLine {
  HuntingAccommodationLine({
    required this.id,
    required this.invoiceId,
    required this.personType,
    required this.nights,
    required this.ratePerNight,
    required this.fromDate,
    required this.createdAt,
  });
  final String id;
  final String invoiceId;
  final String personType; // 'hunter' | 'non_hunter'
  final double nights;
  final double ratePerNight;
  final String fromDate;
  final DateTime createdAt;

  double get total => nights * ratePerNight;

  factory HuntingAccommodationLine.fromJson(Map<String, dynamic> j) => HuntingAccommodationLine(
        id: j['id'] as String,
        invoiceId: j['invoice_id'] as String,
        personType: j['person_type'] as String? ?? 'hunter',
        nights: (j['nights'] as num?)?.toDouble() ?? 0,
        ratePerNight: (j['rate_per_night'] as num?)?.toDouble() ?? 0,
        fromDate: j['from_date'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

/// One row of the price list laid out like the farm's printed "Jagpryse"
/// sheet: Spesie / Geslag / Prys / Nota. `species` is blank on a
/// species' second and later rows, as on the sheet.
class PriceSheetRow {
  PriceSheetRow({required this.species, required this.sex, this.price, this.notes = const []});
  final String species;
  final String sex;
  final double? price;
  final List<String> notes;
}

const _sheetOrder = [
  'rooibok', 'vlakvark', 'waterbok', 'gemsbok', 'kudu', 'blouwildebees', 'goue wildebees', 'sebra',
  'kameelperd', 'eland', 'rooihartbees', 'steenbok', 'duiker', 'nyala', 'bosbok',
];
const _ramSpecies = {'rooibok', 'bosbok'};
final _suffix = RegExp(r'\s*\((bull|cow|knypkop)\)\s*$', caseSensitive: false);

String _money(double v) {
  final whole = v.round().toString();
  final grouped = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
  return 'R $grouped';
}

/// Rebuilds the sheet layout from how prices are stored: flat entries
/// (plain species = female/either-sex price; "(Bull)", "(Cow)",
/// "(Knypkop)" suffixes for sex-specific flat prices) plus horn-length
/// bands for males, where the 0" band is the base price and the rest
/// become the "≥N\" Rx" notes.
List<PriceSheetRow> buildPriceSheetRows(List<HuntingPriceEntry> prices, List<HuntingHornPriceBand> bands) {
  final names = <String, String>{};
  for (final p in prices) {
    final base = p.species.replaceAll(_suffix, '').trim();
    names.putIfAbsent(base.toLowerCase(), () => base);
  }
  for (final b in bands) {
    names.putIfAbsent(b.species.trim().toLowerCase(), () => b.species.trim());
  }
  final keys = names.keys.toList()
    ..sort((a, b) {
      final ia = _sheetOrder.indexOf(a);
      final ib = _sheetOrder.indexOf(b);
      if (ia >= 0 && ib >= 0) return ia.compareTo(ib);
      if (ia >= 0) return -1;
      if (ib >= 0) return 1;
      return a.compareTo(b);
    });

  final rows = <PriceSheetRow>[];
  for (final key in keys) {
    final name = names[key]!;
    final isRam = _ramSpecies.contains(key);
    final male = isRam ? 'Ram' : 'Bul';
    final female = isRam ? 'Ooi' : 'Koei';
    HuntingPriceEntry? flat(String? suffix) {
      final target = suffix == null ? key : '$key ($suffix)';
      final match = prices.where((p) => p.species.trim().toLowerCase() == target);
      return match.isEmpty ? null : match.first;
    }

    final plain = flat(null);
    final bull = flat('bull');
    final cow = flat('cow');
    final knypkop = flat('knypkop');
    final speciesBands = bands.where((b) => b.species.trim().toLowerCase() == key).toList()
      ..sort((a, b) => a.minInches.compareTo(b.minInches));
    final baseBand = speciesBands.where((b) => b.minInches <= 0);
    final basePrice = baseBand.isEmpty ? null : baseBand.first.price;
    final notes = [
      for (final b in speciesBands)
        if (b.minInches > 0) '≥${b.minInches.toStringAsFixed(0)}" ${_money(b.price)}',
    ];

    final speciesRows = <PriceSheetRow>[];
    var plainUsed = false;
    if (speciesBands.isNotEmpty) {
      // Same flat and base price with bands = one row covering both sexes
      // (e.g. Steenbok "Albei R5 000 ≥4'"), or a ram-only species.
      if (plain != null && plain.price == basePrice) {
        speciesRows.add(PriceSheetRow(species: name, sex: isRam ? male : 'Albei', price: basePrice, notes: notes));
        plainUsed = true;
      } else {
        speciesRows.add(PriceSheetRow(species: name, sex: male, price: basePrice, notes: notes));
      }
    } else if (bull != null) {
      speciesRows.add(PriceSheetRow(species: name, sex: male, price: bull.price));
    }
    if (knypkop != null) speciesRows.add(PriceSheetRow(species: name, sex: 'Knypkop', price: knypkop.price));
    if (cow != null) speciesRows.add(PriceSheetRow(species: name, sex: female, price: cow.price));
    if (plain != null && !plainUsed) {
      final hasMaleRow = speciesBands.isNotEmpty || bull != null;
      speciesRows.add(PriceSheetRow(species: name, sex: hasMaleRow ? female : 'Albei', price: plain.price));
    }

    for (var i = 0; i < speciesRows.length; i++) {
      final r = speciesRows[i];
      rows.add(i == 0 ? r : PriceSheetRow(species: '', sex: r.sex, price: r.price, notes: r.notes));
    }
  }
  return rows;
}

/// "Kameelperd (Bull)" -> "Kameelperd": the species as it should read on
/// the permit, without the price-list sex suffix.
String animalSpeciesName(String species) => species.replaceAll(_suffix, '').trim();

/// Male/Female for the permit -- a "(Bull)"/"(Cow)"/"(Knypkop)" price-list
/// entry decides it outright, otherwise the sex recorded on the animal.
String animalGenderLabel(HuntingAnimalLine a) {
  final s = a.species.toLowerCase();
  if (s.endsWith('(bull)') || s.endsWith('(knypkop)')) return 'Male';
  if (s.endsWith('(cow)')) return 'Female';
  return switch (a.sex) {
    'male' => 'Male',
    'female' => 'Female',
    _ => '',
  };
}
