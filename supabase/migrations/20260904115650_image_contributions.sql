CREATE TABLE public.catalog_product_image_contributions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    catalog_product_id UUID NOT NULL REFERENCES public.catalog_products(id) ON DELETE CASCADE,
    storage_provider TEXT NOT NULL CHECK (storage_provider = 'cloudinary'),
    provider_asset_id TEXT NOT NULL,
    provider_public_id TEXT NOT NULL,
    provider_version TEXT NOT NULL,
    delivery_url TEXT NOT NULL,
    shop_id UUID REFERENCES public.shops(id) ON DELETE SET NULL,
    uploaded_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    is_canonical BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    CONSTRAINT uq_provider_asset UNIQUE (storage_provider, provider_asset_id)
);

CREATE UNIQUE INDEX idx_unique_canonical_image 
ON public.catalog_product_image_contributions(catalog_product_id) 
WHERE is_canonical = true;

CREATE OR REPLACE FUNCTION public.catalog_product_image_contributions_update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER handle_updated_at BEFORE UPDATE ON public.catalog_product_image_contributions
FOR EACH ROW EXECUTE FUNCTION public.catalog_product_image_contributions_update_timestamp();

ALTER TABLE public.catalog_product_image_contributions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their own contributions"
ON public.catalog_product_image_contributions FOR SELECT
TO authenticated
USING (uploaded_by = auth.uid());

CREATE OR REPLACE FUNCTION public.contribute_catalog_product_image(
    p_shop_id UUID,
    p_catalog_product_id UUID,
    p_provider_asset_id TEXT,
    p_provider_public_id TEXT,
    p_provider_version TEXT,
    p_delivery_url TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
    v_existing_contribution RECORD;
    v_new_id UUID;
BEGIN
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'Not authenticated';
    END IF;

    IF NOT public.is_shop_member(p_shop_id) THEN
        RAISE EXCEPTION 'Not a member of the shop';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.products
        WHERE shop_id = p_shop_id AND catalog_product_id = p_catalog_product_id
    ) THEN
        RAISE EXCEPTION 'Shop does not have a product linked to this catalog product';
    END IF;

    SELECT * INTO v_existing_contribution
    FROM public.catalog_product_image_contributions
    WHERE storage_provider = 'cloudinary' AND provider_asset_id = p_provider_asset_id;

    IF FOUND THEN
        IF v_existing_contribution.shop_id != p_shop_id THEN
            RAISE EXCEPTION 'Asset already contributed by a different shop';
        END IF;
        IF v_existing_contribution.catalog_product_id != p_catalog_product_id THEN
            RAISE EXCEPTION 'Asset already contributed for a different catalog product';
        END IF;
        IF v_existing_contribution.uploaded_by != v_user_id THEN
            RAISE EXCEPTION 'Asset already contributed by a different user';
        END IF;
        
        IF v_existing_contribution.status != 'pending' THEN
            RETURN v_existing_contribution.id;
        END IF;

        UPDATE public.catalog_product_image_contributions
        SET provider_public_id = p_provider_public_id,
            provider_version = p_provider_version,
            delivery_url = p_delivery_url
        WHERE id = v_existing_contribution.id;

        RETURN v_existing_contribution.id;
    END IF;

    INSERT INTO public.catalog_product_image_contributions (
        catalog_product_id,
        storage_provider,
        provider_asset_id,
        provider_public_id,
        provider_version,
        delivery_url,
        shop_id,
        uploaded_by,
        status,
        is_canonical
    ) VALUES (
        p_catalog_product_id,
        'cloudinary',
        p_provider_asset_id,
        p_provider_public_id,
        p_provider_version,
        p_delivery_url,
        p_shop_id,
        v_user_id,
        'pending',
        false
    ) RETURNING id INTO v_new_id;

    RETURN v_new_id;
END;
$$;

REVOKE ALL ON FUNCTION public.contribute_catalog_product_image FROM public, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.contribute_catalog_product_image TO authenticated;

CREATE OR REPLACE FUNCTION public.set_catalog_product_canonical_image(
    p_contribution_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_catalog_product_id UUID;
    v_delivery_url TEXT;
BEGIN
    SELECT catalog_product_id, delivery_url INTO v_catalog_product_id, v_delivery_url
    FROM public.catalog_product_image_contributions
    WHERE id = p_contribution_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Contribution not found';
    END IF;

    PERFORM 1 FROM public.catalog_products WHERE id = v_catalog_product_id FOR UPDATE;

    UPDATE public.catalog_product_image_contributions
    SET is_canonical = false
    WHERE catalog_product_id = v_catalog_product_id AND is_canonical = true;

    UPDATE public.catalog_product_image_contributions
    SET status = 'approved',
        is_canonical = true
    WHERE id = p_contribution_id;

    UPDATE public.catalog_products
    SET image_url = v_delivery_url
    WHERE id = v_catalog_product_id;

END;
$$;

REVOKE ALL ON FUNCTION public.set_catalog_product_canonical_image FROM public, authenticated, anon;
GRANT EXECUTE ON FUNCTION public.set_catalog_product_canonical_image TO service_role;
