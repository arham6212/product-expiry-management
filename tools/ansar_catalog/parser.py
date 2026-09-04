from __future__ import annotations

from dataclasses import dataclass
from html import unescape
from html.parser import HTMLParser
import json
import re
from urllib.parse import unquote, urljoin, urlparse, parse_qs

from .config import BASE_URL


@dataclass(frozen=True)
class ListingCandidate:
    name: str
    url: str
    image_url: str | None
    category: str
    sku_hint: str | None
    coverage_key: str | None = None


class _CatalogHTMLParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.anchors: list[tuple[dict[str, str], str | None]] = []
        self.scripts: list[tuple[str | None, str]] = []
        self._anchor: dict[str, str] | None = None
        self._anchor_image: str | None = None
        self._script_type: str | None = None
        self._script_data: list[str] | None = None

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        data = {k: v or "" for k, v in attrs}
        if tag == "a":
            self._anchor = data
            self._anchor_image = None
        elif tag == "img" and self._anchor is not None:
            raw = data.get("src") or data.get("srcset")
            self._anchor_image = _unwrap_image(raw)
        elif tag == "script":
            self._script_type = data.get("type")
            self._script_data = []

    def handle_endtag(self, tag: str) -> None:
        if tag == "a" and self._anchor is not None:
            self.anchors.append((self._anchor, self._anchor_image))
            self._anchor = None
            self._anchor_image = None
        elif tag == "script" and self._script_data is not None:
            self.scripts.append((self._script_type, "".join(self._script_data)))
            self._script_type = None
            self._script_data = None

    def handle_data(self, data: str) -> None:
        if self._script_data is not None:
            self._script_data.append(data)


def _unwrap_image(value: str | None) -> str | None:
    if not value:
        return None
    value = unescape(value.split()[0])
    parsed = urlparse(value)
    if parsed.path.endswith("/_next/image") or parsed.path == "/_next/image":
        return unquote(parse_qs(parsed.query).get("url", [""])[0]) or None
    return urljoin(BASE_URL, value)


def _sku_from_url(url: str) -> str | None:
    match = re.search(r"-qatar-([A-Za-z0-9_-]+?)(?:\.html)?/?$", url)
    return match.group(1) if match else None


def parse_listing(html: str, category: str) -> list[ListingCandidate]:
    parser = _CatalogHTMLParser()
    parser.feed(html)
    seen: set[str] = set()
    products: list[ListingCandidate] = []
    for attrs, image in parser.anchors:
        href, title = attrs.get("href", ""), attrs.get("title", "").strip()
        if not title or not href.startswith("/en/") or "-qatar-" not in href:
            continue
        url = urljoin(BASE_URL, href)
        if url in seen:
            continue
        seen.add(url)
        products.append(ListingCandidate(title, url, image, category, _sku_from_url(url)))
    return products


def parse_product(html: str) -> dict:
    parser = _CatalogHTMLParser()
    parser.feed(html)
    product: dict = {}
    breadcrumbs: list[dict] = []
    decoded_flights: list[str] = []
    for script_type, data in parser.scripts:
        if script_type == "application/ld+json":
            try:
                payload = json.loads(unescape(data))
            except (json.JSONDecodeError, TypeError):
                continue
            if payload.get("@type") == "Product":
                product = payload
            elif payload.get("@type") == "BreadcrumbList":
                breadcrumbs = payload.get("itemListElement") or []
        elif data.startswith("self.__next_f.push([1,"):
            match = re.match(r"self\.__next_f\.push\(\[1,(.*)\]\)$", data, re.DOTALL)
            if match:
                try:
                    decoded_flights.append(json.loads(match.group(1)))
                except json.JSONDecodeError:
                    pass
    if not product:
        raise ValueError("product JSON-LD not found")
    flight = "\n".join(decoded_flights)
    sku = str(product.get("sku") or "")
    window = flight
    if sku:
        pos = flight.find(f'"sku":"{sku}"')
        if pos >= 0:
            window = flight[pos:pos + 30000]
    def field(name: str) -> str | None:
        match = re.search(rf'"{re.escape(name)}":(?:null|"([^"\\]*(?:\\.[^"\\]*)*)")', window)
        if not match or match.group(1) is None:
            return None
        try:
            return json.loads(f'"{match.group(1)}"')
        except json.JSONDecodeError:
            return match.group(1)
    names = [str(x.get("name") or "").strip() for x in breadcrumbs]
    names = [x for x in names if x]
    category = names[2] if len(names) >= 4 else None
    subcategory = names[-2] if len(names) >= 2 else None
    brand = product.get("brand")
    if isinstance(brand, dict):
        brand = brand.get("name")
    image = product.get("image")
    if isinstance(image, list):
        image = image[0] if image else None
    manufacturer = product.get("manufacturer")
    if isinstance(manufacturer, dict):
        manufacturer = manufacturer.get("name")
    return {
        "name": product.get("name"), "sku": sku or None, "brand": brand or None,
        "image": image or None, "category": category, "subcategory": subcategory,
        "country_of_origin": product.get("countryOfOrigin") or field("country_of_manufacture"),
        "manufacturer": manufacturer or field("manufacturer"),
    }
