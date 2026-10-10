# DrummFix verification

Hardware check: Alesis Turbo Mesh via USB, MacBook Pro M1 Pro, macOS 26.6.2, GarageBand 10.4.14. The user confirmed that holding the pedal and striking the hi-hat produces the correct closed sound in GarageBand. A GarageBand recording showed closed note 42 and open note 46, with different recorded velocities on closed hits (64, 41, and 48 in the inspected passage). How audible those differences are depends on the selected GarageBand kit.

The following checks passed for the 0.2.1 MIDI implementation:

- Seven transformation scenarios cover open/closed hi-hat, pedal changes between Note On and Note Off, zero-velocity Note On, repeated hits, other pads/channels/Aftertouch/SysEx, unknown state and UMP groups, and dynamics curves.
- A CoreMIDI loopback covered input callback, conversion, virtual output, event contents, and timestamps. Silence test emitted no fixture events; a 1,024-word packet was not truncated.
- The real Alesis input was hidden while the fix ran and visible again afterward. A separate DrummFixGuard process restored it after a forced `SIGKILL` of the main process.
- Release-build tests and `codesign --verify --deep --strict` passed. A synthetic release-loopback run measured mean callback processing at 0.024 ms and max at 0.050 ms. This is not end-to-end audio latency.
- The user's live playing produced more than 100 corrected hits. The observed trace contained CC4/127 and paired Note On/Off conversions 46 → 42, while other pad notes passed through unchanged.

Version 0.2.2 changes English UI strings and public documentation; the MIDI transformation itself is unchanged. Its build, automated MIDI checks, disk-image integrity, and local app launch were verified on the same Mac.

Still to test on separate hardware: clean installation and Gatekeeper flow; macOS 14; USB unplug/replug and sleep/wake with GarageBand; Intel support; other kits and DAWs. A passing loopback test does not establish those behaviors.

On 10 October 2026, GarageBand's saved **Input Device** was a parenthesized “(MacBook Pro Microphone)” entry, distinct from the plain **MacBook Pro Microphone** entry. The Mac's system default input was also the built-in microphone. The plain entry was explicitly selected in GarageBand → Settings → Audio/MIDI. After quitting and reopening GarageBand from an active DrummFix session, the setting still displayed **MacBook Pro Microphone** without parentheses. The iPhone-side connection prompt was not directly observable in this verification. DrummFix only opens GarageBand via `NSWorkspace` and does not access Core Audio input settings.
