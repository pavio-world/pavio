-- Migration 18: directory search, search appearances and Search_Trust.
-- Spec 00 Req 14.22, 16.6 to 16.10, 22.1 to 22.5, 24.1 to 24.11, NQ-2, NQ-4, NQ-6; design
-- "search_directory", "Helper functions" (search_trust), "search_appearances and
-- search_appearance_marks", "Row Level Security policies", "Grants and revokes strategy", "Error Handling".
-- Only public data is searched: names, handles, what_i_do tags, public bios, city and business category.
-- The weekly summary that reads search_appearances comes with migration 19.

-- ---------------------------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------------------------
create table public.search_appearances (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  appeared_on date not null,
  count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint search_appearances_count_check check (count >= 0),
  -- One row per profile and Nairobi day (Req 16.6); also the leading index of the profile foreign key.
  constraint search_appearances_profile_day_key unique (profile_id, appeared_on)
);
create trigger search_appearances_set_updated_at
  before update on public.search_appearances
  for each row execute function private.set_updated_at();

-- Remembers which signed in searcher already counted for which profile on which day (Req 16.7).
-- Internal only: no grant and no policy for the API roles.
create table public.search_appearance_marks (
  id uuid primary key default gen_random_uuid(),
  searcher_profile_id uuid not null references public.profiles (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  appeared_on date not null,
  created_at timestamptz not null default now(),
  constraint search_appearance_marks_searcher_profile_day_key
    unique (searcher_profile_id, profile_id, appeared_on)
);
create index search_appearance_marks_profile_id_idx on public.search_appearance_marks (profile_id);

-- ---------------------------------------------------------------------------------------------
-- Row Level Security and grants (Req 16.9, 16.10, 22.1 to 22.3, 22.5).
-- Only the owner of the profile reads its appearances. Nobody writes through the API: the writes
-- happen inside private.record_search_appearances, called by search_directory.
-- ---------------------------------------------------------------------------------------------
alter table public.search_appearances enable row level security;
revoke all on table public.search_appearances from anon, authenticated;
grant select on table public.search_appearances to authenticated;
create policy search_appearances_authenticated_select on public.search_appearances
  for select to authenticated
  using (public.acts_as(profile_id));

alter table public.search_appearance_marks enable row level security;
revoke all on table public.search_appearance_marks from anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- Search_Trust (NQ-2, NQ-4, Req 14.22): featured public vouches about the subject. One vouch per
-- author and subject, so this counts distinct authors. Hidden vouches still count.
-- ---------------------------------------------------------------------------------------------
create or replace function private.search_trust(p_profile uuid)
returns integer
language sql
stable
security definer
set search_path = ''
as $$
  select count(*)::integer
  from public.vouches v
  where v.subject_profile_id = p_profile
    and v.top8_position is not null
    and v.audience = 'public';
$$;
revoke execute on function private.search_trust(uuid) from public;
revoke execute on function private.search_trust(uuid) from anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- Appearance recording (Req 16.6 to 16.8, NQ-6).
-- Anonymous: +1 per returned profile on every search.
-- Signed in: +1 at most once per searcher, profile and Nairobi day, through the marks table.
-- ---------------------------------------------------------------------------------------------
create or replace function private.record_search_appearances(p_profiles uuid[], p_searcher uuid)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_day date := private.nairobi_today();
begin
  if p_searcher is null then
    insert into public.search_appearances (profile_id, appeared_on, count)
    select x, v_day, 1 from unnest(p_profiles) as x
    on conflict (profile_id, appeared_on)
      do update set count = public.search_appearances.count + 1;
  else
    with fresh as (
      insert into public.search_appearance_marks (searcher_profile_id, profile_id, appeared_on)
      select p_searcher, x, v_day from unnest(p_profiles) as x
      on conflict do nothing
      returning profile_id
    )
    insert into public.search_appearances (profile_id, appeared_on, count)
    select f.profile_id, v_day, 1 from fresh f
    on conflict (profile_id, appeared_on)
      do update set count = public.search_appearances.count + 1;
  end if;
end;
$$;
revoke execute on function private.record_search_appearances(uuid[], uuid) from public;
revoke execute on function private.record_search_appearances(uuid[], uuid) from anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- Load the pg_trgm library into this session first. Until it is loaded, pg_trgm.* is an unknown
-- placeholder setting and "set pg_trgm.word_similarity_threshold" on a function is refused with
-- "permission denied to set parameter". Once loaded, it is an ordinary user level setting.
-- ---------------------------------------------------------------------------------------------
select extensions.word_similarity('pavio', 'pavio');

-- ---------------------------------------------------------------------------------------------
-- search_directory (Req 24). Callable by anon and authenticated (Req 24.9).
-- pg_trgm lives in schema extensions and search_path is empty, so every trigram operator and
-- function is schema qualified. The returned columns are fixed by the returns table clause and
-- hold public data only (Req 24.5).
-- ---------------------------------------------------------------------------------------------
create or replace function public.search_directory(
  p_query text,
  p_type public.profile_type default null,
  p_city text default null,
  p_limit integer default 20,
  p_offset integer default 0,
  p_searcher uuid default null
)
returns table (
  profile_id uuid,
  type public.profile_type,
  handle text,
  display_name text,
  bio text,
  avatar_path text,
  city text,
  country text,
  what_i_do text[],
  dot_colour public.dot_colour,
  category text,
  search_trust integer,
  rank real
)
language plpgsql
volatile
security definer
set search_path = ''
set pg_trgm.word_similarity_threshold = 0.3
as $$
#variable_conflict use_column
declare
  v_query text;
  v_words text[];
  v_tsq tsquery;
  v_searcher uuid;
  v_page_ids uuid[];
  v_page_ranks real[];
begin
  v_query := lower(btrim(regexp_replace(coalesce(p_query, ''), '\s+', ' ', 'g')));
  -- Too short: no results and no appearance recorded (Req 24.10).
  if length(replace(v_query, ' ', '')) < 2 then
    return;
  end if;
  if p_limit is null or p_offset is null or p_limit not between 1 and 50 or p_offset < 0 then
    raise exception using errcode = 'PT422', message = 'search.bad_page';
  end if;

  v_words := array(
    select w from unnest(string_to_array(v_query, ' ')) as w where length(w) >= 2
  );
  if cardinality(v_words) = 0 then
    v_words := array[replace(v_query, ' ', '')];
  end if;
  -- websearch_to_tsquery never raises on odd input.
  v_tsq := websearch_to_tsquery('simple', array_to_string(v_words, ' or '));
  -- A searcher id the caller does not act as counts as anonymous.
  v_searcher := case when p_searcher is not null and public.acts_as(p_searcher) then p_searcher end;

  -- 1. rank one page into arrays, 2. record appearances for exactly that page, 3. return it
  select array_agg(page.id order by page.final_rank desc, page.trust desc, page.handle asc),
         array_agg(page.final_rank order by page.final_rank desc, page.trust desc, page.handle asc)
    into v_page_ids, v_page_ranks
  from (
    with candidates as (
      select p.*, bd.category, private.search_trust(p.id) as trust
      from public.profiles p
      left join public.business_details bd on bd.profile_id = p.id
      where (p_type is null or p.type = p_type)
        and (p_city is null or lower(p.city) = lower(btrim(p_city)))
        and (
          exists (
            select 1 from unnest(v_words) as w
            where w operator(extensions.<%) lower(p.display_name)
               or w operator(extensions.<%) p.handle
               or w operator(extensions.<%) p.tags_text
               or w operator(extensions.<%) lower(coalesce(p.bio, ''))
               or w operator(extensions.<%) lower(coalesce(p.city, ''))
               or w operator(extensions.<%) lower(coalesce(bd.category, ''))
          )
          or p.search_tsv @@ v_tsq
        )
    ), scored as (
      select c.*,
             ( (select avg(greatest(
                  1.0 * extensions.word_similarity(w, lower(c.display_name)),
                  0.9 * extensions.word_similarity(w, c.handle),
                  1.0 * extensions.word_similarity(w, coalesce(c.tags_text, '')),
                  0.8 * extensions.word_similarity(w, lower(coalesce(c.category, ''))),
                  0.5 * extensions.word_similarity(w, lower(coalesce(c.city, ''))),
                  0.4 * extensions.word_similarity(w, lower(coalesce(c.bio, '')))))
                from unnest(v_words) as w)
               + ts_rank(c.search_tsv, v_tsq) ) as text_score
      from candidates c
    ), ranked as (
      select s.id, s.handle, s.trust,
             (s.text_score * (1 + 0.15 * ln(1 + s.trust)))::real as final_rank
      from scored s
      order by final_rank desc, s.trust desc, s.handle asc
      limit p_limit offset p_offset
    )
    select r.id, r.handle, r.trust, r.final_rank from ranked r
  ) as page;

  if v_page_ids is null then
    return;
  end if;
  perform private.record_search_appearances(v_page_ids, v_searcher);

  return query
  select p.id, p.type, p.handle, p.display_name, p.bio, p.avatar_path, p.city, p.country,
         p.what_i_do, p.dot_colour, bd.category, private.search_trust(p.id), o.final_rank
  from unnest(v_page_ids, v_page_ranks) with ordinality as o (id, final_rank, ord)
  join public.profiles p on p.id = o.id
  left join public.business_details bd on bd.profile_id = p.id
  order by o.ord;
end;
$$;
revoke execute on function public.search_directory(text, public.profile_type, text, integer, integer, uuid)
  from public;
revoke execute on function public.search_directory(text, public.profile_type, text, integer, integer, uuid)
  from anon, authenticated;
grant execute on function public.search_directory(text, public.profile_type, text, integer, integer, uuid)
  to anon, authenticated;
