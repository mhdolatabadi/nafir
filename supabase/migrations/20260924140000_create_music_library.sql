-- Private per-user music library for SOT.
-- Apply with: supabase db push

create table if not exists public.tracks (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  title text not null check (char_length(title) between 1 and 300),
  artist text,
  album text,
  duration_ms integer check (duration_ms is null or duration_ms >= 0),
  storage_path text not null unique,
  artwork_path text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tracks_must_live_in_owners_folder check (
    storage_path like ('users/' || owner_id::text || '/tracks/%')
  )
);

alter table public.tracks enable row level security;

create policy "Users can view their own tracks"
  on public.tracks for select
  using (auth.uid() = owner_id);

create policy "Users can insert their own tracks"
  on public.tracks for insert
  with check (auth.uid() = owner_id);

create policy "Users can update their own tracks"
  on public.tracks for update
  using (auth.uid() = owner_id)
  with check (auth.uid() = owner_id);

create policy "Users can delete their own tracks"
  on public.tracks for delete
  using (auth.uid() = owner_id);

insert into storage.buckets (id, name, public)
values ('music', 'music', false)
on conflict (id) do update set public = false;

create policy "Users can read their own music objects"
  on storage.objects for select
  using (
    bucket_id = 'music'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

create policy "Users can upload to their own music folder"
  on storage.objects for insert
  with check (
    bucket_id = 'music'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

create policy "Users can update their own music objects"
  on storage.objects for update
  using (
    bucket_id = 'music'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
  )
  with check (
    bucket_id = 'music'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
  );

create policy "Users can delete their own music objects"
  on storage.objects for delete
  using (
    bucket_id = 'music'
    and (storage.foldername(name))[1] = 'users'
    and (storage.foldername(name))[2] = auth.uid()::text
  );
