---
name: start-ztabby
description: Build, launch, and drive the Debug build of Ztabby (this repo's macOS window switcher / app launcher). Use when asked to run, start, rebuild, or interact with the app to confirm a change works.
---

# Start Ztabby (Debug)

Ztabby is a macOS app (window switcher + Spotlight-style app launcher). It has
no test-only entrypoint worth trusting for "does it work" — you must launch the
real app and drive it.

## Build and launch

Two repo-relative scripts do everything; they derive paths from their own
location, so there is nothing to edit per-machine:

```bash
ai/build.sh    # incremental Debug build into ./DerivedData (passes extra args to xcodebuild)
ai/run.sh      # builds, kills any running instance, relaunches with --logs=debug
```

`ai/build.sh` auto-falls back to `/Applications/Xcode.app` when the active
toolchain is only CommandLineTools, so a bare `xcodebuild` env still builds.

## Launch via `open`, never directly — this is the #1 trap

The product is **`Ztabby-Debug.app`** (binary `Ztabby-Debug`, bundle id
`com.dzearing.ztabby.debug`) under
`DerivedData/Build/Products/Debug/`.

Always start it with `open` (which `ai/run.sh` does). If you launch the binary
directly from a shell (`nohup .../Ztabby-Debug`, `&`, etc.) macOS attributes the
Accessibility (TCC) grant to the *terminal*, the app's AX calls time out, and
the window list comes back **empty** — looking exactly like a broken build. It
is not broken; it is mis-launched. `open` is launchd-parented and gets the grant
right.

Debug builds are signed with a local self-signed cert ("Ztabby Debug Signing")
for a stable code identity, so the Accessibility grant survives rebuilds. On a
fresh machine the cert won't exist — regenerate it or sign ad-hoc.

## Drive it (the app is a background agent — LSUIElement, no dock icon)

Interact through its CLI, which talks to the running instance over a message
port. Build a quick alias first:

```bash
ZT=DerivedData/Build/Products/Debug/Ztabby-Debug.app/Contents/MacOS/Ztabby-Debug
"$ZT" --list            # JSON: visible windows (empty => mis-launched, see above)
"$ZT" --detailed-list   # JSON: full per-window metadata
"$ZT" --show=0          # show the window-switcher UI for shortcut index 0
```

To confirm the switcher visually: `"$ZT" --show=0` then
`screencapture -x /tmp/zt.png` and read the screenshot. A populated panel = working.

## Hotkeys

- **Window switcher**: the configured shortcut (default index 0).
- **App launcher** (Spotlight replacement): **⌥Space**. Enabled by default via
  `launcherEnabled`. You cannot synthesize this global hotkey from a sandboxed
  shell (osascript lacks keystroke permission); confirm launcher startup instead
  via the log line `Launcher started; ⌥Space hotkey registered:true`
  (run with `--logs=debug` and grep it).

## Profiling

`ai/profile.sh` records a 20s Time Profiler trace and exports it to XML in /tmp.
