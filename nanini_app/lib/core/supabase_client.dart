import 'package:supabase_flutter/supabase_flutter.dart';

/// The publishable (anon) key is safe client-side: on its own it opens
/// nothing. Tables need a logged-in, active Nanini user and capture phones
/// only get the capture_* functions -- see docs/sql/lockdown_*.sql.
const String kSupabaseUrl = 'https://nwyizwccmyanbdjmmdds.supabase.co';
const String kSupabaseAnonKey = 'sb_publishable_rJTMVGBh4FleAEBrDPWQzw_QC7c2dxV';

Future<void> initSupabase() async {
  await Supabase.initialize(url: kSupabaseUrl, publishableKey: kSupabaseAnonKey);
}

SupabaseClient get sb => Supabase.instance.client;
