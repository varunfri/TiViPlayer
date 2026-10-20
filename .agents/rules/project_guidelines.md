# TiViPlayer TV Rules & Development Guidelines

These rules apply to all code modifications, refactorings, and feature additions in `tv_player_app`.

## Architecture & Code Standards

1. **Provider State Management**:
   - Keep business logic in [`lib/providers/tv_state_provider.dart`](./lib/providers/tv_state_provider.dart) or dedicated services.
   - Keep UI widgets focused strictly on layout, local animations, and `FocusNode` listeners.
2. **Persistence Guarantee**:
   - Any user preference, playback state, volume level, or active channel/playlist/group selection must be written to SQLite through [`lib/services/database_service.dart`](./lib/services/database_service.dart).
   - Use multi-tier matching when restoring state (ID $\rightarrow$ stream URL $\rightarrow$ name $\rightarrow$ first in group).
3. **Async BuildContext & Player Lifecycle**:
   - Cache provider values and states _before_ calling `await _player!.open()` or `await controller.initialize()`.
   - Guard callbacks with `if (!mounted) return;` to avoid `use_build_context_synchronously` warnings and unmounted widget crashes.
4. **Safe SQLite Migrations**:
   - Never rely solely on `_createDB` when adding columns. Always add a `try { await db.execute('ALTER TABLE ...'); } catch (_) {}` block inside `onOpen`.
5. **10-Foot UI, Remote Control & Back Hierarchy**:
   - Every clickable widget must maintain an explicit `FocusNode` with visible focus borders (`TvTheme.focusedBorder`).
   - Remote Back button must dismiss overlays (OSD $\rightarrow$ drawers/modals $\rightarrow$ dialogs) before triggering exit prompts.
6. **Platform Isolation**:
   - Never import `dart:io` in files shared with Web. Always route platform checks through [`lib/services/app_platform.dart`](./lib/services/app_platform.dart).
7. **Zero-Warning Code Quality**:
   - All code must pass `flutter analyze` with 0 warnings/errors.
   - All tests in `test/` must pass with `flutter test`.
8. **Automation Script**:
   - Always run and build via [`./run.sh`](./run.sh).
