import "jsr:@supabase/functions-js@2/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  sha1Signature,
  uploadContext,
  shopUploadContext,
  validateAuthoritativeImage,
} from "../_shared/image_upload_security.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
const basicAuth = (value: string) => btoa(unescape(encodeURIComponent(value)));

async function destroyOwnedAsset(
  baseUrl: string,
  publicId: string,
  apiKey: string,
  secret: string,
) {
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const params = { invalidate: "true", public_id: publicId, timestamp };
  const body = new URLSearchParams({
    ...params,
    api_key: apiKey,
    signature: await sha1Signature(params, secret),
  });
  await fetch(`${baseUrl}/image/destroy`, { method: "POST", body }).catch(() =>
    null
  );
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Missing authorization" }, 401);
    const body = await req.json().catch(() => null);
    const shopId = body?.shopId;
    const catalogProductId = body?.catalogProductId;
    const productId = body?.productId;
    const isShopPhoto = typeof productId === "string" && productId.length > 0;
    const publicId = body?.publicId;
    const version = String(body?.version ?? "");
    if (
      [shopId, isShopPhoto ? productId : catalogProductId, publicId, version].some((value) =>
        typeof value !== "string" || !value
      )
    ) return json({ error: "Missing required parameters" }, 400);

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !anonKey || !serviceKey) {
      return json({ error: "Missing server configuration" }, 500);
    }
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: authError } = await userClient.auth
      .getUser();
    if (authError || !user) {
      return json({ error: "Invalid JWT or unauthenticated" }, 401);
    }
    const { data: product, error: productError } = await userClient.from(
      "products",
    ).select("id,catalog_product_id")
      .eq("shop_id", shopId).eq(isShopPhoto ? "id" : "catalog_product_id", isShopPhoto ? productId : catalogProductId).limit(1)
      .maybeSingle();
    if (productError || !product) {
      return json({ error: "Unauthorized or invalid product" }, 403);
    }

    const cloudName = Deno.env.get("CLOUDINARY_CLOUD_NAME");
    const apiKey = Deno.env.get("CLOUDINARY_API_KEY");
    const apiSecret = Deno.env.get("CLOUDINARY_API_SECRET");
    if (!cloudName || !apiKey || !apiSecret) {
      return json({ error: "Missing Cloudinary configuration" }, 500);
    }
    const baseUrl = Deno.env.get("CLOUDINARY_API_BASE_URL") ??
      `https://api.cloudinary.com/v1_1/${cloudName}`;
    const resource = await fetch(
      `${baseUrl}/resources/image/upload/${encodeURIComponent(publicId)}`,
      {
        headers: {
          Authorization: `Basic ${basicAuth(`${apiKey}:${apiSecret}`)}`,
        },
      },
    );
    if (!resource.ok) {
      return json({ error: "Cloudinary could not verify this upload" }, 400);
    }
    const adminData = await resource.json() as Record<string, unknown>;
    const context =
      (adminData.context as { custom?: Record<string, unknown> } | undefined)
        ?.custom;
    const ownsAsset = context?.uploaded_by === user.id &&
      context?.shop_id === shopId &&
      (isShopPhoto ? context?.product_id === productId : context?.catalog_product_id === catalogProductId);
    let verified;
    try {
      verified = validateAuthoritativeImage({
        data: adminData,
        cloudName,
        publicId,
        version,
        expectedFolder: isShopPhoto ? `shops/${shopId}/products/${productId}` : `product-catalog/contributions/${catalogProductId}`,
        expectedContext: isShopPhoto ? shopUploadContext(user.id, shopId, productId) : uploadContext(user.id, shopId, catalogProductId),
      });
    } catch (error) {
      if (ownsAsset) {
        await destroyOwnedAsset(baseUrl, publicId, apiKey, apiSecret);
      }
      return json({
        error: error instanceof Error ? error.message : "Invalid image",
      }, 400);
    }

    const serviceClient = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false },
    });
    if (isShopPhoto) {
      const { data: saved, error } = await serviceClient.rpc(
        "record_verified_shop_product_image", {
          p_uploaded_by: user.id, p_shop_id: shopId, p_product_id: productId,
          p_provider_asset_id: verified.assetId, p_provider_public_id: verified.publicId,
          p_provider_version: verified.version, p_delivery_url: verified.secureUrl,
          p_mime_type: verified.mimeType, p_byte_size: verified.byteSize,
          p_pixel_width: verified.width, p_pixel_height: verified.height,
        },
      ).single();
      // Do not destroy on an uncertain database response: it may already be saved.
      // Retrying the same verified asset is idempotent.
      if (error || !saved) return json({ error: "Photo could not be saved. Retry." }, 500);
      return json({ imageId: saved.image_id, status: "saved", deliveryUrl: saved.delivery_url });
    }

    const { data: contribution, error: recordError } = await serviceClient.rpc(
      "record_verified_catalog_product_image_contribution",
      {
        p_uploaded_by: user.id,
        p_shop_id: shopId,
        p_catalog_product_id: catalogProductId,
        p_provider_asset_id: verified.assetId,
        p_provider_public_id: verified.publicId,
        p_provider_version: verified.version,
        p_delivery_url: verified.secureUrl,
        p_mime_type: verified.mimeType,
        p_byte_size: verified.byteSize,
        p_pixel_width: verified.width,
        p_pixel_height: verified.height,
      },
    ).single();
    if (recordError || !contribution) {
      const { data: existing, error: lookupError } = await serviceClient
        .from("catalog_product_image_contributions")
        .select("id,status,delivery_url")
        .eq("storage_provider", "cloudinary")
        .eq("provider_asset_id", verified.assetId)
        .maybeSingle();
      if (existing) {
        return json({
          contributionId: existing.id,
          status: existing.status,
          deliveryUrl: existing.delivery_url,
        });
      }
      if (!lookupError) {
        await destroyOwnedAsset(baseUrl, publicId, apiKey, apiSecret);
      }
      return json({ error: "The verified image could not be recorded" }, 500);
    }
    const recorded = contribution as Record<string, unknown>;
    return json({
      contributionId: recorded.contribution_id,
      status: recorded.contribution_status,
      deliveryUrl: recorded.delivery_url,
    });
  } catch (_) {
    return json({ error: "Internal Server Error" }, 500);
  }
});
