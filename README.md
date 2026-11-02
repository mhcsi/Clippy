# Clippy

**A lightweight macOS clipboard history for quickly finding and reusing copied text and images, with a glass interface that follows system Light/Dark mode and quick paste shortcuts.**

Clippy saves each copied text snippet and picture locally while it runs. Instead of switching between apps to recopy details—or losing an earlier item when you copy something new—open Clippy, search your history, and restore what you need with one click.

## Why it saves time

Copy an email, a customer name, and a screenshot from one app. Then switch to another app and retrieve each item from Clippy’s history without returning to the original source. Search narrows the list as you type, and image thumbnails make pictures easy to recognize before pasting.

## Features

- Automatically saves copied text and images while Clippy is running.
- Keeps history between app restarts, stored locally on your Mac.
- Searches entries and groups them by day.
- Shows image previews and readable text snippets.
- Copies any selected item back to the system clipboard with one click.
- Right-click a history item to delete it or pin one item to the top and to **⌘⌥2**.
- Clear the full history from the top-right filter menu.
- Opens and closes from anywhere with **⌘⇧V**.
- Uses **⌘⌥2** for the pinned item, or the 2nd newest item when nothing is pinned. **⌘⌥3** through **⌘⌥9** paste the correspondingly numbered newest items. Quick paste restores the newest item to the clipboard so regular **⌘V** continues to paste it.
- Matches the macOS Light or Dark appearance setting while keeping the translucent glass interface.
- Avoids consecutive duplicate entries.

## Recent updates

- Added per-item context actions to delete a clip or pin it. A pinned clip stays at the top of the history and is assigned to **⌘⌥2**; without a pin, that shortcut pastes the second newest clip.
- Fixed quick paste so restoring an older item does not replace the newest clip used by regular **⌘V**. **⌘⌥3–9** continue to paste the correspondingly ranked recent items.
- Added a clear-history action to the filter menu and improved the translucent scrollbar to match the glass window.

## Build and run

Requires macOS 13 or newer, Swift 6, and Xcode Command Line Tools.

```sh
./Scripts/build-app.sh
open dist/Clippy.app
```

If SwiftPM chooses an incompatible SDK, set `MACOS_SDK_PATH` to the macOS SDK for your active Swift toolchain before running the build script.

History is stored at `~/Library/Application Support/ClipHistory/history.json`. macOS asks for pasteboard access the first time Clippy reads copied content; allow it for automatic capture to work. To use **⌘⌥2–9** for pasting directly into another app, allow Clippy under **System Settings → Privacy & Security → Accessibility**. Clippy only monitors while running, records plain text and images, and does not preserve rich-text formatting or sync to the cloud.
