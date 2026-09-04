from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal
import re


@dataclass(frozen=True)
class Packaging:
    pack_count: int | None = None
    unit_quantity: Decimal | None = None
    unit_quantity_unit: str | None = None
    total_quantity: Decimal | None = None
    total_quantity_unit: str | None = None
    packaging_display: str | None = None
    product_type: str = "packaged"


UNIT_MAP = {
    "kg": "kg", "g": "g", "gm": "g", "mg": "mg",
    "l": "L", "ltr": "L", "litre": "L", "liter": "L",
    "ml": "ml", "cl": "cl", "oz": "oz",
}


def _decimal(text: str) -> Decimal:
    return Decimal(text)


def _display_number(value: Decimal) -> str:
    return format(value.normalize(), "f")


def parse_packaging(name: str) -> Packaging:
    multipack = re.search(
        r"(?P<count>\d{1,3})\s*[x×]\s*(?P<qty>\d+(?:\.\d+)?)\s*"
        r"(?P<unit>kg|gm|g|mg|litres?|liters?|ltr|l|ml|cl|oz)\b",
        name, re.IGNORECASE,
    )
    if multipack:
        count = int(multipack.group("count"))
        qty = _decimal(multipack.group("qty"))
        unit = UNIT_MAP[multipack.group("unit").lower().rstrip("s")]
        total = qty * count
        return Packaging(count, qty, unit, total, unit, f"{count} x {_display_number(qty)}{unit}", "multipack")

    single_matches = list(re.finditer(
        r"(?<![\d.])(?P<qty>\d+(?:\.\d+)?)\s*"
        r"(?P<unit>kg|gm|g|mg|litres?|liters?|ltr|l|ml|cl|oz)\b",
        name, re.IGNORECASE,
    ))
    if single_matches:
        match = single_matches[-1]
        qty = _decimal(match.group("qty"))
        unit = UNIT_MAP[match.group("unit").lower().rstrip("s")]
        return Packaging(1, qty, unit, qty, unit, f"{_display_number(qty)}{unit}", "packaged")

    pieces = re.search(r"\b(?P<count>\d{1,3})\s*(?:pieces?|pcs|count|ct)\b", name, re.IGNORECASE)
    if pieces:
        count = int(pieces.group("count"))
        return Packaging(count, None, None, None, None, f"{count} pieces", "multipack" if count > 1 else "packaged")

    trailing_s = re.search(r"\b(?P<count>\d{1,3})\s*[sS]\b", name)
    if trailing_s:
        count = int(trailing_s.group("count"))
        return Packaging(count, None, None, None, None, f"{count} pieces", "multipack" if count > 1 else "packaged")
    return Packaging()


def normalize_space(value: str | None) -> str:
    return re.sub(r"\s+", " ", (value or "").strip())


def identity_text(name: str | None) -> str:
    return re.sub(r"[^a-z0-9]+", " ", normalize_space(name).casefold()).strip()


def infer_family_variant(name: str, packaging_display: str | None) -> tuple[str | None, str | None]:
    base = normalize_space(name)
    if packaging_display:
        escaped = re.escape(packaging_display).replace(r"\ x\ ", r"\s*[x×]\s*").replace(r"\ ", r"\s*")
        base = re.sub(escaped + r"\s*$", "", base, flags=re.IGNORECASE).strip(" -,")
    # Conservative: only explicit flavor/variant suffixes are split.
    match = re.search(
        r"\b(?P<variant>Original|Zero(?: Sugar)?|Diet|Migoreng|Carbonara|Cheese|"
        r"Special Chicken|Chicken|Beef|Curry|Strawberry|Chocolate|Vanilla|Peach|"
        r"Mango|Orange|Apple|Lemon Mint Mojito|Lemon|Salted)"
        r"(?:\s+Flavou?red?|\s+Flavor)?$", base, re.IGNORECASE,
    )
    if match and match.start() > 2:
        family = base[:match.start()].strip(" -,")
        return family or base, normalize_space(match.group("variant"))
    return base or None, None


def json_number(value: Decimal | None) -> int | float | None:
    if value is None:
        return None
    return int(value) if value == value.to_integral() else float(value)

