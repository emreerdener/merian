CREATE TYPE export_status AS ENUM ('pending', 'processing', 'completed', 'failed');

CREATE TABLE public.export_jobs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    export_scope TEXT NOT NULL DEFAULT 'user',
    include_precise_coordinates BOOLEAN NOT NULL DEFAULT true,
    status export_status NOT NULL DEFAULT 'pending',
    file_url TEXT,
    error_message TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ
);

ALTER TABLE public.export_jobs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert their own export jobs."
    ON public.export_jobs FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view their own export jobs."
    ON public.export_jobs FOR SELECT
    USING (auth.uid() = user_id);

-- PostgreSQL function to trigger the processing webhook
CREATE OR REPLACE FUNCTION public.trigger_export_dwca_webhook()
RETURNS TRIGGER AS $$
DECLARE
    project_url text;
    service_role_key text;
    edge_endpoint text;
    payload jsonb;
BEGIN
    SELECT decrypted_secret INTO project_url FROM vault.decrypted_secrets WHERE name = 'SUPABASE_URL' LIMIT 1;
    SELECT decrypted_secret INTO service_role_key FROM vault.decrypted_secrets WHERE name = 'SUPABASE_SERVICE_ROLE_KEY' LIMIT 1;
    
    IF project_url IS NULL THEN
        project_url := current_setting('app.settings.supabase_url', true);
    END IF;
    IF service_role_key IS NULL THEN
        service_role_key := current_setting('app.settings.service_role_key', true);
    END IF;

    -- Using the local loopback proxy or external API gateway for functions
    edge_endpoint := project_url || '/functions/v1/export-dwca';

    -- Build payload to pass the job ID and user ID
    payload := jsonb_build_object(
        'job_id', NEW.id,
        'user_id', NEW.user_id,
        'export_scope', NEW.export_scope,
        'include_precise_coordinates', NEW.include_precise_coordinates
    );

    PERFORM net.http_post(
        url := edge_endpoint,
        headers := jsonb_build_object(
            'Content-Type', 'application/json',
            'Authorization', 'Bearer ' || service_role_key
        ),
        body := payload
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_export_job_created
    AFTER INSERT ON public.export_jobs
    FOR EACH ROW
    EXECUTE FUNCTION public.trigger_export_dwca_webhook();
