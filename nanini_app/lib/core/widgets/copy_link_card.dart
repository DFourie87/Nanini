import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/nanini_theme.dart';
import '../run_once.dart';

/// Download links for the apps (always the latest build).
const kHubApkUrl = 'https://github.com/DFourie87/Nanini/releases/latest/download/app-release.apk';
const kCaptureApkUrl = 'https://github.com/DFourie87/Nanini/releases/latest/download/nanini-capture.apk';

/// A link shown in full (selectable) with a Copy button, to paste into
/// WhatsApp or a message.
class CopyLinkCard extends StatelessWidget {
  const CopyLinkCard({super.key, required this.url, this.copiedMessage = 'Link copied -- paste it in WhatsApp or a message'});
  final String url;
  final String copiedMessage;

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          leading: const Icon(Icons.link, color: NaniniColors.rust),
          title: SelectableText(url, style: const TextStyle(fontSize: 13)),
          trailing: TextButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copy'),
            onPressed: () => runOnce('copy_link_card.1', () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(copiedMessage)));
            }),
          ),
        ),
      );
}
