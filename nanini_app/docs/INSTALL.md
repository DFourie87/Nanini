# Installing the Nanini Boerdery app

Send this link to anyone who needs the app on their Android phone:

**https://github.com/DFourie87/Nanini/releases/latest/download/app-release.apk**

This always points at the newest build — no GitHub account needed to open
it, and the link never changes, so it's safe to save as a shortcut or send
once in a group chat.

## On the phone

1. Open the link above (in the browser, WhatsApp, email — anywhere).
2. Android will download the `.apk` file.
3. Tap the downloaded file to install it. The first time, Android will ask
   to allow installs from that app (e.g. Chrome or WhatsApp) — allow it,
   then tap install again.
4. Open "Nanini Boerdery" from the home screen and log in with the
   username/PIN an admin created for you (Hub → Manage users → Add user).

## Updating

To get the latest version later, just open the same link again and install
over the existing app — it updates in place, nothing is lost.

## For admins

The link is produced automatically by `.github/workflows/build-apk.yml`
every time something is pushed to `main`: it builds the release APK and
publishes it to a GitHub Release tagged `latest`, whose asset URL never
changes even though the file behind it does.
