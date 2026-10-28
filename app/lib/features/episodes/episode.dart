/// Episode model. Plain immutable class for D1; freezed/json_serializable
/// are in pubspec for later models (run build_runner when adding @freezed).
class Episode {
  const Episode({
    required this.id,
    required this.title,
    required this.videoUrl,
    this.coverUrl,
    this.index = 0,
  });

  final String id;
  final String title;
  final String videoUrl;
  final String? coverUrl;
  final int index;

  factory Episode.fromJson(Map<String, dynamic> json) => Episode(
        id: json['id'] as String,
        title: json['title'] as String,
        videoUrl: json['videoUrl'] as String,
        coverUrl: json['coverUrl'] as String?,
        index: (json['index'] as num?)?.toInt() ?? 0,
      );
}
