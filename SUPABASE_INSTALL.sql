-- ============================================================
-- ANIMO PICKLEBALL CUP 2026
-- Realtime Player Live-Courts public-safe mirror
-- Run once in Supabase SQL Editor.
-- ============================================================

begin;

create table if not exists public.ppx_public_live_state (
  event_id text not null,
  match_id text not null,
  court integer,
  division text,
  stage text,
  team_a text,
  team_b text,
  status text not null default 'Scheduled',
  score_a integer,
  score_b integer,
  winner_team text,
  timeout_kind text,
  timeout_team text,
  timeout_started_at timestamptz,
  umpire_name text,
  umpire_id text,
  actual_start_at timestamptz,
  actual_end_at timestamptz,
  result_confirmed_at timestamptz,
  row_version bigint not null default 0,
  updated_at timestamptz not null default clock_timestamp(),
  primary key (event_id, match_id)
);

alter table public.ppx_public_live_state enable row level security;
alter table public.ppx_public_live_state replica identity full;

drop policy if exists ppx_public_live_state_animo_read
  on public.ppx_public_live_state;

create policy ppx_public_live_state_animo_read
on public.ppx_public_live_state
for select
to anon, authenticated
using (event_id = 'ANIMO-PICKLEBALL-CUP-2026');

revoke all on table public.ppx_public_live_state from anon, authenticated;
grant select on table public.ppx_public_live_state to anon, authenticated;

create or replace function public.ppx_sync_public_live_state()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_name text;
  v_umpire_id text;
begin
  if tg_op = 'DELETE' then
    delete from public.ppx_public_live_state
    where event_id = old.event_id
      and match_id = old.match_id;
    return old;
  end if;

  if new.event_id <> 'ANIMO-PICKLEBALL-CUP-2026' then
    return new;
  end if;

  select p.display_name, p.umpire_id
    into v_name, v_umpire_id
  from public.ppx_umpire_profiles p
  where p.event_id = new.event_id
    and p.user_id = new.operator_user_id
  limit 1;

  insert into public.ppx_public_live_state (
    event_id, match_id, court, division, stage,
    team_a, team_b, status, score_a, score_b, winner_team,
    timeout_kind, timeout_team, timeout_started_at,
    umpire_name, umpire_id,
    actual_start_at, actual_end_at, result_confirmed_at,
    row_version, updated_at
  )
  values (
    new.event_id, new.match_id, new.court, new.division, new.stage,
    new.team_a, new.team_b, new.status, new.score_a, new.score_b, new.winner_team,
    new.timeout_kind, new.timeout_team, new.timeout_started_at,
    v_name, v_umpire_id,
    new.actual_start_at, new.actual_end_at, new.result_confirmed_at,
    coalesce(new.row_version,0), clock_timestamp()
  )
  on conflict (event_id, match_id) do update set
    court = excluded.court,
    division = excluded.division,
    stage = excluded.stage,
    team_a = excluded.team_a,
    team_b = excluded.team_b,
    status = excluded.status,
    score_a = excluded.score_a,
    score_b = excluded.score_b,
    winner_team = excluded.winner_team,
    timeout_kind = excluded.timeout_kind,
    timeout_team = excluded.timeout_team,
    timeout_started_at = excluded.timeout_started_at,
    umpire_name = excluded.umpire_name,
    umpire_id = excluded.umpire_id,
    actual_start_at = excluded.actual_start_at,
    actual_end_at = excluded.actual_end_at,
    result_confirmed_at = excluded.result_confirmed_at,
    row_version = excluded.row_version,
    updated_at = excluded.updated_at;

  return new;
end;
$$;

drop trigger if exists trg_ppx_sync_public_live_state
on public.ppx_match_ops;

create trigger trg_ppx_sync_public_live_state
after insert or update or delete
on public.ppx_match_ops
for each row
execute function public.ppx_sync_public_live_state();

-- Seed / repair the public mirror from current operator state.
insert into public.ppx_public_live_state (
  event_id, match_id, court, division, stage,
  team_a, team_b, status, score_a, score_b, winner_team,
  timeout_kind, timeout_team, timeout_started_at,
  umpire_name, umpire_id,
  actual_start_at, actual_end_at, result_confirmed_at,
  row_version, updated_at
)
select
  m.event_id, m.match_id, m.court, m.division, m.stage,
  m.team_a, m.team_b, m.status, m.score_a, m.score_b, m.winner_team,
  m.timeout_kind, m.timeout_team, m.timeout_started_at,
  p.display_name, p.umpire_id,
  m.actual_start_at, m.actual_end_at, m.result_confirmed_at,
  coalesce(m.row_version,0), clock_timestamp()
from public.ppx_match_ops m
left join public.ppx_umpire_profiles p
  on p.event_id = m.event_id
 and p.user_id = m.operator_user_id
where m.event_id = 'ANIMO-PICKLEBALL-CUP-2026'
on conflict (event_id, match_id) do update set
  court = excluded.court,
  division = excluded.division,
  stage = excluded.stage,
  team_a = excluded.team_a,
  team_b = excluded.team_b,
  status = excluded.status,
  score_a = excluded.score_a,
  score_b = excluded.score_b,
  winner_team = excluded.winner_team,
  timeout_kind = excluded.timeout_kind,
  timeout_team = excluded.timeout_team,
  timeout_started_at = excluded.timeout_started_at,
  umpire_name = excluded.umpire_name,
  umpire_id = excluded.umpire_id,
  actual_start_at = excluded.actual_start_at,
  actual_end_at = excluded.actual_end_at,
  result_confirmed_at = excluded.result_confirmed_at,
  row_version = excluded.row_version,
  updated_at = excluded.updated_at;

-- Add the safe table to Supabase Realtime exactly once.
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'ppx_public_live_state'
  ) then
    execute 'alter publication supabase_realtime add table public.ppx_public_live_state';
  end if;
end
$$;

commit;

-- ============================================================
-- VERIFICATION
-- Expected:
-- table_exists = true
-- trigger_exists = true
-- realtime_enabled = true
-- public_rows should match seeded Animo match rows.
-- ============================================================
select
  to_regclass('public.ppx_public_live_state') is not null as table_exists,
  exists (
    select 1
    from pg_trigger
    where tgname = 'trg_ppx_sync_public_live_state'
      and not tgisinternal
  ) as trigger_exists,
  exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'ppx_public_live_state'
  ) as realtime_enabled,
  (
    select count(*)
    from public.ppx_public_live_state
    where event_id = 'ANIMO-PICKLEBALL-CUP-2026'
  ) as public_rows;
