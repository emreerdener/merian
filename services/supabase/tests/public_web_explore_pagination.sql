\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(1);

INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    is_anonymous
)
VALUES (
    '00000000-0000-0000-0000-000000000000',
    '00000000-0000-4000-8000-00000000e801',
    'authenticated',
    'authenticated',
    'public-web-explore@naturebook.invalid',
    pg_catalog.NOW(),
    '{"provider":"email","providers":["email"]}'::JSONB,
    '{}'::JSONB,
    pg_catalog.NOW(),
    pg_catalog.NOW(),
    FALSE
);

INSERT INTO public.users (
    id,
    email,
    subscription_tier,
    public_username,
    public_author_name,
    public_identity_source
)
VALUES (
    '00000000-0000-4000-8000-00000000e801',
    'public-web-explore@naturebook.invalid',
    'pro',
    'public_web_e801',
    'Public Web Explorer',
    'alias'
)
ON CONFLICT (id) DO UPDATE
SET email = EXCLUDED.email,
    subscription_tier = EXCLUDED.subscription_tier,
    public_username = EXCLUDED.public_username,
    public_author_name = EXCLUDED.public_author_name,
    public_identity_source = EXCLUDED.public_identity_source;

INSERT INTO public.species_dictionary (
    id,
    scientific_name,
    common_names,
    kingdom,
    phylum,
    class,
    "order",
    family,
    genus,
    native_region
)
VALUES (
    '00000000-0000-4000-8000-00000000e811',
    'Publicus webensis',
    '{"en":"Public web species"}'::JSONB,
    'Animalia',
    'Chordata',
    'Aves',
    'Passeriformes',
    'Publicidae',
    'Publicus',
    'Test region'
);

INSERT INTO public.scans (
    id,
    user_id,
    species_id,
    image_storage_urls,
    ai_confidence_score,
    geoprivacy
)
VALUES (
    '00000000-0000-4000-8000-00000000e821',
    '00000000-0000-4000-8000-00000000e801',
    '00000000-0000-4000-8000-00000000e811',
    ARRAY['https://media.example.invalid/public-web.webp'],
    0.95,
    'private'
);

INSERT INTO public.explore_posts (
    id,
    user_id,
    scan_id,
    species_common_name,
    location_sharing,
    field_notes,
    shared_at
)
VALUES (
    '00000000-0000-4000-8000-00000000e831',
    '00000000-0000-4000-8000-00000000e801',
    '00000000-0000-4000-8000-00000000e821',
    'Public web species',
    'private',
    'Public field note',
    pg_catalog.NOW()
);

INSERT INTO public.explore_post_media (
    id,
    post_id,
    kind,
    url,
    thumbnail_url,
    order_index
)
VALUES (
    '00000000-0000-4000-8000-00000000e841',
    '00000000-0000-4000-8000-00000000e831',
    'image',
    'https://media.example.invalid/public-web.webp',
    'https://media.example.invalid/public-web.webp',
    0
);


-- Add a second same-timestamp post to exercise the UUID tie breaker.
INSERT INTO public.scans (id,user_id,species_id,image_storage_urls,ai_confidence_score,geoprivacy)
SELECT '00000000-0000-4000-8000-00000000e822',user_id,species_id,image_storage_urls,ai_confidence_score,geoprivacy
FROM public.scans WHERE id='00000000-0000-4000-8000-00000000e821';
INSERT INTO public.explore_posts (id,user_id,scan_id,species_common_name,location_sharing,field_notes,shared_at)
SELECT '00000000-0000-4000-8000-00000000e832',user_id,'00000000-0000-4000-8000-00000000e822',species_common_name,location_sharing,field_notes,shared_at
FROM public.explore_posts WHERE id='00000000-0000-4000-8000-00000000e831';
INSERT INTO public.explore_post_media (id,post_id,kind,url,thumbnail_url,order_index)
SELECT '00000000-0000-4000-8000-00000000e842','00000000-0000-4000-8000-00000000e832',kind,url,thumbnail_url,order_index
FROM public.explore_post_media WHERE id='00000000-0000-4000-8000-00000000e841';

SET LOCAL ROLE anon;
DO $$ BEGIN
  BEGIN
    PERFORM public.get_public_web_explore_posts_page(48,NULL,NULL);
    RAISE EXCEPTION 'anon executed paginated projection';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET LOCAL ROLE authenticated;
DO $$ BEGIN
  BEGIN
    PERFORM public.get_public_web_explore_posts_page(48,NULL,NULL);
    RAISE EXCEPTION 'authenticated executed paginated projection';
  EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SET LOCAL ROLE service_role;
DO $$
DECLARE first_post RECORD; second_post RECORD; n INTEGER;
BEGIN
  SELECT * INTO first_post FROM public.get_public_web_explore_posts_page(1,NULL,NULL) LIMIT 1;
  IF first_post.post_id <> '00000000-0000-4000-8000-00000000e832'::uuid THEN
    RAISE EXCEPTION 'incorrect newest UUID ordering';
  END IF;
  SELECT count(*) INTO n FROM public.get_public_web_explore_posts_page(1,NULL,NULL);
  IF n <> 2 THEN RAISE EXCEPTION 'missing bounded lookahead'; END IF;
  SELECT * INTO STRICT second_post FROM public.get_public_web_explore_posts_page(1,first_post.shared_at,first_post.post_id);
  IF second_post.post_id <> '00000000-0000-4000-8000-00000000e831'::uuid OR second_post.public_location_label IS NOT NULL
     OR second_post.viewer_has_liked OR second_post.is_owned_by_viewer OR second_post.like_count <> 0 THEN
    RAISE EXCEPTION 'cursor duplicated, skipped or exposed private state';
  END IF;
  SELECT count(*) INTO n FROM public.get_public_web_explore_posts_page(1,second_post.shared_at,second_post.post_id);
  IF n <> 0 THEN RAISE EXCEPTION 'cursor did not reach end'; END IF;
  BEGIN
    PERFORM public.get_public_web_explore_posts_page(49,NULL,NULL);
    RAISE EXCEPTION 'unbounded limit accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
  BEGIN
    PERFORM public.get_public_web_explore_posts_page(1,first_post.shared_at,NULL);
    RAISE EXCEPTION 'partial cursor accepted';
  EXCEPTION WHEN invalid_parameter_value THEN NULL; END;
END $$;
RESET ROLE;
UPDATE public.explore_posts SET moderated_at=now() WHERE id='00000000-0000-4000-8000-00000000e832';
UPDATE public.explore_posts SET unshared_at=now() WHERE id='00000000-0000-4000-8000-00000000e831';
SET LOCAL ROLE service_role;
DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM public.get_public_web_explore_posts_page(48,NULL,NULL)) THEN
    RAISE EXCEPTION 'pagination exposed withdrawn or moderated content';
  END IF;
END $$;
RESET ROLE;
SELECT extensions.pass('public pagination enforces role, bound, tie ordering, end and canonical withdrawal filters');
SELECT * FROM extensions.finish();
ROLLBACK;
