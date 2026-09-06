import { assertEquals, assertThrows } from "jsr:@std/assert@1";
import {
  uploadContext,
  validateAuthoritativeImage,
} from "./image_upload_security.ts";

const ids = { user: "user-1", shop: "shop-1", catalog: "catalog-1" };
const publicId = `product-catalog/contributions/${ids.catalog}/asset-1`;
const valid = {
  asset_id: "asset-1",
  public_id: publicId,
  version: 42,
  resource_type: "image",
  type: "upload",
  format: "jpg",
  bytes: 1024,
  width: 1200,
  height: 900,
  secure_url:
    `https://res.cloudinary.com/demo/image/upload/v42/${publicId}.jpg`,
  context: {
    custom: {
      uploaded_by: ids.user,
      shop_id: ids.shop,
      catalog_product_id: ids.catalog,
    },
  },
};
const verify = (data: Record<string, unknown>) =>
  validateAuthoritativeImage({
    data,
    cloudName: "demo",
    publicId,
    version: "42",
    expectedFolder: `product-catalog/contributions/${ids.catalog}`,
    expectedContext: uploadContext(ids.user, ids.shop, ids.catalog),
  });

Deno.test("accepts authoritative bounded image metadata", () =>
  assertEquals(verify(valid).mimeType, "image/jpeg"));
Deno.test("rejects spoofed ownership context", () => {
  assertThrows(() =>
    verify({
      ...valid,
      context: { custom: { ...valid.context.custom, shop_id: "other" } },
    })
  );
});
Deno.test("rejects unsupported formats and oversized content", () => {
  assertThrows(() => verify({ ...valid, format: "svg" }));
  assertThrows(() => verify({ ...valid, bytes: 5 * 1024 * 1024 + 1 }));
  assertThrows(() => verify({ ...valid, width: 2049 }));
});
Deno.test("rejects another delivery host", () => {
  assertThrows(() =>
    verify({ ...valid, secure_url: "https://example.test/image.jpg" })
  );
});
