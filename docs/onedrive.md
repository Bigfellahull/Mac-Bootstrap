# OneDrive access from the Air

The work mini profile installs [Microsoft OneDrive through Homebrew](https://formulae.brew.sh/cask/onedrive).
The Air can use macOS File Sharing to access files held on the work mini.
Bootstrap verifies the application installation; sign-in, sync selection,
sharing permissions and Air connections remain manual.

## Set up the work mini

1. Run `bin/mac apply work-mini`, then open OneDrive and sign in with the work
   account. Complete its permission prompts and choose the folders to sync.
2. In Finder, select the OneDrive folder or subfolders intended for sharing and
   choose **Always Keep on This Device**. Allow downloads to finish and confirm
   OneDrive reports that synchronisation is complete. Allow enough disk space
   for these files.
3. Open **System Settings > General > Sharing**, then the information button
   beside **File Sharing**. Add the intended OneDrive folder to **Shared Folders**
   and enable File Sharing. Under **Options**, enable **Share files and folders
   using SMB**.
4. Grant the intended macOS account **Read Only**, or **Read & Write** if the Air
   needs to edit files. Set **Everyone** to **No Access** and leave guest access
   disabled for this share. Review the other shared folders before connecting.

Use the folder opened by OneDrive in Finder; its location and name depend on
the account. Keep that path and all account details outside the repository.
See Apple's [File Sharing](https://support.apple.com/en-gb/guide/mac-help/mh17131/mac)
and [SMB setup](https://support.apple.com/en-gb/guide/mac-help/mh14107/mac) instructions.

OneDrive uses macOS File Provider and Files On-Demand. Pinning files downloads
their contents, but does not establish that a particular macOS and OneDrive
combination will serve them correctly over SMB. Test the share before relying
on it; do not assume that opening an online-only placeholder from the Air will
trigger a download. See Microsoft's [Files On-Demand guidance](https://support.microsoft.com/en-us/onedrive/fix-onedrive-files-on-demand-issues-on-macos-12-1-or-later).

## Connect from the Air

1. In Finder, choose **Go > Connect to Server** (`Command-K`). Enter
   `smb://work-mini.TAILNET.ts.net`, replacing the placeholder with the work
   mini's full Tailscale DNS name. Both Macs must be connected to Tailscale and
   its access rules must permit SMB. On the LAN, the address shown in the mini's
   File Sharing settings is another option. The SSH alias `work-mini` does not
   configure Finder connections.
2. Connect as a **Registered User** with the macOS credentials authorised on the
   work mini, then select the share. These are macOS credentials, not the
   Microsoft account used by OneDrive.
3. Open a downloaded file. If write access is enabled, create and edit a
   disposable test file from the Air and confirm it appears in OneDrive on the
   web. Make a web edit and check that it reaches the Air after the mini syncs.
   Remove the test file when finished.

The mini must be awake and reachable for SMB access. OneDrive must be running
in its signed-in macOS session for cloud changes to sync. After a restart,
complete FileVault unlock and user login, then check syncing and reconnect the
share. The Air does not receive an offline OneDrive copy through this setup.

If the downloaded files cannot be served reliably, use OneDrive on the web
from the Air or consider a separate OneDrive installation there. Bootstrap does
not grant broad disk access or alter File Provider storage to make sharing work.
