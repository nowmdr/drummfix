# DrummFix user guide

DrummFix converts a hi-hat pad hit from MIDI note 46 to 42 when the Alesis Turbo Mesh pedal reports a closed position. Pedal-only sounds and all other pads remain unchanged. The **Original** dynamics mode preserves the incoming hit velocity; **Moderate** and **Strong** raise softer closed-hi-hat velocities only. Your choice is saved.

## Start playing

1. Power on the Alesis Turbo Mesh and connect it to your Mac via USB.
2. Save your project and quit GarageBand completely with `⌘Q`.
3. Open DrummFix from Applications, select Alesis Turbo, and click **Enable fix**.
4. Click **Open GarageBand**. Select a Software Instrument → Drum Kit track, such as Sunset or Smash.
5. Keep DrummFix open during play and recording.

GarageBand's **Input Device** setting is for audio, so you do not need to change it. You also do not need to change **MIDI Controller**.

## One-minute check

- With the pedal released, hit the hi-hat pad three times. It should sound open.
- Hold the pedal down and hit the pad five times. It should sound closed; **Corrected hits** should increase by five.
- Release the pedal and hit the pad again. It should sound open.
- Press the pedal without hitting the pad. Its short closing sound should remain normal.
- Expand **Diagnostics and tests**, click **Silence test**, and hit a few pads. GarageBand should be silent. Click **Restore sound** when finished.
- Record a short passage in GarageBand and play it back to confirm the closed hits were recorded.

If you still hear drums during Silence test, GarageBand may be receiving the original MIDI input as well. Quit GarageBand, keep DrummFix enabled, reopen GarageBand, and test again. Listen to the Mac's audio output rather than the Alesis module.

## Dynamics and diagnostics

The pedal indicator shows the last state received from the kit. The Turbo Mesh may send its release state only with the next pad hit, so the indicator can briefly remain **Closed** after your foot leaves the pedal.

The **Open**, **Closed**, and **Pedal** test buttons send notes 46, 42, and 44 to GarageBand. **Soft (20)** and **Hard (110)** send closed note 42 at different velocities, without applying DrummFix's dynamics curve. If those two buttons sound alike, try another GarageBand Drum Kit; some kits may respond less noticeably to this note's velocity. If they differ, compare Original, Moderate, and Strong while playing.

**Save log…** exports the latest 240 MIDI events, input/output notes, and processing statistics. The processing time shown in the window excludes GarageBand and audio-output latency. DrummFix does not upload the log.

## Stop, unplug, and recover

Click **Turn off** or close the window to stop the fix and restore visibility of the original MIDI input. Restart GarageBand if you want to play directly through the kit after stopping DrummFix.

After USB disconnection or Mac sleep, DrummFix waits for the kit. Quit GarageBand before resuming. When the Alesis kit is available, DrummFix restores the route automatically; reopen GarageBand afterward. This prevents GarageBand from attaching to the unmodified input during reconnection.

DrummFix temporarily hides only the selected original MIDI source so GarageBand does not receive both raw and corrected hits. A separate DrummFixGuard process restores that source if the main app crashes. Before modifying the source, DrummFix saves its prior state in `~/Library/Application Support/DrummFix/recovery.json`. If the kit was absent during recovery, reconnect it and restart DrummFix. Do not manually delete `recovery.json` before recovery completes.

## Build and test

Apple Command Line Tools, Swift 6, and macOS 14 or later are required. Run `zsh scripts/build-app.sh` from the repository root. The result is `dist/DrummFix.app`; it is ad-hoc signed and not notarized.

Run `swift build`, `.build/debug/DrummFixTests`, and `.build/debug/DrummFixProbe --test-loopback` for source-level checks. The loopback check uses a temporary virtual MIDI source; it does not play sound through the physical drums.

Back to the [project page](../README.md).
