import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../../models/playlist.dart';
import '../../providers/tv_state_provider.dart';
import '../../services/epg_parser.dart';
import '../../ui/theme.dart';
import '../widgets/tv_toast.dart';

class PlaylistManagerDialog extends StatefulWidget {
  final int initialTabIndex;

  const PlaylistManagerDialog({super.key, this.initialTabIndex = 0});

  @override
  State<PlaylistManagerDialog> createState() => _PlaylistManagerDialogState();
}

class _PlaylistManagerDialogState extends State<PlaylistManagerDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Local File form
  final _localFileNameController = TextEditingController();
  final _localEpgUrlController = TextEditingController();
  String? _selectedFilePath;
  String? _selectedFileName;
  String? _selectedLocalEpgName;

  // M3U URL form
  final _m3uNameController = TextEditingController();
  final _m3uUrlController = TextEditingController();
  final _m3uEpgUrlController = TextEditingController();

  // Xtream form
  final _xtreamNameController = TextEditingController();
  final _xtreamServerController = TextEditingController();
  final _xtreamUserController = TextEditingController();
  final _xtreamPassController = TextEditingController();

  // Syncing state per playlist ID for quick actions
  final Set<int> _syncingPlaylistIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    _localFileNameController.dispose();
    _localEpgUrlController.dispose();
    _m3uNameController.dispose();
    _m3uUrlController.dispose();
    _m3uEpgUrlController.dispose();
    _xtreamNameController.dispose();
    _xtreamServerController.dispose();
    _xtreamUserController.dispose();
    _xtreamPassController.dispose();
    super.dispose();
  }

  String _formatSyncTime(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 2) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatSourcePreview(Playlist playlist) {
    if (playlist.type == PlaylistType.xtream) {
      try {
        final uri = Uri.parse(playlist.url);
        return uri.host.isNotEmpty ? '${uri.host}:${uri.port}' : playlist.url;
      } catch (_) {
        return playlist.url;
      }
    }
    if (playlist.url.startsWith('http://') ||
        playlist.url.startsWith('https://')) {
      try {
        final uri = Uri.parse(playlist.url);
        final pathSeg = uri.pathSegments.isNotEmpty
            ? uri.pathSegments.last
            : '';
        return pathSeg.isNotEmpty ? '${uri.host}/$pathSeg' : uri.host;
      } catch (_) {
        return playlist.url;
      }
    }
    final parts = playlist.url.split(RegExp(r'[/\\]'));
    return parts.isNotEmpty ? parts.last : playlist.url;
  }

  Future<void> _pickLocalFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['m3u', 'm3u8', 'txt'],
      );

      if (files.isNotEmpty) {
        final file = files.first;
        setState(() {
          _selectedFilePath = file.path;
          _selectedFileName = file.name;
          if (_localFileNameController.text.trim().isEmpty) {
            _localFileNameController.text = file.name.replaceAll(
              RegExp(r'\.(m3u8?|txt)$'),
              '',
            );
          }
        });
      }
    } catch (e) {
      if (mounted) {
        TvToast.error(context, 'File selection notice: $e');
      }
    }
  }

  Future<void> _pickLocalEpgFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xml', 'gz', 'xmltv', 'txt'],
      );

      if (files.isNotEmpty) {
        final file = files.first;
        setState(() {
          _selectedLocalEpgName = file.name;
          _localEpgUrlController.text = file.path ?? '';
        });
      }
    } catch (e) {
      if (mounted) {
        TvToast.error(context, 'EPG file selection notice: $e');
      }
    }
  }

  Future<void> _quickSyncEpg(Playlist playlist) async {
    if (playlist.id == null ||
        playlist.epgUrl == null ||
        playlist.epgUrl!.isEmpty) {
      return;
    }
    final pid = playlist.id!;
    setState(() => _syncingPlaylistIds.add(pid));

    try {
      final tvState = context.read<TvStateProvider>();
      TvToast.info(context, 'Syncing EPG for "${playlist.name}"...');
      final count = await tvState.syncEpgForPlaylist(pid, playlist.epgUrl!);
      if (mounted) {
        TvToast.success(
          context,
          'EPG Synced! Loaded $count program schedules.',
        );
      }
    } catch (e) {
      if (mounted) {
        TvToast.error(context, 'EPG sync failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _syncingPlaylistIds.remove(pid));
      }
    }
  }

  void _showEpgDialog(Playlist playlist) {
    final controller = TextEditingController(text: playlist.epgUrl ?? '');
    String? localPickedEpgName;
    bool isSyncing = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dlgCtx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF161925),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2E3448)),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: TvTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.calendar_month_rounded,
                  color: TvTheme.primaryAccent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'EPG TV Guide: ${playlist.name}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Assign XMLTV (.xml / .xml.gz) source',
                      style: TextStyle(color: TvTheme.textMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Program titles, current schedules, and live progress bars are generated from XMLTV data.',
                  style: TextStyle(
                    color: TvTheme.textMuted,
                    fontSize: 12,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'EPG / XMLTV URL or File Path',
                    labelStyle: const TextStyle(color: TvTheme.textMuted),
                    hintText: 'https://example.com/epg.xml.gz',
                    hintStyle: const TextStyle(color: Color(0xFF475569)),
                    filled: true,
                    fillColor: const Color(0xFF0F111A),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFF262C3D)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(
                        color: TvTheme.primaryAccent,
                        width: 1.5,
                      ),
                    ),
                    prefixIcon: const Icon(
                      Icons.link_rounded,
                      color: TvTheme.primaryAccent,
                      size: 20,
                    ),
                    suffixIcon: controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear_rounded,
                              size: 18,
                              color: TvTheme.textMuted,
                            ),
                            onPressed: () {
                              controller.clear();
                              setDialogState(() {
                                localPickedEpgName = null;
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: TvTheme.textBright,
                    side: const BorderSide(color: Color(0xFF2E3448)),
                    backgroundColor: const Color(0xFF0F111A),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    try {
                      final files = await FilePicker.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['xml', 'gz', 'xmltv', 'txt'],
                      );
                      if (files.isNotEmpty) {
                        final file = files.first;
                        setDialogState(() {
                          localPickedEpgName = file.name;
                          controller.text = file.path ?? '';
                        });
                      }
                    } catch (e) {
                      if (dlgCtx.mounted) {
                        TvToast.error(dlgCtx, 'File picker notice: $e');
                      }
                    }
                  },
                  icon: const Icon(
                    Icons.folder_open_rounded,
                    size: 18,
                    color: TvTheme.primaryAccent,
                  ),
                  label: Text(
                    localPickedEpgName != null
                        ? 'Selected: $localPickedEpgName'
                        : 'Browse Local XMLTV / .gz File',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                if (playlist.epgUrl != null && playlist.epgUrl!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF262C3D)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: TvTheme.primaryAccent,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Active Source: ${playlist.epgUrl}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: TvTheme.textMuted,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dlgCtx).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: TvTheme.textMuted),
              ),
            ),
            if (playlist.epgUrl != null && playlist.epgUrl!.isNotEmpty)
              TextButton(
                onPressed: isSyncing
                    ? null
                    : () async {
                        final tvState = dlgCtx.read<TvStateProvider>();
                        await tvState.updatePlaylistEpgUrl(playlist.id!, null);
                        if (dlgCtx.mounted) {
                          TvToast.info(
                            dlgCtx,
                            'EPG guide removed from "${playlist.name}"',
                          );
                          Navigator.of(dlgCtx).pop();
                        }
                      },
                child: const Text(
                  'Remove EPG',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: TvTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: isSyncing
                  ? null
                  : () async {
                      final newUrl = EpgParser.sanitizeUrl(controller.text);
                      if (playlist.id == null) return;
                      setDialogState(() => isSyncing = true);

                      try {
                        final tvState = dlgCtx.read<TvStateProvider>();
                        if (newUrl.isEmpty) {
                          await tvState.updatePlaylistEpgUrl(
                            playlist.id!,
                            null,
                          );
                          if (dlgCtx.mounted) {
                            TvToast.info(dlgCtx, 'EPG source cleared');
                            Navigator.of(dlgCtx).pop();
                          }
                          return;
                        }

                        final count = await tvState.syncEpgForPlaylist(
                          playlist.id!,
                          newUrl,
                        );
                        if (dlgCtx.mounted) {
                          TvToast.success(
                            dlgCtx,
                            'EPG synced! Loaded $count program schedules.',
                          );
                          Navigator.of(dlgCtx).pop();
                        }
                      } catch (e) {
                        if (dlgCtx.mounted) {
                          TvToast.error(dlgCtx, 'EPG sync failed: $e');
                          setDialogState(() => isSyncing = false);
                        }
                      }
                    },
              icon: isSyncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.sync_rounded, size: 18),
              label: Text(isSyncing ? 'Syncing...' : 'Save & Sync EPG'),
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(Playlist playlist) {
    final controller = TextEditingController(text: playlist.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161925),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2E3448)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: TvTheme.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.edit_note_rounded,
                color: TvTheme.primaryAccent,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Rename Playlist',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose a recognizable label for this playlist in your guide.',
              style: TextStyle(color: TvTheme.textMuted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Playlist Name',
                labelStyle: const TextStyle(color: TvTheme.textMuted),
                hintText: 'e.g. My Sports M3U, Living Room TV',
                filled: true,
                fillColor: const Color(0xFF0F111A),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF262C3D)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(
                    color: TvTheme.primaryAccent,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: TvTheme.textMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: TvTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isNotEmpty && playlist.id != null) {
                Navigator.of(ctx).pop();
                final tvState = context.read<TvStateProvider>();
                await tvState.renamePlaylist(playlist.id!, newName);
                if (mounted) {
                  TvToast.success(context, 'Playlist renamed to "$newName"');
                }
              }
            },
            child: const Text('Save Name'),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(Playlist playlist) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161925),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFF2E3448)),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.delete_forever_rounded,
                color: Colors.redAccent,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Delete Playlist?',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${playlist.name}"?\nAll channels and categories under this playlist will be removed from local storage.',
          style: const TextStyle(
            color: TvTheme.textMuted,
            fontSize: 13,
            height: 1.4,
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: TvTheme.textMuted),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              if (playlist.id != null) {
                final tvState = context.read<TvStateProvider>();
                await tvState.deletePlaylist(playlist.id!);
                if (mounted) {
                  TvToast.info(context, 'Playlist "${playlist.name}" removed');
                }
              }
            },
            child: const Text('Delete Playlist'),
          ),
        ],
      ),
    );
  }

  Future<void> _switchToPlaylist(Playlist playlist) async {
    final tvState = context.read<TvStateProvider>();
    final nav = Navigator.of(context);
    await tvState.switchPlaylist(playlist);
    if (!mounted) return;
    TvToast.success(context, 'Switched to playlist "${playlist.name}"');
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final tvState = context.watch<TvStateProvider>();
    final size = MediaQuery.sizeOf(context);
    final isMobile = size.width < 700;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 36,
        vertical: isMobile ? 16 : 24,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 740,
          maxHeight: math.min(size.height - 32, 700),
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF141724), Color(0xFF0C0E16)],
          ),
          border: Border.all(color: const Color(0xFF282E42), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.65),
              blurRadius: 36,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 16 : 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(
                            0xFF3B82F6,
                          ).withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.playlist_play_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Playlist Manager',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: isMobile ? 18 : 21,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${tvState.playlists.length} playlists • Switch, sync EPG, or import M3U sources',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: TvTheme.textMuted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: TvTheme.textMuted,
                      size: 20,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Modern Tab Navigation Bar
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF161926),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF252B3D)),
                ),
                padding: const EdgeInsets.all(4),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicator: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  labelColor: Colors.white,
                  unselectedLabelColor: TvTheme.textMuted,
                  labelStyle: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                  labelPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 3,
                  ),
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.layers_rounded, size: 16),
                          const SizedBox(width: 6),
                          Text('My Playlists (${tvState.playlists.length})'),
                        ],
                      ),
                    ),
                    const Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_link_rounded, size: 16),
                          SizedBox(width: 6),
                          Text('Add M3U URL'),
                        ],
                      ),
                    ),
                    const Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.upload_file_rounded, size: 16),
                          SizedBox(width: 6),
                          Text('Add Local File'),
                        ],
                      ),
                    ),
                    const Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.dns_rounded, size: 16),
                          SizedBox(width: 6),
                          Text('Xtream API'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Error banner if any
              if (tvState.errorMessage != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          tvState.errorMessage!,
                          style: const TextStyle(
                            color: Colors.redAccent,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Tab Views
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildMyPlaylistsTab(tvState),
                    _buildAddM3uUrlTab(tvState),
                    _buildAddLocalFileTab(tvState),
                    _buildAddXtreamTab(tvState),
                  ],
                ),
              ),

              const Divider(color: Color(0xFF252B3D), height: 20),

              // Bottom Toolbar (Safe responsive Row, no Spacer in Wrap)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      await tvState.loadDemoPlaylist();
                      if (context.mounted) {
                        TvToast.success(
                          context,
                          'Reset demo channels playlist',
                        );
                      }
                    },
                    icon: const Icon(Icons.restore_rounded, size: 16),
                    label: const Text(
                      'Load Demo Channels',
                      style: TextStyle(fontSize: 12),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: TvTheme.textMuted,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                  ),
                  if (tvState.selectedPlaylist != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161926),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF282E42)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                              color: Color(0xFF10B981),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Active: ${tvState.selectedPlaylist!.name}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMyPlaylistsTab(TvStateProvider tvState) {
    if (tvState.playlists.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.playlist_remove_rounded,
                size: 48,
                color: TvTheme.textMuted,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'No Playlists Added Yet',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add an M3U URL or local file to start streaming live channels.',
              textAlign: TextAlign.center,
              style: TextStyle(color: TvTheme.textMuted, fontSize: 13),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: TvTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => _tabController.animateTo(1),
              icon: const Icon(Icons.add_link_rounded, size: 18),
              label: const Text('Add M3U URL'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: tvState.playlists.length,
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      itemBuilder: (context, index) {
        final playlist = tvState.playlists[index];
        final isActive = tvState.selectedPlaylist?.id == playlist.id;
        final isSyncingThis =
            playlist.id != null &&
            (_syncingPlaylistIds.contains(playlist.id) ||
                (isActive && tvState.isEpgSyncing));

        // Type-based Avatar
        final IconData typeIcon;
        final List<Color> typeGradient;
        final String typeLabel;

        if (playlist.type == PlaylistType.xtream) {
          typeIcon = Icons.dns_rounded;
          typeGradient = const [Color(0xFF8B5CF6), Color(0xFF6D28D9)];
          typeLabel = 'Xtream API';
        } else if (playlist.url.startsWith('http://') ||
            playlist.url.startsWith('https://')) {
          typeIcon = Icons.cloud_rounded;
          typeGradient = const [Color(0xFF38BDF8), Color(0xFF0284C7)];
          typeLabel = 'M3U URL';
        } else {
          typeIcon = Icons.folder_open_rounded;
          typeGradient = const [Color(0xFFF59E0B), Color(0xFFD97706)];
          typeLabel = 'Local File';
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF132A24) : const Color(0xFF151825),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive
                  ? const Color(0xFF10B981)
                  : const Color(0xFF24293D),
              width: isActive ? 1.5 : 1.0,
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                if (!isActive) {
                  _switchToPlaylist(playlist);
                }
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Row: Avatar + Title & Source + Actions
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: typeGradient),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(typeIcon, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      playlist.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 15.5,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ),
                                  if (isActive) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(
                                          0xFF10B981,
                                        ).withValues(alpha: 0.18),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: const Color(0xFF10B981),
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Container(
                                            width: 5,
                                            height: 5,
                                            decoration: const BoxDecoration(
                                              color: Color(0xFF10B981),
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          const Text(
                                            'ACTIVE',
                                            style: TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF10B981),
                                              letterSpacing: 0.5,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _formatSourcePreview(playlist),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: TvTheme.textMuted,
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Action Buttons: Quick Sync + Popup Menu
                        if (isSyncingThis)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: TvTheme.primaryAccent,
                              ),
                            ),
                          )
                        else if (playlist.epgUrl != null &&
                            playlist.epgUrl!.isNotEmpty)
                          IconButton(
                            icon: const Icon(
                              Icons.sync_rounded,
                              size: 19,
                              color: TvTheme.primaryAccent,
                            ),
                            tooltip: 'Sync EPG Now',
                            onPressed: () => _quickSyncEpg(playlist),
                          ),

                        PopupMenuButton<String>(
                          icon: const Icon(
                            Icons.more_vert_rounded,
                            size: 19,
                            color: TvTheme.textMuted,
                          ),
                          tooltip: 'Playlist Options',
                          color: const Color(0xFF1A1E2C),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: const BorderSide(color: Color(0xFF2E3448)),
                          ),
                          onSelected: (value) {
                            if (value == 'rename') {
                              _showRenameDialog(playlist);
                            } else if (value == 'epg') {
                              _showEpgDialog(playlist);
                            } else if (value == 'delete') {
                              _confirmDelete(playlist);
                            }
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                              value: 'rename',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.edit_rounded,
                                    size: 16,
                                    color: TvTheme.textBright,
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'Rename Playlist',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'epg',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calendar_month_rounded,
                                    size: 16,
                                    color: TvTheme.primaryAccent,
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'EPG Guide Source',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const PopupMenuDivider(height: 1),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.delete_outline_rounded,
                                    size: 16,
                                    color: Colors.redAccent,
                                  ),
                                  SizedBox(width: 10),
                                  Text(
                                    'Delete Playlist',
                                    style: TextStyle(
                                      color: Colors.redAccent,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    // Badges Row
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Channels count badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: TvTheme.primary.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.tv_rounded,
                                size: 12,
                                color: TvTheme.primaryAccent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${playlist.channelCount} Channels',
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: TvTheme.primaryAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Format badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: const Color(0xFF2E3448),
                              width: 0.8,
                            ),
                          ),
                          child: Text(
                            typeLabel,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: TvTheme.textMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),

                        // EPG Status Badge
                        InkWell(
                          onTap: () {
                            if (playlist.epgUrl != null &&
                                playlist.epgUrl!.isNotEmpty &&
                                playlist.isEpgStale) {
                              _quickSyncEpg(playlist);
                            } else {
                              _showEpgDialog(playlist);
                            }
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  (playlist.epgUrl != null &&
                                      playlist.epgUrl!.isNotEmpty)
                                  ? (playlist.isEpgStale
                                        ? const Color(
                                            0xFFF59E0B,
                                          ).withValues(alpha: 0.15)
                                        : const Color(
                                            0xFF10B981,
                                          ).withValues(alpha: 0.15))
                                  : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color:
                                    (playlist.epgUrl != null &&
                                        playlist.epgUrl!.isNotEmpty)
                                    ? (playlist.isEpgStale
                                          ? const Color(
                                              0xFFF59E0B,
                                            ).withValues(alpha: 0.4)
                                          : const Color(
                                              0xFF10B981,
                                            ).withValues(alpha: 0.4))
                                    : const Color(0xFF2E3448),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  (playlist.epgUrl != null &&
                                          playlist.epgUrl!.isNotEmpty)
                                      ? (playlist.isEpgStale
                                            ? Icons.schedule_rounded
                                            : Icons.check_circle_rounded)
                                      : Icons.add_circle_outline_rounded,
                                  size: 11,
                                  color:
                                      (playlist.epgUrl != null &&
                                          playlist.epgUrl!.isNotEmpty)
                                      ? (playlist.isEpgStale
                                            ? const Color(0xFFF59E0B)
                                            : const Color(0xFF10B981))
                                      : TvTheme.textMuted,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  (playlist.epgUrl != null &&
                                          playlist.epgUrl!.isNotEmpty)
                                      ? (playlist.isEpgStale
                                            ? 'EPG Expired (Sync)'
                                            : (playlist.lastEpgSync != null
                                                  ? 'EPG Synced • ${_formatSyncTime(playlist.lastEpgSync!)}'
                                                  : 'EPG Active'))
                                      : '+ Add EPG Guide',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color:
                                        (playlist.epgUrl != null &&
                                            playlist.epgUrl!.isNotEmpty)
                                        ? (playlist.isEpgStale
                                              ? const Color(0xFFF59E0B)
                                              : const Color(0xFF10B981))
                                        : TvTheme.textMuted,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Bottom Switch Button if Inactive
                    if (!isActive) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 36,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: TvTheme.primaryAccent,
                            backgroundColor: const Color(0xFF161926),
                            side: const BorderSide(color: Color(0xFF2C344A)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => _switchToPlaylist(playlist),
                          icon: const Icon(
                            Icons.play_circle_outline_rounded,
                            size: 16,
                          ),
                          label: const Text(
                            'Switch to this Playlist',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddM3uUrlTab(TvStateProvider tvState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CUSTOM PLAYLIST NAME',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: TvTheme.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _m3uNameController,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
            decoration: InputDecoration(
              hintText: 'e.g. My Premium IPTV, Sports Live, JioTV',
              hintStyle: const TextStyle(color: Color(0xFF475569)),
              filled: true,
              fillColor: const Color(0xFF0F111A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF262C3D)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: TvTheme.primaryAccent,
                  width: 1.5,
                ),
              ),
              prefixIcon: const Icon(
                Icons.label_outline_rounded,
                color: TvTheme.primaryAccent,
                size: 20,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'M3U / M3U8 STREAM PLAYLIST URL',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: TvTheme.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _m3uUrlController,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
            decoration: InputDecoration(
              hintText:
                  'https://example.com/playlist.m3u8 or http://localhost:8080/live.m3u',
              hintStyle: const TextStyle(color: Color(0xFF475569)),
              filled: true,
              fillColor: const Color(0xFF0F111A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF262C3D)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: TvTheme.primaryAccent,
                  width: 1.5,
                ),
              ),
              prefixIcon: const Icon(
                Icons.link_rounded,
                color: TvTheme.primaryAccent,
                size: 20,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'EPG / XMLTV URL (OPTIONAL)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: TvTheme.textMuted,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: TvTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Auto-detects from M3U if empty',
                  style: TextStyle(
                    fontSize: 10,
                    color: TvTheme.primaryAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _m3uEpgUrlController,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
            decoration: InputDecoration(
              hintText: 'https://example.com/epg.xml.gz or .xml',
              hintStyle: const TextStyle(color: Color(0xFF475569)),
              filled: true,
              fillColor: const Color(0xFF0F111A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF262C3D)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: TvTheme.primaryAccent,
                  width: 1.5,
                ),
              ),
              prefixIcon: const Icon(
                Icons.calendar_month_rounded,
                color: TvTheme.primaryAccent,
                size: 20,
              ),
              suffixIcon: _m3uEpgUrlController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.clear_rounded,
                        size: 18,
                        color: TvTheme.textMuted,
                      ),
                      onPressed: () {
                        setState(() {
                          _m3uEpgUrlController.clear();
                        });
                      },
                    )
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: TvTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: tvState.isLoading
                  ? null
                  : () async {
                      final name = _m3uNameController.text.trim();
                      final url = _m3uUrlController.text.trim();
                      final epgUrl = EpgParser.sanitizeUrl(
                        _m3uEpgUrlController.text,
                      );
                      if (url.isEmpty) {
                        TvToast.warning(
                          context,
                          'Please enter a valid M3U/M3U8 URL',
                        );
                        return;
                      }
                      final customName = name.isNotEmpty
                          ? name
                          : 'Playlist ${tvState.playlists.length + 1}';

                      await tvState.addM3uPlaylist(
                        customName,
                        url,
                        customEpgUrl: epgUrl.isNotEmpty ? epgUrl : null,
                      );
                      if (!mounted) return;
                      if (tvState.errorMessage == null) {
                        TvToast.success(
                          context,
                          'Added playlist "$customName"',
                        );
                        _m3uNameController.clear();
                        _m3uUrlController.clear();
                        _m3uEpgUrlController.clear();
                        _tabController.animateTo(0);
                      } else {
                        TvToast.error(context, tvState.errorMessage!);
                      }
                    },
              icon: tvState.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add_to_photos_rounded),
              label: const Text(
                'Add & Sync M3U Playlist',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddLocalFileTab(TvStateProvider tvState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CUSTOM PLAYLIST NAME',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: TvTheme.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _localFileNameController,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
            decoration: InputDecoration(
              hintText: 'e.g. Local Kodi Playlist, JioTV Dump',
              hintStyle: const TextStyle(color: Color(0xFF475569)),
              filled: true,
              fillColor: const Color(0xFF0F111A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF262C3D)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: TvTheme.primaryAccent,
                  width: 1.5,
                ),
              ),
              prefixIcon: const Icon(
                Icons.label_outline_rounded,
                color: TvTheme.primaryAccent,
                size: 20,
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'SELECT LOCAL .M3U / .M3U8 FILE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: TvTheme.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          InkWell(
            onTap: _pickLocalFile,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F111A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedFileName != null
                      ? const Color(0xFF10B981)
                      : const Color(0xFF2E3448),
                  width: _selectedFileName != null ? 1.8 : 1.0,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _selectedFileName != null
                          ? const Color(0xFF10B981).withValues(alpha: 0.15)
                          : TvTheme.primary.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _selectedFileName != null
                          ? Icons.check_circle_rounded
                          : Icons.upload_file_rounded,
                      size: 24,
                      color: _selectedFileName != null
                          ? const Color(0xFF10B981)
                          : TvTheme.primaryAccent,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _selectedFileName ??
                        'Click to Browse & Select .m3u / .m3u8 file',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: _selectedFileName != null
                          ? Colors.white
                          : TvTheme.textBright,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _selectedFilePath ??
                        'Supports standard M3U, M3U8 with extinf, logos & categories',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: TvTheme.textMuted,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'EPG / XMLTV SOURCE (OPTIONAL)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: TvTheme.textMuted,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: TvTheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'Auto-detects from M3U if empty',
                  style: TextStyle(
                    fontSize: 10,
                    color: TvTheme.primaryAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _localEpgUrlController,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
            decoration: InputDecoration(
              hintText: 'https://example.com/epg.xml.gz or local path',
              hintStyle: const TextStyle(color: Color(0xFF475569)),
              filled: true,
              fillColor: const Color(0xFF0F111A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF262C3D)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: TvTheme.primaryAccent,
                  width: 1.5,
                ),
              ),
              prefixIcon: const Icon(
                Icons.calendar_month_rounded,
                color: TvTheme.primaryAccent,
                size: 20,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_localEpgUrlController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(
                        Icons.clear_rounded,
                        size: 18,
                        color: TvTheme.textMuted,
                      ),
                      onPressed: () {
                        setState(() {
                          _localEpgUrlController.clear();
                          _selectedLocalEpgName = null;
                        });
                      },
                    ),
                  IconButton(
                    icon: const Icon(
                      Icons.folder_open_rounded,
                      size: 20,
                      color: TvTheme.primaryAccent,
                    ),
                    tooltip: 'Browse Local XMLTV file',
                    onPressed: _pickLocalEpgFile,
                  ),
                ],
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          if (_selectedLocalEpgName != null) ...[
            const SizedBox(height: 6),
            Text(
              'Selected local EPG file: $_selectedLocalEpgName',
              style: const TextStyle(color: Color(0xFF10B981), fontSize: 11),
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: TvTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: (tvState.isLoading || _selectedFilePath == null)
                  ? null
                  : () async {
                      final name = _localFileNameController.text.trim();
                      final customName = name.isNotEmpty
                          ? name
                          : (_selectedFileName != null
                                ? _selectedFileName!.replaceAll(
                                    RegExp(r'\.(m3u8?|txt)$'),
                                    '',
                                  )
                                : 'Local Playlist');
                      final epgUrlOrPath = EpgParser.sanitizeUrl(
                        _localEpgUrlController.text,
                      );

                      if (_selectedFilePath != null) {
                        await tvState.addLocalFilePlaylist(
                          customName,
                          _selectedFilePath!,
                          customEpgUrlOrPath: epgUrlOrPath.isNotEmpty
                              ? epgUrlOrPath
                              : null,
                        );
                        if (!mounted) return;
                        if (tvState.errorMessage == null) {
                          TvToast.success(
                            context,
                            'Imported playlist "$customName"',
                          );
                          _localFileNameController.clear();
                          _localEpgUrlController.clear();
                          setState(() {
                            _selectedFilePath = null;
                            _selectedFileName = null;
                            _selectedLocalEpgName = null;
                          });
                          _tabController.animateTo(0);
                        } else {
                          TvToast.error(context, tvState.errorMessage!);
                        }
                      }
                    },
              icon: tvState.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.file_upload_rounded),
              label: const Text(
                'Import & Parse Local Playlist',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddXtreamTab(TvStateProvider tvState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CUSTOM PROFILE NAME',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: TvTheme.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _xtreamNameController,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
            decoration: InputDecoration(
              hintText: 'e.g. Xtream Service, Home IPTV',
              hintStyle: const TextStyle(color: Color(0xFF475569)),
              filled: true,
              fillColor: const Color(0xFF0F111A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF262C3D)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: TvTheme.primaryAccent,
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'SERVER URL & PORT',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
              color: TvTheme.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _xtreamServerController,
            style: const TextStyle(color: Colors.white, fontSize: 13.5),
            decoration: InputDecoration(
              hintText: 'http://provider.dns.net:8080',
              hintStyle: const TextStyle(color: Color(0xFF475569)),
              filled: true,
              fillColor: const Color(0xFF0F111A),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF262C3D)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: TvTheme.primaryAccent,
                  width: 1.5,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'USERNAME',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: TvTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _xtreamUserController,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F111A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF262C3D),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: TvTheme.primaryAccent,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PASSWORD',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: TvTheme.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _xtreamPassController,
                      obscureText: true,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF0F111A),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF262C3D),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: TvTheme.primaryAccent,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: TvTheme.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: tvState.isLoading
                  ? null
                  : () async {
                      final name = _xtreamNameController.text.trim();
                      final server = _xtreamServerController.text.trim();
                      final user = _xtreamUserController.text.trim();
                      final pass = _xtreamPassController.text.trim();

                      if (server.isEmpty || user.isEmpty || pass.isEmpty) {
                        TvToast.warning(
                          context,
                          'Please fill in all server and login credentials',
                        );
                        return;
                      }

                      final customName = name.isNotEmpty
                          ? name
                          : 'Xtream Service';
                      await tvState.addXtreamPlaylist(
                        customName,
                        server,
                        user,
                        pass,
                      );
                      if (!mounted) return;
                      if (tvState.errorMessage == null) {
                        TvToast.success(
                          context,
                          'Connected Xtream profile "$customName"',
                        );
                        _xtreamNameController.clear();
                        _xtreamServerController.clear();
                        _xtreamUserController.clear();
                        _xtreamPassController.clear();
                        _tabController.animateTo(0);
                      } else {
                        TvToast.error(context, tvState.errorMessage!);
                      }
                    },
              icon: tvState.isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.login_rounded),
              label: const Text(
                'Connect Xtream Service',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
