class ShopInviteQr {
  static const _prefix = 'shop-invite:';
  static final RegExp _codePattern = RegExp(r'^[A-Z0-9]{6}$');

  static String normalizeCode(String code) => code.trim().toUpperCase();

  static bool isValidCode(String code) => _codePattern.hasMatch(normalizeCode(code));

  static String encode(String code) {
    final normalizedCode = normalizeCode(code);
    if (!_codePattern.hasMatch(normalizedCode)) {
      throw const FormatException('Invite codes must contain six letters or digits.');
    }
    return '$_prefix$normalizedCode';
  }

  static String? parse(String rawValue) {
    final trimmed = rawValue.trim();
    if (!trimmed.startsWith(_prefix)) {
      return null;
    }

    final code = normalizeCode(trimmed.substring(_prefix.length));
    if (!_codePattern.hasMatch(code)) {
      return null;
    }

    return code;
  }
}
