class Metadata {
  final String title;
  final int pages;

  const Metadata({required this.title, required this.pages});

  factory Metadata.fromJson(Map<String, dynamic> json) {
    return Metadata(
      title: json['filename'] as String,
      pages: (json['total_pages'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'title': title, 'pages': pages};
  }
}
