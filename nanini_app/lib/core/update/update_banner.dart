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
    // A download started earlier keeps going (Android downloads it); pick
    // up its progress, or install it if it finished while away.
    appUpdater?.resume();
    if (widget.enabled) appUpdater?.check();
  }

  @override
  void didUpdateWidget(UpdateBanner old) {
    super.didUpdateWidget(old);
    if (widget.enabled && !old.enabled) appUpdater?.check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    appUpdater?.resume();
    if (widget.enabled) appUpdater?.check();
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
        final ready = u.readyPath != null && !u.downloading;
        if (!(u.available && widget.enabled) && !u.downloading && !ready) return const SizedBox.shrink();
        // One slim red line (with a thin bar while downloading), not a card.
        const red = NaniniColors.red;
        const small = TextStyle(fontSize: 12, color: red);
        return Padding(
          padding: widget.padding,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.system_update, size: 20, color: red),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      u.downloading
                          ? 'Downloading update… ${((u.progress ?? 0) * 100).round()}%'
                          : ready
                              ? 'Update downloaded'
                              : 'New version available',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: red),
                    ),
                  ),
                  if (!u.downloading)
                    TextButton(
                      onPressed: u.install,
                      style: TextButton.styleFrom(foregroundColor: red, visualDensity: VisualDensity.compact),
                      child: Text(ready ? 'INSTALL' : 'UPDATE', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ),
                ],
              ),
              if (u.downloading)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(value: u.progress, color: red, backgroundColor: NaniniColors.line, minHeight: 3),
                  ),
                ),
              if (u.downloading && u.note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(u.note!, style: small)),
              if (u.error != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(u.error!, style: small)),
            ],
          ),
        );
      },
    );
  }
}
