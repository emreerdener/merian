\set ON_ERROR_STOP on

BEGIN;
SELECT extensions.plan(1);

INSERT INTO auth.users (
  instance_id, id, aud, role, email, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, is_anonymous
)
SELECT '00000000-0000-0000-0000-000000000000', seed.user_id, 'authenticated', 'authenticated',
       seed.email, NOW(), jsonb_build_object('provider', 'google', 'providers', jsonb_build_array('google')),
       '{}'::JSONB, NOW(), NOW(), FALSE
FROM (VALUES
  ('00000000-0000-0000-0000-000000000301'::UUID, 'review-owner-test@naturebook.invalid'),
  ('00000000-0000-0000-0000-000000000302'::UUID, 'review-reporter-one@naturebook.invalid'),
  ('00000000-0000-0000-0000-000000000303'::UUID, 'review-reporter-two@naturebook.invalid'),
  ('00000000-0000-0000-0000-000000000304'::UUID, 'review-subject-test@naturebook.invalid')
) AS seed(user_id, email);

INSERT INTO auth.identities (provider_id, user_id, identity_data, provider, created_at, updated_at)
VALUES (
  '00000000-0000-0000-0000-000000000301',
  '00000000-0000-0000-0000-000000000301',
  '{"sub":"00000000-0000-0000-0000-000000000301","email":"review-owner-test@naturebook.invalid"}',
  'google', NOW(), NOW()
);
INSERT INTO auth.sessions (id, user_id, created_at, updated_at, refreshed_at, aal, not_after)
VALUES (
  '00000000-0000-0000-0000-000000000311',
  '00000000-0000-0000-0000-000000000301',
  NOW(), NOW(), NOW(), 'aal2', NOW() + INTERVAL '1 day'
);
INSERT INTO internal.admin_memberships (user_id, role, is_active, created_by)
VALUES (
  '00000000-0000-0000-0000-000000000301', 'owner', TRUE,
  '00000000-0000-0000-0000-000000000301'
);

INSERT INTO public.species_dictionary (
  id, scientific_name, common_names, native_region
)
VALUES (
  '00000000-0000-0000-0000-000000000320',
  'Contractus projectionis', '{"en":"Projection contract species"}', 'Test region'
);

INSERT INTO public.scans (id, user_id, species_id, ai_confidence_score)
VALUES (
  '00000000-0000-0000-0000-000000000321',
  '00000000-0000-0000-0000-000000000304',
  '00000000-0000-0000-0000-000000000320',
  0.91
);
INSERT INTO public.flagged_reviews (id, scan_id, user_id, flag_reason, user_suggestion)
VALUES (
  '00000000-0000-0000-0000-000000000331',
  '00000000-0000-0000-0000-000000000321',
  '00000000-0000-0000-0000-000000000302',
  'Incorrect identification', 'First evidence'
);

DO $$
DECLARE review internal.review_cases%ROWTYPE;
BEGIN
  SELECT * INTO review FROM internal.review_cases
  WHERE case_type = 'identification' AND subject_id = '00000000-0000-0000-0000-000000000321';
  IF review.status <> 'open' OR review.report_count <> 1
    OR NOT (SELECT is_flagged FROM public.scans WHERE id = review.subject_id) THEN
    RAISE EXCEPTION 'first identification report was not grouped and flagged';
  END IF;
END;
$$;
SELECT set_config(
  'test.identification_case_id',
  (SELECT id::TEXT FROM internal.review_cases WHERE case_type = 'identification' AND subject_id = '00000000-0000-0000-0000-000000000321'),
  TRUE
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', jsonb_build_object(
  'sub', '00000000-0000-0000-0000-000000000301', 'role', 'authenticated',
  'aal', 'aal2', 'session_id', '00000000-0000-0000-0000-000000000311'
)::TEXT, TRUE);
SELECT public.admin_begin_session();
SELECT public.admin_update_review_case(
  current_setting('test.identification_case_id')::UUID,
  p_status => 'resolved', p_resolution_code => 'identification_confirmed', p_note => 'Resolved in contract test'
);
RESET ROLE;

INSERT INTO public.flagged_reviews (id, scan_id, user_id, flag_reason, user_suggestion)
VALUES (
  '00000000-0000-0000-0000-000000000332',
  '00000000-0000-0000-0000-000000000321',
  '00000000-0000-0000-0000-000000000302',
  'Incorrect identification', 'Updated evidence from the same reporter'
);
DO $$
DECLARE review internal.review_cases%ROWTYPE;
BEGIN
  SELECT * INTO review FROM internal.review_cases WHERE case_type = 'identification' AND subject_id = '00000000-0000-0000-0000-000000000321';
  IF review.status <> 'resolved' OR review.report_count <> 1
    OR (SELECT is_flagged FROM public.scans WHERE id = review.subject_id) THEN
    RAISE EXCEPTION 'repeat reporter reopened a terminal case';
  END IF;
END;
$$;

INSERT INTO public.flagged_reviews (id, scan_id, user_id, flag_reason, user_suggestion)
VALUES (
  '00000000-0000-0000-0000-000000000333',
  '00000000-0000-0000-0000-000000000321',
  '00000000-0000-0000-0000-000000000303',
  'Incorrect identification', 'Independent evidence'
);
DO $$
DECLARE review internal.review_cases%ROWTYPE;
BEGIN
  SELECT * INTO review FROM internal.review_cases WHERE case_type = 'identification' AND subject_id = '00000000-0000-0000-0000-000000000321';
  IF review.status <> 'open' OR review.report_count <> 2
    OR NOT (SELECT is_flagged FROM public.scans WHERE id = review.subject_id) THEN
    RAISE EXCEPTION 'independent reporter did not reopen the case';
  END IF;
END;
$$;

INSERT INTO public.explore_posts (id, user_id, scan_id, location_sharing, shared_at)
VALUES (
  '00000000-0000-0000-0000-000000000341',
  '00000000-0000-0000-0000-000000000304',
  '00000000-0000-0000-0000-000000000321',
  'obscured', NOW()
);
INSERT INTO public.explore_post_media (id, post_id, kind, url, order_index)
VALUES (
  '00000000-0000-0000-0000-000000000340',
  '00000000-0000-0000-0000-000000000341',
  'image', 'https://naturebook.invalid/admin-contract.jpg', 0
);
INSERT INTO public.explore_post_reports (
  id, post_id, reporter_user_id, post_author_user_id, reason, details
)
VALUES (
  '00000000-0000-0000-0000-000000000342',
  '00000000-0000-0000-0000-000000000341',
  '00000000-0000-0000-0000-000000000302',
  '00000000-0000-0000-0000-000000000304',
  'Spam', 'Public projection contract'
);
SELECT set_config(
  'test.post_case_id',
  (SELECT id::TEXT FROM internal.review_cases WHERE case_type = 'post' AND subject_id = '00000000-0000-0000-0000-000000000341'),
  TRUE
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', jsonb_build_object(
  'sub', '00000000-0000-0000-0000-000000000304', 'role', 'authenticated'
)::TEXT, TRUE);
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.get_explore_post('00000000-0000-0000-0000-000000000304', '00000000-0000-0000-0000-000000000341')) THEN
    RAISE EXCEPTION 'visible post fixture did not enter the public projection';
  END IF;
END;
$$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', jsonb_build_object(
  'sub', '00000000-0000-0000-0000-000000000301', 'role', 'authenticated',
  'aal', 'aal2', 'session_id', '00000000-0000-0000-0000-000000000311'
)::TEXT, TRUE);
SELECT public.admin_set_content_visibility(
  current_setting('test.post_case_id')::UUID,
  TRUE, 'Hide for contract verification'
);
RESET ROLE;
DO $$
BEGIN
  IF (SELECT moderated_at IS NULL FROM public.explore_posts WHERE id = '00000000-0000-0000-0000-000000000341') THEN
    RAISE EXCEPTION 'post moderation state was not persisted';
  END IF;
END;
$$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', jsonb_build_object(
  'sub', '00000000-0000-0000-0000-000000000304', 'role', 'authenticated'
)::TEXT, TRUE);
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.get_explore_post('00000000-0000-0000-0000-000000000304', '00000000-0000-0000-0000-000000000341')) THEN
    RAISE EXCEPTION 'hidden post remained in a public projection';
  END IF;
END;
$$;
RESET ROLE;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', jsonb_build_object(
  'sub', '00000000-0000-0000-0000-000000000301', 'role', 'authenticated',
  'aal', 'aal2', 'session_id', '00000000-0000-0000-0000-000000000311'
)::TEXT, TRUE);
SELECT public.admin_set_content_visibility(
  current_setting('test.post_case_id')::UUID,
  FALSE, 'Restore after contract verification'
);
RESET ROLE;
DO $$
BEGIN
  IF (SELECT moderated_at IS NOT NULL FROM public.explore_posts WHERE id = '00000000-0000-0000-0000-000000000341') THEN
    RAISE EXCEPTION 'post moderation state was not restored';
  END IF;
END;
$$;

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', jsonb_build_object(
  'sub', '00000000-0000-0000-0000-000000000304', 'role', 'authenticated'
)::TEXT, TRUE);
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.get_explore_post('00000000-0000-0000-0000-000000000304', '00000000-0000-0000-0000-000000000341')) THEN
    RAISE EXCEPTION 'restored post did not return to the public projection';
  END IF;
END;
$$;
RESET ROLE;

SELECT public.record_ai_usage_event(
  'contract_usage', 'gemini-2.5-flash', p_effective_plan => 'pro_paid',
  p_input_modality => 'text', p_prompt_tokens => 100, p_cached_tokens => 20,
  p_candidate_tokens => 30, p_thinking_tokens => 10, p_tool_tokens => 5,
  p_total_tokens => 145,
  p_prompt_tokens_by_modality => '{"prompt":{"text":100},"cached":{"text":20}}',
  p_user_id => '00000000-0000-0000-0000-000000000304',
  p_source_type => 'contract', p_source_id => '00000000-0000-0000-0000-000000000351'
);
SELECT public.record_ai_usage_event(
  'contract_usage', 'gemini-2.5-flash', p_source_type => 'contract',
  p_source_id => '00000000-0000-0000-0000-000000000351'
);
DO $$
DECLARE event public.ai_usage_events%ROWTYPE;
BEGIN
  SELECT * INTO event FROM public.ai_usage_events
  WHERE source_type = 'contract' AND source_id = '00000000-0000-0000-0000-000000000351';
  IF (SELECT COUNT(*) FROM public.ai_usage_events WHERE source_type = 'contract' AND source_id = event.source_id) <> 1
    OR event.estimated_cost_microusd IS NULL OR event.pricing_version IS NULL
    OR event.prompt_tokens_by_modality #>> '{prompt,text}' <> '100' THEN
    RAISE EXCEPTION 'AI usage idempotency, pricing, or modality metadata failed';
  END IF;
  BEGIN
    UPDATE public.ai_usage_events SET total_tokens = 999 WHERE id = event.id;
    RAISE EXCEPTION 'expected append-only ledger denial';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
END;
$$;

DELETE FROM public.users WHERE id = '00000000-0000-0000-0000-000000000304';
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.ai_usage_events
    WHERE source_type = 'contract' AND source_id = '00000000-0000-0000-0000-000000000351'
      AND user_id IS NOT NULL
  ) THEN
    RAISE EXCEPTION 'account deletion did not anonymize AI usage linkage';
  END IF;
  BEGIN
    UPDATE internal.admin_notes SET body = 'mutated';
    RAISE EXCEPTION 'expected append-only note denial';
  EXCEPTION WHEN SQLSTATE '42501' THEN NULL;
  END;
END;
$$;

SELECT extensions.pass('review grouping, reopening, moderation projection, and AI ledger contracts hold');
SELECT * FROM extensions.finish();
ROLLBACK;
