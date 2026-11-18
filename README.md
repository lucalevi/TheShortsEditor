# Shorts Editor

A native macOS video editor made for YouTube Shorts: iMovie's calm, simple way of working, with the
features that make a good Short (captions from your voice, titles and stickers, music that fits,
transitions, effects, one-click styles and templates). Everything runs on your Mac; nothing is
uploaded.

## Download

Get the newest `.dmg` from [Releases](https://github.com/lucalevi/TheShortsEditor/releases/latest).
It needs a Mac with Apple silicon (M1 or later) and **macOS 26** or later.

### Opening it the first time

Shorts Editor is free and isn't signed with a paid Apple developer account, so macOS warns you the
first time you open it ("Apple could not verify…"). To open it anyway:

1. Open the `.dmg` and drag **Shorts Editor** onto **Applications**.
2. Double-click Shorts Editor in your Applications folder. When macOS says it could not verify the
   app, click **Done** (not Move to Trash).
3. Open **System Settings ▸ Privacy & Security**, scroll down to Security and click **Open Anyway**
   next to "Shorts Editor" was blocked…, then enter your Mac's password.
4. Click **Open Anyway** once more. From then on it opens like any other app.

Or, in Terminal, after step 1: `xattr -dr com.apple.quarantine "/Applications/Shorts Editor.app"`.

You do this once for each version you download. After an update macOS may ask again for the
microphone (voice-overs), Photos or speech recognition (captions). Each release lists the file's
SHA-256 if you want to check your download: `shasum -a 256 Shorts-Editor-*.dmg`.

**Updates:** Shorts Editor ▸ Check for Updates… asks GitHub whether there is a newer version and
takes you to it. The app never checks by itself.

## Building it yourself

Xcode 27+, XcodeGen and SwiftLint (`brew install xcodegen swiftlint`), then `make run`. `make help`
lists everything else; `CLAUDE.md` describes the code. `make release` builds the `.dmg` into
`build/dist`.

## License

Free to use, change and remix for any **non-commercial** purpose, under the
[PolyForm Noncommercial License 1.0.0](LICENSE). Commercial use of the software
or of anything based on it is not allowed.

Credit is appreciated but not required. Copies you share must keep the license
text (or a link to it) and the Required Notice in `LICENSE`.
