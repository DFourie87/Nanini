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

## On a Windows PC (the office)

The hub also runs as a program on a Windows PC -- the same app, logins and
data as on the phone (the Capture app is for phones only).

1. Download **https://github.com/DFourie87/Nanini/releases/latest/download/nanini-hub-windows.zip**
2. Right-click the zip > **Extract All...** and pick a folder to keep it in,
   e.g. `C:\Nanini Hub` (not the Downloads folder, which gets cleaned out).
3. In that folder, double-click **nanini_app.exe**. Windows may warn
   "Windows protected your PC" (the program isn't signed): click
   **More info > Run anyway**. The first time only.
4. Log in with your username and PIN.
5. For a shortcut: right-click `nanini_app.exe` > **Show more options >
   Send to > Desktop (create shortcut)**.

**Updating:** the PC version doesn't update itself. Close it, download the
zip again and extract it over the same folder (replace the files).

If it doesn't start ("VCRUNTIME140.dll was not found"), install Microsoft's
Visual C++ Redistributable (x64) once: https://aka.ms/vs/17/release/vc_redist.x64.exe

## For admins

The link is produced automatically by `.github/workflows/build-apk.yml`
every time something is pushed to `main`: it builds the release APK and
publishes it to a GitHub Release tagged `latest`, whose asset URL never
changes even though the file behind it does.
