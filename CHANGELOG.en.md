# Changelog

[한국어](CHANGELOG.md)

## 0.2.1

- **Rename shortcut:** Press F2 in a sticky to rename it. Change or turn it off in Settings → Shortcuts.
- **Esc collapses:** Esc used to delete the sticky. It now collapses it.
- **Smaller collapse:** A collapsed sticky also shrinks in width, keeping only the start of the title and the expand button. Expanding restores its full size.
- **Delete with ⌘⌫:** Press ⌘⌫ in a sticky to move it to the Trash after one confirmation (empty stickies aren't asked about).
- **Manage Trash menu:** Opens the Trash directly, right below Manage Stickies in the menu bar.

## 0.2.0

### New

- **Manage Stickies window:** See every note in a list and edit them in one window. Search (with matches highlighted), sorting, hidden stickies used like a notepad, and showing, hiding, or recoloring several notes at once.
- **Trash:** Read and restore deleted stickies from the Trash. It empties itself after 30 days (you can turn this off in Settings). Right after deleting, an Undo notice appears for 6 seconds.
- **Checklists:** ⌘⇧L adds ☐ to a line; click it to check it (☑). Checked lines turn gray with a strikethrough.
- **Links:** Typed or pasted addresses become clickable links. Links that aren't web or mail addresses ask before opening.
- **Find and text size:** ⌘⇧F finds text inside a sticky, and ⌘= / ⌘− change the text size.
- **Alarms:** Snooze for 5 minutes, repeat daily, and get a macOS Notification Center notification. Click anywhere on a ringing sticky to stop it.
- **Lock:** The body of a locked note is now encrypted on disk (the key is in your login keychain). One click on the lock locks or unlocks it, and clicking anywhere on the covered body unlocks it too.
- **Automatic backups:** The last 7 days are backed up once a day. Open them with **File → Show Backups Folder** in the menu bar.
- **Handling stickies:** Stickies snap to screen edges and nearby stickies, ⌘\` / ⌘⇧\` move between stickies, ⌥-clicking the menu-bar icon creates a sticky right away, and a single click on the title of the front sticky edits it.
- **Multiple displays:** New stickies open on the display with the mouse pointer, and stickies left off-screen after unplugging a display move back onto a remaining one.
- **English:** Choose Korean or English in Settings → General; it switches without restarting. The README, user guide, and installation guide are in English too.
- A **Delete Current Sticky** shortcut (⌃⌘⌫) and a **Check for Updates** menu item.
- On first install, a **Getting Started with Floaty** sticky appears.

### Changed

- Settings has a new **General** tab, and the New Sticky tab is merged into the Stickies tab. The menu-bar menu is grouped.
- Color names in the palette menu show a swatch.
- While all stickies are hidden, the menu-bar icon has a dashed outline, and the hidden state survives a restart.
- New installs delete without a confirmation dialog and show an Undo notice instead. Existing settings are kept.
- Empty stickies are deleted without asking.
- Title row buttons are now ordered pin, palette, collapse, trash.
- The app is signed with the hardened runtime.

### Fixed

- Reopening a saved note changed the system font to Helvetica Neue.
- A damaged notes list is no longer overwritten: it is kept aside and the list is restored from the latest backup.
- Launching Floaty twice let both copies overwrite the same files. Now the running copy shows the Manage Stickies window.
- The alarm timer runs only while some note has an alarm, saving power.
- Buttons have names for VoiceOver.

## 0.1.0

First release.
