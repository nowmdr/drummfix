# DrummFix

<img src="assets/DrummFixIcon.png" width="96" alt="DrummFix icon">

DrummFix fixes the closed hi-hat on an **Alesis Turbo Mesh** kit when playing **GarageBand** on a Mac. When the pedal is held down, the kit sends a hi-hat hit as MIDI note 46. DrummFix uses the pedal's CC4 value to send note 42 for that hit. Open hi-hat hits, pedal-only sounds, and other pads pass through unchanged.

DrummFix runs locally. It needs no account or network access.

## Download

**[Download DrummFix 0.2.2 beta 2 for Apple Silicon (.dmg)](https://github.com/nowmdr/drummfix/releases/download/v0.2.2-beta.2/DrummFix-0.2.2-macOS-arm64.dmg)** · [All releases](https://github.com/nowmdr/drummfix/releases)

Open the `.dmg` and drag `DrummFix.app` into **Applications**. This beta is ad-hoc signed, but **not yet signed with an Apple Developer ID or notarized**. macOS may block its first launch. If you trust the download, try opening it, then use **System Settings → Privacy & Security → Open Anyway**. See [Apple's instructions](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac). You do not need to disable Gatekeeper.

You can also download the disk image with GitHub CLI:

```sh
gh release download v0.2.2-beta.2 -R nowmdr/drummfix -p '*.dmg'
```

Or [build the app from source](#build-from-source). A Homebrew package is not available yet.

## Get started

1. Connect and power on your Alesis Turbo Mesh via USB.
2. Save your GarageBand project and quit GarageBand completely with `⌘Q`.
3. Open DrummFix, select **Alesis Turbo**, and click **Enable fix**.
4. Click **Open GarageBand**. Select a Software Instrument → Drum Kit track and your preferred kit.
5. Keep DrummFix open while playing and recording.

Quick check: an open pedal should produce an open hi-hat; a held-down pedal plus a pad hit should produce a closed hi-hat; pressing the pedal without hitting the pad should keep its normal pedal sound. You can adjust closed hi-hat dynamics with the Original, Moderate, and Strong modes.

For diagnostics, USB reconnection, and restoring the original MIDI route, see the [user guide](docs/USER_GUIDE.md).

If GarageBand tries to use an iPhone microphone, open **GarageBand → Settings → Audio/MIDI** and choose your Mac's built-in microphone under **Input Device**. DrummFix uses MIDI, not microphone audio, and does not change GarageBand's audio input. [Apple's GarageBand troubleshooting guide](https://support.apple.com/en-gb/102247) describes this input setting.

## Compatibility

- Tested with Alesis Turbo Mesh over USB on a MacBook Pro M1 Pro, macOS 26.6.2, and GarageBand 10.4.14.
- The downloadable build is for **Apple Silicon (arm64)**. Its declared minimum is macOS 14, but macOS 14 has not been tested. Intel Macs have not been tested or packaged.
- Other drum kits and DAWs have not been tested.

DrummFix is an independent utility. It is not affiliated with Alesis or Apple.

## Build from source

Requires macOS 14 or later, Apple Command Line Tools, and Swift 6. Full Xcode is not required.

```sh
git clone https://github.com/nowmdr/drummfix.git
cd drummfix
zsh scripts/build-app.sh
```

The result is `dist/DrummFix.app`. You can copy it into Applications. To make a `.dmg`:

```sh
zsh scripts/package-dmg.sh
```

Run the MIDI checks:

```sh
swift build
.build/debug/DrummFixTests
.build/debug/DrummFixProbe --test-loopback
```

## Help and privacy

If something fails, [open a GitHub issue](https://github.com/nowmdr/drummfix/issues) with your drum-kit model, macOS and GarageBand versions, steps to reproduce, and what you expected versus what happened. Review any saved diagnostic log before sharing it publicly.

The app processes MIDI locally and never uploads your MIDI events or diagnostic log. [Verification notes](docs/VERIFICATION.md) describe what has and has not been tested.

## License

The source code is available under the [MIT License](LICENSE).
