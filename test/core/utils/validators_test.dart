import 'package:flutter_test/flutter_test.dart';
import 'package:uniclub/core/utils/validators.dart';

void main() {
  group('Validators.email', () {
    test('accepts a normal email address', () {
      expect(Validators.email('student@college.edu'), isNull);
    });

    test('rejects empty and malformed addresses', () {
      expect(Validators.email(''), isNotNull);
      expect(Validators.email('student@college'), isNotNull);
      expect(Validators.email('student college.edu'), isNotNull);
    });
  });

  group('Validators.password', () {
    test('requires at least six characters', () {
      expect(Validators.password('12345'), isNotNull);
      expect(Validators.password('123456'), isNull);
    });
  });

  test('requiredField trims whitespace', () {
    expect(Validators.requiredField('   ', label: 'Name'), 'Name is required');
    expect(Validators.requiredField(' UniClub ', label: 'Name'), isNull);
  });

  group('Validators.username', () {
    test('accepts normalized campus usernames', () {
      expect(Validators.username('student_2026'), isNull);
      expect(Validators.username('ClubLead'), isNull);
    });

    test('rejects unsafe or incorrectly sized usernames', () {
      expect(Validators.username('ab'), isNotNull);
      expect(Validators.username('student name'), isNotNull);
      expect(Validators.username('student-name'), isNotNull);
    });
  });
}
