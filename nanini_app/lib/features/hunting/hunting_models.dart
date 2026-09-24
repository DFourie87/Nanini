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

/// One flat rate per night per farm -- accommodation isn't split by guest
/// type the way animal prices are.
class HuntingAccommodationRate {
  HuntingAccommodationRate({required this.id, required this.farmId, required this.pricePerNight});
  final String id;
  final String farmId;
  final double pricePerNight;

  factory HuntingAccommodationRate.fromJson(Map<String, dynamic> j) => HuntingAccommodationRate(
        id: j['id'] as String,
        farmId: j['farm_id'] as String,
        pricePerNight: (j['price_per_night'] as num?)?.toDouble() ?? 0,
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
    this.idOrPassport,
    required this.farmId,
    required this.guestType,
    required this.paymentMethod,
    required this.visitDate,
    required this.createdAt,
  });
  final String id;
  final int? invoiceNumber;
  final String hunterName;
  final String? idOrPassport;
  final String farmId;
  final String guestType; // 'local' | 'international'
  final HuntingPaymentMethod paymentMethod;
  final String visitDate;
  final DateTime createdAt;

  factory HuntingInvoice.fromJson(Map<String, dynamic> j) => HuntingInvoice(
        id: j['id'] as String,
        invoiceNumber: j['invoice_number'] as int?,
        hunterName: j['hunter_name'] as String,
        idOrPassport: j['id_or_passport'] as String?,
        farmId: j['farm_id'] as String,
        guestType: j['guest_type'] as String,
        paymentMethod: huntingPaymentMethodFromString(j['payment_method'] as String?),
        visitDate: j['visit_date'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

/// One hunted animal -- always gets its own permit_number, since a
/// transport permit is required per animal, not per invoice.
class HuntingAnimalLine {
  HuntingAnimalLine({
    required this.id,
    required this.invoiceId,
    this.permitNumber,
    required this.species,
    required this.price,
    required this.huntDate,
    required this.createdAt,
  });
  final String id;
  final String invoiceId;
  final int? permitNumber;
  final String species;
  final double price;
  final String huntDate;
  final DateTime createdAt;

  factory HuntingAnimalLine.fromJson(Map<String, dynamic> j) => HuntingAnimalLine(
        id: j['id'] as String,
        invoiceId: j['invoice_id'] as String,
        permitNumber: j['permit_number'] as int?,
        species: j['species'] as String,
        price: (j['price'] as num?)?.toDouble() ?? 0,
        huntDate: j['hunt_date'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

class HuntingAccommodationLine {
  HuntingAccommodationLine({
    required this.id,
    required this.invoiceId,
    required this.nights,
    required this.ratePerNight,
    required this.fromDate,
    required this.createdAt,
  });
  final String id;
  final String invoiceId;
  final double nights;
  final double ratePerNight;
  final String fromDate;
  final DateTime createdAt;

  double get total => nights * ratePerNight;

  factory HuntingAccommodationLine.fromJson(Map<String, dynamic> j) => HuntingAccommodationLine(
        id: j['id'] as String,
        invoiceId: j['invoice_id'] as String,
        nights: (j['nights'] as num?)?.toDouble() ?? 0,
        ratePerNight: (j['rate_per_night'] as num?)?.toDouble() ?? 0,
        fromDate: j['from_date'] as String,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}
