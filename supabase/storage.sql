insert into storage.buckets (id, name, public)
values ('videos', 'videos', true)
on conflict (id) do update
set public = excluded.public;

drop policy if exists "Public can view videos bucket" on storage.objects;
create policy "Public can view videos bucket"
on storage.objects for select
to public
using (bucket_id = 'videos');

drop policy if exists "Authenticated users can upload to own video folder" on storage.objects;
create policy "Authenticated users can upload to own video folder"
on storage.objects for insert
to authenticated
with check (
  bucket_id = 'videos'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

drop policy if exists "Users can update their own video files" on storage.objects;
create policy "Users can update their own video files"
on storage.objects for update
to authenticated
using (
  bucket_id = 'videos'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
)
with check (
  bucket_id = 'videos'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);

drop policy if exists "Users can delete their own video files" on storage.objects;
create policy "Users can delete their own video files"
on storage.objects for delete
to authenticated
using (
  bucket_id = 'videos'
  and (storage.foldername(name))[1] = (select auth.uid()::text)
);
