import 'package:dio/dio.dart';
import 'package:nafir/features/upload/data/upload_models.dart';

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
  }) async {
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
        options: Options(responseType: ResponseType.plain),
      );
    } on DioException catch (error) {
      throw UploadFailed(error.response?.statusCode);
    }
  }
}
