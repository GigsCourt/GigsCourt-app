import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ImageKitService {
  static const _publicKey = 'public_YDOcWLpiiHDlpU+y4GXqUjVDEaQ=';

  static Future<Map<String, dynamic>> uploadImage(File imageFile, String fileName) async {
    try {
      debugPrint('IK: Starting upload...');
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        debugPrint('IK: No user logged in');
        return {'success': false, 'error': 'Not logged in'};
      }

      final idToken = await user.getIdToken();
      debugPrint('IK: Got Firebase token');

      final functionUrl =
          'https://us-central1-gigs-court.cloudfunctions.net/getImageKitToken';

      final tokenResponse = await http.post(
        Uri.parse(functionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
      );

      debugPrint('IK: Cloud Function status: ${tokenResponse.statusCode}');
      debugPrint('IK: Cloud Function body: ${tokenResponse.body}');

      if (tokenResponse.statusCode != 200) {
        return {'success': false, 'error': 'Cloud Function failed: ${tokenResponse.statusCode}'};
      }

      final tokenData = jsonDecode(tokenResponse.body);

      final token = tokenData['token'];
      final expire = tokenData['expire'];
      final signature = tokenData['signature'];

      debugPrint('IK: token=$token');
      debugPrint('IK: expire=$expire (type: ${expire.runtimeType})');
      debugPrint('IK: signature=$signature');

      if (token == null || expire == null || signature == null) {
        return {'success': false, 'error': 'Missing token params'};
      }

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

      debugPrint('IK: Sending to ImageKit...');
      debugPrint('IK: Fields: publicKey=$_publicKey, token=$token, expire=${expire.toString()}, signature=$signature');

      final uploadResponse =
          await http.Response.fromStream(await request.send());

      debugPrint('IK: ImageKit status: ${uploadResponse.statusCode}');
      debugPrint('IK: ImageKit body: ${uploadResponse.body}');

      if (uploadResponse.statusCode == 200) {
        final data = jsonDecode(uploadResponse.body);
        return {'success': true, 'url': data['url']};
      }

      return {'success': false, 'error': 'ImageKit upload failed: ${uploadResponse.statusCode} ${uploadResponse.body}'};
    } catch (e) {
      debugPrint('IK: Exception: $e');
      return {'success': false, 'error': e.toString()};
    }
  }
}