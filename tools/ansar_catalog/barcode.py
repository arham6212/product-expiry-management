from __future__ import annotations

from dataclasses import dataclass
import re


@dataclass(frozen=True)
class IdentifierResult:
    raw: str
    global_barcode: str | None
    barcode_type: str | None
    barcode_valid: bool
    classification: str
    rejection_reason: str | None


def _digits(value: str | None) -> str:
    return re.sub(r"[\s-]", "", value or "")


def validate_gtin(value: str | None) -> bool:
    """Validate GTIN-8, UPC-A, EAN-13, or GTIN-14 using GS1 modulo-10."""
    code = _digits(value)
    if not code.isdigit() or len(code) not in {8, 12, 13, 14}:
        return False
    body, check = code[:-1], int(code[-1])
    total = 0
    for index, digit in enumerate(reversed(body), start=1):
        total += int(digit) * (3 if index % 2 == 1 else 1)
    return (10 - total % 10) % 10 == check


def classify_identifier(value: str | None) -> IdentifierResult:
    raw = (value or "").strip()
    code = _digits(raw)
    if not code:
        return IdentifierResult(raw, None, None, False, "unknown", "identifier missing")
    if not code.isdigit():
        classification = "composite identifier" if any(c.isdigit() for c in code) else "retailer/internal SKU"
        return IdentifierResult(raw, None, None, False, classification, "identifier is not numeric")
    if len(code) not in {8, 12, 13, 14}:
        return IdentifierResult(raw, None, None, False, "retailer/internal SKU", f"unsupported GTIN length: {len(code)}")
    if len(set(code)) == 1:
        return IdentifierResult(raw, None, None, False, "retailer/internal SKU", "repeated-digit placeholder")
    if code.startswith("499990"):
        return IdentifierResult(raw, None, None, False, "retailer/internal SKU", "known retailer-assigned 499990 prefix")
    if len(code) == 13 and re.fullmatch(r"\d{6}0{7}", code):
        return IdentifierResult(raw, None, None, False, "weighted/internal product code", "retailer/weighted pattern with seven trailing zeroes")
    # GS1 prefixes 20-29 are restricted-distribution numbers commonly used for
    # store/weighted items; they are not useful global product identities.
    if len(code) in {13, 14} and code[:2] in {str(n) for n in range(20, 30)}:
        return IdentifierResult(raw, None, None, False, "weighted/internal product code", "GS1 restricted-distribution prefix 20-29")
    if not validate_gtin(code):
        return IdentifierResult(raw, None, None, False, "invalid GTIN", "GTIN checksum failed")
    barcode_type = {8: "GTIN-8", 12: "UPC-A", 13: "EAN-13", 14: "GTIN-14"}[len(code)]
    return IdentifierResult(code, code, barcode_type, True, barcode_type, None)
