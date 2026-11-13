# Installation Guide

[← Back to README](../README.en.md) · [한국어 설치 안내](install.md)

## Requirements

- A Mac with Apple silicon (M1 or later). Intel Macs are not supported.
- macOS 13 or later. Developed and tested on macOS 26.

## Installing

1. Download `Floaty-<version>.dmg` (`Floaty.dmg` up to 0.2.1) from [Releases](https://github.com/eddieee-git/mac-app-floaty/releases).
2. Open the dmg and drag Floaty to the Applications folder.
3. Eject the dmg.
4. Open Floaty from the Applications folder.

No Dock icon appears. If a pinned-note icon shows up in the menu bar at the top of the screen, it's running. On first install, a short **Getting Started with Floaty** sticky also appears. Delete it with its trash button when you're done; it won't come back.

## The security warning on first launch

The first time you open Floaty downloaded from the internet, macOS blocks it and shows a warning. The wording depends on the macOS version; it usually says Apple cannot check it for malicious software.

**Why?** By default, macOS blocks apps that aren't signed and notarized through Apple's paid developer program. Floaty is a free project and doesn't have that. The warning doesn't mean a problem was found, but it does mean Apple hasn't checked the app. Only open files from sources you trust. The code is public in this repository, so you can review it and [build it yourself](../README.en.md#build-it-yourself).

### Option 1: Allow it in System Settings

1. Close the warning with **Done** (or **OK**, depending on the version). Don't click **Move to Trash**.
2. Open **System Settings → Privacy & Security**.
3. Scroll down to **Security** and click **Open Anyway** next to the Floaty message.
4. In the confirmation, click **Open Anyway** again and approve with your Mac password or Touch ID.

You only need to do this once. You may need to do it again after installing a new version.

### Option 2: A Terminal command

If you use Terminal, this single command does the same. Run it after moving Floaty to the Applications folder.

```bash
xattr -dr com.apple.quarantine /Applications/Floaty.app
```

It also helps if macOS says the app "is damaged and can't be opened."

## Authentication when unlocking

Unlocking a sticky asks for Touch ID or your Mac login password. macOS handles this directly; Floaty never receives or stores your fingerprint or password.

## Opening at login

Menu bar icon → **Settings…** → **General**, then turn on **Open at login**. Move Floaty to the Applications folder first.

## Updating

Starting with 0.2.1, Floaty checks for a new version once a day and tells you when one is out. You can also check right away with menu bar icon → **Check for Updates…**. Click **Update** to download the new version, replace the app, and restart Floaty.

- The download is installed only after its signature is checked against the developer's signing key. If the signature doesn't match, nothing is installed.
- Because the app downloads the file itself, the security warning and **Open Anyway** don't come back.
- Floaty can update itself only from a folder it can write to, such as Applications.
- If you use locking, the first time you open a locked note after an update macOS may ask about keychain access. Click **Always Allow**.

Turn off automatic checks with **Automatically check for updates** in Settings → General.

To update from 0.2.0 or earlier, or by hand:

1. Quit the app with menu bar icon → **Quit Floaty**.
2. Open the new dmg and drag it to the Applications folder to replace the old app.

Stickies and settings are stored separately from the app, so they stay.

## Moving to another Mac

Quit Floaty, copy this folder, and put it in the same place on the other Mac.

```text
~/Library/Application Support/Floaty
```

This folder contains only your stickies and their automatic backups (`Backups`). Settings such as shortcuts and colors need to be set again on the other Mac.

> [!IMPORTANT]
> Locked notes are encrypted with a key in this Mac's keychain, so they won't open on another Mac. Before moving, choose **Remove Lock** on each locked note, then lock them again afterwards.

## Uninstalling

1. Quit the app with menu bar icon → **Quit Floaty**.
2. Move Floaty from the Applications folder to the Trash.

To delete your stickies as well, run the command below. **All stickies are deleted permanently**, so save anything you need first.

```bash
rm -rf ~/Library/Application\ Support/Floaty
```

To delete the settings too, run:

```bash
defaults delete com.eddieee.Floaty
```

If you ever locked a note, the lock key is still in your keychain. Remove it with the command below. Once it is gone, any remaining locked notes can't be opened, so run it only after deleting your stickies.

```bash
security delete-generic-password -s com.eddieee.Floaty
```
