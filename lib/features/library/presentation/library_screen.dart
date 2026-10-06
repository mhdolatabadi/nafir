import 'package:nafir/core/persian_digits.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:nafir/core/widgets/nafir_icons.dart';
import 'package:nafir/app/app_configuration.dart';
import 'package:nafir/core/format_size.dart';
import 'package:nafir/core/widgets/glass_surface.dart';
import 'package:nafir/features/library/application/library_controller.dart';
import 'package:nafir/features/library/application/library_entries.dart';
import 'package:nafir/features/library/application/library_sync_controller.dart';
import 'package:nafir/features/link_import/application/link_import_controller.dart';
import 'package:nafir/features/link_import/presentation/link_import_dialog.dart';
import 'package:nafir/features/library/application/track_groups.dart';
import 'package:nafir/features/library/application/track_sort.dart';
import 'package:nafir/features/library/application/local_audio_controller.dart';
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
    this.verified = false,
    this.onAdmin,
    required this.onLogout,
    this.onDeleteAccount,
    required this.library,
    this.playlists,
    required this.localAudio,
    required this.uploads,
    required this.sync,
    required this.cache,
    this.botLinks,
    this.linkImports,
    required this.picker,
    required this.player,
  });

  final String email;
  final bool verified;
  final VoidCallback? onAdmin;
  final VoidCallback onLogout;

  /// Deletes the account after checking [password]; null hides the option.
  final Future<void> Function(String password)? onDeleteAccount;
  final LibraryController library;
  final PlaylistsController? playlists;
  final LocalAudioController localAudio;
  final PlayerController player;
  final UploadController uploads;
  final LibrarySyncController sync;
  final CacheController cache;
  final BotLinkController? botLinks;

  /// Adds music from song pages and audio links; null hides the action.
  final LinkImportController? linkImports;
  final AudioPicker picker;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  UploadPhase _lastPhase = UploadPhase.idle;

  /// «آهنگ‌ها», «فهرست‌های پخش» when available, «آلبوم‌ها» and «هنرمندان».
  late final TabController _tabs = TabController(
    length: widget.playlists == null ? 3 : 4,
    vsync: this,
  )..addListener(_onTabChanged);

  /// Once nothing is being imported any more, finds out how this
  /// session's link imports ended.
  void _onLibraryChanged() {
    final links = widget.linkImports;
    if (links != null &&
        links.hasPending &&
        widget.library.importsInProgress == 0) {
      links.refresh();
    }
  }

  Future<void> _importFromLink() async {
    final links = widget.linkImports;
    if (links == null) return;
    final message = await showLinkImportDialog(context, controller: links);
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    // Shows the import in progress and follows it until it is done.
    await widget.library.load();
  }

  void _onTabChanged() {
    // The add-music button belongs to the tracks tab.
    if (!_tabs.indexIsChanging) setState(() {});
  }

  late final AppLifecycleListener _lifecycle;
  late final StreamSubscription<SyncOperation> _syncFinished;

  @override
  void initState() {
    super.initState();
    _syncFinished = widget.sync.finished.listen(_onSyncFinished);
    // Coming back from Bale or Telegram, show what was sent to the bot.
    _lifecycle = AppLifecycleListener(onResume: () {
      widget.library.load();
      widget.botLinks?.load();
    });
    widget.library.load();
    widget.botLinks?.load();
    widget.library.addListener(_onLibraryChanged);
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
    // Opened from a collaboration link: join it once signed in.
    final collabToken = AppConfiguration.takeInitialCollabToken();
    if (collabToken != null && playlists != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        joinCollabPlaylist(context,
            collabToken: collabToken,
            controller: playlists,
            libraryTracks: widget.library.tracks,
            player: widget.player);
      });
    }
    widget.uploads.addListener(_onUploadChanged);
  }

  @override
  void dispose() {
    _tabs.dispose();
    _lifecycle.dispose();
    widget.uploads.removeListener(_onUploadChanged);
    _syncFinished.cancel();
    widget.library.removeListener(_onLibraryChanged);
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

  void _onSyncFinished(SyncOperation operation) {
    if (!mounted) return;
    final title = operation.track.title;
    final error = operation.error;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error == null
          ? '«$title» روی سرور آپلود شد.'
          : 'آپلود «$title» ناموفق بود. ${syncErrorMessage(error)}'),
    ));
  }

  Future<void> _confirmRemoveFromDevice(Track track) async {
    final synced = locationOf(track) == TrackLocation.synced;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(NafirIcons.deviceMobile),
        title: Text('حذف «${track.title}» از دستگاه؟'),
        content: Text(synced
            ? 'فایل از حافظهٔ دستگاه پاک می‌شود و نسخهٔ سرور می‌ماند.'
            : 'این آهنگ روی سرور نیست؛ با حذف از دستگاه برای همیشه پاک می‌شود.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            style: synced
                ? null
                : FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                    foregroundColor: Theme.of(context).colorScheme.onError,
                  ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف از دستگاه'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await widget.localAudio.delete(track);
    if (!mounted) return;
    final message = switch (result) {
      DeviceDeleteResult.deleted => '«${track.title}» از دستگاه حذف شد.',
      DeviceDeleteResult.declined => null,
      DeviceDeleteResult.permissionDenied =>
        'ریتمو اجازهٔ تغییر حافظهٔ دستگاه را ندارد.',
      DeviceDeleteResult.failed => 'حذف از دستگاه ناموفق بود.',
    };
    if (result == DeviceDeleteResult.deleted && !synced) {
      await widget.player.removeTrack(track.id);
    }
    if (message == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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
        icon: const Icon(NafirIcons.trash),
        title: Text('حذف «${track.title}»؟'),
        content: Text(locationOf(track) == TrackLocation.synced
            ? 'نسخهٔ سرور برای همیشه از فضای ابری و فهرست‌های پخش حذف می‌شود؛ '
                'فایل روی دستگاه می‌ماند.'
            : 'این آهنگ برای همیشه از فضای ابری و فهرست‌های پخش حذف می‌شود. '
                'این کار قابل بازگشت نیست.'),
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
            child: Text(locationOf(track) == TrackLocation.synced
                ? 'حذف از سرور'
                : 'حذف برای همیشه'),
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

  void _openSettings() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
          builder: (_) => SettingsScreen(
            email: widget.email,
            onDeleteAccount: widget.onDeleteAccount,
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
          'بات ریتمو «${track.title}» را در ${bot.name} برایت می‌فرستد.',
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

  /// Each file once: the account's tracks, matched with their copies on
  /// this device, then the device's other music.
  List<Track> _unifiedTracks() => [
        for (final entry
            in mergeLibrary(widget.library.tracks, widget.localAudio.tracks))
          entry.track,
      ];

  List<Widget> _accountActions(BuildContext context) {
    final wideActions = widget.onAdmin == null ? 720 : 960;
    if (MediaQuery.sizeOf(context).width >= wideActions) {
      return [
        _AccountChip(email: widget.email),
        if (widget.verified)
          const Tooltip(
            message: 'حساب تأییدشده',
            child: Icon(NafirIcons.checkCircle),
          ),
        if (widget.onAdmin != null)
          TextButton.icon(
            onPressed: widget.onAdmin,
            icon: const Icon(NafirIcons.usersFill),
            label: const Text('مدیریت حساب‌ها'),
          ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'تنظیمات',
          child: FilledButton.tonalIcon(
            onPressed: _openSettings,
            icon: const Icon(NafirIcons.gear, size: 19),
            label: const Text('تنظیمات'),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: 'خروج',
          child: OutlinedButton.icon(
            onPressed: widget.onLogout,
            icon: const Icon(NafirIcons.signOut, size: 19),
            label: const Text('خروج'),
          ),
        ),
        const SizedBox(width: 32),
      ];
    }
    return [
      PopupMenuButton<_HeaderAction>(
        tooltip: 'حساب و تنظیمات',
        icon: const Icon(NafirIcons.userCircle),
        onSelected: (action) {
          switch (action) {
            case _HeaderAction.settings:
              _openSettings();
            case _HeaderAction.admin:
              widget.onAdmin?.call();
            case _HeaderAction.logout:
              widget.onLogout();
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem<_HeaderAction>(
            enabled: false,
            child: Text(
              widget.email,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.verified)
            const PopupMenuItem<_HeaderAction>(
              enabled: false,
              child: Text('حساب تأییدشده'),
            ),
          if (widget.onAdmin != null)
            const PopupMenuItem(
              value: _HeaderAction.admin,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(NafirIcons.usersFill),
                title: Text('مدیریت حساب‌ها'),
              ),
            ),
          const PopupMenuDivider(),
          const PopupMenuItem(
            value: _HeaderAction.settings,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(NafirIcons.gear),
              title: Text('تنظیمات'),
            ),
          ),
          const PopupMenuItem(
            value: _HeaderAction.logout,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(NafirIcons.signOut),
              title: Text('خروج از حساب'),
            ),
          ),
        ],
      ),
      const SizedBox(width: 8),
    ];
  }

  /// Height of the big title area above the toolbar when fully expanded.
  static const double _largeTitleHeight = 88;

  /// The large, collapsing title with the category tabs pinned under it.
  Widget _header(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final tabs = TabBar(
      controller: _tabs,
      // On a phone the four short tabs share the width so all stay in view;
      // on wide screens they sit together at the start.
      isScrollable: wide,
      tabAlignment: wide ? TabAlignment.start : TabAlignment.fill,
      labelStyle: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w800),
      unselectedLabelStyle: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w500),
      tabs: [
        const Tab(text: 'آهنگ‌ها'),
        if (widget.playlists != null) const Tab(text: 'فهرست‌های پخش'),
        const Tab(text: 'آلبوم‌ها'),
        const Tab(text: 'هنرمندان'),
      ],
    );
    final bar = wide
        ? SliverAppBar(
            pinned: true,
            toolbarHeight: 76,
            titleSpacing: 32,
            title: const _NafirBrand(compact: false),
            actions: _accountActions(context),
            bottom: tabs,
          )
        : SliverAppBar(
            pinned: true,
            expandedHeight: _largeTitleHeight + kToolbarHeight,
            // Opaque, because the lists scroll underneath it.
            backgroundColor: NafirGlass.background,
            actions: _accountActions(context),
            flexibleSpace: const _CollapsingTitle(),
            bottom: tabs,
          );
    return SliverOverlapAbsorber(
      handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
      sliver: bar,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      bottomNavigationBar: MiniPlayer(player: widget.player),
      floatingActionButton: _tabs.index != 0
          ? null
          : ListenableBuilder(
              listenable: widget.uploads,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.linkImports != null) ...[
                    FloatingActionButton.small(
                      heroTag: 'link-import',
                      tooltip: 'افزودن از لینک',
                      onPressed: _importFromLink,
                      child: const Icon(NafirIcons.link),
                    ),
                    const SizedBox(height: 12),
                  ],
                  FloatingActionButton.extended(
                    heroTag: 'upload',
                    onPressed: widget.uploads.isBusy ? null : _pickAndUpload,
                    icon: const Icon(NafirIcons.plus),
                    label: const Text('افزودن موسیقی'),
                  ),
                ],
              ),
            ),
      body: NafirBackdrop(
        child: NestedScrollView(
          headerSliverBuilder: (context, _) => [_header(context)],
          body: TabBarView(
            controller: _tabs,
            children: [
              _Tab(child: _unifiedLibrary()),
              if (widget.playlists case final playlists?)
                _Tab(
                  child: PlaylistsView(
                    controller: playlists,
                    libraryTracks: widget.library.tracks,
                    player: widget.player,
                    onSharedSaved: widget.library.load,
                    underHeader: true,
                  ),
                ),
              _Tab(child: _groupsTab(albums: true)),
              _Tab(child: _groupsTab(albums: false)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _groupsTab({required bool albums}) => ListenableBuilder(
        listenable: Listenable.merge([widget.library, widget.localAudio]),
        builder: (context, _) {
          final tracks = _unifiedTracks();
          return _GroupList(
            groups: albums ? groupByAlbum(tracks) : groupByArtist(tracks),
            albums: albums,
            onOpen: (group) => _openGroup(group, albums: albums),
          );
        },
      );

  void _openGroup(TrackGroup group, {required bool albums}) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _TrackGroupScreen(
        groupKey: group.key,
        albums: albums,
        library: Listenable.merge([widget.library, widget.localAudio]),
        tracks: _unifiedTracks,
        player: widget.player,
      ),
    ));
  }

  Widget _unifiedLibrary() => ListenableBuilder(
        listenable: Listenable.merge([
          widget.library,
          widget.localAudio,
          widget.sync,
          if (widget.botLinks != null) widget.botLinks,
        ]),
        builder: (context, _) {
          final localStatus = widget.localAudio.status;
          final localLoading = widget.localAudio.supported &&
              (localStatus == LocalAudioViewStatus.idle ||
                  localStatus == LocalAudioViewStatus.loading);
          final tracks = _unifiedTracks();
          final top = Column(
            children: [
              UploadStatusCard(controller: widget.uploads),
              if (widget.linkImports case final links?)
                LinkImportFailures(controller: links),
              if (widget.library.importsInProgress case final n when n > 0)
                _ImportsInProgress(count: n),
            ],
          );
          Widget state(Widget child) => _TabScrollView(slivers: [
                SliverToBoxAdapter(child: top),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 56),
                    child: child,
                  ),
                ),
              ]);

          if (tracks.isEmpty &&
              (widget.library.status == LibraryStatus.loading ||
                  localLoading)) {
            return state(const Center(child: CircularProgressIndicator()));
          }
          if (widget.library.status == LibraryStatus.error && tracks.isEmpty) {
            return state(_LoadError(onRetry: widget.library.load));
          }
          final notice = _DeviceNotice.fromStatus(
            localStatus,
            widget.localAudio.supported,
          );
          return RefreshIndicator(
            onRefresh: _refreshLibrary,
            child: tracks.isEmpty
                ? state(_EmptyLibrary(deviceNotice: notice))
                : _TrackList(
                    top: top,
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
                    sync: widget.sync,
                    onRemoveFromDevice: widget.localAudio.supported
                        ? _confirmRemoveFromDevice
                        : null,
                    deviceNotice: notice,
                  ),
          );
        },
      );
}

enum _HeaderAction { settings, logout, admin }

enum _TrackAction {
  addToPlaylist,
  sendToBot,
  uploadToServer,
  removeFromDevice,
  retrySync,
  cancelSync,
  dismissSync,
  editMetadata,
  delete,
}

/// The phone header's title: large above the tabs, shrinking into the
/// toolbar as the library scrolls, as in Samsung Music.
class _CollapsingTitle extends StatelessWidget {
  const _CollapsingTitle();

  @override
  Widget build(BuildContext context) {
    final settings =
        context.dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>()!;
    final range = settings.maxExtent - settings.minExtent;
    // 1 when fully expanded, 0 when collapsed into the toolbar.
    final open = range <= 0
        ? 0.0
        : ((settings.currentExtent - settings.minExtent) / range)
            .clamp(0.0, 1.0);
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final tabsHeight = settings.minExtent - top - kToolbarHeight;
    return Stack(
      children: [
        // The small title, in the toolbar once the large one is gone.
        PositionedDirectional(
          top: top,
          start: 16,
          height: kToolbarHeight,
          child: Opacity(
            opacity: (1 - open * 2).clamp(0.0, 1.0),
            child: ExcludeSemantics(
              excluding: open > 0.5,
              child: const Row(
                children: [
                  _NafirMark(size: 32),
                  SizedBox(width: 10),
                  Text(
                    'ریتمو',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ),
        // The large title, just above the tabs.
        PositionedDirectional(
          start: 20,
          end: 20,
          bottom: tabsHeight + 12,
          child: Opacity(
            opacity: open,
            child: ExcludeSemantics(
              excluding: open <= 0.5,
              child: Transform.scale(
                scale: 0.8 + 0.2 * open,
                alignment: AlignmentDirectional.bottomStart,
                child: Row(
                  children: [
                    const _NafirMark(size: 44),
                    const SizedBox(width: 14),
                    Flexible(
                      child: Text(
                        'ریتمو',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The rhythmo logo mark: the horn's sound wave on the brand gradient.
class _NafirMark extends StatelessWidget {
  const _NafirMark({this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
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
      child: Icon(
        NafirIcons.waveform,
        size: size * 0.55,
        color: const Color(0xFFFFF5F5),
      ),
    );
  }
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
            const _NafirMark(),
            const SizedBox(width: 12),
            Flexible(
              child: showSubtitle
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'ریتمو',
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
                      'ریتمو',
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
              const Icon(NafirIcons.userCircle, size: 19),
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

/// One library tab, kept alive so its scroll position survives switching
/// tabs.
class _Tab extends StatefulWidget {
  const _Tab({required this.child});

  final Widget child;

  @override
  State<_Tab> createState() => _TabState();
}

class _TabState extends State<_Tab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

/// Albums or artists, each played from its first track when tapped.
/// Albums as a grid of cards, or artists as a list; each opens its page.
class _GroupList extends StatelessWidget {
  const _GroupList({
    required this.groups,
    required this.albums,
    required this.onOpen,
  });

  final List<TrackGroup> groups;
  final bool albums;
  final void Function(TrackGroup group) onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (groups.isEmpty) {
      return _TabScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 56, 8, 0),
            sliver: SliverToBoxAdapter(
              child: _LibraryState(
                icon: albums ? NafirIcons.vinylRecord : NafirIcons.user,
                title: albums ? 'هنوز آلبومی نیست' : 'هنوز خواننده‌ای نیست',
                message: 'با افزودن موسیقی، آلبوم‌ها و خواننده‌ها اینجا '
                    'دسته‌بندی می‌شوند.',
              ),
            ),
          ),
        ],
      );
    }
    if (albums) {
      return _TabScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.only(top: 8),
            sliver: SliverGrid.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 200,
                mainAxisSpacing: 16,
                crossAxisSpacing: 14,
                // The square cover plus two lines of text.
                childAspectRatio: 0.74,
              ),
              itemCount: groups.length,
              itemBuilder: (context, index) => _AlbumCard(
                group: groups[index],
                onTap: () => onOpen(groups[index]),
              ),
            ),
          ),
        ],
      );
    }
    return _TabScrollView(
      slivers: [
        SliverList.builder(
          itemCount: groups.length,
          itemBuilder: (context, index) {
            final group = groups[index];
            return ListTile(
              minTileHeight: 64,
              minVerticalPadding: 14,
              contentPadding:
                  const EdgeInsetsDirectional.only(start: 8, end: 8),
              leading: _GroupArt(albums: false, size: 48),
              title: Text(
                group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: group.unknown ? colors.onSurfaceVariant : null,
                ),
              ),
              subtitle: Text(
                '${persianDigits(group.tracks.length)} آهنگ',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              trailing: const Icon(NafirIcons.caretLeft),
              onTap: () => onOpen(group),
            );
          },
        ),
      ],
    );
  }
}

/// A rounded square for an album, a circle for an artist.
class _GroupArt extends StatelessWidget {
  const _GroupArt({required this.albums, required this.size});

  final bool albums;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(albums ? size * 0.16 : size / 2),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [colors.surfaceContainerHighest, colors.primaryContainer],
        ),
      ),
      child: Icon(
        albums ? NafirIcons.vinylRecord : NafirIcons.user,
        size: size * 0.45,
        color: colors.onSurfaceVariant,
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.group, required this.onTap});

  final TrackGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (context, constraints) =>
                  _GroupArt(albums: true, size: constraints.maxWidth),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            group.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: group.unknown ? colors.onSurfaceVariant : null,
            ),
          ),
          Text(
            [
              if (group.artist case final artist?) artist,
              '${persianDigits(group.tracks.length)} آهنگ'
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// One album or artist: its tracks, with play-all and shuffle. It follows
/// the library, so edits and deletions show up while it is open.
class _TrackGroupScreen extends StatelessWidget {
  const _TrackGroupScreen({
    required this.groupKey,
    required this.albums,
    required this.library,
    required this.tracks,
    required this.player,
  });

  final String groupKey;
  final bool albums;
  final Listenable library;
  final List<Track> Function() tracks;
  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([library, player]),
      builder: (context, _) {
        final all = tracks();
        final group = groupWithKey(
            albums ? groupByAlbum(all) : groupByArtist(all), groupKey);
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(
            title: Text(
              group?.name ?? (albums ? 'آلبوم' : 'خواننده'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          bottomNavigationBar: MiniPlayer(player: player),
          body: NafirBackdrop(
            child: group == null
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: _LibraryState(
                      icon: NafirIcons.musicNotesMinus,
                      title: 'آهنگی نمانده است',
                      message: 'آهنگ‌های این بخش حذف یا ویرایش شده‌اند.',
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final side = constraints.maxWidth >= 900
                          ? (constraints.maxWidth - 880) / 2
                          : 16.0;
                      final groupTracks = group.tracks;
                      return CustomScrollView(
                        slivers: [
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(side, 20, side, 8),
                            sliver: SliverToBoxAdapter(
                              child: Column(
                                children: [
                                  _GroupArt(albums: albums, size: 132),
                                  const SizedBox(height: 16),
                                  Text(
                                    group.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: theme.textTheme.headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    [
                                      if (group.artist case final artist?)
                                        artist,
                                      '${persianDigits(groupTracks.length)} آهنگ',
                                    ].join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                        color:
                                            theme.colorScheme.onSurfaceVariant),
                                  ),
                                  const SizedBox(height: 16),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 8,
                                    alignment: WrapAlignment.center,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: () =>
                                            player.playFrom(groupTracks, 0),
                                        icon: const Icon(NafirIcons.playFill),
                                        label: const Text('پخش همه'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            player.playShuffled(groupTracks),
                                        icon: const Icon(NafirIcons.shuffle),
                                        label: const Text('پخش تصادفی'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          SliverPadding(
                            // Room for the mini player under the last row.
                            padding: EdgeInsets.fromLTRB(side, 8, side, 128),
                            sliver: SliverList.builder(
                              itemCount: groupTracks.length,
                              itemBuilder: (context, index) {
                                final track = groupTracks[index];
                                return _TrackRow(
                                  track: track,
                                  current: player.track?.id == track.id,
                                  onTap: () =>
                                      player.playFrom(groupTracks, index),
                                  actions: null,
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
          ),
        );
      },
    );
  }
}

class _TrackList extends StatefulWidget {
  const _TrackList({
    this.top,
    required this.tracks,
    required this.player,
    this.playlists,
    this.onDelete,
    this.onEditMetadata,
    this.isDeleting,
    this.linkedBots = const [],
    this.onSendToBot,
    this.sync,
    this.onRemoveFromDevice,
    this.deviceNotice,
  });

  /// Shown above the search, scrolling with the list.
  final Widget? top;
  final List<Track> tracks;
  final PlayerController player;
  final PlaylistsController? playlists;
  final Future<void> Function(Track track)? onDelete;
  final Future<void> Function(Track track)? onEditMetadata;
  final bool Function(String trackId)? isDeleting;

  /// Bots with a linked chat, offered as «ارسال به …» for each track.
  final List<MessengerBot> linkedBots;
  final Future<void> Function(Track track, MessengerBot bot)? onSendToBot;

  /// Device and server copies: when set, rows show transfers and offer
  /// uploading, retrying and cancelling.
  final LibrarySyncController? sync;
  final Future<void> Function(Track track)? onRemoveFromDevice;
  final _DeviceNotice? deviceNotice;

  @override
  State<_TrackList> createState() => _TrackListState();
}

class _TrackListState extends State<_TrackList> {
  static const _createPlaylistAction = '__create_playlist__';

  final TextEditingController _search = TextEditingController();
  String _query = '';

  /// Kept for the whole session, whichever screen shows the list.
  static TrackSort _sessionSort = TrackSort.recent;
  TrackSort _sort = _sessionSort;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Track> get _filteredTracks {
    final query = _query.trim().toLowerCase();
    final matching = query.isEmpty
        ? widget.tracks
        : widget.tracks.where((track) {
            final searchable = [track.title, track.artist, track.album]
                .whereType<String>()
                .join(' ')
                .toLowerCase();
            return searchable.contains(query);
          }).toList(growable: false);
    return sortTracks(matching, _sort);
  }

  void _setSort(TrackSort sort) => setState(() {
        _sort = sort;
        _sessionSort = sort;
      });

  /// The track's «اقدامات آهنگ» menu, or null when there is nothing to offer.
  Widget? _actionsFor(BuildContext context, Track track) {
    final sync = widget.sync;
    final location = locationOf(track);
    final onServer = location != TrackLocation.device;
    final onDevice = location != TrackLocation.server;
    final operation = sync?.operationFor(track.id);
    if (widget.isDeleting?.call(track.id) == true) {
      return const SizedBox.square(
        dimension: 48,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }
    final error = Theme.of(context).colorScheme.error;
    PopupMenuItem<(_TrackAction, MessengerBot?)> item(
      _TrackAction action,
      IconData icon,
      String label, {
      bool destructive = false,
      bool enabled = true,
    }) =>
        PopupMenuItem(
          value: (action, null),
          enabled: enabled,
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(icon, color: destructive ? error : null),
            title: Text(
              label,
              style: destructive ? TextStyle(color: error) : null,
            ),
          ),
        );

    final items = <PopupMenuEntry<(_TrackAction, MessengerBot?)>>[
      if (operation != null && operation.active)
        item(
          _TrackAction.cancelSync,
          NafirIcons.x,
          'لغو آپلود',
          enabled: sync!.canCancel(track.id),
        ),
      if (operation != null && !operation.active) ...[
        item(_TrackAction.retrySync, NafirIcons.arrowsClockwise,
            'تلاش دوباره برای آپلود'),
        item(_TrackAction.dismissSync, NafirIcons.x, 'بستن خطا'),
      ],
      if (sync != null && operation == null && location == TrackLocation.device)
        item(_TrackAction.uploadToServer, NafirIcons.cloudArrowUp,
            'آپلود به سرور'),
      if (onServer) ...[
        item(_TrackAction.editMetadata, NafirIcons.pencilSimple,
            'ویرایش اطلاعات آهنگ'),
        if (widget.playlists != null)
          item(_TrackAction.addToPlaylist, NafirIcons.listPlus,
              'افزودن به فهرست پخش'),
        for (final bot in widget.linkedBots)
          PopupMenuItem(
            value: (_TrackAction.sendToBot, bot),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(NafirIcons.paperPlaneTilt),
              title: Text('ارسال به ${bot.name}'),
            ),
          ),
      ],
      if (onDevice && widget.onRemoveFromDevice != null && operation == null)
        item(_TrackAction.removeFromDevice, NafirIcons.deviceMobile,
            'حذف از دستگاه',
            destructive: location == TrackLocation.device),
      if (onServer && widget.onDelete != null)
        item(
          _TrackAction.delete,
          NafirIcons.trash,
          location == TrackLocation.synced ? 'حذف از سرور' : 'حذف آهنگ',
          destructive: true,
        ),
    ];
    if (items.isEmpty) return null;
    return PopupMenuButton<(_TrackAction, MessengerBot?)>(
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
            sync?.upload(track);
          case (_TrackAction.removeFromDevice, _):
            widget.onRemoveFromDevice?.call(track);
          case (_TrackAction.retrySync, _):
            sync?.retry(track.id);
          case (_TrackAction.cancelSync, _):
            sync?.cancel(track.id);
          case (_TrackAction.dismissSync, _):
            sync?.dismiss(track.id);
          case (_TrackAction.sendToBot, null):
            break;
        }
      },
      itemBuilder: (context) => items,
    );
  }

  Future<void> _addToPlaylist(BuildContext context, Track track) async {
    final controller = widget.playlists;
    if (controller == null) return;
    final loaded = await controller.load();
    if (!context.mounted) return;
    if (!loaded) {
      _message(context, 'دریافت فهرست‌های پخش ناموفق بود.');
      return;
    }

    var playlistId = controller.playlists.isEmpty
        ? await _createPlaylist(context, controller)
        : await showDialog<String>(
            context: context,
            builder: (context) => SimpleDialog(
              title: const Text('افزودن به فهرست پخش'),
              children: [
                SimpleDialogOption(
                  onPressed: () =>
                      Navigator.pop(context, _createPlaylistAction),
                  child: const ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(NafirIcons.plus),
                    title: Text('فهرست پخش جدید'),
                  ),
                ),
                const Divider(height: 1),
                for (final playlist in controller.playlists)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, playlist.id),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(NafirIcons.playlist),
                      title: Text(playlist.name),
                      subtitle: Text(
                          '${persianDigits(playlist.displayTrackCount)} قطعه موسیقی'),
                    ),
                  ),
              ],
            ),
          );

    if (!context.mounted || playlistId == null) return;
    if (playlistId == _createPlaylistAction) {
      playlistId = await _createPlaylist(context, controller);
      if (!context.mounted || playlistId == null) return;
    }

    final result = await controller.addTrack(playlistId, track.id);
    if (!context.mounted) return;
    switch (result) {
      case AddTrackResult.added:
        _message(context, 'آهنگ به فهرست پخش اضافه شد.');
      case AddTrackResult.alreadyPresent:
        _message(context, 'این آهنگ از قبل در فهرست پخش است.');
      case AddTrackResult.failure:
        _message(context, 'افزودن آهنگ به فهرست پخش ناموفق بود.');
    }
  }

  Future<String?> _createPlaylist(
    BuildContext context,
    PlaylistsController controller,
  ) async {
    final nameController = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('فهرست پخش جدید'),
        content: TextField(
          controller: nameController,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(labelText: 'نام فهرست پخش'),
          onSubmitted: (value) {
            final name = value.trim();
            if (name.isNotEmpty) Navigator.pop(context, name);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) Navigator.pop(context, name);
            },
            child: const Text('ساخت'),
          ),
        ],
      ),
    );
    if (!context.mounted || name == null) return null;

    final playlist = await controller.create(name);
    if (!context.mounted) return null;
    if (playlist == null) {
      _message(context, 'ساخت فهرست پخش ناموفق بود.');
      return null;
    }
    return playlist.id;
  }

  void _message(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final tracks = _filteredTracks;
    return _TabScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              if (widget.top case final top?) top,
              if (widget.deviceNotice case final notice?)
                _DeviceStatusBanner(notice: notice),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                child: SearchBar(
                  controller: _search,
                  hintText: 'جست‌وجوی آهنگ، خواننده یا آلبوم',
                  leading: const Icon(NafirIcons.magnifyingGlass),
                  trailing: [
                    if (_query.isNotEmpty)
                      IconButton(
                        tooltip: 'پاک کردن جست‌وجو',
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(NafirIcons.x),
                      ),
                  ],
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              _TrackListHeader(
                shown: tracks.length,
                total: widget.tracks.length,
                filtered: _query.trim().isNotEmpty,
                sort: _sort,
                onSort: _setSort,
                onShuffle: tracks.isEmpty
                    ? null
                    : () => widget.player.playShuffled(tracks),
              ),
            ],
          ),
        ),
        if (tracks.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 56, 24, 0),
              child: _LibraryState(
                icon: NafirIcons.magnifyingGlassMinus,
                title: 'نتیجه‌ای پیدا نشد',
                message: 'عبارت دیگری را امتحان کن یا جست‌وجو را پاک کن.',
                action: OutlinedButton.icon(
                  onPressed: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                  icon: const Icon(NafirIcons.x),
                  label: const Text('پاک کردن جست‌وجو'),
                ),
              ),
            ),
          )
        else
          ListenableBuilder(
            listenable: widget.player,
            builder: (context, _) => SliverList.builder(
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                return _TrackRow(
                  track: track,
                  current: widget.player.track?.id == track.id,
                  onTap: () => widget.player.playFrom(tracks, index),
                  actions: _actionsFor(context, track),
                  sync: widget.sync?.operationFor(track.id),
                );
              },
            ),
          ),
      ],
    );
  }
}

/// The scrolling body of a library tab: below the pinned header's overlap,
/// centered at most 880 px wide, with room at the end for the add button
/// and the mini player so they never cover the last row.
class _TabScrollView extends StatelessWidget {
  const _TabScrollView({required this.slivers});

  static const double _maxWidth = 880;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.maxWidth >= 900
            ? ((constraints.maxWidth - _maxWidth) / 2).clamp(40.0, 10000.0)
            : 16.0;
        return CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 12, side, 128),
              sliver: SliverMainAxisGroup(slivers: slivers),
            ),
          ],
        );
      },
    );
  }
}

/// «N آهنگ» with sorting and shuffle, above the track list.
class _TrackListHeader extends StatelessWidget {
  const _TrackListHeader({
    required this.shown,
    required this.total,
    required this.filtered,
    required this.sort,
    required this.onSort,
    required this.onShuffle,
  });

  final int shown;
  final int total;
  final bool filtered;
  final TrackSort sort;
  final ValueChanged<TrackSort> onSort;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 0, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              filtered
                  ? '${persianDigits(shown)} از ${persianDigits(total)} آهنگ'
                  : '${persianDigits(total)} آهنگ',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          PopupMenuButton<TrackSort>(
            tooltip: 'مرتب‌سازی: ${sort.label}',
            onSelected: onSort,
            icon: const Icon(NafirIcons.sortAscending),
            itemBuilder: (context) => [
              for (final option in TrackSort.values)
                CheckedPopupMenuItem(
                  value: option,
                  checked: option == sort,
                  child: Text(option.label),
                ),
            ],
          ),
          TextButton.icon(
            onPressed: onShuffle,
            icon: const Icon(NafirIcons.shuffle, size: 20),
            label: Text(filtered ? 'پخش تصادفی نتایج' : 'پخش تصادفی'),
          ),
        ],
      ),
    );
  }
}

/// One track: artwork, title, then artist and size on one line.
class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.track,
    required this.current,
    required this.onTap,
    required this.actions,
    this.sync,
  });

  final Track track;

  /// The track's upload, while queued, running or failed.
  final SyncOperation? sync;

  /// Whether this is the track in the player.
  final bool current;
  final VoidCallback onTap;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final artist = track.artist?.trim();
    final secondary = theme.textTheme.bodySmall
        ?.copyWith(color: colors.onSurfaceVariant, height: 1.3);
    return ListTile(
      selected: current,
      onTap: onTap,
      minTileHeight: 64,
      // With tall Persian text ListTile lays out by padding, not by
      // minTileHeight, so the padding is what keeps the row about 64 px.
      minVerticalPadding: 14,
      contentPadding: const EdgeInsetsDirectional.only(start: 8, end: 0),
      horizontalTitleGap: 12,
      leading: _TrackArtwork(track: track, current: current, sync: sync),
      title: Row(
        children: [
          if (current) ...[
            Semantics(
              label: 'در حال پخش',
              child: Icon(NafirIcons.waveformFill,
                  size: 18, color: colors.primary),
            ),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: current ? FontWeight.w700 : FontWeight.w600,
                color: current ? colors.primary : colors.onSurface,
              ),
            ),
          ),
        ],
      ),
      subtitle: switch (sync) {
        SyncOperation(phase: SyncPhase.failed, :final error?) => Text(
            syncErrorMessage(error),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: secondary?.copyWith(color: colors.error),
          ),
        SyncOperation(:final phase, :final progress) => Text(
            phase == SyncPhase.queued
                ? 'در صف آپلود · ${formatSize(track.sizeBytes)}'
                : 'در حال آپلود ${persianDigits((progress * 100).round())}٪ · '
                    '${formatSize(track.sizeBytes)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: secondary?.copyWith(color: colors.primary),
          ),
        null => Row(
            children: [
              Flexible(
                child: Text(
                  artist == null || artist.isEmpty ? 'خواننده نامشخص' : artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: secondary,
                ),
              ),
              Text(' · ${formatSize(track.sizeBytes)}',
                  maxLines: 1, style: secondary),
            ],
          ),
      },
      trailing: actions,
    );
  }
}

/// A rounded artwork square with a small badge saying where the track is:
/// on the device, on the server, on both, being uploaded, or failed.
class _TrackArtwork extends StatelessWidget {
  const _TrackArtwork({required this.track, required this.current, this.sync});

  final Track track;
  final bool current;
  final SyncOperation? sync;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final location = locationOf(track);
    final (where, Widget badge) = switch (sync) {
      SyncOperation(phase: SyncPhase.failed) => (
          'آپلود ناموفق',
          Icon(NafirIcons.warningCircle, size: 13, color: colors.error),
        ),
      SyncOperation(:final phase, :final progress) => (
          phase == SyncPhase.queued ? 'در صف آپلود' : 'در حال آپلود',
          SizedBox.square(
            dimension: 13,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value:
                  phase == SyncPhase.running && progress > 0 ? progress : null,
            ),
          ),
        ),
      null => switch ((location, track.importedFrom)) {
          (TrackLocation.device, _) => (
              'فقط روی دستگاه',
              Icon(NafirIcons.deviceMobile,
                  size: 13, color: colors.onSurfaceVariant),
            ),
          (TrackLocation.synced, _) => (
              'روی دستگاه و سرور',
              Icon(NafirIcons.checkCircle, size: 13, color: colors.primary),
            ),
          (TrackLocation.server, final String from) => (
              'از $from',
              Icon(NafirIcons.robot, size: 13, color: colors.onSurfaceVariant),
            ),
          (TrackLocation.server, _) => (
              'روی سرور',
              Icon(NafirIcons.cloud, size: 13, color: colors.onSurfaceVariant),
            ),
        },
    };
    return SizedBox.square(
      dimension: 48,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: current
                  ? colors.primaryContainer
                  : colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              NafirIcons.musicNote,
              color:
                  current ? colors.onPrimaryContainer : colors.onSurfaceVariant,
            ),
          ),
          PositionedDirectional(
            end: -4,
            bottom: -4,
            child: Tooltip(
              message: where,
              child: Semantics(
                label: where,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: badge,
                ),
              ),
            ),
          ),
        ],
      ),
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
      icon: const Icon(NafirIcons.notePencil),
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
                prefixIcon: Icon(NafirIcons.musicNote),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _artist,
              enabled: !_saving,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'خواننده',
                prefixIcon: Icon(NafirIcons.user),
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
                prefixIcon: Icon(NafirIcons.vinylRecord),
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
              : const Icon(NafirIcons.check),
          label: const Text('ذخیره'),
        ),
      ],
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
          icon: NafirIcons.folderSimpleDashed,
          message: 'برای نمایش آهنگ‌های دستگاه، اجازهٔ دسترسی صوتی لازم است.',
          actionLabel: 'از تنظیمات دستگاه اجازه بده',
        ),
      LocalAudioViewStatus.error => const _DeviceNotice(
          icon: NafirIcons.warningCircle,
          message:
              'خواندن آهنگ‌های دستگاه ناموفق بود؛ آهنگ‌های سرور همچنان دیده می‌شوند.',
          actionLabel: 'صفحه را پایین بکش',
        ),
      LocalAudioViewStatus.unsupported => null,
      LocalAudioViewStatus.idle ||
      LocalAudioViewStatus.loading =>
        const _DeviceNotice(
          icon: NafirIcons.arrowsClockwise,
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
                  ? 'یک فایل در حال اضافه شدن است…'
                  : '${persianDigits(count)} فایل در حال اضافه شدن است…',
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
    return Column(
      children: [
        if (deviceNotice case final notice?) ...[
          _DeviceStatusBanner(notice: notice),
          const SizedBox(height: 16),
        ],
        const _LibraryState(
          icon: NafirIcons.musicNotes,
          title: 'کتابخانهٔ شما خالی است',
          message:
              'با «افزودن موسیقی» آهنگ آپلود کن یا اجازه بده ریتمو آهنگ‌های دستگاه را هم همین‌جا نشان بدهد.',
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
        icon: NafirIcons.cloudSlash,
        title: 'کتابخانه دریافت نشد',
        message: 'اتصال اینترنت را بررسی کن و دوباره تلاش کن.',
        action: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(NafirIcons.arrowsClockwise),
          label: const Text('تلاش دوباره'),
        ),
      ),
    );
  }
}
