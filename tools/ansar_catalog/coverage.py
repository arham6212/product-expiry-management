from __future__ import annotations

import re

from .normalizer import identity_text, normalize_space


# These profiles describe product-name terms shown by Ansar for major umbrella
# brands. They are crawl hints only: the product page remains the source of
# truth for the row's own brand/manufacturer fields.
UMBRELLA_BRAND_PROFILES = {
    "nestle": {
        "display_name": "Nestle",
        "terms": [
            "nestle", "nesquik", "nescafe", "coffee mate", "maggi", "milo",
            "nido", "cerelac", "kitkat", "kit kat", "lion cereal",
        ],
    },
    "coca cola": {
        "display_name": "Coca-Cola",
        "terms": ["coca cola", "coke"],
    },
}

SOFT_DRINK_TERMS = [
    "soft drink", "carbonated drink", "cola", "coca cola", "coke", "pepsi",
    "sprite", "fanta", "7up", "7 up", "mirinda", "mountain dew", "schweppes",
    "ginger ale", "tonic water", "soda water", "root beer", "energy drink",
]

EXPLICIT_BRAND_PREFIXES = [
    ("coca cola", "Coca-Cola"),
    ("kit kat", "KitKat"),
    ("kitkat", "KitKat"),
    ("coffee mate", "Coffee mate"),
    ("nestle", "Nestle"),
    ("nesquik", "Nesquik"),
    ("nescafe", "Nescafe"),
    ("maggi", "Maggi"),
    ("milo", "Milo"),
    ("nido", "Nido"),
    ("cerelac", "Cerelac"),
    ("coke", "Coca-Cola"),
]

REQUESTED_COVERAGE_SPECS = [
    {
        "kind": "brand",
        "display_name": UMBRELLA_BRAND_PROFILES["nestle"]["display_name"],
        "match_terms": UMBRELLA_BRAND_PROFILES["nestle"]["terms"],
        "category_names": None,
    },
    {
        "kind": "category_family",
        "display_name": "Soft Drinks",
        "match_terms": SOFT_DRINK_TERMS,
        "category_names": ["Beverages"],
    },
]


def normalize_match_term(value: str | None) -> str:
    return identity_text(value)


def term_in_name(term: str, name: str) -> bool:
    normalized_term = normalize_match_term(term)
    normalized_name = normalize_match_term(name)
    if not normalized_term or not normalized_name:
        return False
    return re.search(rf"(?:^| ){re.escape(normalized_term)}(?: |$)", normalized_name) is not None


def coverage_job_matches(job: dict, product_name: str) -> bool:
    return any(term_in_name(term, product_name) for term in job.get("match_terms", []))


def infer_explicit_brand_prefix(product_name: str | None) -> str | None:
    normalized = normalize_match_term(product_name)
    for prefix, brand in EXPLICIT_BRAND_PREFIXES:
        normalized_prefix = normalize_match_term(prefix)
        if normalized == normalized_prefix or normalized.startswith(normalized_prefix + " "):
            return brand
    return None


def _profile_for_text(value: str | None) -> dict | None:
    normalized = normalize_match_term(value)
    if not normalized:
        return None
    for key, profile in UMBRELLA_BRAND_PROFILES.items():
        if term_in_name(key, normalized) or any(term_in_name(term, normalized) for term in profile["terms"]):
            return profile
    return None


def coverage_specs_for_product(row: dict) -> list[dict]:
    """Return conservative, idempotent coverage targets for one product row."""
    specs: list[dict] = []
    name = normalize_space(str(row.get("canonical_name") or row.get("source_display_name") or ""))
    brand = normalize_space(str(row.get("brand") or ""))
    category = normalize_space(str(row.get("category") or ""))

    profile = _profile_for_text(brand) or _profile_for_text(name)
    if profile:
        specs.append({
            "kind": "brand",
            "display_name": profile["display_name"],
            "match_terms": profile["terms"],
            "category_names": None,
        })
    elif brand and len(normalize_match_term(brand)) >= 3:
        specs.append({
            "kind": "brand",
            "display_name": brand,
            "match_terms": [brand],
            "category_names": None,
        })

    family = normalize_space(str(row.get("product_family") or ""))
    variant = normalize_space(str(row.get("variant_name") or ""))
    if family and variant and bool(row.get("global_barcode")):
        specs.append({
            "kind": "product_family",
            "display_name": family,
            "match_terms": [family],
            "category_names": [category] if category else None,
        })

    if category == "Beverages" and any(term_in_name(term, name) for term in SOFT_DRINK_TERMS):
        specs.append({
            "kind": "category_family",
            "display_name": "Soft Drinks",
            "match_terms": SOFT_DRINK_TERMS,
            "category_names": ["Beverages"],
        })
    return specs
