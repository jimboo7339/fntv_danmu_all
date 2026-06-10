class ApiResponse<T> {
  final int code;
  final String? msg;
  final T? data;

  ApiResponse({required this.code, this.msg, this.data});

  factory ApiResponse.fromJson(Map<String, dynamic> json, T Function(dynamic)? fromData) {
    return ApiResponse(
      code: json['code'] ?? -1,
      msg: json['msg'],
      data: json['data'] != null && fromData != null ? fromData(json['data']) : json['data'],
    );
  }
}
