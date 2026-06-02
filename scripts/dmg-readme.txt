Open Multiplayer Server Manager — Install

1. Drag “Open Multiplayer — Server Manager.app” onto the Applications folder.
2. Eject this disk image.
3. Open it from Applications.


If macOS blocks it ("damaged" or "unidentified developer")
-----------------------------------------------------------
The app is safe — it just isn't notarized. Do ONE of these:

• Right-click the app in Applications → Open → Open.

• System Settings → Privacy & Security → "Open Anyway".

• Terminal:
    xattr -dr com.apple.quarantine "/Applications/Open Multiplayer — Server Manager.app"


Requires Apple Silicon (arm64) and macOS 14+.
