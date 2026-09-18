import 'package:supabase_flutter/supabase_flutter.dart';

/// Same Supabase project the existing web app (`Nanini App/`) uses, so both
/// clients read/write the same data in real time. The key is a publishable
/// (anon) key — safe client-side; Postgres Row Level Security is what
/// actually protects the data.
const String kSupabaseUrl = 'https://nwyizwccmyanbdjmmdds.supabase.co';
const String kSupabaseAnonKey = 'sb_publishable_rJTMVGBh4FleAEBrDPWQzw_QC7c2dxV';

Future<void> initSupabase() async {
  await Supabase.initialize(url: kSupabaseUrl, publishableKey: kSupabaseAnonKey);
}

SupabaseClient get sb => Supabase.instance.client;
