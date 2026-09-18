import 'package:flutter/material.dart';
import '../../theme/nanini_theme.dart';

void showToast(BuildContext context, String message, {bool isError = false}) {
  ScaffoldMessenger.of(context).hideCurrentSnackBar();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? NaniniColors.red : NaniniColors.ink,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 2, milliseconds: 200),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}
