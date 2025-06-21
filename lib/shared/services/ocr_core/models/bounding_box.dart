class BBox {
  final double x;
  final double y;
  final double width;
  final double height;

  const BBox({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  Map<String, dynamic> toJson() {
    return {'x': x, 'y': y, 'width': width, 'height': height};
  }

  factory BBox.fromJson(List json) {
    final x1 = (json[0] as num).toDouble();
    final y1 = (json[1] as num).toDouble();
    final x2 = (json[2] as num).toDouble();
    final y2 = (json[3] as num).toDouble();
    return BBox(x: x1, y: y1, width: x2 - x1, height: y2 - y1);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is BBox &&
        other.x == x &&
        other.y == y &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode => Object.hash(x, y, width, height);
}
