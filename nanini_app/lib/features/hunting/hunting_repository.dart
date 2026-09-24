import '../../core/supabase_client.dart';
import 'hunting_models.dart';

class HuntingRepository {
  Stream<List<HuntingPriceEntry>> watchPriceList() =>
      sb.from('hunting_price_list').stream(primaryKey: ['id']).order('species').map((r) => r.map(HuntingPriceEntry.fromJson).toList());

  Future<void> upsertPrice({required String farmId, required String species, required String guestType, required double price}) =>
      sb.from('hunting_price_list').upsert(
        {'farm_id': farmId, 'species': species, 'guest_type': guestType, 'price': price},
        onConflict: 'farm_id,species,guest_type',
      );

  Future<void> deletePrice(String id) => sb.from('hunting_price_list').delete().eq('id', id);

  Stream<List<HuntingAccommodationRate>> watchAccommodationRates() =>
      sb.from('hunting_accommodation_rates').stream(primaryKey: ['id']).map((r) => r.map(HuntingAccommodationRate.fromJson).toList());

  Future<void> setAccommodationRate({required String farmId, required double hunterRate, required double nonHunterRate}) => sb
      .from('hunting_accommodation_rates')
      .upsert({'farm_id': farmId, 'hunter_rate': hunterRate, 'non_hunter_rate': nonHunterRate}, onConflict: 'farm_id');

  Stream<List<HuntingInvoice>> watchInvoices() =>
      sb.from('hunting_invoices').stream(primaryKey: ['id']).order('created_at').map((r) => r.map(HuntingInvoice.fromJson).toList());

  Stream<List<HuntingAnimalLine>> watchAnimalLines() =>
      sb.from('hunting_animal_lines').stream(primaryKey: ['id']).order('created_at').map((r) => r.map(HuntingAnimalLine.fromJson).toList());

  Stream<List<HuntingAccommodationLine>> watchAccommodationLines() => sb
      .from('hunting_accommodation_lines')
      .stream(primaryKey: ['id'])
      .order('created_at')
      .map((r) => r.map(HuntingAccommodationLine.fromJson).toList());

  Future<int> _nextInvoiceNumber() async {
    final rows = await sb.from('hunting_invoices').select('id');
    return (rows as List).length + 1;
  }

  Future<HuntingInvoice> addInvoice({
    required String hunterName,
    String? idOrPassport,
    required String farmId,
    required String guestType,
    required HuntingPaymentMethod paymentMethod,
    required String visitDate,
  }) async {
    final number = await _nextInvoiceNumber();
    final data = await sb.from('hunting_invoices').insert({
      'invoice_number': number,
      'hunter_name': hunterName,
      'id_or_passport': idOrPassport,
      'farm_id': farmId,
      'guest_type': guestType,
      'payment_method': paymentMethod.name,
      'visit_date': visitDate,
    }).select().single();
    return HuntingInvoice.fromJson(data);
  }

  Future<void> deleteInvoice(String id) => sb.from('hunting_invoices').delete().eq('id', id);

  Future<int> _nextPermitNumber() async {
    final rows = await sb.from('hunting_animal_lines').select('id');
    return (rows as List).length + 1;
  }

  Future<void> addAnimalLine({
    required String invoiceId,
    required String species,
    String? sex,
    double? hornInches,
    required double price,
    required String huntDate,
  }) async {
    final permitNumber = await _nextPermitNumber();
    await sb.from('hunting_animal_lines').insert({
      'invoice_id': invoiceId,
      'permit_number': permitNumber,
      'species': species,
      'sex': sex,
      'horn_inches': hornInches,
      'price': price,
      'hunt_date': huntDate,
    });
  }

  Future<void> deleteAnimalLine(String id) => sb.from('hunting_animal_lines').delete().eq('id', id);

  Future<void> addAccommodationLine({
    required String invoiceId,
    required String personType,
    required double nights,
    required double ratePerNight,
    required String fromDate,
  }) =>
      sb.from('hunting_accommodation_lines').insert({
        'invoice_id': invoiceId,
        'person_type': personType,
        'nights': nights,
        'rate_per_night': ratePerNight,
        'from_date': fromDate,
      });

  Future<void> deleteAccommodationLine(String id) => sb.from('hunting_accommodation_lines').delete().eq('id', id);

  Stream<List<HuntingBooking>> watchBookings() =>
      sb.from('hunting_bookings').stream(primaryKey: ['id']).order('from_date').map((r) => r.map(HuntingBooking.fromJson).toList());

  Future<void> addBooking({
    required String hunterName,
    String? idOrPassport,
    required String farmId,
    required String guestType,
    required String fromDate,
    required String toDate,
    String? phone,
    String? email,
    String? notes,
  }) =>
      sb.from('hunting_bookings').insert({
        'hunter_name': hunterName,
        'id_or_passport': idOrPassport,
        'farm_id': farmId,
        'guest_type': guestType,
        'from_date': fromDate,
        'to_date': toDate,
        'phone': phone,
        'email': email,
        'notes': notes,
      });

  Future<void> deleteBooking(String id) => sb.from('hunting_bookings').delete().eq('id', id);

  Future<void> markBookingConverted(String id) => sb.from('hunting_bookings').update({'converted': true}).eq('id', id);

  Stream<List<HuntingHornPriceBand>> watchHornBands() => sb
      .from('hunting_horn_price_bands')
      .stream(primaryKey: ['id'])
      .order('min_inches')
      .map((r) => r.map(HuntingHornPriceBand.fromJson).toList());

  Future<void> addHornBand({
    required String farmId,
    required String species,
    required String guestType,
    required double minInches,
    double? maxInches,
    required double price,
  }) =>
      sb.from('hunting_horn_price_bands').insert({
        'farm_id': farmId,
        'species': species,
        'guest_type': guestType,
        'min_inches': minInches,
        'max_inches': maxInches,
        'price': price,
      });

  Future<void> deleteHornBand(String id) => sb.from('hunting_horn_price_bands').delete().eq('id', id);

  Stream<List<HuntingExemptionCertificate>> watchCertificates() => sb
      .from('hunting_exemption_certificates')
      .stream(primaryKey: ['id'])
      .order('expiry_date')
      .map((r) => r.map(HuntingExemptionCertificate.fromJson).toList());

  Future<void> addCertificate({
    required String farmId,
    String? permitNumber,
    String? issueDate,
    required String expiryDate,
  }) =>
      sb.from('hunting_exemption_certificates').insert({
        'farm_id': farmId,
        'permit_number': permitNumber,
        'issue_date': issueDate,
        'expiry_date': expiryDate,
      });

  Future<void> deleteCertificate(String id) => sb.from('hunting_exemption_certificates').delete().eq('id', id);
}
