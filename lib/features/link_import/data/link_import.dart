/// Music being added from a link: a song page on a music site, or an audio
/// file itself.
class LinkImport {
  const LinkImport({
    required this.id,
    required this.fileName,
    required this.site,
    required this.state,
    this.error,
    this.trackId,
  });

  factory LinkImport.fromJson(Map<String, dynamic> json) => LinkImport(
        id: json['id'] as String,
        fileName: json['fileName'] as String,
        site: json['site'] as String? ?? '',
        state: switch (json['state']) {
          'done' => LinkImportState.done,
          'failed' => LinkImportState.failed,
          'downloading' => LinkImportState.downloading,
          _ => LinkImportState.queued,
        },
        error: json['error'] as String?,
        trackId: json['trackId'] as String?,
      );

  final String id;
  final String fileName;

  /// The site the file comes from, for example `music.example.ir`.
  final String site;
  final LinkImportState state;

  /// Why a failed import was refused, as the server names it.
  final String? error;
  final String? trackId;

  bool get finished =>
      state == LinkImportState.done || state == LinkImportState.failed;
}

enum LinkImportState { queued, downloading, done, failed }

abstract interface class LinkImportsApi {
  /// Starts importing the audio a link leads to.
  Future<LinkImport> importFromLink(String token, String url);

  /// The user's latest link imports, newest first.
  Future<List<LinkImport>> listLinkImports(String token);
}

/// What a refused link or a failed import means, in Persian.
String linkImportMessage(String? code) => switch (code) {
      'invalid_url' => 'این لینک معتبر نیست. یک لینک http یا https بچسبان.',
      'blocked_url' => 'نفیر اجازه ندارد به نشانی این لینک وصل شود.',
      'unreachable' =>
        'صفحه باز نشد. لینک را بررسی کن یا کمی بعد دوباره امتحان کن.',
      'no_audio' =>
        'در این صفحه فایل صوتی پیدا نشد. لینک صفحه‌ی خود آهنگ یا لینک مستقیم فایل را بچسبان.',
      'unsupported_format' => 'این لینک به فایل صوتی پشتیبانی‌شده نمی‌رسد.',
      'too_large' => 'این فایل از حد مجاز بزرگ‌تر است.',
      'duplicate_import' => 'این آهنگ همین حالا در حال اضافه شدن است.',
      'too_many_imports' ||
      'too_many_pending_uploads' ||
      'rate_limited' =>
        'چند فایل در حال اضافه شدن است؛ کمی صبر کن و دوباره امتحان کن.',
      'quota_exceeded' =>
        'فضای کافی در حسابت نیست. چند آهنگ را حذف کن و دوباره امتحان کن.',
      'uploads_disabled' => 'افزودن آهنگ فعلاً غیرفعال است.',
      'invalid_audio' => 'فایل دریافت‌شده صوتی معتبر نبود.',
      _ => 'افزودن از لینک ناموفق بود. دوباره تلاش کن.',
    };
