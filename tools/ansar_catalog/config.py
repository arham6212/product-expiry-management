from __future__ import annotations

from pathlib import Path

SOURCE = "Ansar Gallery Qatar"
BASE_URL = "https://www.ansargallery.com"
GROCERY_URL = f"{BASE_URL}/en/grocery"
PROJECT_ROOT = Path(__file__).resolve().parents[2]
DATA_DIR = PROJECT_ROOT / "data"
WORKBOOK_PATH = DATA_DIR / "ansar_gallery_product_catalog.xlsx"
STATE_PATH = DATA_DIR / "ansar_gallery_crawl_state.json"
LOG_DIR = DATA_DIR / "logs"
LOCK_PATH = DATA_DIR / ".ansar_catalog.lock"
TARGET_PRODUCTS = 50

USER_AGENT = (
    "AnsarCatalogResearchBot/1.0 "
    "(+catalog research/data-seeding; conservative sequential requests)"
)

PRODUCT_COLUMNS = [
    "id", "canonical_name", "source_display_name", "brand", "product_family",
    "variant_name", "product_type", "global_barcode", "barcode_type",
    "barcode_valid", "ansar_sku", "identifier_classification", "pack_count",
    "unit_quantity", "unit_quantity_unit", "total_quantity",
    "total_quantity_unit", "packaging_display", "category", "subcategory",
    "country_of_origin", "manufacturer", "primary_image_url",
    "source_product_url", "source", "first_seen_at", "last_seen_at",
    "data_confidence", "notes",
]

RUN_LOG_COLUMNS = [
    "run_id", "started_at", "completed_at", "candidate_products_examined",
    "new_products_added", "duplicates_skipped", "valid_global_barcodes",
    "invalid_or_internal_identifiers", "errors", "notes",
]

# Deliberately ordered for bakala/supermarket usefulness. State rotates across
# these queues and advances each category's page independently.
CATEGORY_SEEDS = [
    ("Beverages", "/en/grocery/beverages"),
    ("Dairy - Egg & Cheese", "/en/grocery/dairy-egg-cheese"),
    ("Snacks & Candy", "/en/grocery/snacks-candy"),
    ("Dry Food", "/en/grocery/dry-food"),
    ("Cooking & Baking", "/en/grocery/cooking-baking-products"),
    ("Condiments & Seasoning", "/en/grocery/condiments-seasoning"),
    ("Canned & Jarred Food", "/en/grocery/canned-jarred-food"),
    ("Coffee & Tea", "/en/grocery/coffee-tea-sugar"),
    ("Breakfast Food", "/en/grocery/breakfast-food"),
    ("Frozen Food", "/en/grocery/frozen-food"),
    ("Bakery", "/en/grocery/bakery-breads-cakes"),
    ("International Food", "/en/grocery/international-food"),
    ("Healthy & Organic Foods", "/en/grocery/healthy-organic-foods"),
    ("Dry & Natural Foods", "/en/grocery/dry-natural-foods"),
    ("Ice Cream", "/en/grocery/ice-cream"),
    ("Grab & Go", "/en/grocery/grab-go"),
    ("Cleaning & Laundry", "/en/grocery/cleaning-laundry"),
    ("Disposable & Storage", "/en/grocery/disposable-storage"),
    ("Delicatessen", "/en/grocery/delicatessen"),
    ("Produce", "/en/grocery/produce"),
]
