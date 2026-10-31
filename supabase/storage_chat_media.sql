-- Run once in the Supabase SQL editor (after the backend's sql/019_chat_files.sql).
-- Private bucket for chat videos and audio files: at most 35 MB each (the
-- bucket refuses anything bigger). The app uploads only into its own
-- <user id>/ folder, at the path the API hands out. Nobody reads the bucket
-- directly: the API checks who is in the conversation and gives them a
-- short-lived signed download link.
--
-- Supabase's project-wide upload limit must be at least this big
-- (Project Settings → Storage → "Upload file size limit"); the Free plan's
-- 50 MB is enough.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'chat-media',
  'chat-media',
  false,
  36700160,
  array[
    'video/mp4', 'video/quicktime', 'video/webm', 'video/3gpp', 'video/x-matroska',
    'audio/mpeg', 'audio/mp4', 'audio/m4a', 'audio/x-m4a', 'audio/aac',
    'audio/wav', 'audio/x-wav', 'audio/wave', 'audio/ogg', 'audio/opus',
    'audio/flac', 'audio/x-flac', 'audio/webm'
  ]
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "chat_media_owner_insert" on storage.objects;
create policy "chat_media_owner_insert" on storage.objects for insert to authenticated
  with check (bucket_id = 'chat-media' and (storage.foldername(name))[1] = auth.uid()::text);

-- Lets a resumable upload check on itself; people can only see their own
-- uploads, never anyone else's.
drop policy if exists "chat_media_owner_select" on storage.objects;
create policy "chat_media_owner_select" on storage.objects for select to authenticated
  using (bucket_id = 'chat-media' and (storage.foldername(name))[1] = auth.uid()::text);
