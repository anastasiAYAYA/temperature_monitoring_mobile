//final - неизменяемые значения, this. - ссылка на свойство класса, required - обязательное значение,
// null - значение по умолчанию, const - константа, enum - перечисление
enum UserRole { admin, editor, viewer } // роль пользователя, список фиксированных значений

// фабричный метод для создания модели роли пользователя из строки
UserRole parseRole(String value) => switch (value) { // switch - выбор из списка фиксированных значений
  'admin' => UserRole.admin, // admin
  'editor' => UserRole.editor, // editor
  _ => UserRole.viewer, // viewer
}; // если не найдено, то viewer, _ - неиспользуемая переменная
