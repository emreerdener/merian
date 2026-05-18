create table if not exists public.scan_import_jobs (
  id uuid primary key default gen_random_uuid(),
  scan_id uuid not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'queued' check (status in ('queued', 'processing', 'completed', 'failed')),
  r2_object_key text not null,
  mime_type text not null,
  response_status integer,
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists scan_import_jobs_scan_user_idx
  on public.scan_import_jobs (scan_id, user_id);

create index if not exists scan_import_jobs_user_status_idx
  on public.scan_import_jobs (user_id, status, created_at desc);

alter table public.scan_import_jobs enable row level security;

drop policy if exists "scan_import_jobs_select_own" on public.scan_import_jobs;
create policy "scan_import_jobs_select_own"
  on public.scan_import_jobs
  for select
  to authenticated
  using (auth.uid() = user_id);
