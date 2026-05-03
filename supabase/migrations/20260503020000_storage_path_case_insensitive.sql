-- Make item-photos folder-prefix RLS comparisons case-insensitive.
-- Postgres formats `auth.uid()::text` lowercase, Swift's UUID().uuidString
-- formats uppercase. Without `lower()` on both sides, every upload from the
-- iOS client is RLS-denied and the customer's offer post falls through to
-- the "local fallback" path so no driver ever sees the job.
--
-- Also drop the legacy "Anyone can upload"/"Anyone can read" policies that
-- were created via the Supabase dashboard before any migrations existed.
-- Postgres OR's policies, so leaving these in place makes every restriction
-- below useless: any authenticated user can upload anywhere in the bucket
-- and read every other user's photos.

drop policy if exists "Anyone can upload" on storage.objects;
drop policy if exists "Anyone can read" on storage.objects;
drop policy if exists "item-photos: customer can upload to own folder" on storage.objects;
drop policy if exists "item-photos: customer can read own uploads" on storage.objects;

create policy "item-photos: customer can upload to own folder"
  on storage.objects for insert
  with check (
    bucket_id = 'item-photos'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
  );

create policy "item-photos: customer can read own uploads"
  on storage.objects for select
  using (
    bucket_id = 'item-photos'
    and lower((storage.foldername(name))[1]) = lower(auth.uid()::text)
  );
