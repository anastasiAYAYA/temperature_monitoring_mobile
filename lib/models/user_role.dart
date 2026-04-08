enum UserRole { admin, editor, viewer }

UserRole parseRole(String value) {
  switch (value) {
    case 'admin':
      return UserRole.admin;
    case 'editor':
      return UserRole.editor;
    default:
      return UserRole.viewer;
  }
}
