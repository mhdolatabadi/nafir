import 'package:flutter/material.dart';
import 'package:nafir/core/format_size.dart';
import 'package:nafir/features/library/application/library_controller.dart';
import 'package:nafir/features/library/application/local_audio_controller.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/player/application/player_controller.dart';
import 'package:nafir/features/player/presentation/mini_player.dart';
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
    required this.localAudio,
    required this.uploads,
    required this.cache,
    required this.picker,
    required this.player,
  });

  final String email;
  final VoidCallback onLogout;
  final LibraryController library;
  final LocalAudioController localAudio;
  final PlayerController player;
  final UploadController uploads;
  final CacheController cache;
  final AudioPicker picker;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  UploadPhase _lastPhase = UploadPhase.idle;

  @override
  void initState() {
    super.initState();
    widget.library.load();
    if (widget.localAudio.supported) widget.localAudio.load();
    widget.uploads.addListener(_onUploadChanged);
  }

  @override
  void dispose() {
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
    final file = await widget.picker.pick(onReading: uploads.readingFile);
    if (file == null) return uploads.pickCancelled();
    await uploads.upload(file);
  }

  Future<void> _refreshCloud() async {
    final ok = await widget.library.load();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('به‌روزرسانی فهرست ناموفق بود.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasDeviceLibrary = widget.localAudio.supported;
    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('نفیر'),
        bottom: hasDeviceLibrary
            ? const TabBar(
                tabs: [
                  Tab(text: 'ابری', icon: Icon(Icons.cloud_outlined)),
                  Tab(text: 'دستگاه', icon: Icon(Icons.phone_android)),
                ],
              )
            : null,
        actions: [
          IconButton(
            tooltip: 'تنظیمات',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => SettingsScreen(cache: widget.cache),
            )),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: 'خروج (${widget.email})',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          ),
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
      body: hasDeviceLibrary
          ? TabBarView(children: [_cloudLibrary(), _deviceLibrary()])
          : _cloudLibrary(),
    );
    return hasDeviceLibrary
        ? DefaultTabController(length: 2, child: scaffold)
        : scaffold;
  }

  Widget _cloudLibrary() => Column(
        children: [
          UploadStatusCard(controller: widget.uploads),
          Expanded(
            child: ListenableBuilder(
              listenable: widget.library,
              builder: (context, _) => switch (widget.library.status) {
                LibraryStatus.loading =>
                  const Center(child: CircularProgressIndicator()),
                LibraryStatus.error => _LoadError(onRetry: widget.library.load),
                LibraryStatus.loaded => RefreshIndicator(
                    onRefresh: _refreshCloud,
                    child: widget.library.tracks.isEmpty
                        ? const _EmptyLibrary()
                        : _TrackList(
                            tracks: widget.library.tracks,
                            player: widget.player,
                          ),
                  ),
              },
            ),
          ),
        ],
      );

  Widget _deviceLibrary() => ListenableBuilder(
        listenable: widget.localAudio,
        builder: (context, _) => switch (widget.localAudio.status) {
          LocalAudioViewStatus.idle ||
          LocalAudioViewStatus.loading =>
            const Center(child: CircularProgressIndicator()),
          LocalAudioViewStatus.loaded => widget.localAudio.tracks.isEmpty
              ? _DeviceMessage(
                  icon: Icons.audio_file_outlined,
                  message: 'فایل صوتی‌ای روی دستگاه پیدا نشد.',
                  onRetry: widget.localAudio.load,
                )
              : RefreshIndicator(
                  onRefresh: widget.localAudio.load,
                  child: _TrackList(
                    tracks: widget.localAudio.tracks,
                    player: widget.player,
                  ),
                ),
          LocalAudioViewStatus.permissionDenied => _DeviceMessage(
              icon: Icons.folder_off_outlined,
              message:
                  'برای نمایش موسیقی‌های دستگاه، اجازهٔ دسترسی صوتی لازم است.',
              onRetry: widget.localAudio.load,
            ),
          LocalAudioViewStatus.error => _DeviceMessage(
              icon: Icons.error_outline,
              message: 'خواندن موسیقی‌های دستگاه ناموفق بود.',
              onRetry: widget.localAudio.load,
            ),
          LocalAudioViewStatus.unsupported => const SizedBox.shrink(),
        },
      );
}

class _TrackList extends StatelessWidget {
  const _TrackList({required this.tracks, required this.player});

  final List<Track> tracks;
  final PlayerController player;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) => ListView.builder(
        padding: const EdgeInsets.only(bottom: 88),
        itemCount: tracks.length,
        itemBuilder: (context, index) {
          final track = tracks[index];
          final current = player.track?.id == track.id;
          final details = [track.artist, track.album]
              .whereType<String>()
              .where((text) => text.isNotEmpty)
              .join(' — ');
          return ListTile(
            selected: current,
            onTap: () => player.playFrom(tracks, index),
            leading: CircleAvatar(
              child: Icon(
                current
                    ? Icons.graphic_eq
                    : track.isLocal
                        ? Icons.phone_android
                        : Icons.music_note,
              ),
            ),
            title:
                Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              details.isEmpty ? formatSize(track.sizeBytes) : details,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        },
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: const [
        SizedBox(height: 120),
        Icon(Icons.cloud_queue_outlined, size: 64),
        SizedBox(height: 16),
        Text(
          'کتابخانهٔ شما خالی است',
          style: TextStyle(fontSize: 20),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: 8),
        Text(
          'با «افزودن موسیقی» فایل‌هایت را آپلود کن.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _DeviceMessage extends StatelessWidget {
  const _DeviceMessage({
    required this.icon,
    required this.message,
    required this.onRetry,
  });

  final IconData icon;
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('تلاش دوباره'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('دریافت فهرست موسیقی ناموفق بود.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('تلاش دوباره'),
          ),
        ],
      ),
    );
  }
}
