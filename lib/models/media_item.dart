class MediaDbItem {
  final String guid;
  final String title;
  final String? poster;
  final List<String>? posters;
  final String? category;
  final int viewType;
  final int posterType;

  MediaDbItem({
    required this.guid,
    required this.title,
    this.poster,
    this.posters,
    this.category,
    this.viewType = 0,
    this.posterType = 0,
  });

  String? get firstPoster {
    if (poster != null && poster!.isNotEmpty) return poster;
    if (posters != null && posters!.isNotEmpty) return posters!.first;
    return null;
  }

  factory MediaDbItem.fromJson(Map<String, dynamic> json) {
    return MediaDbItem(
      guid: json['guid'] ?? '',
      title: json['title'] ?? '',
      poster: json['poster'],
      posters: json['posters'] != null ? List<String>.from(json['posters']) : null,
      category: json['category'],
      viewType: json['view_type'] ?? 0,
      posterType: json['poster_type'] ?? 0,
    );
  }
}
