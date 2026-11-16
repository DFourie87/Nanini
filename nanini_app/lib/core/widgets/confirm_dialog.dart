import 'package:flutter/material.dart';

import 'dialog_error.dart';

Future<bool> confirmDialog(
  BuildContext context, {
  required String message,
  String title = 'Are you sure?',
  String confirmLabel = 'Confirm',
  bool danger = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: copyableMessage(message),
      actions: [
        CopyTextButton('$title\n\n$message'),
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: Colors.red.shade700) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}
