import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ImageKitService {
  static const _publicKey = 'public_YDOcWLpiiHDlpU+y4GXqUjVDEaQ=';

  static Future<String?> uploadImage(File imageFile, String fileName) async {
    try {
      debugPrint('ImageKit: Starting upload...');
      final idToken = await FirebaseAuth.instance.currentUser!.getIdToken();
      debugPrint('ImageKit: Got auth token');

      final functionUrl =
          'https://us-central1-gigs-court.cloudfunctions.net/getImageKitToken';

      final tokenResponse = await http.post(
        Uri.parse(functionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
      );

      debugPrint('ImageKit: Token response status: ${tokenResponse.statusCode}');
      debugPrint('ImageKit: Token response body: ${tokenResponse.body}');

      if (tokenResponse.statusCode != 200) return null;

      final tokenData = jsonDecode(tokenResponse.body);
      final result = tokenData['result'];

      final uri = Uri.parse('https://upload.imagekit.io/api/v1/files/upload');

      final request = http.MultipartRequest('POST', uri)
        ..fields['fileName'] = fileName
        ..fields['useUniqueFileName'] = 'true'
        ..fields['publicKey'] = _publicKey
        ..fields['token'] = result['token']
        ..fields['expire'] = result['expire'].toString()
        ..fields['signature'] = result['signature']
        ..files.add(
          await http.MultipartFile.fromPath('file', imageFile.path),
        );

      final uploadResponse =
          await http.Response.fromStream(await request.send());

      debugPrint('ImageKit: Upload response status: ${uploadResponse.statusCode}');
      debugPrint('ImageKit: Upload response body: ${uploadResponse.body}');

      if (uploadResponse.statusCode == 200) {
        final data = jsonDecode(uploadResponse.body);
        return data['url'] as String;
      }
      return null;
    } catch (e) {
      debugPrint('ImageKit: Error: $e');
      return null;
    }
  }
}