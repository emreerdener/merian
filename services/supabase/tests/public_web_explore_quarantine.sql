\set ON_ERROR_STOP on

BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.no_plan();

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
    '00000000-0000-4000-8000-00000000e901',
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
    '00000000-0000-4000-8000-00000000e901',
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
    '00000000-0000-4000-8000-00000000e911',
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
    '00000000-0000-4000-8000-00000000e921',
    '00000000-0000-4000-8000-00000000e901',
    '00000000-0000-4000-8000-00000000e911',
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
    '00000000-0000-4000-8000-00000000e931',
    '00000000-0000-4000-8000-00000000e901',
    '00000000-0000-4000-8000-00000000e921',
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
    '00000000-0000-4000-8000-00000000e941',
    '00000000-0000-4000-8000-00000000e931',
    'image',
    'https://media.example.invalid/public-web.webp',
    'https://media.example.invalid/public-web.webp',
    0
);



SELECT extensions.ok(NOT pg_catalog.has_function_privilege('anon','public.get_public_web_explore_visibility(uuid[])','EXECUTE'), 'anon cannot enumerate eligibility');
SELECT extensions.ok(NOT pg_catalog.has_function_privilege('authenticated','public.get_public_web_explore_visibility(uuid[])','EXECUTE'), 'authenticated cannot enumerate eligibility');
SET LOCAL ROLE service_role;
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.get_public_web_explore_visibility(ARRAY['00000000-0000-4000-8000-00000000e931']::UUID[])), 1, 'eligible initial post');
SELECT extensions.throws_ok($$ SELECT * FROM public.get_public_web_explore_visibility(ARRAY[]::UUID[]) $$, '22023', 'invalid_public_web_visibility_ids', 'empty batch denied');
SELECT extensions.throws_ok($$ SELECT * FROM public.get_public_web_explore_visibility(array_fill('00000000-0000-4000-8000-00000000e931'::UUID, ARRAY[129])) $$, '22023', 'invalid_public_web_visibility_ids', 'oversized batch denied');
SELECT extensions.throws_ok($$ SELECT * FROM public.get_public_web_explore_visibility(ARRAY[NULL]::UUID[]) $$, '22023', 'invalid_public_web_visibility_ids', 'null ID denied');
RESET ROLE;
INSERT INTO public.explore_post_reports(post_id,reporter_user_id,post_author_user_id,reason)
VALUES ('00000000-0000-4000-8000-00000000e931','00000000-0000-4000-8000-00000000e901','00000000-0000-4000-8000-00000000e901','Other');
SET LOCAL ROLE service_role;
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.explore_projected_post_cards(NULL) WHERE post_id='00000000-0000-4000-8000-00000000e931'), 1, 'native anonymous projection remains unchanged');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.get_public_web_explore_posts('00000000-0000-4000-8000-00000000e931',1)), 0, 'report hides legacy web card');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.get_public_web_explore_posts_page(48,NULL,NULL) WHERE post_id='00000000-0000-4000-8000-00000000e931'), 0, 'report hides paginated card');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.get_public_web_explore_post_detail('00000000-0000-4000-8000-00000000e931')), 0, 'report hides standalone detail');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.get_public_web_explore_post_page('00000000-0000-4000-8000-00000000e931')), 0, 'report hides atomic detail page');
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.get_public_web_explore_visibility(ARRAY['00000000-0000-4000-8000-00000000e931']::UUID[])), 0, 'open-page check revokes post');
RESET ROLE;
UPDATE internal.review_cases SET status='dismissed' WHERE case_type='post' AND subject_id='00000000-0000-4000-8000-00000000e931';
SET LOCAL ROLE service_role;
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.get_public_web_explore_posts('00000000-0000-4000-8000-00000000e931',1)), 1, 'dismissal restores despite original PENDING_REVIEW source');
RESET ROLE;
UPDATE public.explore_post_reports SET updated_at=now(),details='Synthetic repeated evidence'
WHERE post_id='00000000-0000-4000-8000-00000000e931';
SELECT extensions.is((SELECT status FROM internal.review_cases WHERE case_type='post' AND subject_id='00000000-0000-4000-8000-00000000e931'), 'dismissed', 'same reporter evidence does not reopen a cleared case');
UPDATE public.explore_posts SET moderated_at=now() WHERE id='00000000-0000-4000-8000-00000000e931';
SET LOCAL ROLE service_role;
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.get_public_web_explore_visibility(ARRAY['00000000-0000-4000-8000-00000000e931']::UUID[])), 0, 'dismissal does not undo manual hiding');
RESET ROLE;
UPDATE public.explore_posts SET moderated_at=NULL WHERE id='00000000-0000-4000-8000-00000000e931';
INSERT INTO public.flagged_reviews(id,scan_id,user_id,flag_reason,user_suggestion)
VALUES ('00000000-0000-4000-8000-00000000e951','00000000-0000-4000-8000-00000000e921','00000000-0000-4000-8000-00000000e901','Other','Synthetic review');
SET LOCAL ROLE service_role;
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.get_public_web_explore_visibility(ARRAY['00000000-0000-4000-8000-00000000e931']::UUID[])), 0, 'identification flag hides public website');
RESET ROLE;
UPDATE internal.review_cases SET status='resolved' WHERE case_type='identification' AND subject_id='00000000-0000-4000-8000-00000000e921';
UPDATE public.scans SET is_flagged=FALSE WHERE id='00000000-0000-4000-8000-00000000e921';
SET LOCAL ROLE service_role;
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.get_public_web_explore_visibility(ARRAY['00000000-0000-4000-8000-00000000e931']::UUID[])), 1, 'cleared flag restores eligible post');
RESET ROLE;
INSERT INTO auth.users(instance_id,id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,is_anonymous)
VALUES ('00000000-0000-0000-0000-000000000000','00000000-0000-4000-8000-00000000e902','authenticated','authenticated','web-review-second@naturebook.invalid',now(),'{"provider":"email","providers":["email"]}','{}',now(),now(),FALSE);
INSERT INTO public.users(id,email,subscription_tier,public_username,public_author_name,public_identity_source)
VALUES ('00000000-0000-4000-8000-00000000e902','web-review-second@naturebook.invalid','free','web_review_second','Second Reviewer','alias')
ON CONFLICT(id) DO UPDATE SET public_username=EXCLUDED.public_username;
INSERT INTO public.explore_post_reports(post_id,reporter_user_id,post_author_user_id,reason)
VALUES ('00000000-0000-4000-8000-00000000e931','00000000-0000-4000-8000-00000000e902','00000000-0000-4000-8000-00000000e901','Other');
SELECT extensions.is((SELECT status FROM internal.review_cases WHERE case_type='post' AND subject_id='00000000-0000-4000-8000-00000000e931'), 'open', 'new independent report reopens dismissed case');
SET LOCAL ROLE service_role;
SELECT extensions.is((SELECT count(*)::INTEGER FROM public.get_public_web_explore_visibility(ARRAY['00000000-0000-4000-8000-00000000e931']::UUID[])), 0, 'reopened case hides again');
RESET ROLE;
SELECT * FROM extensions.finish();
ROLLBACK;
