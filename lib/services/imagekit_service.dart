import 'dart:convert';
import 'dart:io';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;

class ImageKitService {
  static const _publicKey = 'public_YDOcWLpiiHDlpU+y4GXqUjVDEaQ=';

  static Future<String?> uploadImage(File imageFile, String fileName) async {
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('getImageKitToken');
      final result = await callable.call();

      final token = result.data['token'];
      final expire = result.data['expire'];
      final signature = result.data['signature'];

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

      final uploadResponse =
          await http.Response.fromStream(await request.send());

      if (uploadResponse.statusCode == 200) {
        final data = jsonDecode(uploadResponse.body);
        return data['url'] as String;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}