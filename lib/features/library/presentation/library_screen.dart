import 'package:flutter/material.dart';
import 'package:nafir/features/library/application/library_controller.dart';
import 'package:nafir/features/library/data/track.dart';
import 'package:nafir/features/upload/application/upload_controller.dart';
import 'package:nafir/features/upload/data/audio_picker.dart';
import 'package:nafir/features/upload/presentation/upload_status_card.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    required this.email,
    required this.onLogout,
    required this.library,
    required this.uploads,
    required this.picker,
  });

  final String email;
  final VoidCallback onLogout;
  final LibraryController library;
  final UploadController uploads;
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
    widget.uploads.addListener(_onUploadChanged);
  }

  @override
  void dispose() {
    widget.uploads.removeListener(_onUploadChanged);
    super.dispose();
  }

  /// A finished upload becomes visible in the list right away.
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

  Future<void> _refresh() async {
    final ok = await widget.library.load();
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('به‌روزرسانی فهرست ناموفق بود.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('نفیر'),
        actions: [
          IconButton(
            tooltip: 'خروج (${widget.email})',
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: ListenableBuilder(
        listenable: widget.uploads,
        builder: (context, _) => FloatingActionButton.extended(
          onPressed: widget.uploads.isBusy ? null : _pickAndUpload,
          icon: const Icon(Icons.add),
          label: const Text('افزودن موسیقی'),
        ),
      ),
      body: Column(
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
                    onRefresh: _refresh,
                    child: widget.library.tracks.isEmpty
                        ? const _EmptyLibrary()
                        : _TrackList(tracks: widget.library.tracks),
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackList extends StatelessWidget {
  const _TrackList({required this.tracks});

  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      // Leaves room for the floating button over the last item.
      padding: const EdgeInsets.only(bottom: 88),
      itemCount: tracks.length,
      itemBuilder: (context, index) {
        final track = tracks[index];
        final details = [track.artist, track.album]
            .whereType<String>()
            .where((text) => text.isNotEmpty)
            .join(' — ');
        return ListTile(
          leading: const CircleAvatar(child: Icon(Icons.music_note)),
          title:
              Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            details.isEmpty ? _formatSize(track.sizeBytes) : details,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      },
    );
  }

  static String _formatSize(int bytes) {
    final megabytes = bytes / (1024 * 1024);
    return megabytes >= 1
        ? '${megabytes.toStringAsFixed(1)} مگابایت'
        : '${(bytes / 1024).ceil()} کیلوبایت';
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) {
    // Scrollable so pull-to-refresh also works on an empty library.
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
