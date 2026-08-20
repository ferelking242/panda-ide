import 'package:flutter_test/flutter_test.dart';
import 'package:panda/logging/secret_redactor.dart';

void main() {
  group('SecretRedactor', () {
    test('redacts API keys', () {
      final input = 'api_key=sk-abc123def456ghi789jkl012mno';
      final redacted = SecretRedactor.redact(input);
      expect(redacted, contains('********'));
      expect(redacted, isNot(contains('sk-abc123')));
    });

    test('redacts Bearer tokens', () {
      final input = 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9';
      final redacted = SecretRedactor.redact(input);
      expect(redacted, contains('********'));
      expect(redacted, isNot(contains('eyJhbGci')));
    });

    test('redacts GitHub tokens', () {
      final input = 'ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef12';
      final redacted = SecretRedactor.redact(input);
      expect(redacted, '********');
    });

    test('redacts OpenAI API keys', () {
      final input = 'sk-proj-ABCDEFGHIJKLMNOPQRSTUVWXYZabcdef1234567890';
      final redacted = SecretRedactor.redact(input);
      expect(redacted, contains('********'));
    });

    test('redacts passwords', () {
      final input = 'password=SuperSecret123!';
      final redacted = SecretRedactor.redact(input);
      expect(redacted, contains('********'));
      expect(redacted, isNot(contains('SuperSecret123')));
    });

    test('redacts tokens', () {
      final input = 'token=abc123def456ghi789';
      final redacted = SecretRedactor.redact(input);
      expect(redacted, contains('********'));
    });

    test('preserves non-sensitive content', () {
      final input = 'File saved successfully at lib/main.dart';
      final redacted = SecretRedactor.redact(input);
      expect(redacted, input);
    });

    test('preserves file paths', () {
      final input = 'Reading file: /data/data/com.panda.ide/projects/myapp/lib/main.dart';
      final redacted = SecretRedactor.redact(input);
      expect(redacted, input);
    });

    test('preserves log messages', () {
      final input = 'Terminal command completed with exit code 0';
      final redacted = SecretRedactor.redact(input);
      expect(redacted, input);
    });

    test('detects sensitive content', () {
      expect(SecretRedactor.containsSensitive('api_key=abc123'), true);
      expect(SecretRedactor.containsSensitive('Bearer token123'), true);
      expect(SecretRedactor.containsSensitive('password=secret'), true);
      expect(SecretRedactor.containsSensitive('Normal log message'), false);
    });

    test('handles case insensitive matching', () {
      final input = 'API_KEY=test123';
      final redacted = SecretRedactor.redact(input);
      expect(redacted, contains('********'));
    });

    test('redacts multiple secrets in one string', () {
      final input = 'api_key=abc123 and token=def456';
      final redacted = SecretRedactor.redact(input);
      expect(redacted, contains('********'));
    });

    test('redacts AWS secret keys', () {
      final input = 'AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY';
      final redacted = SecretRedactor.redact(input);
      expect(redacted, contains('********'));
    });

    test('does not redact regular text', () {
      final input = 'Building Flutter APK...';
      expect(SecretRedactor.redact(input), input);
    });

    test('handles empty string', () {
      expect(SecretRedactor.redact(''), '');
    });
  });
}
