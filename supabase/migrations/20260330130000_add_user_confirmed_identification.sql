-- Adds a boolean flag that records whether the user explicitly confirmed the AI's
-- primary identification as correct via the CandidatesCard review prompt.
-- This is distinct from `user_identification_override` (which stores a chosen alternative);
-- a confirmed=true row means the user actively agreed with the AI, providing ground-truth
-- positive feedback for identification accuracy research.
ALTER TABLE public.scans
    ADD COLUMN IF NOT EXISTS user_confirmed_identification BOOLEAN DEFAULT FALSE;
