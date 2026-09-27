import 'package:flutter/material.dart';
import '../../theme/nanini_theme.dart';
import 'app_updater.dart';

/// "New version available -- UPDATE" card, shown only when there is one.
/// Checks when it first appears and whenever the app comes back to the
/// front. [enabled] false (e.g. the capture phone is off Wi-Fi) hides it and
/// skips the check, so an update never uses mobile data there.
class UpdateBanner extends StatefulWidget {
  const UpdateBanner({super.key, this.enabled = true, this.padding = EdgeInsets.zero});
  final bool enabled;
  final EdgeInsetsGeometry padding;

  @override
  State<UpdateBanner> createState() => _UpdateBannerState();
}

class _UpdateBannerState extends State<UpdateBanner> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.enabled) appUpdater?.check();
  }

  @override
  void didUpdateWidget(UpdateBanner old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !old.enabled) appUpdater?.check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.enabled) appUpdater?.check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final u = appUpdater;
    if (u == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: u,
      builder: (context, _) {
        if (!(u.available && widget.enabled) && !u.downloading) return const SizedBox.shrink();
        return Padding(
          padding: widget.padding,
          child: Card(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: NaniniColors.rust, width: 2)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.system_update, size: 32, color: NaniniColors.rust),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          u.downloading ? 'Downloading update… ${((u.progress ?? 0) * 100).round()}%' : 'New version available',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: NaniniColors.ink),
                        ),
                      ),
                      if (!u.downloading) FilledButton(onPressed: u.install, child: const Text('UPDATE', style: TextStyle(fontWeight: FontWeight.w700))),
                    ],
                  ),
                  if (u.downloading) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: u.progress, color: NaniniColors.rust, backgroundColor: NaniniColors.disabledBg, minHeight: 8),
                  ],
                  if (u.error != null) ...[
                    const SizedBox(height: 6),
                    Text(u.error!, style: const TextStyle(fontSize: 14, color: NaniniColors.red, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
