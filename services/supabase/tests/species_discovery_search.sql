\set ON_ERROR_STOP on
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT extensions.plan(24);
SELECT extensions.ok(NOT pg_catalog.has_function_privilege('anon','public.search_species_discovery(uuid,text,text,text,text,jsonb,boolean)','EXECUTE') AND NOT pg_catalog.has_function_privilege('authenticated','public.search_species_discovery(uuid,text,text,text,text,jsonb,boolean)','EXECUTE'),'Direct client RPC denied');
SET LOCAL ROLE anon;
SELECT extensions.throws_ok($$ SELECT public.search_species_discovery('00000000-0000-4000-8000-00000000ee01','red') $$,'42501','permission denied for function search_species_discovery','Anon execution denied');
RESET ROLE;
SET LOCAL ROLE authenticated;
SELECT extensions.throws_ok($$ SELECT public.search_species_discovery('00000000-0000-4000-8000-00000000ee01','red') $$,'42501','permission denied for function search_species_discovery','Authenticated execution denied');
RESET ROLE;
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
    '00000000-0000-4000-8000-00000000ee01',
    'authenticated',
    'authenticated',
    'discovery-search-explore@naturebook.invalid',
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
    '00000000-0000-4000-8000-00000000ee01',
    'discovery-search-explore@naturebook.invalid',
    'pro',
    'discovery_search_ee01',
    'Liked Feed Fixture',
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
    '00000000-0000-4000-8000-00000000ee11',
    'Discoveryus ruber',
    '{"en":"Discovery red bird"}'::JSONB,
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
    '00000000-0000-4000-8000-00000000ee21',
    '00000000-0000-4000-8000-00000000ee01',
    '00000000-0000-4000-8000-00000000ee11',
    ARRAY['https://media.example.invalid/discovery-search.webp'],
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
    '00000000-0000-4000-8000-00000000ee31',
    '00000000-0000-4000-8000-00000000ee01',
    '00000000-0000-4000-8000-00000000ee21',
    'Discovery red bird',
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
    '00000000-0000-4000-8000-00000000ee41',
    '00000000-0000-4000-8000-00000000ee31',
    'image',
    'https://media.example.invalid/discovery-search.webp',
    'https://media.example.invalid/discovery-search.webp',
    0
);

INSERT INTO public.species_reference_images (species_id, url, source, license, attribution)
VALUES (
    '00000000-0000-4000-8000-00000000ee11',
    'https://media.example.invalid/liked-reference.webp',
    'gbif', 'CC0', 'Catalog fixture'
);


UPDATE public.species_dictionary SET wikipedia_overview = 'zzdiscoveryfixture A small bird with a red head.', habitat_description = 'Found in forests.' WHERE id = '00000000-0000-4000-8000-00000000ee11';
INSERT INTO public.species_dictionary(id,scientific_name,common_names,kingdom,phylum,class,wikipedia_overview)
SELECT ('00000000-0000-4000-8000-' || pg_catalog.lpad(n::TEXT,12,'0'))::UUID,
       'Discoveryus paging' || n::TEXT, '{}'::JSONB,'Animalia','Arthropoda','Insecta','zzdiscoveryfixture Orange black butterflies'
FROM pg_catalog.generate_series(101,123) n;
INSERT INTO public.species_dictionary(id,scientific_name,common_names,wikipedia_overview)
VALUES ('00000000-0000-4000-8000-00000000ee99','Undefined fixture','{}','zzdiscoveryfixture Orange black butterflies');
SET LOCAL ROLE service_role;
SELECT extensions.is(pg_catalog.jsonb_array_length(public.search_species_discovery('00000000-0000-4000-8000-00000000ee01','Discovery red bird',NULL,NULL,'species',NULL,TRUE)->'species'),1,'Exact common name resolves');
SELECT extensions.is(pg_catalog.jsonb_array_length(public.search_species_discovery('00000000-0000-4000-8000-00000000ee01','Discovery red',NULL,NULL,'species',NULL,TRUE)->'species'),1,'Partial common name resolves without AI');
SELECT extensions.is(pg_catalog.jsonb_array_length(public.search_species_discovery('00000000-0000-4000-8000-00000000ee01','red head','birds')->'species'),1,'Traits AND group retrieve eligible canonical entry');
SELECT extensions.is(pg_catalog.jsonb_array_length(public.search_species_discovery('00000000-0000-4000-8000-00000000ee01','red head','fungi')->'species'),0,'Group filter narrows traits');
SELECT extensions.is(pg_catalog.jsonb_array_length(public.search_species_discovery('00000000-0000-4000-8000-00000000ee01','zzdiscoveryfixture')->'species'),20,'First species page is bounded');
SELECT extensions.is(pg_catalog.jsonb_array_length(public.search_species_discovery('00000000-0000-4000-8000-00000000ee01','zzdiscoveryfixture',NULL,NULL,'species',public.search_species_discovery('00000000-0000-4000-8000-00000000ee01','zzdiscoveryfixture')->'next_cursor')->'species'),4,'Cursor continues after rank/id boundary and excludes ineligible entry');
SELECT extensions.is(pg_catalog.jsonb_array_length(public.search_species_discovery('00000000-0000-4000-8000-00000000ee01','zzdiscoveryfixture',NULL,NULL,'sightings')->'sightings'),1,'Sighting retrieval joins all matching species before pagination');
SELECT extensions.is(pg_catalog.jsonb_array_length(public.search_species_discovery('00000000-0000-4000-8000-00000000ee01','zzdiscoveryfixture',NULL,'audio','sightings')->'sightings'),0,'Media filter applies only to sightings');
SELECT extensions.ok(NOT ((public.search_species_discovery('00000000-0000-4000-8000-00000000ee01','zzdiscoveryfixture',NULL,NULL,'sightings')->'sightings'->0) ?| ARRAY['latitude','longitude','public_latitude','public_longitude','coordinate_visibility','field_notes','gps_latitude','gps_longitude']),'Public search never exposes private source fields');
RESET ROLE;
UPDATE public.explore_posts SET unshared_at = pg_catalog.now() WHERE id = '00000000-0000-4000-8000-00000000ee31';
SET LOCAL ROLE service_role;
SELECT extensions.is(pg_catalog.jsonb_array_length(public.search_species_discovery('00000000-0000-4000-8000-00000000ee01','zzdiscoveryfixture',NULL,NULL,'sightings')->'sightings'),0,'Unshared posts excluded');
RESET ROLE;
UPDATE public.explore_posts SET unshared_at = NULL,media_health_status='quarantined' WHERE id = '00000000-0000-4000-8000-00000000ee31';
SET LOCAL ROLE service_role;
SELECT extensions.is(pg_catalog.jsonb_array_length(public.search_species_discovery('00000000-0000-4000-8000-00000000ee01','zzdiscoveryfixture',NULL,NULL,'sightings')->'sightings'),0,'Quarantined posts excluded');
RESET ROLE;
UPDATE public.explore_posts SET media_health_status='healthy' WHERE id = '00000000-0000-4000-8000-00000000ee31';
UPDATE public.scans SET is_tombstoned=TRUE WHERE id = '00000000-0000-4000-8000-00000000ee21';
SET LOCAL ROLE service_role;
SELECT extensions.is(pg_catalog.jsonb_array_length(public.search_species_discovery('00000000-0000-4000-8000-00000000ee01','zzdiscoveryfixture',NULL,NULL,'sightings')->'sightings'),0,'Deleted observations excluded');
RESET ROLE;
SELECT extensions.is((SELECT daily_limit FROM internal.ai_quota_policies WHERE operation='species_discovery_search' AND effective_plan='free'),20,'Free search has separate bounded allowance');
SELECT extensions.is((SELECT pg_catalog.count(*) FROM internal.ai_quota_policies WHERE operation='species_discovery_search' AND allowed AND daily_bucket LIKE 'species_search:%'),4::BIGINT,'Every plan uses independent search accounting');

-- A second viewer proves block filtering is evaluated for the caller.
INSERT INTO auth.users(id,aud,role,email,raw_app_meta_data,raw_user_meta_data,is_anonymous)
VALUES ('00000000-0000-4000-8000-00000000ee02','authenticated','authenticated','discovery-viewer@naturebook.invalid','{}','{}',FALSE);
INSERT INTO public.users(id,email,public_author_name,public_identity_source,public_username) VALUES ('00000000-0000-4000-8000-00000000ee02','discovery-viewer@naturebook.invalid','Discovery viewer fixture','alias','discovery_viewer_ee02') ON CONFLICT(id) DO NOTHING;
UPDATE public.scans SET is_tombstoned=FALSE WHERE id='00000000-0000-4000-8000-00000000ee21';
SET LOCAL ROLE service_role;
SELECT extensions.is(pg_catalog.jsonb_array_length(public.search_species_discovery('00000000-0000-4000-8000-00000000ee02','zzdiscoveryfixture',NULL,NULL,'sightings')->'sightings'),1,'Other viewers can see the public sighting');
RESET ROLE;
INSERT INTO public.user_blocks(blocker_id,blocked_id) VALUES ('00000000-0000-4000-8000-00000000ee02','00000000-0000-4000-8000-00000000ee01');
SET LOCAL ROLE service_role;
SELECT extensions.is(pg_catalog.jsonb_array_length(public.search_species_discovery('00000000-0000-4000-8000-00000000ee02','zzdiscoveryfixture',NULL,NULL,'sightings')->'sightings'),0,'Blocked authors are excluded for the current viewer');
RESET ROLE;
INSERT INTO public.explore_post_media(id,post_id,kind,url,thumbnail_url,order_index)
VALUES ('00000000-0000-4000-8000-00000000ee42','00000000-0000-4000-8000-00000000ee31','video','https://media.example.invalid/search.mp4','https://media.example.invalid/search.webp',1);
UPDATE public.explore_post_media SET health_status='missing',missing_confirmed_at=pg_catalog.now(),consecutive_missing_checks=2
WHERE id='00000000-0000-4000-8000-00000000ee41';
SET LOCAL ROLE service_role;
SELECT extensions.is(pg_catalog.jsonb_array_length(public.search_species_discovery('00000000-0000-4000-8000-00000000ee01','zzdiscoveryfixture',NULL,'image','sightings')->'sightings'),0,'Missing images cannot qualify a Photos result');
SELECT extensions.is(pg_catalog.jsonb_array_length(public.search_species_discovery('00000000-0000-4000-8000-00000000ee01','zzdiscoveryfixture',NULL,'video','sightings')->'sightings'),1,'Healthy video remains discoverable on a degraded post');
RESET ROLE;
INSERT INTO public.scans(id,user_id,species_id,image_storage_urls,ai_confidence_score,geoprivacy)
SELECT ('00000000-0000-4000-8100-' || pg_catalog.lpad(n::TEXT,12,'0'))::UUID,
'00000000-0000-4000-8000-00000000ee01','00000000-0000-4000-8000-00000000ee11',
ARRAY['https://media.example.invalid/search.webp'],0.9,'private' FROM pg_catalog.generate_series(201,223) n;
INSERT INTO public.explore_posts(id,user_id,scan_id,species_common_name,location_sharing,shared_at)
SELECT ('00000000-0000-4000-8200-' || pg_catalog.lpad(n::TEXT,12,'0'))::UUID,
'00000000-0000-4000-8000-00000000ee01',('00000000-0000-4000-8100-' || pg_catalog.lpad(n::TEXT,12,'0'))::UUID,
'Discovery red bird','private',pg_catalog.now()-n*INTERVAL '1 second' FROM pg_catalog.generate_series(201,223) n;
INSERT INTO public.explore_post_media(id,post_id,kind,url,thumbnail_url,order_index)
SELECT ('00000000-0000-4000-8300-' || pg_catalog.lpad(n::TEXT,12,'0'))::UUID,
('00000000-0000-4000-8200-' || pg_catalog.lpad(n::TEXT,12,'0'))::UUID,'image',
'https://media.example.invalid/search.webp','https://media.example.invalid/search.webp',0 FROM pg_catalog.generate_series(201,223) n;
SET LOCAL ROLE service_role;
SELECT extensions.is(pg_catalog.jsonb_array_length(public.search_species_discovery('00000000-0000-4000-8000-00000000ee01','zzdiscoveryfixture',NULL,NULL,'sightings')->'sightings'),20,'Sightings page is bounded');
SELECT extensions.is(pg_catalog.jsonb_array_length(public.search_species_discovery('00000000-0000-4000-8000-00000000ee01','zzdiscoveryfixture',NULL,NULL,'sightings',public.search_species_discovery('00000000-0000-4000-8000-00000000ee01','zzdiscoveryfixture',NULL,NULL,'sightings')->'next_cursor')->'sightings'),4,'Sightings cursor preserves share-time and identity boundary');
RESET ROLE;

-- Excerpts select supporting source text even when the trait occurs deep in habitat.
UPDATE public.species_dictionary SET wikipedia_overview = pg_catalog.repeat('General dictionary background. ',30),
    habitat_description = 'This bird lives in zzdiscoveryhabitat marshes with dense reed beds.'
WHERE id = '00000000-0000-4000-8000-00000000ee11';
SET LOCAL ROLE service_role;
SELECT extensions.ok((public.search_species_discovery('00000000-0000-4000-8000-00000000ee01','zzdiscoveryhabitat')->'species'->0->>'excerpt') LIKE '%zzdiscoveryhabitat%',
    'Descriptive excerpts contain supporting habitat text beyond the opening overview');
RESET ROLE;

SELECT * FROM extensions.finish();
ROLLBACK;
