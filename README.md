# TiviPlayer - Modern Cross-Platform IPTV & Live TV Player

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-Android%20%7C%20Android%20TV%20%7C%20macOS%20%7C%20Windows%20%7C%20Linux-green)](#supported-platforms)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A high-performance, feature-packed IPTV and Live TV streaming application built with Flutter. Engineered for smooth playback across Android mobile, Android TV / Google TV boxes, and Desktop platforms (macOS, Windows, Linux) with native remote/D-pad navigation, touch gestures, and keyboard/mouse controls.

---

## 🌟 Key Features

### 📺 Advanced Video Playback
- **Multi-Engine Adaptive Architecture**:
  - **Android & Android TV**: Google ExoPlayer via `video_player` with automatic HLS detection, TS/MP4 extractor fallbacks, and query parameter preservation for token-authenticated streams (e.g. JioTV).
  - **Desktop (macOS / Windows / Linux)**: Hardware-accelerated `media_kit` powered by `libmpv`.
- **Display Scaling & Aspect Ratios**: Switch dynamically between `16:9`, `4:3`, `Cover`, `Contain`, `Fit Width`, and `Fit Height`.
- **Configurable Buffer Cache**: Adjustable memory caching from 16 MB up to 128 MB for stutter-free playback on high-bitrate 1080p/4K streams.
- **Audio & Video Controls**: Volume boost, mute toggling, playback rate modification, and quick channel zapping.

### 📅 Real-Time Electronic Program Guide (EPG)
- **Live Program & Progress in Channel Lists**: Every channel displays its active broadcast show title, time range (`12:00 AM - 12:30 AM`), remaining countdown (`15m left`), and a visual progress bar that updates in real-time.
- **High-Performance In-Memory Indexing**: Fast batch SQLite queries with instantaneous $O(1)$ in-memory lookup capable of indexing 70,000+ EPG entries with zero frame drops during fast scrolling.
- **XMLTV & GZ Parser**: Full support for standard `.xml` and gzip-compressed `.xml.gz` EPG feeds.
- **Interactive EPG Timeline Grid**: Horizontal timeline grid to inspect program schedules across multiple hours.
- **EPG Details Sheet**: Deep-dive show panel displaying program descriptions, episode details, categories, and scheduled airings.

### 📑 Flexible Playlist & Source Management
- **M3U & M3U8 Playlists**: Supports remote URL streams, local file imports (`.m3u`, `.m3u8`), and direct file picking.
- **Xtream Codes API**: Native support for Xtream Codes servers (Live channels, VOD, and Series).
- **Custom EPG Source Assignment**: Bind external XMLTV EPG URLs or local files directly to any playlist.
- **Category & Group Filtering**: Automatic categorization of channels with instant search and favorite tagging.
- **Out-of-the-Box Demo Mode**: Pre-loaded with public live news broadcasts (DW News, Sky News, TRT World) for instant evaluation.

### ⏺️ Live Stream Recording & Scheduling
- **Direct-to-Disk Stream Recording**: Background chunked stream recorder with live bitrate and megabyte counters.
- **EPG Program Scheduling**: Schedule recordings directly from the EPG guide to capture future shows automatically.
- **Recordings Library**: Built-in manager to view, play, monitor, and delete recorded broadcasts.

### 🔲 Picture-in-Picture (PiP)
- **Android System-Wide PiP**: Keep video floating above other applications when switching apps or pressing Home, complete with OS action buttons (Play/Pause, Next Channel).
- **Desktop In-App PiP**: Draggable mini-player window for multitasking on desktop platforms.

### 📱 Adaptive & Responsive UI
- **Mobile Mode**: Portrait split-view (player on top, channels and guide below) with one-tap fullscreen landscape orientation.
- **Bottom Carousel Scroll List**: Horizontal channel strip overlaid over live video for effortless channel switching without leaving fullscreen.
- **TV & Large Screen Mode**: Immersive OSD overlay, sleek neon accents, D-pad navigation, and glassmorphic translucent panels.

---

## 🏗️ Architecture & Project Structure

The project follows clean architectural separation with reactive state management and high-performance local SQLite caching:

```text
tv_player_app/
├── lib/
│   ├── main.dart                          # Application entry point & theme initialization
│   ├── models/                            # Data models
│   │   ├── channel.dart                   # Channel entity (URLs, logos, group IDs, favorites)
│   │   ├── channel_group.dart             # Channel categories / groups
│   │   ├── epg_program.dart               # EPG program item (timing, progress, descriptions)
│   │   ├── playlist.dart                  # Playlist entity (M3U, Xtream, local files)
│   │   └── recording_item.dart            # Recorded streams and scheduled timers
│   ├── providers/                         # State Management
│   │   └── tv_state_provider.dart         # Core application state & playback coordinator
│   ├── services/                          # Business logic & background services
│   │   ├── database_service.dart          # SQLite persistence for channels, EPG & recordings
│   │   ├── epg_parser.dart                # XMLTV and Gzip EPG parser
│   │   ├── playlist_parser.dart           # M3U/M3U8 parser & demo generator
│   │   ├── recording_scheduler.dart       # Background timer for scheduled EPG recordings
│   │   ├── stream_recording_service.dart  # Live HTTP stream recording engine
│   │   ├── system_pip_service.dart        # Native Android Picture-in-Picture bridge
│   │   └── xtream_service.dart            # Xtream Codes API client
│   └── ui/                                # Presentation Layer
│       ├── theme.dart                     # Modern dark theme & neon accent palette
│       ├── screens/                       # Main app screens
│       │   ├── tv_home_screen.dart        # Primary TV & mobile playback screen
│       │   ├── playlist_manager_dialog.dart # Playlist addition, editing, and EPG mapping
│       │   ├── recordings_screen.dart     # Recorded media library & scheduler
│       │   └── stream_settings_dialog.dart # Buffer size, scale mode & stream adjustments
│       └── widgets/                       # Reusable UI components
│           ├── bottom_channel_scroll_list.dart # Horizontal bottom channel zapper
│           ├── channel_tile_widget.dart   # Channel list item with live EPG & progress bar
│           ├── epg_detail_panel.dart      # Detailed show description & schedule view
│           ├── epg_grid_view.dart         # Multi-channel horizontal timeline grid
│           ├── player_controls_osd.dart   # On-screen display overlay controls
│           ├── tv_toast.dart              # Non-intrusive TV notification toasts
│           └── video_player_widget.dart   # Dual-engine video surface (ExoPlayer & mpv)
```

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (version 3.12 or later)
- [Android Studio / Android SDK](https://developer.android.com/studio) (for Android / TV builds)
- Xcode (for macOS builds, with CocoaPods installed)

### Installation

1. **Clone the repository**:
   ```bash
   git clone https://github.com/your-username/tv_player_app.git
   cd tv_player_app
   ```

2. **Install Flutter dependencies**:
   ```bash
   flutter pub get
   ```

3. **Universal Runner & Build Script (`run.sh`)**:
   We provide a universal automation script to run and build for all platforms effortlessly:

   ```bash
   # Launch the full-featured interactive menu:
   ./run.sh

   # Quick execution by platform and mode:
   ./run.sh run android             # Run on Android (Debug)
   ./run.sh run android release     # Run on Android (Release)
   ./run.sh run macos               # Run on macOS Desktop (Debug)
   ./run.sh run macos release       # Run on macOS Desktop (Release)
   ./run.sh run web                 # Run on Chrome Browser
   ./run.sh run ios                 # Run on iOS Simulator

   # Package and build applications:
   ./run.sh build apk               # Build Release Android APK
   ./run.sh build bundle            # Build Play Store App Bundle (.aab)
   ./run.sh build macos             # Build macOS Desktop App (.app)
   ./run.sh build web               # Build Web Distribution Bundle
   ./run.sh build all               # Build Android + macOS + Web all at once
   ./run.sh install                 # Build & install directly to Android device/emulator
   ./run.sh clean                   # Clean build caches and fetch fresh dependencies
   ```

---

## ⌨️ Controls & Shortcuts

| Action | Mobile / Touch | TV Remote / Keyboard |
| :--- | :--- | :--- |
| **Select / Play Channel** | Tap Channel Tile | `Enter` / `D-Pad Center` |
| **Channel Navigation** | Scroll List / Carousel | `Up` / `Down` Arrow Keys |
| **Toggle Quick Overlay** | Tap Screen / Back Button | `Left` / `Back` Key |
| **Toggle OSD Controls** | Tap Video Player | `Enter` (while playing) |
| **Volume Up / Down** | On-screen Volume Slider | `Volume Up` / `Down` Keys |
| **Mute / Unmute** | Mute Button on Header | `M` Key |
| **Toggle PiP** | PiP Button on Header | `P` Key |
| **Toggle Fullscreen** | Fullscreen Icon | `F` Key / Double-tap Video |
| **Bottom Channel List** | Carousel Icon | `C` Key |

---

## 📦 Supported Formats

- **Streaming Protocols**: HLS (`.m3u8`), MPEG-TS (`.ts`), MP4, HTTP/HTTPS progressive streams.
- **EPG Formats**: XMLTV (`.xml`), Compressed XMLTV (`.xml.gz`).
- **Playlists**: Extended M3U with `#EXTINF` directives (`tvg-id`, `tvg-name`, `tvg-logo`, `group-title`), Xtream Codes (Live, VOD, Series).

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
