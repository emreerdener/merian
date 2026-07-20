-- Naturebook internal administration foundation.
--
-- The internal schema is intentionally not exposed through the Data API. The
-- admin web app authenticates as a normal Supabase user and can reach only the
-- explicitly granted public RPC wrappers below. Every wrapper re-checks the
-- immutable Auth user id, Google identity, AAL2, role, and active Auth session.

CREATE SCHEMA IF NOT EXISTS internal;
REVOKE ALL ON SCHEMA internal FROM PUBLIC, anon, authenticated;

ALTER TABLE public.explore_posts
  ADD COLUMN IF NOT EXISTS moderated_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS moderated_by_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.scans
  ADD COLUMN IF NOT EXISTS llm_usage_metadata JSONB NOT NULL DEFAULT '{}'::JSONB;
ALTER TABLE public.insight_chat_messages
  ADD COLUMN IF NOT EXISTS llm_usage_metadata JSONB NOT NULL DEFAULT '{}'::JSONB;

CREATE INDEX IF NOT EXISTS idx_explore_posts_visible_shared
  ON public.explore_posts (shared_at DESC, id DESC)
  WHERE unshared_at IS NULL AND moderated_at IS NULL;

-- Keep all currently deployed public Explore projections on the same
-- reversible-moderation boundary. pg_get_functiondef preserves each function's
-- signature, volatility, security mode, and grants while the targeted predicate
-- replacement avoids copying a large and fast-moving projection surface here.
DO $$
DECLARE
  projection RECORD;
  function_definition TEXT;
  hardened_definition TEXT;
BEGIN
  FOR projection IN
    SELECT procedure.oid
    FROM pg_proc procedure
    JOIN pg_namespace namespace ON namespace.oid = procedure.pronamespace
    WHERE namespace.nspname = 'public'
      AND procedure.prokind = 'f'
      AND (
        procedure.proname LIKE 'get_explore_%'
        OR procedure.proname LIKE 'get_community_identification_%'
        OR procedure.proname IN (
          'explore_projected_post_cards',
          'can_view_explore_author_profile',
          'sync_like_notification_for_post',
          'submit_explore_community_identification'
        )
      )
      AND procedure.prosrc ILIKE '%explore_posts%'
      AND procedure.prosrc ILIKE '%unshared_at%'
  LOOP
    function_definition := pg_get_functiondef(projection.oid);
    hardened_definition := regexp_replace(
      function_definition,
      E'([a-zA-Z_][a-zA-Z0-9_]*)\\.unshared_at IS NULL',
      E'\\1.unshared_at IS NULL AND \\1.moderated_at IS NULL',
      'gi'
    );

    -- Community-identification intake historically loaded the post's
    -- unshared state into a variable instead of filtering it in the query, so
    -- it does not match the projection predicate above. Treat a moderated post
    -- as unavailable before accepting a new community identification.
    IF projection.oid::regprocedure::TEXT LIKE 'submit_explore_community_identification(%' THEN
      hardened_definition := regexp_replace(
        hardened_definition,
        E'WHERE ecr\\.id = target_request_id',
        E'WHERE ep.moderated_at IS NULL\n      AND ecr.id = target_request_id',
        'i'
      );
    END IF;

    IF hardened_definition IS DISTINCT FROM function_definition THEN
      EXECUTE hardened_definition;
    END IF;
  END LOOP;
END;
$$;

CREATE TABLE IF NOT EXISTS public.user_reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reported_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reason TEXT NOT NULL CHECK (
    reason IN ('Spam', 'Harassment', 'Impersonation', 'Inappropriate profile', 'Other')
  ),
  details TEXT CHECK (details IS NULL OR char_length(details) <= 1000),
  status TEXT NOT NULL DEFAULT 'PENDING_REVIEW'
    CHECK (status IN ('PENDING_REVIEW', 'DISMISSED', 'ACTIONED')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT user_reports_not_self CHECK (reporter_user_id <> reported_user_id),
  UNIQUE (reporter_user_id, reported_user_id)
);

CREATE INDEX IF NOT EXISTS idx_user_reports_status_created
  ON public.user_reports (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_reports_reported_user
  ON public.user_reports (reported_user_id, created_at DESC);

ALTER TABLE public.user_reports ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.user_reports FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.user_reports TO service_role;

CREATE TABLE IF NOT EXISTS public.ai_usage_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  user_id UUID,
  operation TEXT NOT NULL CHECK (char_length(btrim(operation)) BETWEEN 1 AND 80),
  model TEXT NOT NULL CHECK (char_length(btrim(model)) BETWEEN 1 AND 120),
  effective_plan TEXT NOT NULL DEFAULT 'unknown'
    CHECK (effective_plan IN ('free', 'pro_paid', 'pro_trial', 'unknown')),
  input_modality TEXT NOT NULL DEFAULT 'unknown'
    CHECK (input_modality IN ('text', 'image', 'audio', 'video', 'mixed', 'unknown')),
  prompt_tokens BIGINT CHECK (prompt_tokens IS NULL OR prompt_tokens >= 0),
  cached_tokens BIGINT CHECK (cached_tokens IS NULL OR cached_tokens >= 0),
  candidate_tokens BIGINT CHECK (candidate_tokens IS NULL OR candidate_tokens >= 0),
  thinking_tokens BIGINT CHECK (thinking_tokens IS NULL OR thinking_tokens >= 0),
  tool_tokens BIGINT CHECK (tool_tokens IS NULL OR tool_tokens >= 0),
  total_tokens BIGINT CHECK (total_tokens IS NULL OR total_tokens >= 0),
  prompt_tokens_by_modality JSONB NOT NULL DEFAULT '{}'::JSONB,
  outcome TEXT NOT NULL DEFAULT 'success'
    CHECK (outcome IN ('success', 'refusal', 'error')),
  scan_id UUID,
  conversation_id UUID,
  message_id UUID,
  source_type TEXT,
  source_id UUID,
  is_backfilled BOOLEAN NOT NULL DEFAULT FALSE,
  coverage_scope TEXT NOT NULL DEFAULT 'complete'
    CHECK (coverage_scope IN ('complete', 'primary_only', 'partial')),
  estimated_cost_microusd BIGINT CHECK (
    estimated_cost_microusd IS NULL OR estimated_cost_microusd >= 0
  ),
  pricing_version TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT ai_usage_source_key UNIQUE (source_type, source_id, operation)
);

CREATE INDEX IF NOT EXISTS idx_ai_usage_events_occurred
  ON public.ai_usage_events (occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_usage_events_operation_occurred
  ON public.ai_usage_events (operation, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_usage_events_scan
  ON public.ai_usage_events (scan_id) WHERE scan_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_ai_usage_events_user
  ON public.ai_usage_events (user_id, occurred_at DESC) WHERE user_id IS NOT NULL;

ALTER TABLE public.ai_usage_events ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.ai_usage_events FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.ai_usage_events TO service_role;

CREATE TABLE IF NOT EXISTS internal.admin_memberships (
  user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('owner', 'moderator', 'analyst')),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS internal.admin_sessions (
  session_id UUID PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  last_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '8 hours'),
  revoked_at TIMESTAMPTZ,
  UNIQUE (session_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_admin_sessions_user_active
  ON internal.admin_sessions (user_id, expires_at DESC)
  WHERE revoked_at IS NULL;

CREATE TABLE IF NOT EXISTS internal.admin_audit_log (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  actor_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
  actor_role TEXT NOT NULL CHECK (actor_role IN ('owner', 'moderator', 'analyst')),
  action TEXT NOT NULL CHECK (char_length(btrim(action)) BETWEEN 1 AND 100),
  target_type TEXT,
  target_id TEXT,
  request_id UUID NOT NULL DEFAULT gen_random_uuid(),
  before_state JSONB,
  after_state JSONB,
  reason TEXT CHECK (reason IS NULL OR char_length(reason) <= 1000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_created
  ON internal.admin_audit_log (created_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_admin_audit_actor
  ON internal.admin_audit_log (actor_user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS internal.review_cases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  case_type TEXT NOT NULL CHECK (case_type IN ('identification', 'post', 'comment', 'user')),
  subject_id UUID NOT NULL,
  subject_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  status TEXT NOT NULL DEFAULT 'open'
    CHECK (status IN ('open', 'in_review', 'resolved', 'dismissed')),
  priority TEXT NOT NULL DEFAULT 'normal'
    CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
  assigned_to UUID REFERENCES internal.admin_memberships(user_id) ON DELETE SET NULL,
  report_count INTEGER NOT NULL DEFAULT 0 CHECK (report_count >= 0),
  resolution_code TEXT,
  resolved_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (case_type, subject_id)
);

CREATE INDEX IF NOT EXISTS idx_review_cases_queue
  ON internal.review_cases (status, priority, updated_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_review_cases_assignee
  ON internal.review_cases (assigned_to, status, updated_at DESC)
  WHERE assigned_to IS NOT NULL;

CREATE TABLE IF NOT EXISTS internal.review_case_sources (
  case_id UUID NOT NULL REFERENCES internal.review_cases(id) ON DELETE CASCADE,
  source_type TEXT NOT NULL CHECK (
    source_type IN ('flagged_review', 'explore_post_report', 'explore_comment_report', 'user_report')
  ),
  source_id UUID NOT NULL,
  reporter_user_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (source_type, source_id)
);

CREATE INDEX IF NOT EXISTS idx_review_case_sources_case
  ON internal.review_case_sources (case_id, created_at ASC);

CREATE TABLE IF NOT EXISTS internal.feedback_state (
  source_type TEXT NOT NULL CHECK (
    source_type IN ('community', 'survey', 'chat_message', 'chat_feature')
  ),
  source_id UUID NOT NULL,
  status TEXT NOT NULL DEFAULT 'new'
    CHECK (status IN ('new', 'reviewed', 'planned', 'closed')),
  assigned_to UUID REFERENCES internal.admin_memberships(user_id) ON DELETE SET NULL,
  tags TEXT[] NOT NULL DEFAULT '{}',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (source_type, source_id)
);

CREATE TABLE IF NOT EXISTS internal.admin_notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_type TEXT NOT NULL CHECK (parent_type IN ('review_case', 'feedback')),
  parent_id TEXT NOT NULL,
  author_user_id UUID NOT NULL REFERENCES internal.admin_memberships(user_id) ON DELETE RESTRICT,
  body TEXT NOT NULL CHECK (char_length(btrim(body)) BETWEEN 1 AND 4000),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_notes_parent
  ON internal.admin_notes (parent_type, parent_id, created_at ASC);

CREATE TABLE IF NOT EXISTS internal.ai_model_pricing (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  model TEXT NOT NULL,
  input_modality TEXT NOT NULL CHECK (
    input_modality IN ('text', 'image', 'audio', 'video', 'mixed', 'unknown')
  ),
  prompt_usd_per_million NUMERIC(12,6) NOT NULL CHECK (prompt_usd_per_million >= 0),
  cached_usd_per_million NUMERIC(12,6) NOT NULL DEFAULT 0 CHECK (cached_usd_per_million >= 0),
  output_usd_per_million NUMERIC(12,6) NOT NULL CHECK (output_usd_per_million >= 0),
  effective_from TIMESTAMPTZ NOT NULL,
  effective_to TIMESTAMPTZ,
  version TEXT NOT NULL,
  CHECK (effective_to IS NULL OR effective_to > effective_from),
  UNIQUE (model, input_modality, effective_from)
);

CREATE TABLE IF NOT EXISTS internal.admin_aggregate_cache (
  cache_key TEXT PRIMARY KEY,
  payload JSONB NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO internal.ai_model_pricing (
  model, input_modality, prompt_usd_per_million,
  cached_usd_per_million, output_usd_per_million,
  effective_from, version
)
VALUES
  ('gemini-2.5-flash', 'text', 0.30, 0.03, 2.50, '2025-06-17T00:00:00Z', 'google-2026-07-09'),
  ('gemini-2.5-flash', 'image', 0.30, 0.03, 2.50, '2025-06-17T00:00:00Z', 'google-2026-07-09'),
  ('gemini-2.5-flash', 'video', 0.30, 0.03, 2.50, '2025-06-17T00:00:00Z', 'google-2026-07-09'),
  ('gemini-2.5-flash', 'audio', 1.00, 0.10, 2.50, '2025-06-17T00:00:00Z', 'google-2026-07-09'),
  ('gemini-2.5-flash', 'mixed', 0.30, 0.03, 2.50, '2025-06-17T00:00:00Z', 'google-2026-07-09'),
  ('gemini-2.5-pro', 'text', 1.25, 0.125, 10.00, '2025-06-17T00:00:00Z', 'google-2026-07-09'),
  ('gemini-2.5-pro', 'image', 1.25, 0.125, 10.00, '2025-06-17T00:00:00Z', 'google-2026-07-09'),
  ('gemini-2.5-pro', 'video', 1.25, 0.125, 10.00, '2025-06-17T00:00:00Z', 'google-2026-07-09'),
  ('gemini-2.5-pro', 'audio', 1.25, 0.125, 10.00, '2025-06-17T00:00:00Z', 'google-2026-07-09'),
  ('gemini-2.5-pro', 'mixed', 1.25, 0.125, 10.00, '2025-06-17T00:00:00Z', 'google-2026-07-09')
ON CONFLICT (model, input_modality, effective_from) DO NOTHING;

ALTER TABLE internal.admin_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.admin_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.admin_audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.review_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.review_case_sources ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.feedback_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.admin_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.ai_model_pricing ENABLE ROW LEVEL SECURITY;
ALTER TABLE internal.admin_aggregate_cache ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON ALL TABLES IN SCHEMA internal FROM PUBLIC, anon, authenticated;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA internal FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION internal.admin_role_rank(p_role TEXT)
RETURNS INTEGER
LANGUAGE SQL
IMMUTABLE
SET search_path = ''
AS $$
  SELECT CASE p_role
    WHEN 'analyst' THEN 1
    WHEN 'moderator' THEN 2
    WHEN 'owner' THEN 3
    ELSE 0
  END;
$$;

-- Deliberately callable only from trusted SQL/service-role bootstrap tooling.
-- The immutable Auth UUID is supplied after the first successful Google login,
-- and the one-row guard makes this incapable of replacing an existing owner.
CREATE OR REPLACE FUNCTION internal.bootstrap_first_admin_owner(p_user_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM internal.admin_memberships) THEN
    RAISE EXCEPTION 'The first owner has already been bootstrapped.' USING ERRCODE = '23514';
  END IF;
  IF NOT EXISTS (
    SELECT 1
    FROM auth.users auth_user
    JOIN auth.identities identity ON identity.user_id = auth_user.id
    WHERE auth_user.id = p_user_id
      AND auth_user.is_anonymous = FALSE
      AND identity.provider = 'google'
  ) THEN
    RAISE EXCEPTION 'The bootstrap UUID must be an existing Google user.' USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO internal.admin_memberships (user_id, role, is_active, created_by)
  VALUES (p_user_id, 'owner', TRUE, p_user_id);
END;
$$;

CREATE OR REPLACE FUNCTION internal.current_session_id()
RETURNS UUID
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  session_text TEXT;
BEGIN
  session_text := auth.jwt() ->> 'session_id';
  IF session_text IS NULL OR session_text = '' THEN
    RETURN NULL;
  END IF;
  RETURN session_text::UUID;
EXCEPTION WHEN invalid_text_representation THEN
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION internal.write_admin_audit(
  p_role TEXT,
  p_action TEXT,
  p_target_type TEXT DEFAULT NULL,
  p_target_id TEXT DEFAULT NULL,
  p_before JSONB DEFAULT NULL,
  p_after JSONB DEFAULT NULL,
  p_reason TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE SQL
SECURITY DEFINER
SET search_path = ''
AS $$
  INSERT INTO internal.admin_audit_log (
    actor_user_id, actor_role, action, target_type, target_id,
    before_state, after_state, reason
  ) VALUES (
    auth.uid(), p_role, p_action, p_target_type, p_target_id,
    p_before, p_after, NULLIF(btrim(p_reason), '')
  );
$$;

CREATE OR REPLACE FUNCTION internal.reject_admin_audit_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'Admin audit records are immutable.' USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS trg_reject_admin_audit_mutation ON internal.admin_audit_log;
CREATE TRIGGER trg_reject_admin_audit_mutation
BEFORE UPDATE OR DELETE ON internal.admin_audit_log
FOR EACH ROW EXECUTE FUNCTION internal.reject_admin_audit_mutation();

CREATE OR REPLACE FUNCTION internal.reject_admin_note_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RAISE EXCEPTION 'Admin notes are append-only.' USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS trg_reject_admin_note_mutation ON internal.admin_notes;
CREATE TRIGGER trg_reject_admin_note_mutation
BEFORE UPDATE OR DELETE ON internal.admin_notes
FOR EACH ROW EXECUTE FUNCTION internal.reject_admin_note_mutation();

CREATE OR REPLACE FUNCTION internal.require_admin(p_minimum_role TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id UUID := auth.uid();
  caller_role TEXT;
  caller_session UUID := internal.current_session_id();
  caller_aal TEXT := COALESCE(auth.jwt() ->> 'aal', 'aal1');
BEGIN
  IF caller_id IS NULL OR caller_session IS NULL OR caller_aal <> 'aal2' THEN
    RAISE EXCEPTION 'Admin authentication requires an AAL2 session.' USING ERRCODE = '42501';
  END IF;

  SELECT membership.role
  INTO caller_role
  FROM internal.admin_memberships membership
  JOIN auth.users auth_user ON auth_user.id = membership.user_id
  WHERE membership.user_id = caller_id
    AND membership.is_active = TRUE
    AND auth_user.is_anonymous = FALSE
    AND EXISTS (
      SELECT 1
      FROM auth.identities identity
      WHERE identity.user_id = caller_id
        AND identity.provider = 'google'
    );

  IF caller_role IS NULL
    OR internal.admin_role_rank(caller_role) < internal.admin_role_rank(p_minimum_role) THEN
    RAISE EXCEPTION 'Admin role is not authorized for this operation.' USING ERRCODE = '42501';
  END IF;

  UPDATE internal.admin_sessions session_row
  SET last_seen_at = NOW()
  WHERE session_row.session_id = caller_session
    AND session_row.user_id = caller_id
    AND session_row.revoked_at IS NULL
    AND session_row.expires_at > NOW()
    AND session_row.last_seen_at > NOW() - INTERVAL '30 minutes'
    AND EXISTS (
      SELECT 1 FROM auth.sessions auth_session
      WHERE auth_session.id = caller_session
        AND auth_session.user_id = caller_id
    );

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Admin session is expired or revoked.' USING ERRCODE = '42501';
  END IF;

  RETURN caller_role;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_get_access_state()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id UUID := auth.uid();
  membership_role TEXT;
  membership_active BOOLEAN := FALSE;
  has_google BOOLEAN := FALSE;
  is_registered BOOLEAN := FALSE;
  session_active BOOLEAN := FALSE;
  caller_session UUID := internal.current_session_id();
BEGIN
  IF caller_id IS NULL THEN
    RETURN jsonb_build_object('is_authenticated', FALSE, 'is_member', FALSE);
  END IF;

  SELECT membership.role, membership.is_active
  INTO membership_role, membership_active
  FROM internal.admin_memberships membership
  WHERE membership.user_id = caller_id;

  SELECT EXISTS (
    SELECT 1 FROM auth.identities identity
    WHERE identity.user_id = caller_id AND identity.provider = 'google'
  ) INTO has_google;
  SELECT EXISTS (
    SELECT 1 FROM auth.users auth_user
    WHERE auth_user.id = caller_id AND auth_user.is_anonymous = FALSE
  ) INTO is_registered;

  SELECT EXISTS (
    SELECT 1 FROM internal.admin_sessions session_row
    WHERE session_row.session_id = caller_session
      AND session_row.user_id = caller_id
      AND session_row.revoked_at IS NULL
      AND session_row.expires_at > NOW()
      AND session_row.last_seen_at > NOW() - INTERVAL '30 minutes'
  ) INTO session_active;

  RETURN jsonb_build_object(
    'is_authenticated', TRUE,
    'is_member', COALESCE(membership_active, FALSE) AND has_google AND is_registered,
    'role', membership_role,
    'aal', COALESCE(auth.jwt() ->> 'aal', 'aal1'),
    'session_active', session_active
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_begin_session()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_id UUID := auth.uid();
  caller_session UUID := internal.current_session_id();
  membership_role TEXT;
  existing_session internal.admin_sessions%ROWTYPE;
BEGIN
  IF caller_id IS NULL OR caller_session IS NULL OR COALESCE(auth.jwt() ->> 'aal', 'aal1') <> 'aal2' THEN
    RAISE EXCEPTION 'A verified AAL2 session is required.' USING ERRCODE = '42501';
  END IF;

  SELECT membership.role INTO membership_role
  FROM internal.admin_memberships membership
  WHERE membership.user_id = caller_id AND membership.is_active = TRUE;

  IF membership_role IS NULL OR NOT EXISTS (
    SELECT 1 FROM auth.identities identity
    WHERE identity.user_id = caller_id AND identity.provider = 'google'
  ) OR NOT EXISTS (
    SELECT 1 FROM auth.users auth_user
    WHERE auth_user.id = caller_id AND auth_user.is_anonymous = FALSE
  ) OR NOT EXISTS (
    SELECT 1 FROM auth.sessions auth_session
    WHERE auth_session.id = caller_session AND auth_session.user_id = caller_id
  ) THEN
    RAISE EXCEPTION 'This Google account is not an active admin member.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO existing_session
  FROM internal.admin_sessions
  WHERE session_id = caller_session;

  IF FOUND AND (
    existing_session.revoked_at IS NOT NULL
    OR existing_session.expires_at <= NOW()
    OR existing_session.last_seen_at <= NOW() - INTERVAL '30 minutes'
  ) THEN
    RAISE EXCEPTION 'Start a new Google session to continue.' USING ERRCODE = '42501';
  END IF;

  INSERT INTO internal.admin_sessions (session_id, user_id)
  VALUES (caller_session, caller_id)
  ON CONFLICT (session_id) DO UPDATE
    SET last_seen_at = NOW()
    WHERE internal.admin_sessions.user_id = EXCLUDED.user_id
      AND internal.admin_sessions.revoked_at IS NULL
      AND internal.admin_sessions.expires_at > NOW()
  RETURNING * INTO existing_session;

  PERFORM internal.write_admin_audit(
    membership_role, 'admin_session_started', 'session', caller_session::TEXT
  );

  RETURN jsonb_build_object('role', membership_role, 'expires_at', existing_session.expires_at);
END;
$$;

CREATE OR REPLACE FUNCTION internal.attach_review_source(
  p_case_type TEXT,
  p_subject_id UUID,
  p_subject_user_id UUID,
  p_source_type TEXT,
  p_source_id UUID,
  p_reporter_user_id UUID,
  p_created_at TIMESTAMPTZ
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  target_case_id UUID;
  inserted_source UUID;
  independent_reporter BOOLEAN;
BEGIN
  INSERT INTO internal.review_cases (
    case_type, subject_id, subject_user_id, created_at, updated_at
  ) VALUES (
    p_case_type, p_subject_id, p_subject_user_id,
    COALESCE(p_created_at, NOW()), COALESCE(p_created_at, NOW())
  )
  ON CONFLICT (case_type, subject_id) DO UPDATE
    SET subject_user_id = COALESCE(internal.review_cases.subject_user_id, EXCLUDED.subject_user_id)
  RETURNING id INTO target_case_id;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(target_case_id::TEXT, 0));
  SELECT NOT EXISTS (
    SELECT 1
    FROM internal.review_case_sources source
    WHERE source.case_id = target_case_id
      AND source.reporter_user_id IS NOT DISTINCT FROM p_reporter_user_id
  ) INTO independent_reporter;

  INSERT INTO internal.review_case_sources (
    case_id, source_type, source_id, reporter_user_id, created_at
  ) VALUES (
    target_case_id, p_source_type, p_source_id, p_reporter_user_id,
    COALESCE(p_created_at, NOW())
  )
  ON CONFLICT (source_type, source_id) DO NOTHING
  RETURNING source_id INTO inserted_source;

  IF inserted_source IS NOT NULL AND independent_reporter THEN
    UPDATE internal.review_cases
    SET report_count = report_count + 1,
        status = CASE WHEN status IN ('resolved', 'dismissed') THEN 'open' ELSE status END,
        resolution_code = CASE WHEN status IN ('resolved', 'dismissed') THEN NULL ELSE resolution_code END,
        resolved_at = CASE WHEN status IN ('resolved', 'dismissed') THEN NULL ELSE resolved_at END,
        updated_at = NOW()
    WHERE id = target_case_id;
    IF p_case_type = 'identification' THEN
      UPDATE public.scans SET is_flagged = TRUE WHERE id = p_subject_id;
    END IF;
  ELSIF inserted_source IS NOT NULL THEN
    UPDATE internal.review_cases
    SET updated_at = GREATEST(updated_at, COALESCE(p_created_at, NOW()))
    WHERE id = target_case_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION internal.trg_attach_flagged_review()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  owner_id UUID;
BEGIN
  IF NEW.status = 'MIGRATED_TO_EXPLORE_POST_REPORT' THEN
    RETURN NEW;
  END IF;
  SELECT scan.user_id INTO owner_id FROM public.scans scan WHERE scan.id = NEW.scan_id;
  PERFORM internal.attach_review_source(
    'identification', NEW.scan_id, owner_id,
    'flagged_review', NEW.id, NEW.user_id, NEW.created_at
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION internal.trg_attach_explore_post_report()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM internal.attach_review_source(
    'post', NEW.post_id, NEW.post_author_user_id,
    'explore_post_report', NEW.id, NEW.reporter_user_id, NEW.created_at
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION internal.trg_attach_explore_comment_report()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM internal.attach_review_source(
    'comment', NEW.comment_id, NEW.comment_author_user_id,
    'explore_comment_report', NEW.id, NEW.reporter_user_id, NEW.created_at
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION internal.trg_attach_user_report()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM internal.attach_review_source(
    'user', NEW.reported_user_id, NEW.reported_user_id,
    'user_report', NEW.id, NEW.reporter_user_id, NEW.created_at
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_attach_flagged_review ON public.flagged_reviews;
CREATE TRIGGER trg_attach_flagged_review
AFTER INSERT ON public.flagged_reviews
FOR EACH ROW EXECUTE FUNCTION internal.trg_attach_flagged_review();

DROP TRIGGER IF EXISTS trg_attach_explore_post_report ON public.explore_post_reports;
CREATE TRIGGER trg_attach_explore_post_report
AFTER INSERT ON public.explore_post_reports
FOR EACH ROW EXECUTE FUNCTION internal.trg_attach_explore_post_report();

DROP TRIGGER IF EXISTS trg_attach_explore_comment_report ON public.explore_comment_reports;
CREATE TRIGGER trg_attach_explore_comment_report
AFTER INSERT ON public.explore_comment_reports
FOR EACH ROW EXECUTE FUNCTION internal.trg_attach_explore_comment_report();

DROP TRIGGER IF EXISTS trg_attach_user_report ON public.user_reports;
CREATE TRIGGER trg_attach_user_report
AFTER INSERT ON public.user_reports
FOR EACH ROW EXECUTE FUNCTION internal.trg_attach_user_report();

-- Backfill every existing intake row through the same idempotent grouping path.
DO $$
DECLARE row_record RECORD;
BEGIN
  FOR row_record IN
    SELECT review.id, review.scan_id AS subject_id, scan.user_id AS subject_user_id,
           review.user_id AS reporter_user_id, review.created_at
    FROM public.flagged_reviews review
    JOIN public.scans scan ON scan.id = review.scan_id
    WHERE review.status = 'PENDING_REVIEW'
  LOOP
    PERFORM internal.attach_review_source(
      'identification', row_record.subject_id, row_record.subject_user_id,
      'flagged_review', row_record.id, row_record.reporter_user_id, row_record.created_at
    );
  END LOOP;

  FOR row_record IN
    SELECT id, post_id AS subject_id, post_author_user_id AS subject_user_id,
           reporter_user_id, created_at
    FROM public.explore_post_reports
    WHERE status = 'PENDING_REVIEW'
  LOOP
    PERFORM internal.attach_review_source(
      'post', row_record.subject_id, row_record.subject_user_id,
      'explore_post_report', row_record.id, row_record.reporter_user_id, row_record.created_at
    );
  END LOOP;

  FOR row_record IN
    SELECT id, comment_id AS subject_id, comment_author_user_id AS subject_user_id,
           reporter_user_id, created_at
    FROM public.explore_comment_reports
  LOOP
    PERFORM internal.attach_review_source(
      'comment', row_record.subject_id, row_record.subject_user_id,
      'explore_comment_report', row_record.id, row_record.reporter_user_id, row_record.created_at
    );
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION internal.effective_plan(
  p_subscription_tier public.subscription_tier_enum,
  p_created_at TIMESTAMPTZ,
  p_expires_at TIMESTAMPTZ
)
RETURNS TEXT
LANGUAGE SQL
STABLE
SET search_path = ''
AS $$
  SELECT CASE
    WHEN p_subscription_tier = 'pro'::public.subscription_tier_enum
      AND (p_expires_at IS NULL OR p_expires_at > NOW()) THEN 'pro_paid'
    WHEN p_subscription_tier = 'free'::public.subscription_tier_enum
      AND p_created_at >= NOW() - INTERVAL '7 days' THEN 'pro_trial'
    ELSE 'free'
  END;
$$;

CREATE OR REPLACE FUNCTION internal.estimate_ai_cost_microusd(
  p_model TEXT,
  p_modality TEXT,
  p_occurred_at TIMESTAMPTZ,
  p_prompt BIGINT,
  p_cached BIGINT,
  p_candidate BIGINT,
  p_thinking BIGINT,
  p_tool BIGINT
)
RETURNS TABLE(cost_microusd BIGINT, pricing_version TEXT)
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    ROUND(
      GREATEST(COALESCE(p_prompt, 0) - COALESCE(p_cached, 0), 0) * price.prompt_usd_per_million
      + COALESCE(p_cached, 0) * price.cached_usd_per_million
      + (COALESCE(p_candidate, 0) + COALESCE(p_thinking, 0) + COALESCE(p_tool, 0))
        * price.output_usd_per_million
    )::BIGINT,
    price.version
  FROM internal.ai_model_pricing price
  WHERE price.model = p_model
    AND price.input_modality = CASE
      WHEN p_modality IN ('text', 'image', 'audio', 'video', 'mixed') THEN p_modality
      ELSE 'text'
    END
    AND price.effective_from <= p_occurred_at
    AND (price.effective_to IS NULL OR price.effective_to > p_occurred_at)
  ORDER BY price.effective_from DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.record_ai_usage_event(
  p_operation TEXT,
  p_model TEXT,
  p_effective_plan TEXT DEFAULT 'unknown',
  p_input_modality TEXT DEFAULT 'unknown',
  p_prompt_tokens BIGINT DEFAULT NULL,
  p_cached_tokens BIGINT DEFAULT NULL,
  p_candidate_tokens BIGINT DEFAULT NULL,
  p_thinking_tokens BIGINT DEFAULT NULL,
  p_tool_tokens BIGINT DEFAULT NULL,
  p_total_tokens BIGINT DEFAULT NULL,
  p_prompt_tokens_by_modality JSONB DEFAULT '{}'::JSONB,
  p_outcome TEXT DEFAULT 'success',
  p_user_id UUID DEFAULT NULL,
  p_scan_id UUID DEFAULT NULL,
  p_conversation_id UUID DEFAULT NULL,
  p_message_id UUID DEFAULT NULL,
  p_source_type TEXT DEFAULT NULL,
  p_source_id UUID DEFAULT NULL,
  p_metadata JSONB DEFAULT '{}'::JSONB,
  p_occurred_at TIMESTAMPTZ DEFAULT NOW()
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  event_id UUID;
  cost_row RECORD;
BEGIN
  SELECT * INTO cost_row
  FROM internal.estimate_ai_cost_microusd(
    p_model, p_input_modality, p_occurred_at,
    p_prompt_tokens, p_cached_tokens, p_candidate_tokens,
    p_thinking_tokens, p_tool_tokens
  );

  INSERT INTO public.ai_usage_events (
    occurred_at, user_id, operation, model, effective_plan, input_modality,
    prompt_tokens, cached_tokens, candidate_tokens, thinking_tokens, tool_tokens,
    total_tokens, prompt_tokens_by_modality, outcome, scan_id, conversation_id,
    message_id, source_type, source_id, estimated_cost_microusd, pricing_version,
    metadata
  ) VALUES (
    COALESCE(p_occurred_at, NOW()), p_user_id, btrim(p_operation), btrim(p_model),
    p_effective_plan, p_input_modality, p_prompt_tokens, p_cached_tokens,
    p_candidate_tokens, p_thinking_tokens, p_tool_tokens, p_total_tokens,
    COALESCE(p_prompt_tokens_by_modality, '{}'::JSONB), p_outcome, p_scan_id,
    p_conversation_id, p_message_id, p_source_type, p_source_id,
    cost_row.cost_microusd, cost_row.pricing_version,
    COALESCE(p_metadata, '{}'::JSONB)
  )
  ON CONFLICT (source_type, source_id, operation) DO NOTHING
  RETURNING id INTO event_id;

  IF event_id IS NULL AND p_source_type IS NOT NULL AND p_source_id IS NOT NULL THEN
    SELECT event.id INTO event_id
    FROM public.ai_usage_events event
    WHERE event.source_type = p_source_type
      AND event.source_id = p_source_id
      AND event.operation = btrim(p_operation);
  END IF;

  RETURN event_id;
END;
$$;

-- Historical backfill is intentionally marked primary-only/partial.
INSERT INTO public.ai_usage_events (
  occurred_at, user_id, operation, model, effective_plan, input_modality,
  prompt_tokens, cached_tokens, candidate_tokens, thinking_tokens, total_tokens,
  scan_id, source_type, source_id, is_backfilled, coverage_scope
)
SELECT
  scan.timestamp,
  scan.user_id,
  'scan_identification',
  CASE WHEN scan.inference_tier = 'pro' THEN 'gemini-2.5-pro' ELSE 'gemini-2.5-flash' END,
  'unknown',
  CASE
    WHEN COALESCE(array_length(scan.audio_storage_urls, 1), 0) > 0
      AND COALESCE(array_length(scan.image_storage_urls, 1), 0) > 0 THEN 'mixed'
    WHEN COALESCE(array_length(scan.audio_storage_urls, 1), 0) > 0 THEN 'audio'
    ELSE 'image'
  END,
  scan.llm_prompt_tokens,
  scan.llm_cached_tokens,
  scan.llm_candidate_tokens,
  scan.llm_thinking_tokens,
  scan.llm_total_tokens,
  scan.id,
  'scan',
  scan.id,
  TRUE,
  'primary_only'
FROM public.scans scan
WHERE scan.llm_total_tokens IS NOT NULL
ON CONFLICT (source_type, source_id, operation) DO NOTHING;

CREATE OR REPLACE FUNCTION internal.trg_record_scan_ai_usage()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  resolved_plan TEXT := 'unknown';
  resolved_modality TEXT := 'image';
BEGIN
  IF NEW.llm_total_tokens IS NULL THEN RETURN NEW; END IF;
  SELECT internal.effective_plan(app_user.subscription_tier, app_user.created_at, app_user.subscription_expires_at)
  INTO resolved_plan FROM public.users app_user WHERE app_user.id = NEW.user_id;
  resolved_modality := CASE
    WHEN COALESCE(array_length(NEW.video_storage_urls, 1), 0) > 0
      OR (
        COALESCE(array_length(NEW.audio_storage_urls, 1), 0) > 0
        AND COALESCE(array_length(NEW.image_storage_urls, 1), 0) > 0
      ) THEN 'mixed'
    WHEN COALESCE(array_length(NEW.audio_storage_urls, 1), 0) > 0 THEN 'audio'
    ELSE 'image'
  END;
  PERFORM public.record_ai_usage_event(
    'scan_identification',
    CASE WHEN NEW.inference_tier::TEXT = 'pro' THEN 'gemini-2.5-pro' ELSE 'gemini-2.5-flash' END,
    COALESCE(resolved_plan, 'unknown'), resolved_modality,
    NEW.llm_prompt_tokens, NEW.llm_cached_tokens, NEW.llm_candidate_tokens,
    NEW.llm_thinking_tokens, NULL, NEW.llm_total_tokens, NEW.llm_usage_metadata,
    'success', NEW.user_id, NEW.id, NULL, NULL, 'scan', NEW.id,
    jsonb_build_object('writer', 'scan_trigger'), NEW.timestamp
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_record_scan_ai_usage ON public.scans;
CREATE TRIGGER trg_record_scan_ai_usage
AFTER INSERT OR UPDATE OF llm_total_tokens ON public.scans
FOR EACH ROW
WHEN (NEW.llm_total_tokens IS NOT NULL)
EXECUTE FUNCTION internal.trg_record_scan_ai_usage();

CREATE OR REPLACE FUNCTION internal.trg_record_insight_chat_ai_usage()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  resolved_plan TEXT := 'unknown';
BEGIN
  IF NEW.role <> 'assistant' OR NEW.llm_total_tokens IS NULL THEN RETURN NEW; END IF;
  SELECT internal.effective_plan(app_user.subscription_tier, app_user.created_at, app_user.subscription_expires_at)
  INTO resolved_plan FROM public.users app_user WHERE app_user.id = NEW.user_id;
  PERFORM public.record_ai_usage_event(
    'insight_chat_reply', COALESCE(NEW.model, 'gemini-2.5-flash'),
    COALESCE(resolved_plan, 'unknown'), 'text',
    NEW.llm_prompt_tokens, NEW.llm_cached_tokens, NEW.llm_candidate_tokens,
    NEW.llm_thinking_tokens, NULL, NEW.llm_total_tokens, NEW.llm_usage_metadata,
    CASE WHEN NEW.is_refusal THEN 'refusal' ELSE 'success' END,
    NEW.user_id, NEW.scan_id, NEW.conversation_id, NEW.id,
    'insight_chat_message', NEW.id,
    jsonb_build_object('writer', 'message_trigger'), NEW.created_at
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_record_insight_chat_ai_usage ON public.insight_chat_messages;
CREATE TRIGGER trg_record_insight_chat_ai_usage
AFTER INSERT OR UPDATE OF llm_total_tokens ON public.insight_chat_messages
FOR EACH ROW
WHEN (NEW.role = 'assistant' AND NEW.llm_total_tokens IS NOT NULL)
EXECUTE FUNCTION internal.trg_record_insight_chat_ai_usage();

INSERT INTO public.ai_usage_events (
  occurred_at, user_id, operation, model, effective_plan, input_modality,
  prompt_tokens, cached_tokens, candidate_tokens, thinking_tokens, total_tokens,
  scan_id, conversation_id, message_id, source_type, source_id,
  is_backfilled, coverage_scope
)
SELECT
  message.created_at,
  message.user_id,
  'insight_chat_reply',
  COALESCE(message.model, 'gemini-2.5-flash'),
  'unknown',
  'text',
  message.llm_prompt_tokens,
  message.llm_cached_tokens,
  message.llm_candidate_tokens,
  message.llm_thinking_tokens,
  message.llm_total_tokens,
  message.scan_id,
  message.conversation_id,
  message.id,
  'insight_chat_message',
  message.id,
  TRUE,
  'partial'
FROM public.insight_chat_messages message
WHERE message.role = 'assistant' AND message.llm_total_tokens IS NOT NULL
ON CONFLICT (source_type, source_id, operation) DO NOTHING;

-- Price backfilled rows using the same effective-dated table. This one-time
-- migration update happens before the append-only guard is installed.
WITH priced AS (
  SELECT event.id, cost.cost_microusd, cost.pricing_version
  FROM public.ai_usage_events event
  CROSS JOIN LATERAL internal.estimate_ai_cost_microusd(
    event.model,
    event.input_modality,
    event.occurred_at,
    event.prompt_tokens,
    event.cached_tokens,
    event.candidate_tokens,
    event.thinking_tokens,
    event.tool_tokens
  ) cost
  WHERE event.is_backfilled = TRUE
    AND event.estimated_cost_microusd IS NULL
)
UPDATE public.ai_usage_events event
SET estimated_cost_microusd = priced.cost_microusd,
    pricing_version = priced.pricing_version
FROM priced
WHERE event.id = priced.id;

CREATE OR REPLACE FUNCTION internal.trg_anonymize_ai_usage()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM set_config('internal.ai_usage_anonymizing', 'on', TRUE);
  UPDATE public.ai_usage_events
  SET user_id = NULL,
      scan_id = NULL,
      conversation_id = NULL,
      message_id = NULL,
      source_id = NULL,
      metadata = metadata - 'user_id' - 'scan_id' - 'conversation_id' - 'message_id'
  WHERE user_id = OLD.id;
  RETURN OLD;
END;
$$;

CREATE OR REPLACE FUNCTION internal.trg_protect_ai_usage_events()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF TG_OP = 'UPDATE'
    AND current_setting('internal.ai_usage_anonymizing', TRUE) = 'on'
    AND OLD.user_id IS NOT NULL
    AND NEW.user_id IS NULL THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'AI usage events are append-only.' USING ERRCODE = '42501';
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_ai_usage_events ON public.ai_usage_events;
CREATE TRIGGER trg_protect_ai_usage_events
BEFORE UPDATE OR DELETE ON public.ai_usage_events
FOR EACH ROW EXECUTE FUNCTION internal.trg_protect_ai_usage_events();

DROP TRIGGER IF EXISTS trg_anonymize_ai_usage ON public.users;
CREATE TRIGGER trg_anonymize_ai_usage
AFTER DELETE ON public.users
FOR EACH ROW EXECUTE FUNCTION internal.trg_anonymize_ai_usage();

CREATE OR REPLACE FUNCTION public.admin_get_overview(
  p_days INTEGER DEFAULT 30,
  p_timezone TEXT DEFAULT 'UTC',
  p_refresh BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_role TEXT;
  bounded_days INTEGER := LEAST(GREATEST(COALESCE(p_days, 30), 0), 36500);
  start_at TIMESTAMPTZ := CASE WHEN bounded_days = 0 THEN '1970-01-01T00:00:00Z'::TIMESTAMPTZ
    ELSE NOW() - make_interval(days => bounded_days) END;
  previous_start_at TIMESTAMPTZ := CASE WHEN bounded_days = 0 THEN start_at
    ELSE start_at - make_interval(days => bounded_days) END;
  cache_key_value TEXT := format('overview:%s:%s', bounded_days, COALESCE(p_timezone, 'UTC'));
  result JSONB;
BEGIN
  caller_role := internal.require_admin('analyst');
  IF NOT COALESCE(p_refresh, FALSE) THEN
    SELECT cache.payload INTO result
    FROM internal.admin_aggregate_cache cache
    WHERE cache.cache_key = cache_key_value
      AND cache.created_at > NOW() - INTERVAL '5 minutes';
    IF FOUND THEN
      PERFORM internal.write_admin_audit(caller_role, 'overview_viewed_cached', 'dashboard', bounded_days::TEXT);
      RETURN result;
    END IF;
  END IF;

  SELECT jsonb_build_object(
    'range_start', start_at,
    'range_end', NOW(),
    'coverage_complete_from', (
      SELECT MIN(event.occurred_at) FROM public.ai_usage_events event WHERE event.is_backfilled = FALSE
    ),
    'accounts', (
      SELECT jsonb_build_object(
        'total', COUNT(*),
        'registered', COUNT(*) FILTER (WHERE auth_user.is_anonymous = FALSE),
        'ghost', COUNT(*) FILTER (WHERE auth_user.is_anonymous = TRUE),
        'new_in_range', COUNT(*) FILTER (WHERE auth_user.created_at >= start_at)
      ) FROM auth.users auth_user
    ),
    'plans', (
      SELECT jsonb_build_object(
        'pro_paid', COUNT(*) FILTER (WHERE app_user.id IS NOT NULL AND internal.effective_plan(app_user.subscription_tier, app_user.created_at, app_user.subscription_expires_at) = 'pro_paid'),
        'pro_trial', COUNT(*) FILTER (WHERE app_user.id IS NULL OR internal.effective_plan(app_user.subscription_tier, app_user.created_at, app_user.subscription_expires_at) = 'pro_trial'),
        'free', COUNT(*) FILTER (WHERE app_user.id IS NOT NULL AND internal.effective_plan(app_user.subscription_tier, app_user.created_at, app_user.subscription_expires_at) = 'free')
      ) FROM auth.users auth_user LEFT JOIN public.users app_user ON app_user.id = auth_user.id
    ),
    'open_reviews', (
      SELECT COUNT(*) FROM internal.review_cases review
      WHERE review.status IN ('open', 'in_review')
    ),
    'new_feedback', (
      SELECT
        (SELECT COUNT(*) FROM public.community_feedback feedback
          LEFT JOIN internal.feedback_state state ON state.source_type = 'community' AND state.source_id = feedback.id
          WHERE COALESCE(state.status, 'new') = 'new')
        + (SELECT COUNT(*) FROM public.feedback_survey_responses survey
          LEFT JOIN internal.feedback_state state ON state.source_type = 'survey' AND state.source_id = survey.id
          WHERE COALESCE(state.status, 'new') = 'new')
        + (SELECT COUNT(*) FROM public.insight_chat_message_feedback feedback
          LEFT JOIN internal.feedback_state state ON state.source_type = 'chat_message' AND state.source_id = feedback.id
          WHERE COALESCE(state.status, 'new') = 'new')
        + (SELECT COUNT(*) FROM public.insight_chat_feature_feedback feedback
          LEFT JOIN internal.feedback_state state ON state.source_type = 'chat_feature' AND state.source_id = feedback.id
          WHERE COALESCE(state.status, 'new') = 'new')
    ),
    'ai', (
      SELECT jsonb_build_object(
        'events', COUNT(*),
        'total_tokens', COALESCE(SUM(event.total_tokens), 0),
        'estimated_cost_microusd', COALESCE(SUM(event.estimated_cost_microusd), 0),
        'avg_tokens_per_scan', ROUND(AVG(event.total_tokens) FILTER (
          WHERE event.operation = 'scan_identification' AND event.outcome = 'success' AND event.scan_id IS NOT NULL
        ))
      ) FROM public.ai_usage_events event WHERE event.occurred_at >= start_at
    ),
    'previous_period', CASE WHEN bounded_days = 0 THEN NULL ELSE (
      SELECT jsonb_build_object(
        'scans', COUNT(*) FILTER (
          WHERE event.operation = 'scan_identification' AND event.outcome = 'success' AND event.scan_id IS NOT NULL
        ),
        'total_tokens', COALESCE(SUM(event.total_tokens), 0),
        'estimated_cost_microusd', COALESCE(SUM(event.estimated_cost_microusd), 0)
      )
      FROM public.ai_usage_events event
      WHERE event.occurred_at >= previous_start_at AND event.occurred_at < start_at
    ) END,
    'daily', (
      SELECT COALESCE(jsonb_agg(to_jsonb(day_row) ORDER BY day_row.day), '[]'::JSONB)
      FROM (
        SELECT
          date_trunc('day', event.occurred_at AT TIME ZONE p_timezone)::DATE AS day,
          COUNT(*) FILTER (
            WHERE event.operation = 'scan_identification' AND event.outcome = 'success' AND event.scan_id IS NOT NULL
          ) AS scans,
          COALESCE(SUM(event.total_tokens), 0) AS total_tokens,
          COALESCE(SUM(event.estimated_cost_microusd), 0) AS estimated_cost_microusd
        FROM public.ai_usage_events event
        WHERE event.occurred_at >= start_at
        GROUP BY 1
      ) day_row
    )
  ) INTO result;

  INSERT INTO internal.admin_aggregate_cache (cache_key, payload, created_at)
  VALUES (cache_key_value, result, NOW())
  ON CONFLICT (cache_key) DO UPDATE SET payload = EXCLUDED.payload, created_at = EXCLUDED.created_at;

  PERFORM internal.write_admin_audit(caller_role, 'overview_viewed', 'dashboard', bounded_days::TEXT);
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_review_cases(
  p_status TEXT DEFAULT NULL,
  p_case_type TEXT DEFAULT NULL,
  p_priority TEXT DEFAULT NULL,
  p_assigned_to UUID DEFAULT NULL,
  p_reason TEXT DEFAULT NULL,
  p_from TIMESTAMPTZ DEFAULT NULL,
  p_to TIMESTAMPTZ DEFAULT NULL,
  p_cursor_updated_at TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL,
  p_limit INTEGER DEFAULT 50
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_role TEXT;
  safe_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
  result JSONB;
BEGIN
  caller_role := internal.require_admin('moderator');

  SELECT jsonb_build_object(
    'items', COALESCE(jsonb_agg(to_jsonb(queue_row) ORDER BY queue_row.updated_at DESC), '[]'::JSONB),
    'limit', safe_limit,
    'next_cursor', CASE WHEN COUNT(*) = 0 THEN NULL ELSE jsonb_build_object(
      'updated_at', (array_agg(queue_row.updated_at ORDER BY queue_row.updated_at ASC, queue_row.id ASC))[1],
      'id', (array_agg(queue_row.id ORDER BY queue_row.updated_at ASC, queue_row.id ASC))[1]
    ) END
  ) INTO result
  FROM (
    SELECT
      review.id, review.case_type, review.subject_id, review.subject_user_id,
      review.status, review.priority, review.assigned_to, review.report_count,
      review.resolution_code, review.created_at, review.updated_at,
      app_user.email,
      app_user.public_username
    FROM internal.review_cases review
    LEFT JOIN public.users app_user ON app_user.id = review.subject_user_id
    WHERE (p_status IS NULL OR review.status = p_status)
      AND (p_case_type IS NULL OR review.case_type = p_case_type)
      AND (p_priority IS NULL OR review.priority = p_priority)
      AND (p_assigned_to IS NULL OR review.assigned_to = p_assigned_to)
      AND (p_from IS NULL OR review.created_at >= p_from)
      AND (p_to IS NULL OR review.created_at < p_to)
      AND (
        p_reason IS NULL OR EXISTS (
          SELECT 1 FROM internal.review_case_sources source
          WHERE source.case_id = review.id AND (
            EXISTS (SELECT 1 FROM public.flagged_reviews intake WHERE source.source_type = 'flagged_review' AND intake.id = source.source_id AND intake.flag_reason = p_reason)
            OR EXISTS (SELECT 1 FROM public.explore_post_reports intake WHERE source.source_type = 'explore_post_report' AND intake.id = source.source_id AND intake.reason = p_reason)
            OR EXISTS (SELECT 1 FROM public.explore_comment_reports intake WHERE source.source_type = 'explore_comment_report' AND intake.id = source.source_id AND intake.reason = p_reason)
            OR EXISTS (SELECT 1 FROM public.user_reports intake WHERE source.source_type = 'user_report' AND intake.id = source.source_id AND intake.reason = p_reason)
          )
        )
      )
      AND (
        p_cursor_updated_at IS NULL OR p_cursor_id IS NULL
        OR (review.updated_at, review.id) < (p_cursor_updated_at, p_cursor_id)
      )
    ORDER BY review.updated_at DESC, review.id DESC
    LIMIT safe_limit
  ) queue_row;

  PERFORM internal.write_admin_audit(caller_role, 'review_queue_viewed', 'review_queue', NULL);
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_get_review_case(p_case_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_role TEXT;
  target_case internal.review_cases%ROWTYPE;
  subject_context JSONB;
  source_context JSONB;
  notes_context JSONB;
BEGIN
  caller_role := internal.require_admin('moderator');
  SELECT * INTO target_case FROM internal.review_cases WHERE id = p_case_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Review case not found.' USING ERRCODE = 'P0002'; END IF;

  SELECT to_jsonb(user_row) INTO subject_context
  FROM (
    SELECT app_user.*, auth_user.email AS auth_email, auth_user.is_anonymous,
           auth_user.created_at AS auth_created_at, auth_user.last_sign_in_at
    FROM public.users app_user
    LEFT JOIN auth.users auth_user ON auth_user.id = app_user.id
    WHERE app_user.id = target_case.subject_user_id
  ) user_row;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'source_type', source.source_type,
      'source_id', source.source_id,
      'reporter_user_id', source.reporter_user_id,
      'created_at', source.created_at,
      'payload', CASE source.source_type
        WHEN 'flagged_review' THEN (SELECT to_jsonb(row_value) FROM public.flagged_reviews row_value WHERE row_value.id = source.source_id)
        WHEN 'explore_post_report' THEN (SELECT to_jsonb(row_value) FROM public.explore_post_reports row_value WHERE row_value.id = source.source_id)
        WHEN 'explore_comment_report' THEN (SELECT to_jsonb(row_value) FROM public.explore_comment_reports row_value WHERE row_value.id = source.source_id)
        WHEN 'user_report' THEN (SELECT to_jsonb(row_value) FROM public.user_reports row_value WHERE row_value.id = source.source_id)
        ELSE NULL
      END
    ) ORDER BY source.created_at ASC
  ), '[]'::JSONB) INTO source_context
  FROM internal.review_case_sources source
  WHERE source.case_id = p_case_id;

  SELECT COALESCE(jsonb_agg(to_jsonb(note_row) ORDER BY note_row.created_at ASC), '[]'::JSONB)
  INTO notes_context
  FROM internal.admin_notes note_row
  WHERE note_row.parent_type = 'review_case' AND note_row.parent_id = p_case_id::TEXT;

  PERFORM internal.write_admin_audit(caller_role, 'review_case_viewed', 'review_case', p_case_id::TEXT);
  RETURN jsonb_build_object(
    'case', to_jsonb(target_case),
    'subject', subject_context,
    'sources', source_context,
    'notes', notes_context,
    'scan', CASE WHEN target_case.case_type = 'identification' THEN (
      SELECT to_jsonb(scan_row) FROM (
        SELECT scan.id, scan.user_id, scan.timestamp, scan.image_storage_urls,
               scan.audio_storage_urls, scan.gps_lat_exact, scan.gps_long_exact,
               scan.ai_confidence_score, scan.human_intervention_notes,
               species.scientific_name, species.common_names
        FROM public.scans scan
        LEFT JOIN public.species_dictionary species ON species.id = scan.species_id
        WHERE scan.id = target_case.subject_id
      ) scan_row
    ) ELSE NULL END
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_update_review_case(
  p_case_id UUID,
  p_status TEXT DEFAULT NULL,
  p_priority TEXT DEFAULT NULL,
  p_assigned_to UUID DEFAULT NULL,
  p_change_assignee BOOLEAN DEFAULT FALSE,
  p_resolution_code TEXT DEFAULT NULL,
  p_note TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_role TEXT;
  before_row internal.review_cases%ROWTYPE;
  after_row internal.review_cases%ROWTYPE;
BEGIN
  caller_role := internal.require_admin('moderator');
  SELECT * INTO before_row FROM internal.review_cases WHERE id = p_case_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Review case not found.' USING ERRCODE = 'P0002'; END IF;

  IF p_status IS NOT NULL AND p_status NOT IN ('open', 'in_review', 'resolved', 'dismissed') THEN
    RAISE EXCEPTION 'Invalid review status.' USING ERRCODE = '22023';
  END IF;
  IF p_priority IS NOT NULL AND p_priority NOT IN ('low', 'normal', 'high', 'urgent') THEN
    RAISE EXCEPTION 'Invalid review priority.' USING ERRCODE = '22023';
  END IF;
  IF COALESCE(p_change_assignee, FALSE) AND p_assigned_to IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM internal.admin_memberships membership
    WHERE membership.user_id = p_assigned_to
      AND membership.is_active = TRUE
      AND membership.role IN ('owner', 'moderator')
  ) THEN
    RAISE EXCEPTION 'Assignee is not an active admin member.' USING ERRCODE = '22023';
  END IF;

  UPDATE internal.review_cases
  SET status = COALESCE(p_status, status),
      priority = COALESCE(p_priority, priority),
      assigned_to = CASE WHEN COALESCE(p_change_assignee, FALSE) THEN p_assigned_to ELSE assigned_to END,
      resolution_code = CASE
        WHEN COALESCE(p_status, status) IN ('resolved', 'dismissed') THEN NULLIF(btrim(p_resolution_code), '')
        ELSE NULL
      END,
      resolved_at = CASE
        WHEN COALESCE(p_status, status) IN ('resolved', 'dismissed') THEN NOW()
        ELSE NULL
      END,
      updated_at = NOW()
  WHERE id = p_case_id
  RETURNING * INTO after_row;

  IF NULLIF(btrim(p_note), '') IS NOT NULL THEN
    INSERT INTO internal.admin_notes (parent_type, parent_id, author_user_id, body)
    VALUES ('review_case', p_case_id::TEXT, auth.uid(), btrim(p_note));
  END IF;

  IF after_row.case_type = 'identification' THEN
    UPDATE public.scans scan
    SET is_flagged = EXISTS (
      SELECT 1 FROM internal.review_cases review
      WHERE review.case_type = 'identification'
        AND review.subject_id = scan.id
        AND review.status IN ('open', 'in_review')
    )
    WHERE scan.id = after_row.subject_id;
  END IF;

  PERFORM internal.write_admin_audit(
    caller_role, 'review_case_updated', 'review_case', p_case_id::TEXT,
    to_jsonb(before_row), to_jsonb(after_row), p_note
  );
  RETURN to_jsonb(after_row);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_content_visibility(
  p_case_id UUID,
  p_hidden BOOLEAN,
  p_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_role TEXT;
  target_case internal.review_cases%ROWTYPE;
  before_state JSONB;
  after_state JSONB;
BEGIN
  caller_role := internal.require_admin('moderator');
  IF char_length(btrim(COALESCE(p_reason, ''))) < 3 THEN
    RAISE EXCEPTION 'A moderation reason is required.' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO target_case FROM internal.review_cases WHERE id = p_case_id;
  IF NOT FOUND OR target_case.case_type NOT IN ('post', 'comment') THEN
    RAISE EXCEPTION 'This case does not target reversible content.' USING ERRCODE = '22023';
  END IF;

  IF target_case.case_type = 'post' THEN
    SELECT jsonb_build_object('moderated_at', post.moderated_at, 'moderated_by', post.moderated_by_user_id)
    INTO before_state FROM public.explore_posts post WHERE post.id = target_case.subject_id;
    IF before_state IS NULL THEN RAISE EXCEPTION 'Review subject not found.' USING ERRCODE = 'P0002'; END IF;
    UPDATE public.explore_posts
    SET moderated_at = CASE WHEN p_hidden THEN NOW() ELSE NULL END,
        moderated_by_user_id = CASE WHEN p_hidden THEN auth.uid() ELSE NULL END
    WHERE id = target_case.subject_id;
    SELECT jsonb_build_object('moderated_at', post.moderated_at, 'moderated_by', post.moderated_by_user_id)
    INTO after_state FROM public.explore_posts post WHERE post.id = target_case.subject_id;
  ELSE
    SELECT jsonb_build_object('moderated_at', comment.moderated_at, 'moderated_by', comment.moderated_by_user_id)
    INTO before_state FROM public.explore_post_comments comment WHERE comment.id = target_case.subject_id;
    IF before_state IS NULL THEN RAISE EXCEPTION 'Review subject not found.' USING ERRCODE = 'P0002'; END IF;
    UPDATE public.explore_post_comments
    SET moderated_at = CASE WHEN p_hidden THEN NOW() ELSE NULL END,
        moderated_by_user_id = CASE WHEN p_hidden THEN auth.uid() ELSE NULL END
    WHERE id = target_case.subject_id;
    SELECT jsonb_build_object('moderated_at', comment.moderated_at, 'moderated_by', comment.moderated_by_user_id)
    INTO after_state FROM public.explore_post_comments comment WHERE comment.id = target_case.subject_id;
  END IF;

  PERFORM internal.write_admin_audit(
    caller_role,
    CASE WHEN p_hidden THEN 'content_hidden' ELSE 'content_restored' END,
    target_case.case_type,
    target_case.subject_id::TEXT,
    before_state,
    after_state,
    p_reason
  );
  RETURN after_state;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_feedback(
  p_source_type TEXT DEFAULT NULL,
  p_status TEXT DEFAULT NULL,
  p_rating TEXT DEFAULT NULL,
  p_app_version TEXT DEFAULT NULL,
  p_cursor_created_at TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL,
  p_limit INTEGER DEFAULT 50
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_role TEXT;
  safe_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
  result JSONB;
BEGIN
  caller_role := internal.require_admin('moderator');
  WITH all_feedback AS (
    SELECT 'community'::TEXT AS source_type, feedback.id AS source_id,
           feedback.user_id, feedback.created_at, NULL::TEXT AS rating, feedback.app_version,
           jsonb_build_object('feedback', feedback.feedback, 'app_version', feedback.app_version,
             'build_number', feedback.build_number, 'platform', feedback.platform,
             'os_version', feedback.os_version) AS payload
    FROM public.community_feedback feedback
    UNION ALL
    SELECT 'survey', survey.id, survey.user_id, survey.created_at,
           survey.satisfaction_rating::TEXT, survey.app_version, to_jsonb(survey)
    FROM public.feedback_survey_responses survey
    UNION ALL
    SELECT 'chat_message', feedback.id, feedback.user_id, feedback.created_at,
           feedback.rating, NULL::TEXT,
           to_jsonb(feedback) || jsonb_build_object(
             'message', (SELECT to_jsonb(message) FROM public.insight_chat_messages message WHERE message.id = feedback.message_id)
           )
    FROM public.insight_chat_message_feedback feedback
    UNION ALL
    SELECT 'chat_feature', feedback.id, feedback.user_id, feedback.created_at,
           feedback.sentiment, NULL::TEXT, to_jsonb(feedback)
    FROM public.insight_chat_feature_feedback feedback
  ), page AS (
    SELECT item.source_type, item.source_id, item.user_id, item.created_at,
           item.rating, item.app_version, item.payload,
           COALESCE(state.status, 'new') AS status,
           state.assigned_to, COALESCE(state.tags, '{}') AS tags,
           app_user.email, app_user.public_username
    FROM all_feedback item
    LEFT JOIN internal.feedback_state state
      ON state.source_type = item.source_type AND state.source_id = item.source_id
    LEFT JOIN public.users app_user ON app_user.id = item.user_id
    WHERE (p_source_type IS NULL OR item.source_type = p_source_type)
      AND (p_status IS NULL OR COALESCE(state.status, 'new') = p_status)
      AND (p_rating IS NULL OR item.rating = p_rating)
      AND (p_app_version IS NULL OR item.app_version = p_app_version)
      AND (
        p_cursor_created_at IS NULL OR p_cursor_id IS NULL
        OR (item.created_at, item.source_id) < (p_cursor_created_at, p_cursor_id)
      )
    ORDER BY item.created_at DESC, item.source_id DESC
    LIMIT safe_limit
  )
  SELECT jsonb_build_object(
    'items', COALESCE(jsonb_agg(to_jsonb(page) ORDER BY page.created_at DESC), '[]'::JSONB),
    'limit', safe_limit,
    'next_cursor', CASE WHEN COUNT(*) = 0 THEN NULL ELSE jsonb_build_object(
      'created_at', (array_agg(page.created_at ORDER BY page.created_at ASC, page.source_id ASC))[1],
      'id', (array_agg(page.source_id ORDER BY page.created_at ASC, page.source_id ASC))[1]
    ) END
  ) INTO result FROM page;

  PERFORM internal.write_admin_audit(caller_role, 'feedback_queue_viewed', 'feedback_queue', NULL);
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_update_feedback(
  p_source_type TEXT,
  p_source_id UUID,
  p_status TEXT,
  p_assigned_to UUID DEFAULT NULL,
  p_tags TEXT[] DEFAULT '{}',
  p_note TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_role TEXT;
  before_state internal.feedback_state%ROWTYPE;
  result internal.feedback_state%ROWTYPE;
BEGIN
  caller_role := internal.require_admin('moderator');
  IF p_source_type NOT IN ('community', 'survey', 'chat_message', 'chat_feature')
    OR p_status NOT IN ('new', 'reviewed', 'planned', 'closed') THEN
    RAISE EXCEPTION 'Invalid feedback source or status.' USING ERRCODE = '22023';
  END IF;
  IF COALESCE(cardinality(p_tags), 0) > 20
    OR EXISTS (SELECT 1 FROM unnest(COALESCE(p_tags, '{}')) tag WHERE char_length(tag) > 40) THEN
    RAISE EXCEPTION 'Feedback tags exceed their bounds.' USING ERRCODE = '22023';
  END IF;
  IF p_assigned_to IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM internal.admin_memberships membership
    WHERE membership.user_id = p_assigned_to
      AND membership.is_active = TRUE
      AND membership.role IN ('owner', 'moderator')
  ) THEN
    RAISE EXCEPTION 'Assignee is not an active reviewer.' USING ERRCODE = '22023';
  END IF;
  IF NOT (
    (p_source_type = 'community' AND EXISTS (SELECT 1 FROM public.community_feedback item WHERE item.id = p_source_id))
    OR (p_source_type = 'survey' AND EXISTS (SELECT 1 FROM public.feedback_survey_responses item WHERE item.id = p_source_id))
    OR (p_source_type = 'chat_message' AND EXISTS (SELECT 1 FROM public.insight_chat_message_feedback item WHERE item.id = p_source_id))
    OR (p_source_type = 'chat_feature' AND EXISTS (SELECT 1 FROM public.insight_chat_feature_feedback item WHERE item.id = p_source_id))
  ) THEN
    RAISE EXCEPTION 'Feedback source not found.' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO before_state
  FROM internal.feedback_state state
  WHERE state.source_type = p_source_type AND state.source_id = p_source_id;

  INSERT INTO internal.feedback_state (source_type, source_id, status, assigned_to, tags)
  VALUES (p_source_type, p_source_id, p_status, p_assigned_to, COALESCE(p_tags, '{}'))
  ON CONFLICT (source_type, source_id) DO UPDATE
    SET status = EXCLUDED.status,
        assigned_to = EXCLUDED.assigned_to,
        tags = EXCLUDED.tags,
        updated_at = NOW()
  RETURNING * INTO result;

  IF NULLIF(btrim(p_note), '') IS NOT NULL THEN
    INSERT INTO internal.admin_notes (parent_type, parent_id, author_user_id, body)
    VALUES ('feedback', p_source_type || ':' || p_source_id::TEXT, auth.uid(), btrim(p_note));
  END IF;

  PERFORM internal.write_admin_audit(
    caller_role, 'feedback_updated', 'feedback', p_source_type || ':' || p_source_id::TEXT,
    CASE WHEN before_state.source_id IS NULL THEN NULL ELSE to_jsonb(before_state) END,
    to_jsonb(result), p_note
  );
  RETURN to_jsonb(result);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_users(
  p_search TEXT DEFAULT NULL,
  p_cursor_created_at TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id UUID DEFAULT NULL,
  p_limit INTEGER DEFAULT 50
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_role TEXT;
  safe_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
  normalized_search TEXT := NULLIF(btrim(p_search), '');
  result JSONB;
BEGIN
  caller_role := internal.require_admin('moderator');
  SELECT jsonb_build_object(
    'items', COALESCE(jsonb_agg(to_jsonb(user_row) ORDER BY user_row.auth_created_at DESC), '[]'::JSONB),
    'limit', safe_limit,
    'next_cursor', CASE WHEN COUNT(*) = 0 THEN NULL ELSE jsonb_build_object(
      'created_at', (array_agg(user_row.auth_created_at ORDER BY user_row.auth_created_at ASC, user_row.id ASC))[1],
      'id', (array_agg(user_row.id ORDER BY user_row.auth_created_at ASC, user_row.id ASC))[1]
    ) END
  ) INTO result
  FROM (
    SELECT
      auth_user.id,
      auth_user.email,
      auth_user.is_anonymous,
      auth_user.created_at AS auth_created_at,
      auth_user.last_sign_in_at,
      COALESCE(auth_user.raw_app_meta_data -> 'providers', '[]'::JSONB) AS providers,
      app_user.public_username,
      app_user.public_author_name,
      app_user.subscription_tier,
      app_user.subscription_expires_at,
      app_user.abuse_strikes,
      app_user.is_shadowbanned,
      CASE WHEN app_user.id IS NULL THEN 'pro_trial'
        ELSE internal.effective_plan(app_user.subscription_tier, app_user.created_at, app_user.subscription_expires_at)
      END AS effective_plan,
      (SELECT COUNT(*) FROM public.scans scan WHERE scan.user_id = auth_user.id AND scan.is_tombstoned = FALSE) AS scan_count,
      (SELECT MAX(scan.timestamp) FROM public.scans scan WHERE scan.user_id = auth_user.id) AS last_scan_at
    FROM auth.users auth_user
    LEFT JOIN public.users app_user ON app_user.id = auth_user.id
    WHERE (
      normalized_search IS NULL
      OR auth_user.id::TEXT ILIKE '%' || normalized_search || '%'
      OR COALESCE(auth_user.email, '') ILIKE '%' || normalized_search || '%'
      OR COALESCE(app_user.public_username, '') ILIKE '%' || normalized_search || '%'
    )
    AND (
      p_cursor_created_at IS NULL OR p_cursor_id IS NULL
      OR (auth_user.created_at, auth_user.id) < (p_cursor_created_at, p_cursor_id)
    )
    ORDER BY auth_user.created_at DESC, auth_user.id DESC
    LIMIT safe_limit
  ) user_row;

  PERFORM internal.write_admin_audit(caller_role, 'users_searched', 'user_directory', NULL);
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_get_user_detail(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_role TEXT;
  result JSONB;
BEGIN
  caller_role := internal.require_admin('moderator');
  IF NOT EXISTS (SELECT 1 FROM auth.users auth_user WHERE auth_user.id = p_user_id) THEN
    RAISE EXCEPTION 'User not found.' USING ERRCODE = 'P0002';
  END IF;

  SELECT jsonb_build_object(
    'auth', (
      SELECT jsonb_build_object(
        'id', auth_user.id,
        'email', auth_user.email,
        'is_anonymous', auth_user.is_anonymous,
        'created_at', auth_user.created_at,
        'last_sign_in_at', auth_user.last_sign_in_at,
        'providers', COALESCE(auth_user.raw_app_meta_data -> 'providers', '[]'::JSONB)
      ) FROM auth.users auth_user WHERE auth_user.id = p_user_id
    ),
    'profile', (
      SELECT to_jsonb(app_user) - 'email'
      FROM public.users app_user WHERE app_user.id = p_user_id
    ),
    'effective_plan', (
      SELECT CASE WHEN app_user.id IS NULL THEN 'pro_trial'
        ELSE internal.effective_plan(app_user.subscription_tier, app_user.created_at, app_user.subscription_expires_at)
      END
      FROM auth.users auth_user
      LEFT JOIN public.users app_user ON app_user.id = auth_user.id
      WHERE auth_user.id = p_user_id
    ),
    'recent_scans', (
      SELECT COALESCE(jsonb_agg(to_jsonb(scan_row) ORDER BY scan_row.timestamp DESC), '[]'::JSONB)
      FROM (
        SELECT scan.id, scan.timestamp, scan.ai_confidence_score, scan.ecology_type,
               scan.is_flagged, scan.is_tombstoned, scan.inference_tier,
               scan.llm_total_tokens, species.scientific_name, species.common_names
        FROM public.scans scan
        LEFT JOIN public.species_dictionary species ON species.id = scan.species_id
        WHERE scan.user_id = p_user_id
        ORDER BY scan.timestamp DESC, scan.id DESC LIMIT 50
      ) scan_row
    ),
    'reports_received', (
      SELECT COALESCE(jsonb_agg(to_jsonb(report_row) ORDER BY report_row.created_at DESC), '[]'::JSONB)
      FROM (
        SELECT report.id, report.reason, report.details, report.status, report.created_at, report.updated_at
        FROM public.user_reports report WHERE report.reported_user_id = p_user_id
        ORDER BY report.created_at DESC LIMIT 50
      ) report_row
    ),
    'reports_submitted', (
      SELECT COALESCE(jsonb_agg(to_jsonb(report_row) ORDER BY report_row.created_at DESC), '[]'::JSONB)
      FROM (
        SELECT report.id, report.reported_user_id, report.reason, report.details, report.status, report.created_at
        FROM public.user_reports report WHERE report.reporter_user_id = p_user_id
        ORDER BY report.created_at DESC LIMIT 50
      ) report_row
    ),
    'review_history', jsonb_build_object(
      'as_subject', (
        SELECT COALESCE(jsonb_agg(to_jsonb(review_row) ORDER BY review_row.updated_at DESC), '[]'::JSONB)
        FROM (
          SELECT review.id, review.case_type, review.subject_id, review.status, review.priority,
                 review.report_count, review.resolution_code, review.updated_at
          FROM internal.review_cases review
          WHERE review.subject_user_id = p_user_id
          ORDER BY review.updated_at DESC LIMIT 100
        ) review_row
      ),
      'as_reporter', (
        SELECT COALESCE(jsonb_agg(to_jsonb(source_row) ORDER BY source_row.created_at DESC), '[]'::JSONB)
        FROM (
          SELECT source.source_type, source.source_id, source.created_at,
                 review.id AS case_id, review.case_type, review.subject_id, review.status
          FROM internal.review_case_sources source
          JOIN internal.review_cases review ON review.id = source.case_id
          WHERE source.reporter_user_id = p_user_id
          ORDER BY source.created_at DESC LIMIT 100
        ) source_row
      )
    ),
    'feedback', (
      SELECT jsonb_build_object(
        'community', COALESCE((SELECT jsonb_agg(to_jsonb(feedback) ORDER BY feedback.created_at DESC) FROM public.community_feedback feedback WHERE feedback.user_id = p_user_id), '[]'::JSONB),
        'surveys', COALESCE((SELECT jsonb_agg(to_jsonb(survey) ORDER BY survey.created_at DESC) FROM public.feedback_survey_responses survey WHERE survey.user_id = p_user_id), '[]'::JSONB),
        'chat_messages', COALESCE((SELECT jsonb_agg(to_jsonb(feedback) ORDER BY feedback.created_at DESC) FROM public.insight_chat_message_feedback feedback WHERE feedback.user_id = p_user_id), '[]'::JSONB),
        'chat_feature', COALESCE((SELECT jsonb_agg(to_jsonb(feedback) ORDER BY feedback.created_at DESC) FROM public.insight_chat_feature_feedback feedback WHERE feedback.user_id = p_user_id), '[]'::JSONB)
      )
    )
  ) INTO result;

  PERFORM internal.write_admin_audit(caller_role, 'user_detail_viewed', 'user', p_user_id::TEXT);
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_ai_usage_summary(
  p_days INTEGER DEFAULT 30,
  p_operation TEXT DEFAULT NULL,
  p_model TEXT DEFAULT NULL,
  p_effective_plan TEXT DEFAULT NULL,
  p_input_modality TEXT DEFAULT NULL,
  p_scan_scope TEXT DEFAULT 'primary',
  p_refresh BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_role TEXT;
  bounded_days INTEGER := LEAST(GREATEST(COALESCE(p_days, 30), 0), 36500);
  start_at TIMESTAMPTZ := CASE WHEN bounded_days = 0 THEN '1970-01-01T00:00:00Z'::TIMESTAMPTZ
    ELSE NOW() - make_interval(days => bounded_days) END;
  cache_key_value TEXT := format(
    'ai:%s:%s:%s:%s:%s:%s', bounded_days, COALESCE(p_operation, '*'), COALESCE(p_model, '*'),
    COALESCE(p_effective_plan, '*'), COALESCE(p_input_modality, '*'), COALESCE(p_scan_scope, 'primary')
  );
  result JSONB;
BEGIN
  caller_role := internal.require_admin('analyst');
  IF COALESCE(p_scan_scope, 'primary') NOT IN ('primary', 'all_scan_related') THEN
    RAISE EXCEPTION 'Invalid scan usage scope.' USING ERRCODE = '22023';
  END IF;
  IF NOT COALESCE(p_refresh, FALSE) THEN
    SELECT cache.payload INTO result FROM internal.admin_aggregate_cache cache
    WHERE cache.cache_key = cache_key_value
      AND cache.created_at > NOW() - INTERVAL '5 minutes';
    IF FOUND THEN
      PERFORM internal.write_admin_audit(caller_role, 'ai_usage_viewed_cached', 'ai_usage', bounded_days::TEXT);
      RETURN result;
    END IF;
  END IF;
  WITH filtered AS MATERIALIZED (
    SELECT * FROM public.ai_usage_events event
    WHERE event.occurred_at >= start_at
      AND (p_operation IS NULL OR event.operation = p_operation)
      AND (p_model IS NULL OR event.model = p_model)
      AND (p_effective_plan IS NULL OR event.effective_plan = p_effective_plan)
      AND (p_input_modality IS NULL OR event.input_modality = p_input_modality)
  ), scan_totals AS (
    SELECT event.scan_id, SUM(COALESCE(event.total_tokens, 0)) AS total_tokens
    FROM filtered event
    WHERE event.scan_id IS NOT NULL
      AND (
        COALESCE(p_scan_scope, 'primary') = 'all_scan_related'
        OR (event.operation = 'scan_identification' AND event.outcome = 'success')
      )
    GROUP BY event.scan_id
  )
  SELECT jsonb_build_object(
    'events', COUNT(*),
    'prompt_tokens', COALESCE(SUM(prompt_tokens), 0),
    'cached_tokens', COALESCE(SUM(cached_tokens), 0),
    'candidate_tokens', COALESCE(SUM(candidate_tokens), 0),
    'thinking_tokens', COALESCE(SUM(thinking_tokens), 0),
    'tool_tokens', COALESCE(SUM(tool_tokens), 0),
    'total_tokens', COALESCE(SUM(total_tokens), 0),
    'estimated_cost_microusd', COALESCE(SUM(estimated_cost_microusd), 0),
    'cache_hit_rate', ROUND(100.0 * COUNT(*) FILTER (WHERE cached_tokens > 0) / NULLIF(COUNT(*) FILTER (WHERE cached_tokens IS NOT NULL), 0), 2),
    'scan_avg', (SELECT ROUND(AVG(scan.total_tokens)) FROM scan_totals scan),
    'scan_p50', (SELECT percentile_cont(0.50) WITHIN GROUP (ORDER BY scan.total_tokens) FROM scan_totals scan),
    'scan_p95', (SELECT percentile_cont(0.95) WITHIN GROUP (ORDER BY scan.total_tokens) FROM scan_totals scan),
    'scan_scope', COALESCE(p_scan_scope, 'primary'),
    'modality_tokens', (
      SELECT COALESCE(jsonb_object_agg(modality_row.modality, modality_row.tokens), '{}'::JSONB)
      FROM (
        SELECT modality.key AS modality, SUM((modality.value #>> '{}')::BIGINT) AS tokens
        FROM filtered event
        CROSS JOIN LATERAL jsonb_each(COALESCE(event.prompt_tokens_by_modality, '{}'::JSONB)) category
        CROSS JOIN LATERAL jsonb_each(
          CASE WHEN jsonb_typeof(category.value) = 'object' THEN category.value ELSE '{}'::JSONB END
        ) modality
        WHERE jsonb_typeof(modality.value) = 'number'
        GROUP BY modality.key
      ) modality_row
    ),
    'complete_from', MIN(occurred_at) FILTER (WHERE is_backfilled = FALSE),
    'daily', (
      SELECT COALESCE(jsonb_agg(to_jsonb(day_row) ORDER BY day_row.day), '[]'::JSONB)
      FROM (
        SELECT date_trunc('day', occurred_at)::DATE AS day,
               COUNT(*) AS events,
               COALESCE(SUM(total_tokens), 0) AS total_tokens,
               COALESCE(SUM(estimated_cost_microusd), 0) AS estimated_cost_microusd
        FROM filtered GROUP BY 1
      ) day_row
    )
  ) INTO result FROM filtered;

  INSERT INTO internal.admin_aggregate_cache (cache_key, payload, created_at)
  VALUES (cache_key_value, result, NOW())
  ON CONFLICT (cache_key) DO UPDATE SET payload = EXCLUDED.payload, created_at = EXCLUDED.created_at;

  PERFORM internal.write_admin_audit(caller_role, 'ai_usage_viewed', 'ai_usage', bounded_days::TEXT);
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_members()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_role TEXT;
  result JSONB;
BEGIN
  caller_role := internal.require_admin('owner');
  SELECT COALESCE(jsonb_agg(to_jsonb(member_row) ORDER BY member_row.created_at ASC), '[]'::JSONB)
  INTO result
  FROM (
    SELECT membership.user_id, auth_user.email, membership.role, membership.is_active,
           membership.created_at, membership.updated_at
    FROM internal.admin_memberships membership
    JOIN auth.users auth_user ON auth_user.id = membership.user_id
  ) member_row;
  PERFORM internal.write_admin_audit(caller_role, 'admin_members_viewed', 'admin_membership', NULL);
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_upsert_member(
  p_email TEXT,
  p_role TEXT,
  p_is_active BOOLEAN DEFAULT TRUE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_role TEXT;
  target_user auth.users%ROWTYPE;
  before_row internal.admin_memberships%ROWTYPE;
  after_row internal.admin_memberships%ROWTYPE;
  active_owner_count INTEGER;
BEGIN
  caller_role := internal.require_admin('owner');
  IF p_role NOT IN ('owner', 'moderator', 'analyst') THEN
    RAISE EXCEPTION 'Invalid admin role.' USING ERRCODE = '22023';
  END IF;
  SELECT * INTO target_user FROM auth.users
  WHERE lower(email) = lower(btrim(p_email))
    AND is_anonymous = FALSE
    AND email_confirmed_at IS NOT NULL
  ORDER BY created_at ASC LIMIT 1;
  IF NOT FOUND OR NOT EXISTS (
    SELECT 1 FROM auth.identities identity
    WHERE identity.user_id = target_user.id AND identity.provider = 'google'
  ) THEN
    RAISE EXCEPTION 'No verified Google user exists for that email.' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO before_row FROM internal.admin_memberships WHERE user_id = target_user.id;
  IF FOUND AND before_row.role = 'owner' AND before_row.is_active = TRUE
    AND (p_role <> 'owner' OR p_is_active = FALSE) THEN
    LOCK TABLE internal.admin_memberships IN EXCLUSIVE MODE;
    SELECT COUNT(*) INTO active_owner_count FROM internal.admin_memberships
    WHERE role = 'owner' AND is_active = TRUE;
    IF active_owner_count <= 1 THEN
      RAISE EXCEPTION 'The final active owner cannot be disabled or demoted.' USING ERRCODE = '23514';
    END IF;
  END IF;

  INSERT INTO internal.admin_memberships (user_id, role, is_active, created_by)
  VALUES (target_user.id, p_role, p_is_active, auth.uid())
  ON CONFLICT (user_id) DO UPDATE
    SET role = EXCLUDED.role, is_active = EXCLUDED.is_active, updated_at = NOW()
  RETURNING * INTO after_row;

  IF p_is_active = FALSE THEN
    UPDATE internal.admin_sessions SET revoked_at = NOW()
    WHERE user_id = target_user.id AND revoked_at IS NULL;
  END IF;

  PERFORM internal.write_admin_audit(
    caller_role, 'admin_member_updated', 'admin_membership', target_user.id::TEXT,
    CASE WHEN before_row.user_id IS NULL THEN NULL ELSE to_jsonb(before_row) END,
    to_jsonb(after_row), NULL
  );
  RETURN to_jsonb(after_row) || jsonb_build_object('email', target_user.email);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_sessions()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_role TEXT;
  result JSONB;
BEGIN
  caller_role := internal.require_admin('owner');
  SELECT COALESCE(jsonb_agg(to_jsonb(session_row) ORDER BY session_row.created_at DESC), '[]'::JSONB)
  INTO result
  FROM (
    SELECT session.id AS session_id, session.user_id, auth_user.email,
           session.created_at, session.updated_at AS auth_updated_at,
           admin_session.last_seen_at, admin_session.expires_at, admin_session.revoked_at
    FROM auth.sessions session
    JOIN auth.users auth_user ON auth_user.id = session.user_id
    LEFT JOIN internal.admin_sessions admin_session ON admin_session.session_id = session.id
    WHERE EXISTS (
      SELECT 1 FROM internal.admin_memberships membership
      WHERE membership.user_id = session.user_id
    )
  ) session_row;
  PERFORM internal.write_admin_audit(caller_role, 'admin_sessions_viewed', 'admin_session', NULL);
  RETURN result;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_revoke_session(p_session_id UUID, p_reason TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_role TEXT;
BEGIN
  caller_role := internal.require_admin('owner');
  IF char_length(btrim(COALESCE(p_reason, ''))) < 3 THEN
    RAISE EXCEPTION 'A revocation reason is required.' USING ERRCODE = '22023';
  END IF;
  UPDATE internal.admin_sessions SET revoked_at = NOW()
  WHERE session_id = p_session_id AND revoked_at IS NULL;
  IF NOT FOUND THEN RETURN FALSE; END IF;
  DELETE FROM auth.sessions WHERE id = p_session_id;
  PERFORM internal.write_admin_audit(
    caller_role, 'admin_session_revoked', 'session', p_session_id::TEXT,
    NULL, jsonb_build_object('revoked', TRUE), p_reason
  );
  RETURN TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_audit(
  p_action TEXT DEFAULT NULL,
  p_cursor_created_at TIMESTAMPTZ DEFAULT NULL,
  p_cursor_id BIGINT DEFAULT NULL,
  p_limit INTEGER DEFAULT 50
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  caller_role TEXT;
  safe_limit INTEGER := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
  result JSONB;
BEGIN
  caller_role := internal.require_admin('owner');
  SELECT jsonb_build_object(
    'items', COALESCE(jsonb_agg(to_jsonb(audit_row) ORDER BY audit_row.created_at DESC, audit_row.id DESC), '[]'::JSONB),
    'limit', safe_limit,
    'next_cursor', CASE WHEN COUNT(*) = 0 THEN NULL ELSE jsonb_build_object(
      'created_at', (array_agg(audit_row.created_at ORDER BY audit_row.created_at ASC, audit_row.id ASC))[1],
      'id', (array_agg(audit_row.id ORDER BY audit_row.created_at ASC, audit_row.id ASC))[1]
    ) END
  ) INTO result
  FROM (
    SELECT log.id, log.actor_user_id, auth_user.email AS actor_email,
           log.actor_role, log.action, log.target_type, log.target_id,
           log.request_id, log.before_state, log.after_state, log.reason, log.created_at
    FROM internal.admin_audit_log log
    JOIN auth.users auth_user ON auth_user.id = log.actor_user_id
    WHERE (p_action IS NULL OR log.action = p_action)
      AND (
        p_cursor_created_at IS NULL OR p_cursor_id IS NULL
        OR (log.created_at, log.id) < (p_cursor_created_at, p_cursor_id)
      )
    ORDER BY log.created_at DESC, log.id DESC
    LIMIT safe_limit
  ) audit_row;
  PERFORM internal.write_admin_audit(caller_role, 'audit_history_viewed', 'admin_audit_log', NULL);
  RETURN result;
END;
$$;

-- Public RPCs are deny-by-default, then granted to the exact runtime role.
REVOKE ALL ON FUNCTION public.admin_get_access_state() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_begin_session() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_get_overview(INTEGER, TEXT, BOOLEAN) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_review_cases(TEXT, TEXT, TEXT, UUID, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ, UUID, INTEGER) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_get_review_case(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_update_review_case(UUID, TEXT, TEXT, UUID, BOOLEAN, TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_content_visibility(UUID, BOOLEAN, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_feedback(TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, UUID, INTEGER) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_update_feedback(TEXT, UUID, TEXT, UUID, TEXT[], TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_users(TEXT, TIMESTAMPTZ, UUID, INTEGER) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_get_user_detail(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_ai_usage_summary(INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_members() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_upsert_member(TEXT, TEXT, BOOLEAN) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_sessions() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_revoke_session(UUID, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_audit(TEXT, TIMESTAMPTZ, BIGINT, INTEGER) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_ai_usage_event(TEXT, TEXT, TEXT, TEXT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, JSONB, TEXT, UUID, UUID, UUID, UUID, TEXT, UUID, JSONB, TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;

GRANT EXECUTE ON FUNCTION public.admin_get_access_state() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_begin_session() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_overview(INTEGER, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_review_cases(TEXT, TEXT, TEXT, UUID, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TIMESTAMPTZ, UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_review_case(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_review_case(UUID, TEXT, TEXT, UUID, BOOLEAN, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_content_visibility(UUID, BOOLEAN, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_feedback(TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_feedback(TEXT, UUID, TEXT, UUID, TEXT[], TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_users(TEXT, TIMESTAMPTZ, UUID, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_user_detail(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_ai_usage_summary(INTEGER, TEXT, TEXT, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_members() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_upsert_member(TEXT, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_sessions() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_revoke_session(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_audit(TEXT, TIMESTAMPTZ, BIGINT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_ai_usage_event(TEXT, TEXT, TEXT, TEXT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, BIGINT, JSONB, TEXT, UUID, UUID, UUID, UUID, TEXT, UUID, JSONB, TIMESTAMPTZ) TO service_role;

-- No direct runtime access to the internal implementation functions.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA internal FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
