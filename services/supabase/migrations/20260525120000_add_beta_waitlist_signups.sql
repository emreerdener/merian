CREATE TABLE IF NOT EXISTS public.beta_waitlist_signups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT NOT NULL,
    email_normalized TEXT GENERATED ALWAYS AS (LOWER(BTRIM(email))) STORED,
    source TEXT NOT NULL DEFAULT 'web_waitlist',
    user_agent TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS beta_waitlist_signups_email_normalized_key
    ON public.beta_waitlist_signups (email_normalized);

ALTER TABLE public.beta_waitlist_signups ENABLE ROW LEVEL SECURITY;
