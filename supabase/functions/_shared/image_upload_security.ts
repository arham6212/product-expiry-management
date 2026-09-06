export const imageLimits = {
  maxBytes: 5 * 1024 * 1024,
  maxDimension: 2048,
  allowedFormats: ["jpg", "jpeg", "png", "webp"] as const,
};

export function uploadContext(
  userId: string,
  shopId: string,
  catalogProductId: string,
): string {
  return `uploaded_by=${userId}|shop_id=${shopId}|catalog_product_id=${catalogProductId}`;
}

export function mimeTypeForFormat(format: unknown): string | null {
  if (format === "jpg" || format === "jpeg") return "image/jpeg";
  if (format === "png") return "image/png";
  if (format === "webp") return "image/webp";
  return null;
}

export type VerifiedImage = {
  assetId: string;
  publicId: string;
  version: string;
  secureUrl: string;
  mimeType: string;
  byteSize: number;
  width: number;
  height: number;
};

export function validateAuthoritativeImage(args: {
  data: Record<string, unknown>;
  cloudName: string;
  publicId: string;
  version: string;
  expectedFolder: string;
  expectedContext: string;
}): VerifiedImage {
  const {
    data,
    cloudName,
    publicId,
    version,
    expectedFolder,
    expectedContext,
  } = args;
  const context =
    (data.context as { custom?: Record<string, unknown> } | undefined)?.custom;
  const expectedEntries = expectedContext.split("|").map((entry) => entry.split("="));
  if (!context || expectedEntries.some(([key, value]) => context[key] !== value)) {
    throw new Error("Asset ownership context mismatch");
  }
  if (data.resource_type !== "image" || data.type !== "upload") {
    throw new Error("Asset is not an uploaded image");
  }
  if (data.public_id !== publicId || String(data.version) !== version) {
    throw new Error("Asset identity mismatch");
  }
  if (!publicId.startsWith(`${expectedFolder}/`)) {
    throw new Error("Asset folder mismatch");
  }
  const mimeType = mimeTypeForFormat(data.format);
  if (mimeType == null) throw new Error("Unsupported image format");
  const byteSize = Number(data.bytes);
  const width = Number(data.width);
  const height = Number(data.height);
  if (
    !Number.isInteger(byteSize) || byteSize < 1 ||
    byteSize > imageLimits.maxBytes
  ) throw new Error("Image exceeds the byte-size limit");
  if (
    !Number.isInteger(width) || !Number.isInteger(height) || width < 1 ||
    height < 1 || width > imageLimits.maxDimension ||
    height > imageLimits.maxDimension
  ) throw new Error("Image exceeds the dimension limit");
  const secureUrl = data.secure_url;
  if (
    typeof secureUrl !== "string" ||
    !secureUrl.startsWith(
      `https://res.cloudinary.com/${cloudName}/image/upload/`,
    )
  ) {
    throw new Error(
      "Asset delivery URL is not from the configured Cloudinary account",
    );
  }
  if (typeof data.asset_id !== "string" || data.asset_id.length === 0) {
    throw new Error("Asset ID is missing");
  }
  return {
    assetId: data.asset_id,
    publicId,
    version,
    secureUrl,
    mimeType,
    byteSize,
    width,
    height,
  };
}

export async function sha1Signature(
  params: Record<string, string>,
  secret: string,
): Promise<string> {
  const value =
    Object.keys(params).sort().map((key) => `${key}=${params[key]}`).join("&") +
    secret;
  const digest = await crypto.subtle.digest(
    "SHA-1",
    new TextEncoder().encode(value),
  );
  return Array.from(new Uint8Array(digest)).map((byte) =>
    byte.toString(16).padStart(2, "0")
  ).join("");
}

export function shopUploadContext(userId: string, shopId: string, productId: string): string {
  return `uploaded_by=${userId}|shop_id=${shopId}|product_id=${productId}`;
}
