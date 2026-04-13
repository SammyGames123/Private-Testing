create extension if not exists "pgcrypto";

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = timezone('utc', now());
  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text unique,
  username text unique,
  display_name text,
  avatar_url text,
  bio text,
  interests text[] not null default '{}',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.videos (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references public.profiles (id) on delete cascade,
  playback_url text,
  thumbnail_url text,
  storage_path text,
  title text not null,
  caption text,
  category text,
  duration_seconds integer,
  visibility text not null default 'public' check (visibility in ('public', 'private', 'unlisted')),
  is_pinned boolean not null default false,
  is_archived boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.videos add column if not exists is_pinned boolean not null default false;
alter table public.videos add column if not exists is_archived boolean not null default false;

create table if not exists public.video_tags (
  video_id uuid not null references public.videos (id) on delete cascade,
  tag text not null,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (video_id, tag)
);

create table if not exists public.follows (
  follower_id uuid not null references public.profiles (id) on delete cascade,
  following_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (follower_id, following_id),
  constraint follows_no_self_follow check (follower_id <> following_id)
);

create table if not exists public.likes (
  user_id uuid not null references public.profiles (id) on delete cascade,
  video_id uuid not null references public.videos (id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now()),
  primary key (user_id, video_id)
);

create table if not exists public.comments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  video_id uuid not null references public.videos (id) on delete cascade,
  parent_comment_id uuid references public.comments (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.watch_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles (id) on delete cascade,
  video_id uuid not null references public.videos (id) on delete cascade,
  watch_seconds integer not null default 0,
  completed boolean not null default false,
  rewatch_count integer not null default 0,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.message_threads (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.thread_participants (
  thread_id uuid not null references public.message_threads (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default timezone('utc', now()),
  primary key (thread_id, user_id)
);

create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.message_threads (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default timezone('utc', now())
);

create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute function public.set_updated_at();

create trigger videos_set_updated_at
before update on public.videos
for each row
execute function public.set_updated_at();

create trigger comments_set_updated_at
before update on public.comments
for each row
execute function public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.videos enable row level security;
alter table public.video_tags enable row level security;
alter table public.follows enable row level security;
alter table public.likes enable row level security;
alter table public.comments enable row level security;
alter table public.watch_events enable row level security;
alter table public.message_threads enable row level security;
alter table public.thread_participants enable row level security;
alter table public.messages enable row level security;

drop policy if exists "profiles are viewable by everyone" on public.profiles;
create policy "profiles are viewable by everyone"
on public.profiles for select
to authenticated
using (true);

drop policy if exists "users can insert their own profile" on public.profiles;
create policy "users can insert their own profile"
on public.profiles for insert
to authenticated
with check (auth.uid() = id);

drop policy if exists "users can update their own profile" on public.profiles;
create policy "users can update their own profile"
on public.profiles for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

drop policy if exists "public videos are viewable by everyone signed in" on public.videos;
create policy "public videos are viewable by everyone signed in"
on public.videos for select
to authenticated
using ((visibility = 'public' and is_archived = false) or creator_id = auth.uid());

drop policy if exists "creators can insert their own videos" on public.videos;
create policy "creators can insert their own videos"
on public.videos for insert
to authenticated
with check (creator_id = auth.uid());

drop policy if exists "creators can update their own videos" on public.videos;
create policy "creators can update their own videos"
on public.videos for update
to authenticated
using (creator_id = auth.uid())
with check (creator_id = auth.uid());

drop policy if exists "creators can delete their own videos" on public.videos;
create policy "creators can delete their own videos"
on public.videos for delete
to authenticated
using (creator_id = auth.uid());

drop policy if exists "video tags follow video visibility" on public.video_tags;
create policy "video tags follow video visibility"
on public.video_tags for select
to authenticated
using (
  exists (
    select 1
    from public.videos
    where public.videos.id = video_id
      and (public.videos.visibility = 'public' or public.videos.creator_id = auth.uid())
  )
);

drop policy if exists "creators manage tags on own videos" on public.video_tags;
create policy "creators manage tags on own videos"
on public.video_tags for all
to authenticated
using (
  exists (
    select 1
    from public.videos
    where public.videos.id = video_id
      and public.videos.creator_id = auth.uid()
  )
)
with check (
  exists (
    select 1
    from public.videos
    where public.videos.id = video_id
      and public.videos.creator_id = auth.uid()
  )
);

drop policy if exists "authenticated users can see follows" on public.follows;
create policy "authenticated users can see follows"
on public.follows for select
to authenticated
using (true);

drop policy if exists "users can manage their own follows" on public.follows;
create policy "users can manage their own follows"
on public.follows for all
to authenticated
using (follower_id = auth.uid())
with check (follower_id = auth.uid());

drop policy if exists "authenticated users can see likes" on public.likes;
create policy "authenticated users can see likes"
on public.likes for select
to authenticated
using (true);

drop policy if exists "users can manage their own likes" on public.likes;
create policy "users can manage their own likes"
on public.likes for all
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "authenticated users can see comments" on public.comments;
create policy "authenticated users can see comments"
on public.comments for select
to authenticated
using (true);

drop policy if exists "users can create their own comments" on public.comments;
create policy "users can create their own comments"
on public.comments for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "users can update their own comments" on public.comments;
create policy "users can update their own comments"
on public.comments for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "users can delete their own comments" on public.comments;
create policy "users can delete their own comments"
on public.comments for delete
to authenticated
using (user_id = auth.uid());

drop policy if exists "users can see their own watch events" on public.watch_events;
create policy "users can see their own watch events"
on public.watch_events for select
to authenticated
using (user_id = auth.uid());

drop policy if exists "users can create their own watch events" on public.watch_events;
create policy "users can create their own watch events"
on public.watch_events for insert
to authenticated
with check (user_id = auth.uid());

drop policy if exists "users can update their own watch events" on public.watch_events;
create policy "users can update their own watch events"
on public.watch_events for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

drop policy if exists "participants can see threads" on public.message_threads;
create policy "participants can see threads"
on public.message_threads for select
to authenticated
using (
  exists (
    select 1
    from public.thread_participants
    where public.thread_participants.thread_id = id
      and public.thread_participants.user_id = auth.uid()
  )
);

drop policy if exists "users can create threads they own" on public.message_threads;
create policy "users can create threads they own"
on public.message_threads for insert
to authenticated
with check (created_by = auth.uid());

drop policy if exists "participants can see thread participants" on public.thread_participants;
create policy "participants can see thread participants"
on public.thread_participants for select
to authenticated
using (
  exists (
    select 1
    from public.thread_participants as tp
    where tp.thread_id = thread_id
      and tp.user_id = auth.uid()
  )
);

drop policy if exists "thread creators add participants" on public.thread_participants;
create policy "thread creators add participants"
on public.thread_participants for insert
to authenticated
with check (
  exists (
    select 1
    from public.message_threads
    where public.message_threads.id = thread_id
      and public.message_threads.created_by = auth.uid()
  )
);

drop policy if exists "participants can see messages" on public.messages;
create policy "participants can see messages"
on public.messages for select
to authenticated
using (
  exists (
    select 1
    from public.thread_participants
    where public.thread_participants.thread_id = thread_id
      and public.thread_participants.user_id = auth.uid()
  )
);

drop policy if exists "participants can send messages" on public.messages;
create policy "participants can send messages"
on public.messages for insert
to authenticated
with check (
  sender_id = auth.uid()
  and exists (
    select 1
    from public.thread_participants
    where public.thread_participants.thread_id = thread_id
      and public.thread_participants.user_id = auth.uid()
  )
);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, username, display_name)
  values (
    new.id,
    new.email,
    split_part(new.email, '@', 1),
    split_part(new.email, '@', 1)
  )
  on conflict (id) do update
  set email = excluded.email;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row
execute procedure public.handle_new_user();

insert into public.profiles (id, email, username, display_name)
select
  users.id,
  users.email,
  split_part(users.email, '@', 1),
  split_part(users.email, '@', 1)
from auth.users as users
where not exists (
  select 1
  from public.profiles
  where public.profiles.id = users.id
);
