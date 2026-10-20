# TiviPlayer TV - Modern Cross-Platform IPTV & Live TV Player

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Platform](<https://img.shields.io/badge/Platform-Android%20%7C%20Android%20TV%20%7C%20macOS%20%7C%20Web%20%7C%20iOS%20%7C%20Windows%20%7C%20Linux-green>)](#-supported-platforms)
[![Release Workflow](<https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-blue?logo=githubactions>)](.github/workflows/release.yml)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**TiviPlayer TV** (`tv_player_app`) is a high-performance, feature-rich IPTV, Live TV, and VOD player built with Flutter. Engineered specifically for a cinematic 10-foot TV experience (Android TV / Google TV / Fire TV) with full D-Pad remote control, while seamlessly responsive for desktop mouse/keyboard (macOS, Windows, Linux), touchscreens (Android Mobile, iOS), and modern web browsers (Chrome/Firefox/Safari via Shaka Player).

---

## 🌟 Key Features

### 📺 Multi-Engine Adaptive Video Player

- **Cross-Platform Engine Isolation**:
  - **Android (Mobile & Android TV)**: Native Google ExoPlayer (Media3 1.9.2) with hardware-accelerated SurfaceView decoding, automatic progressive container (MP4, MKV, TS) vs. HLS format fallback, Cleartext IPTV streaming, and emulator loopback (`10.0.2.2`).
  - **macOS Desktop**: Ultra-low-latency `media_kit` powered by `libmpv` with hardware decoding and seamless In-App Web Player fallback.
  - **Web**: Google Shaka Player v4 interop for DASH (`.mpd`) and HLS (`.m3u8`) playback with DRM configurations.
- **DRM Protection Support**:
  - Out-of-the-box support for **Google Widevine Modular** and **W3C ClearKey** DRM streams via custom platform channels and Shaka Player interop.
- **Self-Hosted TLS & Cleartext Resilience**:
  - Built-in platform-safe HTTP certificate overrides (`setupHttpOverrides`) permitting connection to self-hosted media servers (Teleplay, JioTV Go, Tvheadend) utilizing self-signed certificates or local LAN IPs.
- **Dynamic Display Scaling**:
  - Switch on-the-fly between `Contain`, `Cover`, `16:9`, `4:3`, `Fit Width`, and `Fit Height`.
- **Configurable Hardware Buffering**:
  - Adjustable memory caching from 16 MB up to 128 MB for stutter-free playback on high-bitrate 1080p and 4K streams.

---

### 🎬 Intelligent Live TV vs. VOD Stream Engine

- **Playlist-Layer Heuristics**:
  - Parses `#EXTINF` duration attributes and category titles. Automatically tags streams with duration $> 0$ or VOD keywords as on-demand movies/series.
- **RFC 8216 Manifest Prober (`HlsManifestProber`)**:
  - Lightweight, streamed HTTP prober (reads $\le 32$ KB) that inspects `#EXTM3U`, `#EXT-X-PLAYLIST-TYPE`, and `#EXT-X-MEDIA-SEQUENCE` headers.
  - Distinguishes sliding-window live broadcasts from finite VOD media in $<300$ ms without buffering large media files.
- **Rich VOD Scrubber & Playback Controls**:
  - Interactive scrub bar with elapsed and remaining time indicators.
  - Dedicated $\pm 10\text{s}$ seeking (`J` / `L` or Remote Left/Right).
  - Playback speed adjustment cycling from `0.5x` up to `2.0x`.

---

### 📅 Real-Time Electronic Program Guide (EPG)

- **Live Show Progress in Channel Lists**:
  - Real-time display of active show title, schedule range (`08:00 PM - 09:30 PM`), countdown timer (`24m left`), and live progress bar.
- **High-Performance In-Memory Indexing**:
  - Batch SQLite queries combined with an $O(1)$ in-memory lookup cache capable of indexing 70,000+ EPG entries with zero frame drops during fast scrolling.
- **XMLTV & Gzip Feed Support**:
  - Full support for plain `.xml` and compressed `.xml.gz` XMLTV program guides with resilient unescaped entity handling.
- **Horizontal Timeline EPG Grid**:
  - Interactive multi-hour timeline matrix for inspecting program schedules.
- **EPG Synopsis Sheet**:
  - Deep-dive modal displaying full show synopsis, episode details, categories, and future airings.

---

### 📑 Flexible Playlist & Source Management

- **M3U & M3U8 Multi-Variant Playlists**: Remote URLs, local storage files, and file picker imports.
- **Xtream Codes API v2**: Native integration for Live streams, VOD movies, and TV Series.
- **Automatic EPG Header Extraction**: Parses `url-tvg` and `x-tvg-url` directives directly from playlist headers.
- **Group & Category Filtering**: Instant group filtering, multi-attribute search, and persistent favorite channel toggles.
- **Zero-Loss State Persistence**: Automatically persists volume, scale mode, view mode, buffer size, playback speed, and last-watched channel/group to SQLite on every change.

---

### ⏺️ Live Stream Recording (DVR) & Scheduling

- **Direct-to-Disk Stream Recording**: Background chunked MPEG-TS capture engine with live bitrate and MB counters.
- **EPG Program Scheduler**: Schedule future recordings directly from the EPG guide to capture broadcasts automatically.
- **DVR Library Manager**: View, play, monitor, and delete recorded programs from disk.

---

### 🔲 Picture-in-Picture (PiP)

- **Android System-Wide PiP**: Video continues playing in an OS floating window when switching apps or pressing Home, complete with Play/Pause and Next Channel controls.
- **Desktop Windowed PiP**: Resizable always-on-top floating window for desktop multitasking.

---

## 🏗️ Architecture & Codebase Structure

```text
tv_player_app/
├── lib/
│   ├── main.dart                          # Application bootstrap & dependency injection
│   ├── models/                            # Data models
│   │   ├── channel.dart                   # Channel entity (URLs, DRM metadata, VOD flags, logos)
│   │   ├── channel_group.dart             # Channel categories / groups
│   │   ├── epg_program.dart               # EPG program item (timing, progress, descriptions)
│   │   ├── playlist.dart                  # Playlist entity (M3U, Xtream, local files)
│   │   └── recording_item.dart            # Recorded streams & scheduled DVR jobs
│   ├── providers/                         # Reactive State Management
│   │   └── tv_state_provider.dart         # Central application state & playback coordinator
│   ├── services/                          # Business logic, hardware & OS bridges
│   │   ├── app_platform.dart              # Multi-platform capability abstraction
│   │   ├── database_service.dart          # SQLite schema, non-destructive migrations, state cache
│   │   ├── desktop_pip_service.dart       # macOS windowed always-on-top PiP
│   │   ├── epg_parser.dart                # XMLTV plain and Gzip decompressor / scheduler
│   │   ├── external_player_service.dart   # Intent bridge to VLC / MX Player / Just Player
│   │   ├── hls_manifest_prober.dart       # RFC 8216 streamed manifest prober (<32KB chunked)
│   │   ├── http_overrides.dart            # Platform-safe TLS certificate bypass
│   │   ├── playlist_parser.dart           # M3U/M3U8 parser & Live vs. VOD classifier
│   │   ├── recording_scheduler.dart       # Background timer & recording job manager
│   │   ├── screen_wake_service.dart       # Wakelock / keep-screen-on controller
│   │   ├── stream_recording_service.dart  # MPEG-TS chunked disk capture engine
│   │   ├── system_pip_service.dart        # Android native Picture-in-Picture bridge
│   │   └── xtream_service.dart            # Xtream Codes API v2 client
│   └── ui/                                # Presentation Layer
│       ├── theme.dart                     # Premium cinematic dark theme & neon focus glow
│       ├── screens/                       # Full-screen views
│       │   ├── tv_home_screen.dart        # Primary TV & mobile playback screen
│       │   ├── playlist_manager_dialog.dart # Playlist addition, editing, and EPG mapping
│       │   ├── recordings_screen.dart     # Recorded media library & scheduler
│       │   └── stream_settings_dialog.dart # Buffer size, scale mode & quality selector
│       └── widgets/                       # Modular UI components
│           ├── bottom_channel_scroll_list.dart # Horizontal bottom channel switcher drawer
│           ├── channel_tile_widget.dart   # Channel card with live EPG & progress bar
│           ├── epg_detail_panel.dart      # Deep-dive program synopsis modal
│           ├── epg_grid_view.dart         # Multi-channel horizontal timeline grid
│           ├── player_controls_osd.dart   # On-screen display overlay & VOD scrubber
│           ├── shaka_player/              # Google Shaka Player interop for Web
│           ├── tv_toast.dart              # Non-intrusive animated TV toast HUD
│           └── video_player_widget.dart   # Multi-engine video surface (ExoPlayer, mpv, Shaka)
├── test/                                  # Unit, widget, and integration test suite
├── .github/workflows/                     # CI/CD automated release pipeline
└── run.sh                                 # Universal automation CLI engine
```

---

## 🚀 Getting Started

### Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) ($\ge 3.12$)
- [Android Studio / Android SDK](https://developer.android.com/studio) (for Android / Android TV builds)
- Xcode (for macOS and iOS builds, with CocoaPods installed)

### Quick Setup

1. **Clone the repository**:

   ```bash
   git clone https://github.com/your-username/tv_player_app.git
   cd tv_player_app
   ```
2. **Fetch dependencies**:

   ```bash
   flutter pub get
   ```
3. **Universal Automation CLI (`run.sh`)**:
   Use the workspace automation script for interactive debugging, building, and diagnostics:

   ```bash
   # Launch interactive terminal dashboard:
   ./run.sh

   # Direct execution by platform:
   ./run.sh run android             # Run on Android TV / Device (Debug)
   ./run.sh run android release     # Run on Android TV / Device (Release)
   ./run.sh run macos               # Run on macOS Desktop (Debug - libmpv)
   ./run.sh run macos release       # Run on macOS Desktop (Release)
   ./run.sh run web                 # Run on Chrome with Shaka Player
   ./run.sh run ios                 # Run on iOS Simulator

   # Build distribution packages:
   ./run.sh build apk               # Build split Android APKs (arm64, armeabi-v7a, x86_64)
   ./run.sh build bundle            # Build Android App Bundle (.aab)
   ./run.sh build macos             # Build macOS .app bundle and .dmg installer
   ./run.sh build dmg               # Package release .dmg directly using hdiutil
   ./run.sh build web               # Build optimized Web distribution
   ./run.sh build all               # Build Android APK + macOS DMG + Web in sequence
   ./run.sh clean                   # Execute flutter clean && flutter pub get
   ./run.sh doctor                  # Run Flutter diagnostic checks
   ```

---

## ⌨️ Global Keyboard & TV Remote Navigation

All interactive items feature high-contrast visual focus borders (`TvTheme.focusedBorder`) optimized for Android TV remotes and keyboard navigation:

| Shortcut / Button                 | Scope   | Action                                                                                                                      |
| :-------------------------------- | :------ | :-------------------------------------------------------------------------------------------------------------------------- |
| `Space` / `K`                 | Global  | Toggle Play / Pause                                                                                                         |
| `M`                             | Global  | Toggle Audio Mute / Unmute                                                                                                  |
| `+` / `=` / `]`             | Global  | Volume Up (+5%)                                                                                                             |
| `-` / `[`                     | Global  | Volume Down (-5%)                                                                                                           |
| `F` / `F11`                   | Global  | Toggle Fullscreen (auto-rotates orientation on mobile)                                                                      |
| `Cmd+F` / `Ctrl+F` / `/`    | Global  | Focus Channel & EPG Search                                                                                                  |
| `C`                             | Global  | Toggle Bottom Channel Drawer / Quick Switcher                                                                               |
| `G` / `E` / `Tab`           | Global  | Toggle Horizontal EPG Timeline Guide Overlay                                                                                |
| `V`                             | Global  | Cycle View Mode (Side-by-Side$\rightarrow$ Overlay $\rightarrow$ Fullscreen)                                            |
| `A`                             | Global  | Cycle Aspect Ratio (`Contain`, `Cover`, `16:9`, `4:3`, `Fit Width`, `Fit Height`)                               |
| `P`                             | Global  | Toggle Picture-in-Picture (System PiP on Android / Windowed on macOS)                                                       |
| `R`                             | Global  | Open Recordings & DVR Scheduler Screen                                                                                      |
| `O` / `Cmd+,`                 | Global  | Open Stream Settings & Buffer Configuration Dialog                                                                          |
| `B` / `D`                     | Global  | Bookmark / Toggle Active Channel as Favorite                                                                                |
| `J` / `Rewind`                | VOD     | Seek Backward 10 Seconds                                                                                                    |
| `L` / `Fast Forward`          | VOD     | Seek Forward 10 Seconds                                                                                                     |
| `PageUp` / `PageDown` / `N` | Global  | Jump to Previous / Next Channel                                                                                             |
| `Up` / `Down` Arrow           | Playing | Jump to Previous / Next Channel                                                                                             |
| `Left` / `Right` Arrow        | Playing | VOD Seek$\pm 10\text{s}$ (VOD) or Volume Adjust (Live TV)                                                                 |
| `Enter` / `Select` / `I`    | Playing | Trigger OSD Controls & Channel Information Banner                                                                           |
| `0` – `9`                    | Global  | Direct Numeric Channel Number Zapping                                                                                       |
| `Esc` / `Remote Back`         | Global  | **Dismiss Hierarchy**: Drawer $\rightarrow$ OSD $\rightarrow$ Fullscreen $\rightarrow$ PiP $\rightarrow$ Exit |

---

## 📦 Supported Protocols & Formats

- **Video Streaming Protocols**: HLS (`.m3u8`), MPEG-DASH (`.mpd`), MPEG-TS (`.ts`), SmoothStreaming (`.ism`), MP4, MKV, AVI, HTTP/HTTPS progressive streams.
- **DRM Decryption**: Google Widevine Modular (CENC), W3C ClearKey hex key pairs.
- **Electronic Program Guide (EPG)**: XMLTV (`.xml`), Gzip-compressed XMLTV (`.xml.gz`).
- **Playlists & Providers**: Extended M3U with `#EXTINF` metadata (`tvg-id`, `tvg-name`, `tvg-logo`, `group-title`), Xtream Codes API v2 (Live, VOD, Series).

---

* [ ] 🤖 Continuous Integration & Automated Releases

Automated releases are handled via GitHub Actions in [`.github/workflows/release.yml`](.github/workflows/release.yml). Simply pushing any version tag (e.g. `git tag v1.0.1 && git push origin v1.0.1`) automatically triggers parallel matrix builds and publishes a complete GitHub Release with all compiled assets attached:

- **Android**: Release APKs split by ABI (`arm64-v8a`, `armeabi-v7a`, `x86_64`) + Universal APK.
- **macOS**: Signed `.dmg` disk image installer packaged directly with `hdiutil`.
- **Web**: Production-ready static distribution bundle (`.zip`).
- **GitHub Release**: Automatically aggregates release notes and publishes all binary assets.

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
