//final - неизменяемые значения, this. - ссылка на свойство класса, required - обязательное значение,
// null - значение по умолчанию, const - константа, enum - перечисление
class UserModel {
  UserModel({ // конструктор модели пользователя
    required this.id, // id пользователя
    required this.username, // username пользователя
    required this.fullName, // fullName пользователя
    required this.role, // role пользователя
    this.email, // email пользователя
  });

  final int id; // id пользователя
  final String username; // username пользователя
  final String fullName; // fullName пользователя
  final String role; // role пользователя
  final String? email; // email пользователя
}
