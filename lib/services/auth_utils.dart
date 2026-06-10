import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class FnAuthUtils {
  static const _apiKey = 'NDzZTVxnRKP8Z0jXg1VAMonaG8akvh';
  static const _apiSecret = '16CCEB3D-AB42-077D-36A1-F355324E4237';

  static String md5Hex(String input) {
    return md5.convert(utf8.encode(input)).toString();
  }

  static String generateNonce() {
    return (100000 + Random().nextInt(900000)).toString();
  }

  static String genAuthx(String url, String? jsonBody) {
    final nonce = generateNonce();
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    // 修复：空 body 也要算 MD5 (md5 of empty string)
    final dataMd5 = jsonBody != null ? md5Hex(jsonBody) : md5Hex('');
    final parts = [_apiKey, url, nonce, timestamp, dataMd5, _apiSecret];
    final signStr = parts.join('_');
    final sign = md5Hex(signStr);
    return 'nonce=$nonce&timestamp=$timestamp&sign=$sign';
  }

  static String md5Account(String account) {
    return md5Hex(account);
  }
}
