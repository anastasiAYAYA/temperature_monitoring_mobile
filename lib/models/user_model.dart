class UserModel {
  UserModel({
    required this.id,
    required this.username,
    required this.fullName,
    required this.role,
    this.email,
  });

  final int id;
  final String username;
  final String fullName;
  final String role;
  final String? email;
}
