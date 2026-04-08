class LocationModel {
  LocationModel({
    required this.id,
    required this.name,
    this.imageUrl,
  });

  final int id;
  final String name;
  final String? imageUrl;
}
