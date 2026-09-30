import 'package:flutter/material.dart';
import 'package:nafir/app/app_configuration.dart';
import 'package:nafir/core/format_size.dart';
import 'package:nafir/core/widgets/glass_surface.dart';
import 'package:nafir/features/library/application/library_controller.dart';
import 'package:nafir/features/library/application/local_audio_controller.dart';
import 'package:nafir/features/library/data/local_audio_upload.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/player/application/player_controller.dart';
import 'package:nafir/features/player/presentation/mini_player.dart';
import 'package:nafir/features/playlists/presentation/shared_playlist_screen.dart';
import 'package:nafir/features/playlists/application/playlists_controller.dart';
import 'package:nafir/features/playlists/presentation/playlists_screen.dart';
import 'package:nafir/features/bots/application/bot_link_controller.dart';
import 'package:nafir/features/bots/data/messenger_bot.dart';
import 'package:nafir/features/settings/application/cache_controller.dart';
import 'package:nafir/features/settings/presentation/settings_screen.dart';
import 'package:nafir/features/upload/application/upload_controller.dart';
import 'package:nafir/features/upload/data/audio_picker.dart';
import 'package:nafir/features/upload/presentation/upload_status_card.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.email,
    required this.onLogout,
    required this.library,
    this.playlists,
    required this.localAudio,
    required this.uploads,
    required this.cache,
    this.botLinks,
    required this.picker,
    required this.player,
  });

  final String email;
  final VoidCallback onLogout;
  final LibraryController library;
  final PlaylistsController? playlists;
  final LocalAudioController localAudio;
  final PlayerController player;
  final UploadController uploads;
  final CacheController cache;
  final BotLinkController? botLinks;
  final AudioPicker picker;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  UploadPhase _lastPhase = UploadPhase.idle;
  late final AppLifecycleListener _lifecycle;
  late final LocalAudioUploadSource _localUpload;

  @override
  void initState() {
    super.initState();
    _localUpload = createLocalAudioUploadSource();
    // Coming back from Bale or Telegram, show what was sent to the bot.
    _lifecycle = AppLifecycleListener(onResume: () {
      widget.library.load();
      widget.botLinks?.load();
    });
    widget.library.load();
    widget.botLinks?.load();
    if (widget.localAudio.supported) widget.localAudio.load();
    // Opened from a shared playlist link: show it once signed in.
    final shareToken = AppConfiguration.takeInitialShareToken();
    final playlists = widget.playlists;
    if (shareToken != null && playlists != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => SharedPlaylistScreen(
            shareToken: shareToken,
            controller: playlists,
            player: widget.player,
            onSaved: widget.library.load,
          ),
        ));
      });
    }
    widget.uploads.addListener(_onUploadChanged);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.uploads.removeListener(_onUploadChanged);
    super.dispose();
  }

  void _onUploadChanged() {
    final phase = widget.uploads.phase;
    if (phase == UploadPhase.done && _lastPhase != UploadPhase.done) {
      widget.library.load();
    }
    _lastPhase = phase;
  }

  Future<void> _pickAndUpload() async {
    final uploads = widget.uploads;
    final files = await widget.picker.pickMany(onReading: uploads.readingFile);
    if (files == null) return uploads.pickCancelled();
    await uploads.uploadAll(files);
  }

  Future<void> _uploadLocalTrack(Track track) async {
    if (!track.isLocal || widget.uploads.isBusy) return;
    widget.uploads.readingFile();
    try {
      final file = await _localUpload.prepare(track);
      await widget.uploads.upload(file);
      if (!mounted) return;
      if (widget.uploads.phase == UploadPhase.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('«${track.title}» روی سرور آپلود شد.')),
        );
        await _refreshLibrary();
      }
    } catch (_) {
      if (!mounted) return;
      widget.uploads.pickCancelled();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('آماده‌سازی آهنگ دستگاه برای آپلود ناموفق بود.'),
        ),
      );
    }
  }

  Future<void> _editTrackMetadata(Track track) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _TrackMetadataDialog(
        track: track,
        onSave: (title, artist, album) => widget.library.updateTrackMetadata(
          track.id,
          title: title,
          artist: artist,
          album: album,
        ),
      ),
    );
    if (!mounted || saved != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('اطلاعات «${track.title}» به‌روزرسانی شد.')),
    );
  }

  Future<void> _confirmDeleteTrack(Track track) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_forever_outlined),
        title: Text('حذف «${track.title}»؟'),
        content: const Text(
          'این آهنگ برای همیشه از فضای ابری و Playlistها حذف می‌شود. '
          'این کار قابل بازگشت نیست.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف برای همیشه'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final deleted = await widget.library.deleteTrack(track.id);
    if (!mounted) return;
    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('حذف آهنگ ناموفق بود. دوباره تلاش کن.')),
      );
      return;
    }
    await widget.player.removeTrack(track.id);
    if (!mounted) return;
    widget.playlists?.load();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('«${track.title}» حذف شد.')),
    );
  }

  void _openPlaylists() {
    final playlists = widget.playlists;
    if (playlists == null) return;
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => PlaylistsScreen(
              controller: playlists,
              libraryTracks: widget.library.tracks,
              player: widget.player,
            ),
          ),
        )
        // A shared playlist may have been saved, bringing its tracks along.
        .then((_) => widget.library.load());
  }

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
          builder: (_) => SettingsScreen(
            cache: widget.cache,
            botLinks: widget.botLinks,
            library: widget.library,
          ),
        ))
        // A chat may have been linked meanwhile; offer sending to it.
        .then((_) => widget.botLinks?.load());
  }

  Future<void> _sendToBot(Track track, MessengerBot bot) async {
    final links = widget.botLinks;
    if (links == null) return;
    final result = await links.send(bot.provider, track.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(switch (result) {
        BotSendResult.queued =>
          'بات نفیر «${track.title}» را در ${bot.name} برایت می‌فرستد.',
        BotSendResult.notLinked =>
          'گفتگوی ${bot.name} دیگر به حسابت وصل نیست. از تنظیمات دوباره وصلش کن.',
        BotSendResult.tooLarge =>
          '«${track.title}» برای فرستادن با بات ${bot.name} بزرگ است.',
        BotSendResult.failed =>
          'فرستادن به ${bot.name} ناموفق بود. دوباره تلاش کن.',
      }),
    ));
  }

  Future<void> _refreshLibrary() async {
    widget.botLinks?.load();
    if (widget.localAudio.supported) widget.localAudio.load();
    final ok = await widget.library.load();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('به‌روزرسانی فهرست ناموفق بود.')),
      );
    }
  }

  List<Track> _unifiedTracks() {
    final byKey = <String, Track>{};
    for (final track in widget.library.tracks) {
      byKey[track.id] = track;
    }
    for (final track in widget.localAudio.tracks) {
      byKey.putIfAbsent(track.sourceUri?.toString() ?? track.id, () => track);
    }
    return byKey.values.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: AppBar(
        toolbarHeight: MediaQuery.sizeOf(context).width >= 720 ? 76 : 64,
        titleSpacing: MediaQuery.sizeOf(context).width >= 720 ? 32 : 16,
        title: _NafirBrand(
          compact: MediaQuery.sizeOf(context).width < 720,
        ),
        actions: MediaQuery.sizeOf(context).width >= 720
            ? [
                if (widget.playlists != null) ...[
                  FilledButton.tonalIcon(
                    onPressed: _openPlaylists,
                    icon: const Icon(Icons.queue_music, size: 19),
                    label: const Text('Playlistها'),
                  ),
                  const SizedBox(width: 8),
                ],
                _AccountChip(email: widget.email),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'تنظیمات',
                  child: FilledButton.tonalIcon(
                    onPressed: _openSettings,
                    icon: const Icon(Icons.settings_outlined, size: 19),
                    label: const Text('تنظیمات'),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'خروج',
                  child: OutlinedButton.icon(
                    onPressed: widget.onLogout,
                    icon: const Icon(Icons.logout, size: 19),
                    label: const Text('خروج'),
                  ),
                ),
                const SizedBox(width: 32),
              ]
            : [
                PopupMenuButton<_HeaderAction>(
                  tooltip: 'حساب و تنظیمات',
                  icon: const Icon(Icons.account_circle_outlined),
                  onSelected: (action) {
                    switch (action) {
                      case _HeaderAction.playlists:
                        _openPlaylists();
                      case _HeaderAction.settings:
                        _openSettings();
                      case _HeaderAction.logout:
                        widget.onLogout();
                    }
                  },
                  itemBuilder: (context) => [
                    if (widget.playlists != null)
                      const PopupMenuItem(
                        value: _HeaderAction.playlists,
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.queue_music),
                          title: Text('Playlistها'),
                        ),
                      ),
                    PopupMenuItem<_HeaderAction>(
                      enabled: false,
                      child: Text(
                        widget.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: _HeaderAction.settings,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.settings_outlined),
                        title: Text('تنظیمات'),
                      ),
                    ),
                    const PopupMenuItem(
                      value: _HeaderAction.logout,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.logout),
                        title: Text('خروج از حساب'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 8),
              ],
      ),
      bottomNavigationBar: MiniPlayer(player: widget.player),
      floatingActionButton: ListenableBuilder(
        listenable: widget.uploads,
        builder: (context, _) => FloatingActionButton.extended(
          onPressed: widget.uploads.isBusy ? null : _pickAndUpload,
          icon: const Icon(Icons.add),
          label: const Text('افزودن موسیقی'),
        ),
      ),
      body: NafirBackdrop(child: _unifiedLibrary()),
    );
  }

  Widget _unifiedLibrary() => _ResponsiveLibraryContent(
        child: Column(
          children: [
            UploadStatusCard(controller: widget.uploads),
            ListenableBuilder(
              listenable: widget.library,
              builder: (context, _) => Column(
                children: [
                  if (widget.library.importsInProgress case final n when n > 0)
                    _ImportsInProgress(count: n),
                ],
              ),
            ),
            Expanded(
              child: ListenableBuilder(
                listenable: Listenable.merge([
                  widget.library,
                  widget.localAudio,
                  if (widget.botLinks != null) widget.botLinks,
                ]),
                builder: (context, _) {
                  final localStatus = widget.localAudio.status;
                  final localLoading = widget.localAudio.supported &&
                      (localStatus == LocalAudioViewStatus.idle ||
                          localStatus == LocalAudioViewStatus.loading);
                  final tracks = _unifiedTracks();

                  if (widget.library.status == LibraryStatus.loading &&
                      tracks.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (widget.library.status == LibraryStatus.error &&
                      tracks.isEmpty) {
                    return _LoadError(onRetry: widget.library.load);
                  }
                  if (localLoading && tracks.isEmpty) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final notice = _DeviceNotice.fromStatus(
                    localStatus,
                    widget.localAudio.supported,
                  );
                  return RefreshIndicator(
                    onRefresh: _refreshLibrary,
                    child: tracks.isEmpty
                        ? _EmptyLibrary(deviceNotice: notice)
                        : _TrackList(
                            tracks: tracks,
                            player: widget.player,
                            playlists: widget.playlists,
                            onDelete: _confirmDeleteTrack,
                            onEditMetadata: _editTrackMetadata,
                            isDeleting: (trackId) =>
                                widget.library.isDeleting(trackId) ||
                                widget.library.isUpdating(trackId),
                            linkedBots: widget.botLinks?.linkedBots ?? const [],
                            onSendToBot: _sendToBot,
                            onUploadToServer: _uploadLocalTrack,
                            uploadsBusy: widget.uploads.isBusy,
                            deviceNotice: notice,
                            showLocationBadges: true,
                          ),
                  );
                },
              ),
            ),
          ],
        ),
      );
}

enum _HeaderAction { playlists, settings, logout }

enum _TrackAction {
  addToPlaylist,
  sendToBot,
  uploadToServer,
  downloadToDevice,
  removeFromDevice,
  editMetadata,
  delete,
}

class _NafirBrand extends StatelessWidget {
  const _NafirBrand({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showSubtitle = !compact && constraints.maxWidth >= 220;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [NafirGlass.primary, Color(0xFFB72E50)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: NafirGlass.primary.withValues(alpha: 0.24),
                    offset: const Offset(0, 8),
                    blurRadius: 22,
                  ),
                ],
              ),
              child: const Icon(
                Icons.graphic_eq_rounded,
                color: Color(0xFFFFF5F5),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: showSubtitle
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'نفیر',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'کتابخانهٔ موسیقی',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    )
                  : const Text(
                      'نفیر',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _AccountChip extends StatelessWidget {
  const _AccountChip({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: email,
      child: GlassSurface(
        blur: 0,
        shadow: false,
        radius: 14,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.account_circle_outlined, size: 19),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResponsiveLibraryContent extends StatelessWidget {
  const _ResponsiveLibraryContent({required this.child});

  static const double _maxWidth = 880;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final horizontal = constraints.maxWidth >= 900 ? 40.0 : 16.0;
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxWidth),
            child: Padding(
              padding: EdgeInsets.fromLTRB(horizontal, 12, horizontal, 0),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

class _TrackList extends StatefulWidget {
  const _TrackList({
    required this.tracks,
    required this.player,
    this.playlists,
    this.onDelete,
    this.onEditMetadata,
    this.isDeleting,
    this.linkedBots = const [],
    this.onSendToBot,
    this.onUploadToServer,
    this.uploadsBusy = false,
    this.deviceNotice,
    this.showLocationBadges = false,
  });

  final List<Track> tracks;
  final PlayerController player;
  final PlaylistsController? playlists;
  final Future<void> Function(Track track)? onDelete;
  final Future<void> Function(Track track)? onEditMetadata;
  final bool Function(String trackId)? isDeleting;

  /// Bots with a linked chat, offered as «ارسال به …» for each track.
  final List<MessengerBot> linkedBots;
  final Future<void> Function(Track track, MessengerBot bot)? onSendToBot;
  final Future<void> Function(Track track)? onUploadToServer;
  final bool uploadsBusy;
  final _DeviceNotice? deviceNotice;
  final bool showLocationBadges;

  @override
  State<_TrackList> createState() => _TrackListState();
}

class _TrackListState extends State<_TrackList> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Track> get _filteredTracks {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return widget.tracks;
    return widget.tracks.where((track) {
      final searchable = [track.title, track.artist, track.album]
          .whereType<String>()
          .join(' ')
          .toLowerCase();
      return searchable.contains(query);
    }).toList(growable: false);
  }

  Future<void> _addToPlaylist(BuildContext context, Track track) async {
    final controller = widget.playlists;
    if (controller == null) return;
    final loaded = await controller.load();
    if (!context.mounted) return;
    if (!loaded) {
      _message(context, 'دریافت Playlistها ناموفق بود.');
      return;
    }
    if (controller.playlists.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Playlistی نداری'),
          content: const Text('اول از بخش Playlistها یک Playlist بساز.'),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('متوجه شدم'),
            ),
          ],
        ),
      );
      return;
    }
    final playlistId = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('افزودن به Playlist'),
        children: [
          for (final playlist in controller.playlists)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, playlist.id),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.queue_music),
                title: Text(playlist.name),
                subtitle: Text('${playlist.trackCount} قطعه موسیقی'),
              ),
            ),
        ],
      ),
    );
    if (playlistId == null) return;
    final result = await controller.addTrack(playlistId, track.id);
    if (!context.mounted) return;
    switch (result) {
      case AddTrackResult.added:
        _message(context, 'آهنگ به Playlist اضافه شد.');
      case AddTrackResult.alreadyPresent:
        _message(context, 'این آهنگ از قبل در Playlist است.');
      case AddTrackResult.failure:
        _message(context, 'افزودن آهنگ به Playlist ناموفق بود.');
    }
  }

  void _message(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _filteredTracks;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
          child: Row(
            children: [
              Text(
                'آهنگ‌ها',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              if (MediaQuery.sizeOf(context).width >= 520)
                FilledButton.tonalIcon(
                  onPressed: tracks.isEmpty
                      ? null
                      : () => widget.player.playShuffled(tracks),
                  icon: const Icon(Icons.shuffle_rounded, size: 18),
                  label: Text(
                    _query.trim().isEmpty
                        ? 'پخش تصادفی همه'
                        : 'پخش تصادفی نتایج',
                  ),
                )
              else
                IconButton.filledTonal(
                  tooltip: _query.trim().isEmpty
                      ? 'پخش تصادفی همه'
                      : 'پخش تصادفی نتایج',
                  onPressed: tracks.isEmpty
                      ? null
                      : () => widget.player.playShuffled(tracks),
                  icon: const Icon(Icons.shuffle_rounded),
                ),
              if (MediaQuery.sizeOf(context).width >= 520) ...[
                const SizedBox(width: 12),
                Text(
                  '${tracks.length} از ${widget.tracks.length} قطعه',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
        if (widget.deviceNotice case final notice?)
          _DeviceStatusBanner(notice: notice),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: SearchBar(
            controller: _search,
            hintText: 'جست‌وجوی آهنگ، خواننده یا آلبوم',
            leading: const Icon(Icons.search),
            trailing: [
              if (_query.isNotEmpty)
                IconButton(
                  tooltip: 'پاک کردن جست‌وجو',
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                  icon: const Icon(Icons.close),
                ),
            ],
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: widget.player,
            builder: (context, _) {
              if (tracks.isEmpty) {
                return ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 72, 24, 96),
                  children: [
                    _LibraryState(
                      icon: Icons.search_off_rounded,
                      title: 'نتیجه‌ای پیدا نشد',
                      message: 'عبارت دیگری را امتحان کن یا جست‌وجو را پاک کن.',
                      action: OutlinedButton.icon(
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close),
                        label: const Text('پاک کردن جست‌وجو'),
                      ),
                    ),
                  ],
                );
              }
              return ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 128),
                itemCount: tracks.length,
                itemBuilder: (context, index) {
                  final track = tracks[index];
                  final current = widget.player.track?.id == track.id;
                  final artist = track.artist?.trim();
                  final artistLabel = artist == null || artist.isEmpty
                      ? 'خواننده نامشخص'
                      : artist;
                  return ListTile(
                    selected: current,
                    onTap: () => widget.player.playFrom(tracks, index),
                    leading: CircleAvatar(
                      backgroundColor: current
                          ? Theme.of(context).colorScheme.secondaryContainer
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                      foregroundColor: current
                          ? Theme.of(context).colorScheme.onSecondaryContainer
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      child: Icon(
                        current
                            ? Icons.graphic_eq
                            : track.isLocal
                                ? Icons.phone_android
                                : Icons.music_note,
                      ),
                    ),
                    title: Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: current ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    subtitle: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Text(
                            artistLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (widget.showLocationBadges)
                          _TrackLocationBadge(track: track),
                        if (track.importedFrom case final from?)
                          _TrackMetaPill(
                            icon: Icons.smart_toy_outlined,
                            label: 'از $from',
                          ),
                        _TrackMetaPill(
                          icon: Icons.sd_storage_outlined,
                          label: formatSize(track.sizeBytes),
                        ),
                      ],
                    ),
                    trailing: widget.playlists == null &&
                            widget.onDelete == null &&
                            widget.linkedBots.isEmpty &&
                            !widget.showLocationBadges
                        ? null
                        : widget.isDeleting?.call(track.id) == true
                            ? const SizedBox.square(
                                dimension: 48,
                                child: Padding(
                                  padding: EdgeInsets.all(12),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                  ),
                                ),
                              )
                            : PopupMenuButton<(_TrackAction, MessengerBot?)>(
                                tooltip: 'اقدامات آهنگ',
                                onSelected: (choice) {
                                  switch (choice) {
                                    case (_TrackAction.addToPlaylist, _):
                                      _addToPlaylist(context, track);
                                    case (_TrackAction.sendToBot, final bot?):
                                      widget.onSendToBot?.call(track, bot);
                                    case (_TrackAction.delete, _):
                                      widget.onDelete?.call(track);
                                    case (_TrackAction.editMetadata, _):
                                      widget.onEditMetadata?.call(track);
                                    case (_TrackAction.uploadToServer, _):
                                      widget.onUploadToServer?.call(track);
                                    case (_TrackAction.downloadToDevice, _):
                                      _message(
                                        context,
                                        'دانلود روی دستگاه در issue #43 دنبال می‌شود.',
                                      );
                                    case (_TrackAction.removeFromDevice, _):
                                      _message(
                                        context,
                                        'حذف نسخهٔ دستگاه در گام sync اضافه می‌شود.',
                                      );
                                    case (_TrackAction.sendToBot, null):
                                      break;
                                  }
                                },
                                itemBuilder: (context) => [
                                  if (widget.showLocationBadges &&
                                      track.isLocal)
                                    PopupMenuItem(
                                      value: const (
                                        _TrackAction.uploadToServer,
                                        null
                                      ),
                                      enabled: !widget.uploadsBusy,
                                      child: const ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading:
                                            Icon(Icons.cloud_upload_outlined),
                                        title: Text('آپلود به سرور'),
                                      ),
                                    ),
                                  if (widget.showLocationBadges &&
                                      !track.isLocal)
                                    const PopupMenuItem(
                                      value: (
                                        _TrackAction.downloadToDevice,
                                        null
                                      ),
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                          Icons.download_for_offline_outlined,
                                        ),
                                        title: Text('دانلود روی دستگاه'),
                                      ),
                                    ),
                                  if (!track.isLocal)
                                    const PopupMenuItem(
                                      value: (_TrackAction.editMetadata, null),
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(Icons.edit_outlined),
                                        title: Text('ویرایش اطلاعات آهنگ'),
                                      ),
                                    ),
                                  if (widget.playlists != null &&
                                      !track.isLocal)
                                    const PopupMenuItem(
                                      value: (_TrackAction.addToPlaylist, null),
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(Icons.playlist_add),
                                        title: Text('افزودن به Playlist'),
                                      ),
                                    ),
                                  if (!track.isLocal)
                                    for (final bot in widget.linkedBots)
                                      PopupMenuItem(
                                        value: (_TrackAction.sendToBot, bot),
                                        child: ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: const Icon(Icons.send),
                                          title: Text('ارسال به ${bot.name}'),
                                        ),
                                      ),
                                  if (widget.onDelete != null && !track.isLocal)
                                    PopupMenuItem(
                                      value: (_TrackAction.delete, null),
                                      child: ListTile(
                                        contentPadding: EdgeInsets.zero,
                                        leading: Icon(
                                          Icons.delete_outline,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                        title: Text(
                                          'حذف آهنگ',
                                          style: TextStyle(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .error,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TrackMetadataDialog extends StatefulWidget {
  const _TrackMetadataDialog({
    required this.track,
    required this.onSave,
  });

  final Track track;
  final Future<bool> Function(String title, String? artist, String? album)
      onSave;

  @override
  State<_TrackMetadataDialog> createState() => _TrackMetadataDialogState();
}

class _TrackMetadataDialogState extends State<_TrackMetadataDialog> {
  late final TextEditingController _title =
      TextEditingController(text: widget.track.title);
  late final TextEditingController _artist =
      TextEditingController(text: widget.track.artist ?? '');
  late final TextEditingController _album =
      TextEditingController(text: widget.track.album ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'عنوان آهنگ نباید خالی باشد.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await widget.onSave(title, _artist.text, _album.text);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _saving = false;
      _error = 'ذخیرهٔ اطلاعات ناموفق بود. دوباره تلاش کن.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.edit_note_outlined),
      title: const Text('ویرایش اطلاعات آهنگ'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              enabled: !_saving,
              autofocus: true,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'عنوان',
                prefixIcon: Icon(Icons.music_note_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _artist,
              enabled: !_saving,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'خواننده',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _album,
              enabled: !_saving,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!_saving) _save();
              },
              decoration: const InputDecoration(
                labelText: 'آلبوم',
                prefixIcon: Icon(Icons.album_outlined),
              ),
            ),
            if (_error case final error?) ...[
              const SizedBox(height: 12),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('انصراف'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check),
          label: const Text('ذخیره'),
        ),
      ],
    );
  }
}

class _TrackLocationBadge extends StatelessWidget {
  const _TrackLocationBadge({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    return _TrackMetaPill(
      icon: track.isLocal ? Icons.phone_android : Icons.cloud_done_outlined,
      label: track.isLocal ? 'دستگاه' : 'سرور',
      emphasized: !track.isLocal,
    );
  }
}

class _TrackMetaPill extends StatelessWidget {
  const _TrackMetaPill({
    required this.icon,
    required this.label,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground = emphasized ? colors.primary : colors.onSurfaceVariant;
    final background = emphasized
        ? colors.primaryContainer.withValues(alpha: 0.35)
        : colors.surfaceContainerHighest.withValues(alpha: 0.55);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: foreground),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontSize: 11,
                fontWeight: emphasized ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceNotice {
  const _DeviceNotice({
    required this.icon,
    required this.message,
    required this.actionLabel,
  });

  final IconData icon;
  final String message;
  final String actionLabel;

  static _DeviceNotice? fromStatus(
    LocalAudioViewStatus status,
    bool supported,
  ) {
    if (!supported || status == LocalAudioViewStatus.loaded) return null;
    return switch (status) {
      LocalAudioViewStatus.permissionDenied => const _DeviceNotice(
          icon: Icons.folder_off_outlined,
          message: 'برای نمایش آهنگ‌های دستگاه، اجازهٔ دسترسی صوتی لازم است.',
          actionLabel: 'از تنظیمات دستگاه اجازه بده',
        ),
      LocalAudioViewStatus.error => const _DeviceNotice(
          icon: Icons.error_outline,
          message:
              'خواندن آهنگ‌های دستگاه ناموفق بود؛ آهنگ‌های سرور همچنان دیده می‌شوند.',
          actionLabel: 'صفحه را پایین بکش',
        ),
      LocalAudioViewStatus.unsupported => null,
      LocalAudioViewStatus.idle ||
      LocalAudioViewStatus.loading =>
        const _DeviceNotice(
          icon: Icons.sync,
          message: 'در حال بررسی آهنگ‌های روی دستگاه…',
          actionLabel: 'Library یکپارچه می‌ماند',
        ),
      LocalAudioViewStatus.loaded => null,
    };
  }
}

class _DeviceStatusBanner extends StatelessWidget {
  const _DeviceStatusBanner({required this.notice});

  final _DeviceNotice notice;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: GlassSurface(
        blur: 8,
        radius: 16,
        shadow: false,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(notice.icon, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                notice.message,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              notice.actionLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImportsInProgress extends StatelessWidget {
  const _ImportsInProgress({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          const SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 1
                  ? 'یک فایل از بات در حال اضافه شدن است…'
                  : '$count فایل از بات در حال اضافه شدن است…',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryState extends StatelessWidget {
  const _LibraryState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.secondaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Icon(icon, size: 36, color: colors.onSecondaryContainer),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.6,
                  ),
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({this.deviceNotice});

  final _DeviceNotice? deviceNotice;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 72, 24, 140),
      children: [
        if (deviceNotice case final notice?) ...[
          _DeviceStatusBanner(notice: notice),
          const SizedBox(height: 16),
        ],
        const _LibraryState(
          icon: Icons.library_music_outlined,
          title: 'کتابخانهٔ شما خالی است',
          message:
              'با «افزودن موسیقی» آهنگ آپلود کن یا اجازه بده نفیر آهنگ‌های دستگاه را هم همین‌جا نشان بدهد.',
        ),
      ],
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: _LibraryState(
        icon: Icons.cloud_off_outlined,
        title: 'کتابخانه دریافت نشد',
        message: 'اتصال اینترنت را بررسی کن و دوباره تلاش کن.',
        action: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
          label: const Text('تلاش دوباره'),
        ),
      ),
    );
  }
}
