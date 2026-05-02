class Validators {
  static final RegExp _lettersSpaces = RegExp(r'^[A-Za-z\s]+$');
  static final RegExp _mobile = RegExp(r'^[0-9]{10}$');

  static bool isLettersSpaces(String? s) =>
      s != null && _lettersSpaces.hasMatch(s.trim());

  static bool isMobile(String? s) => s != null && _mobile.hasMatch(s);

  static String? requiredField(String? value, [String field = 'This field']) {
    if (value == null || value.trim().isEmpty) {
      return '$field is required';
    }
    return null;
  }
}
