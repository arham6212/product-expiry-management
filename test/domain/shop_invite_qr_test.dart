import 'package:flutter_test/flutter_test.dart';
import 'package:product_expiry_management/domain/entities/shop_invite_qr.dart';

void main() {
  group('ShopInviteQr', () {
    test('encode returns correct payload', () {
      expect(ShopInviteQr.encode('A1B2C3'), 'shop-invite:A1B2C3');
      expect(ShopInviteQr.encode(' a1b2c3 '), 'shop-invite:A1B2C3');
    });

    test('normalizes codes independently of QR parsing', () {
      expect(ShopInviteQr.normalizeCode('  a1b2c3  '), 'A1B2C3');
      expect(ShopInviteQr.isValidCode(' a1b2c3 '), isTrue);
      expect(ShopInviteQr.isValidCode('A1B-23'), isFalse);
    });

    test('encode rejects malformed codes', () {
      expect(() => ShopInviteQr.encode('A1B2C'), throwsFormatException);
      expect(() => ShopInviteQr.encode('A1B-23'), throwsFormatException);
    });

    test('parse extracts code correctly from valid payload', () {
      expect(ShopInviteQr.parse('shop-invite:A1B2C3'), 'A1B2C3');
      expect(ShopInviteQr.parse('  shop-invite:A1B2C3  '), 'A1B2C3');
      expect(ShopInviteQr.parse('shop-invite:a1b2c3'), 'A1B2C3');
    });

    test('parse rejects arbitrary QR content', () {
      expect(ShopInviteQr.parse('http://example.com'), isNull);
      expect(ShopInviteQr.parse('A1B2C3'), isNull);
      expect(ShopInviteQr.parse('shop-invite:'), isNull);
    });

    test('parse rejects malformed codes', () {
      expect(ShopInviteQr.parse('shop-invite:A1B2C'), isNull); // too short
      expect(ShopInviteQr.parse('shop-invite:A1B2C34'), isNull); // too long
      expect(ShopInviteQr.parse('shop-invite:A1B-C3'), isNull); // invalid char
      expect(ShopInviteQr.parse('SHOP-INVITE:A1B2C3'), isNull);
    });
  });
}
