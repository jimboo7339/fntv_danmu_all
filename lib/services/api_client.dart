import 'dart:convert';
import 'package:dio/dio.dart';
import 'auth_utils.dart';

class ApiClient {
  late Dio _dio;
  String? _token;
  String _baseUrl = '';

  ApiClient() {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final urlPath = options.uri.path;
        String? bodyStr;
        if (options.data != null) {
          bodyStr = options.data is String ? options.data as String : jsonEncode(options.data);
        }
        final authx = FnAuthUtils.genAuthx(urlPath, bodyStr);
        options.headers['Authx'] = authx;
        options.headers['Content-Type'] = 'application/json';
        options.headers['Cookie'] = 'mode=relay';
        if (_token != null) {
          options.headers['Authorization'] = _token;
        }
        handler.next(options);
      },
    ));
  }

  String get baseUrl => _baseUrl;

  void updateBaseUrl(String host) {
    _baseUrl = host.replaceAll(RegExp(r'/+$'), '');
    final vIdx = _baseUrl.indexOf('/v');
    if (vIdx != -1) _baseUrl = _baseUrl.substring(0, vIdx);
    _dio.options.baseUrl = '$_baseUrl/v/';
  }

  void setToken(String token) { _token = token; }
  String? get token => _token;

  Dio get dio => _dio;

  // ====== API Methods ======

  Future<Map<String, dynamic>> login(String username, String password) async {
    final resp = await _dio.post('api/v1/login', data: {
      'app_name': 'trimemedia-web',
      'username': username,
      'password': password,
      'nonce': FnAuthUtils.generateNonce(),
    });
    return resp.data;
  }

  Future<Map<String, dynamic>> getUserInfo() async {
    final resp = await _dio.get('api/v1/user/info');
    return resp.data;
  }

  Future<Map<String, dynamic>> getMediaDbList() async {
    final resp = await _dio.get('api/v1/mediadb/list');
    return resp.data;
  }

  Future<Map<String, dynamic>> getItemList(Map<String, dynamic> body) async {
    final resp = await _dio.post('api/v1/item/list', data: body);
    return resp.data;
  }

  Future<Map<String, dynamic>> getEpisodeList(String id) async {
    final resp = await _dio.get('api/v1/episode/list/$id');
    return resp.data;
  }

  Future<Map<String, dynamic>> getPlayInfo(String itemGuid) async {
    final resp = await _dio.post('api/v1/play/info', data: {'item_guid': itemGuid});
    return resp.data;
  }

  Future<Map<String, dynamic>> getItemDetail(String guid) async {
    final resp = await _dio.get('api/v1/item/$guid');
    return resp.data;
  }

  Future<Map<String, dynamic>> getPersonList(String itemGuid, {int page = 1, int pageSize = 200}) async {
    final resp = await _dio.post('api/v1/person/list/$itemGuid', data: {'page': page, 'page_size': pageSize});
    return resp.data;
  }

  Future<Map<String, dynamic>> getStream(Map<String, dynamic> body) async {
    final resp = await _dio.post('api/v1/stream', data: body);
    return resp.data;
  }

  String getMediaUrl(String mediaGuid) {
    return '$_baseUrl/v/api/v1/media/range/$mediaGuid';
  }

  String getMediaUrlWithQuality(String mediaGuid, int qualityIndex) {
    return '$_baseUrl/v/api/v1/media/range/$mediaGuid?direct_link_quality_index=$qualityIndex';
  }

  String getImageUrl(String? path, {int width = 400}) {
    if (path == null || path.isEmpty) return '';
    final p = path.startsWith('/') ? path : '/$path';
    return '$_baseUrl/v/api/v1/sys/img$p?w=$width';
  }

  /// 返回图片请求所需的认证头，供 CachedNetworkImage 使用
  Map<String, String> get imageHeaders {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Cookie': 'mode=relay',
    };
    if (_token != null) {
      headers['Authorization'] = _token!;
    }
    // Authx 需要 url path 和 body，对图片 GET 请求 body 为 null
    final authx = FnAuthUtils.genAuthx('/v/api/v1/sys/img', null);
    headers['Authx'] = authx;
    return headers;
  }

  Future<void> recordPlayStatus(Map<String, dynamic> body) async {
    await _dio.post('api/v1/play/record', data: body);
  }

  /// 获取继续观看列表（服务端播放记录）
  Future<Map<String, dynamic>> getPlayList() async {
    final resp = await _dio.get('api/v1/play/list');
    return resp.data;
  }

  Future<void> setWatched(Map<String, dynamic> body) async {
    await _dio.post('api/v1/item/watched', data: body);
  }
}
