-- ============================================================
--  TheGrint World Cup Pool 2026 — Supabase Schema
--  Run this entire file in: Supabase → SQL Editor → Run
-- ============================================================

-- ── 1. PROFILES (extends Supabase auth.users) ──────────────
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text not null,
  is_admin    boolean not null default false,
  created_at  timestamptz not null default now()
);
alter table public.profiles enable row level security;

create policy "Users can read all profiles"
  on public.profiles for select using (true);

create policy "Users can update own profile"
  on public.profiles for update using (auth.uid() = id);

-- Auto-create profile on signup
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', 'New Member'));
  return new;
end;
$$;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();


-- ── 2. MATCHES ─────────────────────────────────────────────
create table public.matches (
  id           serial primary key,
  match_group  text not null,          -- e.g. 'Group A', 'Round of 16', 'Final'
  stage        text not null default 'group',  -- group | r16 | qf | sf | final
  team_a       text not null,
  flag_a       text not null,
  team_b       text not null,
  flag_b       text not null,
  kickoff_at   timestamptz not null,
  score_a      int,                    -- null until admin sets result
  score_b      int,
  status       text not null default 'upcoming'  -- upcoming | live | finished
);
alter table public.matches enable row level security;

create policy "Anyone can read matches"
  on public.matches for select using (true);

create policy "Only admins can modify matches"
  on public.matches for all using (
    exists (select 1 from public.profiles where id = auth.uid() and is_admin = true)
  );

-- ── 3. BONUS PICKS (champion, top scorer, etc.) ────────────
create table public.bonus_picks (
  id           serial primary key,
  user_id      uuid not null references public.profiles(id) on delete cascade,
  category     text not null,   -- 'champion' | 'top_scorer' | 'finalist_1' | 'finalist_2' | 'cinderella'
  value        text not null,   -- team name or player name
  points       int not null default 0,
  created_at   timestamptz not null default now(),
  unique(user_id, category)
);
alter table public.bonus_picks enable row level security;

create policy "Users read all bonus picks"
  on public.bonus_picks for select using (true);

create policy "Users insert/update own bonus picks"
  on public.bonus_picks for insert with check (auth.uid() = user_id);

create policy "Users update own bonus picks"
  on public.bonus_picks for update using (auth.uid() = user_id);

create policy "Admins can update bonus points"
  on public.bonus_picks for update using (
    exists (select 1 from public.profiles where id = auth.uid() and is_admin = true)
  );

-- ── 4. PICKS ───────────────────────────────────────────────
create table public.picks (
  id          serial primary key,
  user_id     uuid not null references public.profiles(id) on delete cascade,
  match_id    int not null references public.matches(id) on delete cascade,
  pick_a      int not null,
  pick_b      int not null,
  points      int not null default 0,  -- calculated by trigger/admin
  submitted_at timestamptz not null default now(),
  unique(user_id, match_id)
);
alter table public.picks enable row level security;

create policy "Users can read all picks"
  on public.picks for select using (true);

create policy "Users can insert own picks before kickoff"
  on public.picks for insert with check (
    auth.uid() = user_id
    and exists (
      select 1 from public.matches
      where id = match_id
        and kickoff_at > now() + interval '1 hour'
        and status = 'upcoming'
    )
  );

create policy "Users can update own picks before kickoff"
  on public.picks for update using (
    auth.uid() = user_id
    and exists (
      select 1 from public.matches
      where id = match_id
        and kickoff_at > now() + interval '1 hour'
        and status = 'upcoming'
    )
  );

create policy "Admins can update pick points"
  on public.picks for update using (
    exists (select 1 from public.profiles where id = auth.uid() and is_admin = true)
  );

-- ── 5. LEADERBOARD VIEW ────────────────────────────────────
create or replace view public.leaderboard as
select
  p.id,
  p.full_name,
  coalesce(sum(pk.points), 0) + coalesce(sum(bp.points), 0) as total_points,
  coalesce(count(pk.id) filter (where pk.points = 10), 0)   as exact_scores,
  coalesce(count(pk.id) filter (where pk.points = 5),  0)   as correct_results,
  coalesce(count(pk.id), 0)                                  as picks_submitted
from public.profiles p
left join public.picks pk       on pk.user_id = p.id
left join public.bonus_picks bp on bp.user_id = p.id
group by p.id, p.full_name
order by total_points desc, exact_scores desc, correct_results desc;

-- ── 6. SCORE CALCULATION FUNCTION ──────────────────────────
-- Called by admin after updating a match result
create or replace function public.calculate_picks_for_match(p_match_id int)
returns void language plpgsql security definer as $$
declare
  m public.matches%rowtype;
  real_result text;
  pick_result text;
begin
  select * into m from public.matches where id = p_match_id;
  if m.score_a is null or m.score_b is null then
    raise exception 'Match % has no score set', p_match_id;
  end if;

  real_result := case
    when m.score_a > m.score_b then 'A'
    when m.score_a < m.score_b then 'B'
    else 'D'
  end;

  update public.picks
  set points = case
    -- Exact score → 10 pts
    when pick_a = m.score_a and pick_b = m.score_b then 10
    -- Correct result → 5 pts
    when (
      case when pick_a > pick_b then 'A' when pick_a < pick_b then 'B' else 'D' end
    ) = real_result then 5
    else 0
  end
  where match_id = p_match_id;
end;
$$;

-- ── 7. SEED: ALL 104 WORLD CUP 2026 MATCHES (Group Stage) ──
-- Only the 48 group stage games are seeded here.
-- Knockout matches will be added by admin as teams advance.
insert into public.matches (match_group, stage, team_a, flag_a, team_b, flag_b, kickoff_at) values
-- GROUP A
('Group A','group','Mexico','🇲🇽','Colombia','🇨🇴','2026-06-11 20:00:00+00'),
('Group A','group','USA','🇺🇸','New Zealand','🇳🇿','2026-06-12 00:00:00+00'),
('Group A','group','Mexico','🇲🇽','New Zealand','🇳🇿','2026-06-16 20:00:00+00'),
('Group A','group','USA','🇺🇸','Colombia','🇨🇴','2026-06-17 00:00:00+00'),
('Group A','group','Colombia','🇨🇴','New Zealand','🇳🇿','2026-06-21 20:00:00+00'),
('Group A','group','Mexico','🇲🇽','USA','🇺🇸','2026-06-21 20:00:00+00'),
-- GROUP B
('Group B','group','Spain','🇪🇸','Japan','🇯🇵','2026-06-12 17:00:00+00'),
('Group B','group','Australia','🇦🇺','Morocco','🇲🇦','2026-06-12 23:00:00+00'),
('Group B','group','Spain','🇪🇸','Australia','🇦🇺','2026-06-16 17:00:00+00'),
('Group B','group','Japan','🇯🇵','Morocco','🇲🇦','2026-06-16 23:00:00+00'),
('Group B','group','Japan','🇯🇵','Australia','🇦🇺','2026-06-20 17:00:00+00'),
('Group B','group','Morocco','🇲🇦','Spain','🇪🇸','2026-06-20 17:00:00+00'),
-- GROUP C
('Group C','group','Argentina','🇦🇷','Chile','🇨🇱','2026-06-12 20:00:00+00'),
('Group C','group','Canada','🇨🇦','Iran','🇮🇷','2026-06-13 00:00:00+00'),
('Group C','group','Argentina','🇦🇷','Canada','🇨🇦','2026-06-17 20:00:00+00'),
('Group C','group','Chile','🇨🇱','Iran','🇮🇷','2026-06-17 00:00:00+00'),
('Group C','group','Chile','🇨🇱','Canada','🇨🇦','2026-06-21 20:00:00+00'),
('Group C','group','Iran','🇮🇷','Argentina','🇦🇷','2026-06-21 20:00:00+00'),
-- GROUP D
('Group D','group','Germany','🇩🇪','Saudi Arabia','🇸🇦','2026-06-13 17:00:00+00'),
('Group D','group','Belgium','🇧🇪','Ukraine','🇺🇦','2026-06-13 23:00:00+00'),
('Group D','group','Germany','🇩🇪','Belgium','🇧🇪','2026-06-17 17:00:00+00'),
('Group D','group','Saudi Arabia','🇸🇦','Ukraine','🇺🇦','2026-06-17 23:00:00+00'),
('Group D','group','Saudi Arabia','🇸🇦','Belgium','🇧🇪','2026-06-21 17:00:00+00'),
('Group D','group','Ukraine','🇺🇦','Germany','🇩🇪','2026-06-21 17:00:00+00'),
-- GROUP E
('Group E','group','Brazil','🇧🇷','Croatia','🇭🇷','2026-06-13 20:00:00+00'),
('Group E','group','Senegal','🇸🇳','Ecuador','🇪🇨','2026-06-14 00:00:00+00'),
('Group E','group','Brazil','🇧🇷','Senegal','🇸🇳','2026-06-18 20:00:00+00'),
('Group E','group','Croatia','🇭🇷','Ecuador','🇪🇨','2026-06-18 00:00:00+00'),
('Group E','group','Croatia','🇭🇷','Senegal','🇸🇳','2026-06-22 20:00:00+00'),
('Group E','group','Ecuador','🇪🇨','Brazil','🇧🇷','2026-06-22 20:00:00+00'),
-- GROUP F
('Group F','group','France','🇫🇷','Serbia','🇷🇸','2026-06-14 17:00:00+00'),
('Group F','group','Netherlands','🇳🇱','Cameroon','🇨🇲','2026-06-14 23:00:00+00'),
('Group F','group','France','🇫🇷','Netherlands','🇳🇱','2026-06-18 17:00:00+00'),
('Group F','group','Serbia','🇷🇸','Cameroon','🇨🇲','2026-06-18 23:00:00+00'),
('Group F','group','Serbia','🇷🇸','Netherlands','🇳🇱','2026-06-22 17:00:00+00'),
('Group F','group','Cameroon','🇨🇲','France','🇫🇷','2026-06-22 17:00:00+00'),
-- GROUP G
('Group G','group','Portugal','🇵🇹','Ghana','🇬🇭','2026-06-14 20:00:00+00'),
('Group G','group','South Korea','🇰🇷','Ivory Coast','🇨🇮','2026-06-15 00:00:00+00'),
('Group G','group','Portugal','🇵🇹','South Korea','🇰🇷','2026-06-19 20:00:00+00'),
('Group G','group','Ghana','🇬🇭','Ivory Coast','🇨🇮','2026-06-19 00:00:00+00'),
('Group G','group','Ghana','🇬🇭','South Korea','🇰🇷','2026-06-23 20:00:00+00'),
('Group G','group','Ivory Coast','🇨🇮','Portugal','🇵🇹','2026-06-23 20:00:00+00'),
-- GROUP H
('Group H','group','England','🏴󠁧󠁢󠁥󠁮󠁧󠁿','Uzbekistan','🇺🇿','2026-06-15 17:00:00+00'),
('Group H','group','Nigeria','🇳🇬','Peru','🇵🇪','2026-06-15 23:00:00+00'),
('Group H','group','England','🏴󠁧󠁢󠁥󠁮󠁧󠁿','Nigeria','🇳🇬','2026-06-19 17:00:00+00'),
('Group H','group','Uzbekistan','🇺🇿','Peru','🇵🇪','2026-06-19 23:00:00+00'),
('Group H','group','Uzbekistan','🇺🇿','Nigeria','🇳🇬','2026-06-23 17:00:00+00'),
('Group H','group','Peru','🇵🇪','England','🏴󠁧󠁢󠁥󠁮󠁧󠁿','2026-06-23 17:00:00+00');

-- ── 8. REALTIME ─────────────────────────────────────────────
-- Enable realtime on key tables in Supabase dashboard:
-- Database → Replication → Tables → enable for: matches, picks, bonus_picks
