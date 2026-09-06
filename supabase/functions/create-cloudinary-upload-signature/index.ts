import "jsr:@supabase/functions-js@2/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import {
  imageLimits,
  sha1Signature,
  uploadContext,
  shopUploadContext,
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
    if (typeof shopId !== "string" || (!isShopPhoto && typeof catalogProductId !== "string")) {
      return json({ error: "Invalid request parameters" }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    if (!supabaseUrl || !anonKey) {
      return json({ error: "Missing server configuration" }, 500);
    }
    const supabase = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) {
      return json({ error: "Invalid JWT or unauthenticated" }, 401);
    }
    const { data: product, error: productError } = await supabase.from(
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
    const timestamp = Math.floor(Date.now() / 1000).toString();
    const folder = isShopPhoto
      ? `shops/${shopId}/products/${productId}`
      : `product-catalog/contributions/${catalogProductId}`;
    const publicId = crypto.randomUUID();
    const params: Record<string, string> = {
      allowed_formats: imageLimits.allowedFormats.join(","),
      context: isShopPhoto ? shopUploadContext(user.id, shopId, productId) : uploadContext(user.id, shopId, catalogProductId),
      folder,
      overwrite: "false",
      public_id: publicId,
      timestamp,
      transformation:
        `c_limit,w_${imageLimits.maxDimension},h_${imageLimits.maxDimension}`,
    };
    return json({
      cloudName,
      apiKey,
      signature: await sha1Signature(params, apiSecret),
      ...params,
      publicId,
      maxBytes: imageLimits.maxBytes,
    });
  } catch (_) {
    return json({ error: "Internal Server Error" }, 500);
  }
});
