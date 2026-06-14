import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class ImageKitService {
  static const _publicKey = 'public_YDOcWLpiiHDlpU+y4GXqUjVDEaQ=';

  static Future<String?> uploadImage(File imageFile, String fileName) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final idToken = await user.getIdToken();

      final functionUrl =
          'https://us-central1-gigs-court.cloudfunctions.net/getImageKitToken';

      final tokenResponse = await http.post(
        Uri.parse(functionUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
      );

      if (tokenResponse.statusCode != 200) {
        return null;
      }

      final tokenData = jsonDecode(tokenResponse.body);

      final token = tokenData['token'];
      final expire = tokenData['expire'];
      final signature = tokenData['signature'];

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