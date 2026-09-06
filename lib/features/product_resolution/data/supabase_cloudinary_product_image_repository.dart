import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../application/product_image_contribution.dart';

final class SupabaseCloudinaryProductImageRepository implements ProductImageContributionRepository {
  SupabaseCloudinaryProductImageRepository(this._supabase, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();
  final SupabaseClient _supabase;
  final http.Client _http;
  final _pendingVerification = Expando<Map<String, Map<String, dynamic>>>();

  @override
  Future<ProductImageContribution> upload({
    required String shopId,
    required String productId,
    required ProcessedProductImage image,
  }) async {
    if (image.mimeType != 'image/jpeg' || image.bytes.isEmpty || image.bytes.length > 5242880) {
      throw const ProductImageException(
        ProductImageFailureKind.invalidType,
        'The prepared photo is not a valid bounded JPEG.',
      );
    }
    try {
      final target = '$shopId/$productId';
      final pending = _pendingVerification[image] ??= {};
      var uploaded = pending[target];
      if (uploaded == null) {
        final signatureResponse = await _supabase.functions.invoke(
          'create-cloudinary-upload-signature',
          body: {'shopId': shopId, 'productId': productId},
        );
        final signature = _map(signatureResponse.data, 'Upload authorization failed.');
        final cloudName = _requiredString(signature, 'cloudName');
        final request = http.MultipartRequest(
          'POST',
          Uri.https('api.cloudinary.com', '/v1_1/$cloudName/image/upload'),
        );
        for (final key in const [
          'apiKey',
          'timestamp',
          'signature',
          'folder',
          'overwrite',
          'allowed_formats',
          'transformation',
          'context',
        ]) {
          final formKey = key == 'apiKey' ? 'api_key' : key;
          request.fields[formKey] = _requiredString(signature, key);
        }
        request.fields['public_id'] = _requiredString(signature, 'publicId');
        request.files.add(
          http.MultipartFile.fromBytes('file', image.bytes, filename: image.filename),
        );
        final streamed = await _http.send(request);
        final uploadBody = await streamed.stream.bytesToString();
        if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
          throw const ProductImageException(
            ProductImageFailureKind.upload,
            'Cloudinary rejected the photo. Choose another image or retry.',
          );
        }
        uploaded = _map(jsonDecode(uploadBody), 'Cloudinary returned an invalid upload response.');
        pending[target] = uploaded;
      }
      final verifyResponse = await _supabase.functions.invoke(
        'verify-cloudinary-upload',
        body: {
          'shopId': shopId,
          'productId': productId,
          'publicId': _requiredString(uploaded, 'public_id'),
          'version': uploaded['version'].toString(),
        },
      );
      final verified = _map(verifyResponse.data, 'The uploaded photo could not be verified.');
      pending.remove(target);
      return ProductImageContribution(
        id: _requiredString(verified, 'imageId'),
        status: _requiredString(verified, 'status'),
        deliveryUrl: Uri.parse(_requiredString(verified, 'deliveryUrl')),
      );
    } on ProductImageException {
      rethrow;
    } on http.ClientException catch (error) {
      throw ProductImageException(
        ProductImageFailureKind.offline,
        'The network request failed. The photo is kept for retry.',
        cause: error,
      );
    } on FunctionException catch (error) {
      if (error.status == 0) {
        throw ProductImageException(
          ProductImageFailureKind.offline,
          'You appear to be offline. The photo is kept for retry.',
          cause: error,
        );
      }
      throw ProductImageException(
        ProductImageFailureKind.verification,
        'The server could not verify the photo. It was not attached.',
        cause: error,
      );
    } on Object catch (error) {
      throw ProductImageException(
        ProductImageFailureKind.upload,
        'The photo could not be uploaded. It is kept for retry.',
        cause: error,
      );
    }
  }

  Map<String, dynamic> _map(Object? value, String message) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.map((key, item) => MapEntry(key.toString(), item));
    throw ProductImageException(ProductImageFailureKind.verification, message);
  }

  String _requiredString(Map<String, dynamic> value, String key) {
    final result = value[key];
    if (result is String && result.isNotEmpty) return result;
    throw ProductImageException(
      ProductImageFailureKind.verification,
      'The image service returned incomplete data.',
    );
  }
}
