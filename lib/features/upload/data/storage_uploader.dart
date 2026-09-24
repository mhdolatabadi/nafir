import 'package:dio/dio.dart';
import 'package:nafir/features/upload/data/upload_models.dart';

/// Thrown when an upload stops because the user cancelled it.
class UploadCancelled implements Exception {
  const UploadCancelled();
}

class UploadFailed implements Exception {
  const UploadFailed(this.statusCode);

  final int? statusCode;

  @override
  String toString() => 'Storage upload failed (HTTP $statusCode).';
}

/// Sends a file to storage using a presigned form.
abstract interface class StorageUploader {
  Future<void> upload(
    UploadTicket ticket,
    PickedAudio file, {
    required String contentType,
    required void Function(int sent, int total) onProgress,
    required Future<void> cancelled,
  });
}

/// Uses dio because it reports upload progress on every platform, including
/// the web, where `package:http` does not.
class DioStorageUploader implements StorageUploader {
  DioStorageUploader([Dio? dio]) : _dio = dio ?? Dio();

  final Dio _dio;

  @override
  Future<void> upload(
    UploadTicket ticket,
    PickedAudio file, {
    required String contentType,
    required void Function(int sent, int total) onProgress,
    required Future<void> cancelled,
  }) async {
    final cancelToken = CancelToken();
    cancelled.then((_) => cancelToken.cancel());
    final form = FormData.fromMap({
      ...ticket.fields,
      // The file must be the last field of an S3 POST form.
      'file': MultipartFile.fromStream(
        file.openRead,
        file.sizeBytes,
        filename: file.name,
        contentType: DioMediaType.parse(contentType),
      ),
    });
    try {
      await _dio.postUri<void>(
        ticket.url,
        data: form,
        onSendProgress: onProgress,
        cancelToken: cancelToken,
        options: Options(responseType: ResponseType.plain),
      );
    } on DioException catch (error) {
      if (CancelToken.isCancel(error)) throw const UploadCancelled();
      throw UploadFailed(error.response?.statusCode);
    }
  }
}
