class Validators {
  Validators._();

  static String? requiredField(String? value, {String label = 'This field'}) {
    if (value == null || value.trim().isEmpty) {
      return '$label is required';
    }
    return null;
  }

  static String? email(String? value) {
    final requiredError = requiredField(value, label: 'Email');
    if (requiredError != null) return requiredError;

    final normalized = value!.trim();
    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailPattern.hasMatch(normalized)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  static String? password(String? value) {
    final requiredError = requiredField(value, label: 'Password');
    if (requiredError != null) return requiredError;
    if (value!.length < 6) return 'Use at least 6 characters';
    return null;
  }

  static String? strongPassword(String? value) {
    final requiredError = requiredField(value, label: 'Password');
    if (requiredError != null) return requiredError;
    if (value!.length < 10) return 'Use at least 10 characters';
    if (!RegExp(r'[A-Z]').hasMatch(value) ||
        !RegExp(r'[a-z]').hasMatch(value) ||
        !RegExp(r'[0-9]').hasMatch(value)) {
      return 'Include uppercase, lowercase and a number';
    }
    return null;
  }

  static String? username(String? value) {
    final requiredError = requiredField(value, label: 'Username');
    if (requiredError != null) return requiredError;
    final normalized = value!.trim().toLowerCase();
    if (normalized.length < 3 || normalized.length > 30) {
      return 'Use 3–30 characters';
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(normalized)) {
      return 'Use only letters, numbers and underscores';
    }
    return null;
  }
}
