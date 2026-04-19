-- Store APNs device tokens for push notifications
create table if not exists public.push_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  device_token text not null,
  created_at timestamptz default now(),
  unique(user_id, device_token)
);

alter table public.push_tokens enable row level security;

create policy "users manage their own tokens"
  on public.push_tokens for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Allow Edge Functions (service role) to read all tokens
create policy "service role reads all tokens"
  on public.push_tokens for select
  using (auth.role() = 'service_role');
