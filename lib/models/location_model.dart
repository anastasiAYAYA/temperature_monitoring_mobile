//final - неизменяемые значения, this. - ссылка на свойство класса, required - обязательное значение,
// null - значение по умолчанию, const - константа, enum - перечисление
class LocationModel {
  LocationModel({ // конструктор модели локации
    required this.id, // id локации
    required this.name, // название локации
    this.imageUrl, // URL изображения локации
  });

  final int id; // id локации
  final String name; // название локации
  final String? imageUrl; // URL изображения локации
}
