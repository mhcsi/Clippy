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
- Opens and closes from anywhere with **⌘⇧V**.
- Pastes the 2nd through 9th newest history items into the active app with **⌘⌥2** through **⌘⌥9**. Regular **⌘V** continues to paste the latest clipboard item.
- Matches the macOS Light or Dark appearance setting while keeping the translucent glass interface.
- Avoids consecutive duplicate entries.

## Build and run

Requires macOS 13 or newer, Swift 6, and Xcode Command Line Tools.

```sh
./Scripts/build-app.sh
open dist/Clippy.app
```

If SwiftPM chooses an incompatible SDK, set `MACOS_SDK_PATH` to the macOS SDK for your active Swift toolchain before running the build script.

History is stored at `~/Library/Application Support/ClipHistory/history.json`. macOS asks for pasteboard access the first time Clippy reads copied content; allow it for automatic capture to work. To use **⌘⌥2–9** for pasting directly into another app, allow Clippy under **System Settings → Privacy & Security → Accessibility**. Clippy only monitors while running, records plain text and images, and does not preserve rich-text formatting or sync to the cloud.
