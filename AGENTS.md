# AGENTS.md

## Cursor Cloud specific instructions

This repo is **幕布 (Cine)** — a single Flutter cross-platform video client. There is no
backend in this repo; the app talks to a hardcoded remote API that is auto-discovered at
startup (see `lib/api/jp_api.dart`). It needs outbound internet to load content/playback.

Standard commands live in `README.md` and `.github/workflows/build.yml`. Notes below are
the non-obvious bits for this cloud VM.

### Environment
- Flutter SDK (stable) is installed at `/opt/flutter` and is on `PATH` via `~/.bashrc`.
  The `flutter pub get` dependency refresh runs automatically on startup.
- Desktop GUI is available on `DISPLAY=:1` (already set for graphical sessions; export it
  if your shell doesn't have it).

### Run (Linux desktop, dev)
- `flutter run -d linux` (debug/hot-reload), or build then launch the bundle:
  `flutter build linux --debug` → run `build/linux/x64/debug/bundle/cine` (set `DISPLAY=:1`).
- Harmless runtime noise in this headless VM: `libEGL ... DRI3` (falls back to software
  rendering), ALSA / `Failed to create AudioController` (no sound card), and a
  `Failed to load window icon` warning. None of these block the UI or playback.

### Lint / Test
- Lint: `flutter analyze` — succeeds but reports ~196 pre-existing info/warning lints
  (no errors). These are not introduced by setup.
- Test: `flutter test`. The only test, `test/widget_test.dart`, currently FAILS due to a
  pre-existing bug: it pumps `MubuApp` directly without initializing the `late`
  `MubuApiClient.instance` (which `main()` sets up), causing a `LateInitializationError`.
  This is a code/test defect, not an environment problem.

### System build deps (already installed in the snapshot)
`clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libmpv-dev mpv` plus
`libstdc++-14-dev` (clang selects GCC 14, whose `libstdc++.so` link needs this `-14-dev`
package — without it the Linux build fails with `cannot find -lstdc++`). If a Linux build
fails with a stale CMake `/usr/local` install-prefix error, run `flutter clean` first.
