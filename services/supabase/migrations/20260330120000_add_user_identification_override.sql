-- user_identification_override: stores the scientific name selected by the user when they
-- disagree with the AI's primary identification. NULL means no override has been applied.
-- A companion column `user_confirmed_identification` (see migration 20260330130000) records
-- explicit positive confirmation ("Yes, correct"). Both are synced to the client.
ALTER TABLE public.scans
    ADD COLUMN IF NOT EXISTS user_identification_override TEXT DEFAULT NULL;
