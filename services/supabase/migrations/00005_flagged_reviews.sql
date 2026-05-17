ALTER TABLE public.scans ADD COLUMN IF NOT EXISTS is_flagged BOOLEAN NOT NULL DEFAULT false;

CREATE TABLE public.flagged_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    scan_id UUID NOT NULL REFERENCES public.scans(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    flag_reason TEXT NOT NULL,
    user_suggestion TEXT,
    status TEXT NOT NULL DEFAULT 'PENDING_REVIEW',
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

ALTER TABLE public.flagged_reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert their own flagged reviews" ON public.flagged_reviews FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can fully read their own flagged reviews" ON public.flagged_reviews FOR SELECT USING (auth.uid() = user_id);
