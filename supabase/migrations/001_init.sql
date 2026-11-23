-- SongNotes schema: one row per song you've noted, many notes per song.

create table if not exists public.tracks (
  persistent_id  text primary key,          -- Apple Music's stable track ID
  title          text not null,
  artist         text,
  album          text,
  duration_s     int,
  bpm            int,
  genre          text,
  in_library     boolean not null default true,
  first_noted_at timestamptz not null default now()
);

create table if not exists public.notes (
  id            uuid primary key default gen_random_uuid(),
  persistent_id text not null references public.tracks(persistent_id) on delete cascade,
  raw_text      text not null,
  source        text not null default 'typed' check (source in ('typed', 'voice')),
  created_at    timestamptz not null default now(),
  -- filled in by Claude after the note is saved
  vibes         text[] not null default '{}',
  energy        int check (energy between 1 and 5),
  set_role      text check (set_role in ('opener','warmup','build','peak','cooldown','closer','none')),
  tags          text[] not null default '{}',
  ai_summary    text,
  tag_status    text not null default 'pending' check (tag_status in ('pending','done','failed'))
);

create index if not exists notes_persistent_id_idx on public.notes (persistent_id);
create index if not exists notes_vibes_idx on public.notes using gin (vibes);
create index if not exists notes_tags_idx on public.notes using gin (tags);

-- Personal tool: RLS on, no public policies. Only the secret/service key (kept on your Mac) can read/write.
alter table public.tracks enable row level security;
alter table public.notes  enable row level security;

-- One row per song with every note merged. Build playlists from this.
create or replace view public.track_profile with (security_invoker = true) as
select
  t.persistent_id, t.title, t.artist, t.album, t.duration_s, t.bpm, t.genre, t.in_library,
  coalesce((select array_agg(distinct v order by v) from public.notes n, unnest(n.vibes) v
            where n.persistent_id = t.persistent_id), '{}') as vibes,
  coalesce((select array_agg(distinct g order by g) from public.notes n, unnest(n.tags) g
            where n.persistent_id = t.persistent_id), '{}') as tags,
  (select n.energy from public.notes n where n.persistent_id = t.persistent_id and n.energy is not null
   order by n.created_at desc limit 1) as energy,
  (select n.set_role from public.notes n where n.persistent_id = t.persistent_id and n.set_role is not null
   and n.set_role <> 'none' order by n.created_at desc limit 1) as set_role,
  (select string_agg(n.raw_text, ' | ' order by n.created_at) from public.notes n
   where n.persistent_id = t.persistent_id) as all_notes,
  (select count(*) from public.notes n where n.persistent_id = t.persistent_id) as note_count,
  (select max(n.created_at) from public.notes n where n.persistent_id = t.persistent_id) as last_noted_at
from public.tracks t;

-- Every label you've used and how many songs carry it (feeds the "Make playlist" menu).
create or replace view public.tag_counts with (security_invoker = true) as
select label, kind, count(distinct persistent_id)::int as songs
from (
  select unnest(vibes) as label, 'vibe' as kind, persistent_id from public.notes
  union all
  select unnest(tags), 'tag', persistent_id from public.notes
  union all
  select set_role, 'role', persistent_id from public.notes where set_role is not null and set_role <> 'none'
) x
group by label, kind
order by songs desc, label;
