import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class FnAuthUtils {
  static const _apiKey = 'vD2P9mXkL3Qr5YtUwEa6FbHcJdN1zR0Wg';
  static const _apiSecret = 'CA8CEF1E-5B91-4F82-9DB7-E8D6A9B1C2D4';

  static String md5Hex(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }

  static String generateNonce() {
    return (100000 + Random().nextInt(900000)).toString();
  }

  static String genAuthx(String url, String? jsonBody) {
    final nonce = generateNonce();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final dataMd5 = jsonBody != null ? md5Hex(jsonBody) : '';
    final parts = [_apiKey, url, nonce, timestamp, dataMd5, _apiSecret];
    final signStr = parts.join('_');
    final sign = md5Hex(signStr);
    return 'nonce=$nonce&timestamp=$timestamp&sign=$sign';
  }

  static String md5Account(String account) {
    return md5Hex(account);
  }
}
