import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;

class ImageKitService {
  static const _publicKey = 'public_YDOcWLpiiHDlpU+y4GXqUjVDEaQ=';

  static Future<String?> uploadImage(File imageFile, String fileName) async {
    try {
      debugPrint('ImageKit: Step 1 - Calling Cloud Function...');
      final callable =
          FirebaseFunctions.instance.httpsCallable('getImageKitToken');
      final result = await callable.call();
      debugPrint('ImageKit: Step 1 - Success. Data: ${result.data}');

      final token = result.data['token'];
      final expire = result.data['expire'];
      final signature = result.data['signature'];
      debugPrint('ImageKit: Step 2 - Got token=$token, expire=$expire, signature=$signature');

      final uri = Uri.parse('https://upload.imagekit.io/api/v1/files/upload');

      final request = http.MultipartRequest('POST', uri)
        ..fields['publicKey'] = _publicKey
        ..fields['token'] = token
        ..fields['expire'] = expire.toString()
        ..fields['signature'] = signature
        ..fields['fileName'] = fileName
        ..fields['useUniqueFileName'] = 'true'
        ..files.add(
          await http.MultipartFile.fromPath('file', imageFile.path),
        );

      debugPrint('ImageKit: Step 3 - Uploading to ImageKit...');
      final uploadResponse =
          await http.Response.fromStream(await request.send());

      debugPrint('ImageKit: Step 4 - Response status: ${uploadResponse.statusCode}');
      debugPrint('ImageKit: Step 4 - Response body: ${uploadResponse.body}');

      if (uploadResponse.statusCode == 200) {
        final data = jsonDecode(uploadResponse.body);
        debugPrint('ImageKit: Step 5 - Success! URL: ${data['url']}');
        return data['url'] as String;
      }
      debugPrint('ImageKit: FAILED - Status code: ${uploadResponse.statusCode}');
      return null;
    } catch (e) {
      debugPrint('ImageKit: ERROR - $e');
      return null;
    }
  }
}