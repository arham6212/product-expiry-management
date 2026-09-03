import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/core/identity/secure_id_generator.dart';

void main() {
  test('generates unique RFC 4122 version 4 identifiers', () {
    final values = List.generate(100, (_) => SecureIdGenerator.uuidV4());

    expect(values.toSet(), hasLength(values.length));
    expect(
      values,
      everyElement(
        matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
      ),
    );
  });
}
