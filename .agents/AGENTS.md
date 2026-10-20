# AGENTS.md — TiViPlayer TV Project Instructions

Welcome to **TiViPlayer TV** (`tv_player_app`), a high-performance, cross-platform IPTV / Live TV player built with Flutter for Android TV, Android Mobile, macOS Desktop, Web, and iOS.

---

## 1. Project Overview & Philosophy

* **Target Experience**: 10-foot TV UI optimized for D-Pad / remote control navigation, while seamlessly responsive for desktop mouse/keyboard and mobile touch screens.
* **Design System**: Premium dark cinematic aesthetic defined in [`lib/ui/theme.dart`](file:///Users/varunkv/Documents/rea/tv_player_app/lib/ui/theme.dart) (`TvTheme`). Avoid generic light/flat styling; preserve glassmorphism, accent glow, and high-contrast focus rings.
* **Stream Resilience**: Robust multi-protocol streaming (HLS `.m3u8`, MPEG-TS, Xtream Codes streams, ClearKey/Widevine DRM) across multi-engine player backends.

---

## 2. Codebase Architecture

```text
tv_player_app/
├── lib/
│   ├── models/            # Data models (Channel, ChannelGroup, Playlist, EpgProgram, RecordingItem)
│   ├── providers/         # Centralized reactive state management (TvStateProvider)
│   ├── services/          # Low-level engines, parsing, databases, hardware & OS bridges:
│   │   ├── database_service.dart        # SQLite schema, migrations, settings, caching
│   │   ├── playlist_parser.dart         # M3U / M3U8 multi-variant parsing
│   │   ├── xtream_service.dart          # Xtream Codes API v2 integration
│   │   ├── epg_parser.dart              # XMLTV gzip/plain parser & timeline scheduler
│   │   ├── stream_recording_service.dart# TS chunked stream capture & disk flusher
│   │   ├── recording_scheduler.dart     # Background timer & recording job manager
│   │   ├── system_pip_service.dart      # Android native Picture-in-Picture bridge
│   │   ├── desktop_pip_service.dart     # macOS windowed always-on-top PiP
│   │   ├── screen_wake_service.dart     # Wakelock / keep-screen-on controller
│   │   ├── app_platform.dart            # Multi-platform capability abstraction
│   │   └── external_player_service.dart # Intent bridge to VLC / MX Player / Just Player
│   ├── ui/
│   │   ├── screens/       # Full-screen views (TvHomeScreen, PlaylistManagerDialog, StreamSettingsDialog, RecordingsScreen)
│   │   ├── widgets/       # Modular UI components:
│   │   │   ├── video_player_widget.dart       # Cross-platform video surface (libmpv, ExoPlayer, Shaka)
│   │   │   ├── player_controls_osd.dart       # On-screen display, channel banner, scrub bar
│   │   │   ├── epg_grid_view.dart             # Horizontal timeline EPG matrix
│   │   │   ├── bottom_channel_scroll_list.dart# Quick channel switcher drawer
│   │   │   └── epg_detail_panel.dart          # Deep-dive program synopsis modal
│   │   └── theme.dart     # Design tokens, color palette, focus borders, typography
│   └── main.dart          # Application bootstrap & dependency injection
├── test/                  # Unit and widget test suite
└── run.sh                 # Universal automation CLI engine
```

---

## 3. Core Development Principles & Constraints

### A. State Persistence & Playback Resume
* Every change in channel, category, playlist, volume, mute state, buffer size, video scaling mode, view mode, and playback speed **must be persisted immediately** via SQLite (`app_settings` table in [`lib/services/database_service.dart`](file:///Users/varunkv/Documents/rea/tv_player_app/lib/services/database_service.dart)).
* **Multi-tier Channel Resolution**: Never rely solely on integer channel IDs across reboots or playlist re-syncs. Always resolve using:
  $$\text{Target Channel} \longrightarrow \text{By ID} \longrightarrow \text{By Stream URL} \longrightarrow \text{By Case-Insensitive Name} \longrightarrow \text{First in Group}$$

### B. Remote / D-Pad Navigation & Back-Stack Hierarchy
* All interactive items (channel cards, settings rows, dialog buttons) must maintain an explicit `FocusNode`.
* Ensure visual focus indication (`TvTheme.focusedBorder` or highlight glow) is always present when focused via TV remote.
* **Back-Key Hierarchy**: TV remotes lack mouse escape gestures. Remote Back / ESC must strictly follow this dismissal hierarchy:
  1. Dismiss active OSD / Player controls $\rightarrow$
  2. Dismiss bottom channel drawer / EPG detail modal $\rightarrow$
  3. Close open dialogs / settings sheets $\rightarrow$
  4. Show exit confirmation dialog (never exit abruptly mid-broadcast).

### C. Cross-Platform Player Backends & Import Isolation
* **macOS Desktop**: Utilizes `media_kit` / `libmpv` with hardware decoding flags and configurable buffer sizes (`bufferSizeBytes`).
* **Android (Mobile & TV)**: Utilizes `video_player` / ExoPlayer supporting hardware acceleration and Widevine DRM licenses.
* **Web**: Utilizes Shaka Player via JavaScript interop for DASH / HLS playback.
* **Import Isolation**: Never import `dart:io` in shared widgets without conditional imports. Route platform checks through [`lib/services/app_platform.dart`](file:///Users/varunkv/Documents/rea/tv_player_app/lib/services/app_platform.dart) and maintain stub patterns (e.g. `shaka_player_stub.dart`).

### D. Async BuildContext & Player Lifecycle Safety
* Video player initialization (`await _player!.open()` or `await controller.initialize()`) introduces async gaps.
* Never call `context.read<TvStateProvider>()` or `Navigator.of(context)` after an `await` without guarding.
* **Rule**: Always cache state values (e.g. `final tvState = context.read<TvStateProvider>()`, volume, speed) **before** async operations, or check `if (!mounted) return;`.

### E. Non-Destructive SQLite Schema Migrations
* When introducing new columns (e.g., for PIN locks, catch-up timestamps, or custom channel ordering), never rely solely on `_createDB`.
* **Rule**: Every new table or column in [`lib/services/database_service.dart`](file:///Users/varunkv/Documents/rea/tv_player_app/lib/services/database_service.dart) must include a safe migration block inside `onOpen`:
  ```dart
  try {
    await db.execute('ALTER TABLE channels ADD COLUMN new_feature TEXT;');
  } catch (_) {}
  ```

### F. Stream Parsing & DRM Data Flow Integrity
* M3U playlists frequently include DRM tags:
  * `#KODIPROP:inputstream.adaptive.license_type=clearkey|widevine`
  * `#KODIPROP:inputstream.adaptive.license_key=...`
* When modifying [`PlaylistParser`](file:///Users/varunkv/Documents/rea/tv_player_app/lib/services/playlist_parser.dart) or [`Channel`](file:///Users/varunkv/Documents/rea/tv_player_app/lib/models/channel.dart), always preserve and propagate `drmType`, `drmLicenseUrl`, and `drmHeaders` directly into [`VideoPlayerWidget`](file:///Users/varunkv/Documents/rea/tv_player_app/lib/ui/widgets/video_player_widget.dart).

### G. Headless Testing Safeguards
* Standard `flutter test` VM runners lack native platform channels (`path_provider`, `wakelock`, `pip`).
* Always guard native platform calls and SQLite initializers with mock fallbacks or safe `try/catch` to guarantee `flutter test` executes cleanly without unhandled exceptions.

---

## 4. Automation & CLI Commands (`run.sh`)

Use the workspace CLI automation script [`./run.sh`](file:///Users/varunkv/Documents/rea/tv_player_app/run.sh) for all tasks:

| Command | Action |
| :--- | :--- |
| `./run.sh` | Launch interactive terminal dashboard |
| `./run.sh run android [debug\|release]` | Run on connected Android TV / emulator |
| `./run.sh run macos [debug\|release]` | Run desktop build via libmpv |
| `./run.sh run web` | Run on Chrome with Shaka Player |
| `./run.sh build apk [release\|debug]` | Build Android APK package |
| `./run.sh build bundle [release]` | Build Android App Bundle (.aab) |
| `./run.sh build macos [release]` | Build macOS Application bundle (.app) and DMG installer (.dmg) |
| `./run.sh build dmg [release]` | Package release `.dmg` installer directly using `hdiutil` |
| `./run.sh build all` | Build Android APK + macOS App & DMG + Web distribution in sequence |
| `./run.sh clean` | Execute `flutter clean && flutter pub get` |
| `./run.sh doctor` | Run Flutter diagnostic checks |

---

## 5. Quality Standards & Verification Checklist

Before completing any task or pull request:
1. **Analyze**: Run `flutter analyze` — must report `0 issues found`.
2. **Test**: Run `flutter test` — all test suites (including persistence and widget smoke tests) must pass.
3. **Format**: Maintain standard Dart formatting (`dart format .`).
4. **Preserve Documentation**: Retain all existing docstrings, explanatory comments, and copyright headers.
5. **Continuous History Logging**: At the end of every conversation, update [`.agents/CHAT_HISTORY.md`](file:///Users/varunkv/Documents/rea/tv_player_app/.agents/CHAT_HISTORY.md) with newly completed tasks, technical decisions, and user prompts.
