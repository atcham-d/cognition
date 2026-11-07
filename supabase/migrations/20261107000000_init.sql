-- Slí initial schema: profiles, friends, live location, plans, gamification.
create extension if not exists postgis;

-- Profiles ---------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  handle text unique not null check (handle ~ '^[a-z0-9_]{3,20}$'),
  display_name text not null,
  avatar_seed int not null default floor(random() * 1000),
  xp int not null default 0,
  streak_days int not null default 0,
  last_trip_date date,
  co2_saved_g bigint not null default 0,
  created_at timestamptz not null default now()
);

-- Friendships ------------------------------------------------------------
create type friendship_status as enum ('pending', 'accepted', 'blocked');

create table public.friendships (
  requester uuid not null references public.profiles on delete cascade,
  addressee uuid not null references public.profiles on delete cascade,
  status friendship_status not null default 'pending',
  created_at timestamptz not null default now(),
  primary key (requester, addressee),
  check (requester <> addressee)
);

create or replace function public.are_friends(a uuid, b uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from friendships
    where status = 'accepted'
      and ((requester = a and addressee = b) or (requester = b and addressee = a))
  );
$$;

-- Live location (last known point only, auto-expiring) -------------------
create type share_mode as enum ('precise', 'approximate', 'paused');

create table public.live_locations (
  user_id uuid primary key references public.profiles on delete cascade,
  share_mode share_mode not null default 'paused',
  position geography(point, 4326),
  accuracy_m real,
  transit_mode text,
  route text,
  toward text,
  eta_minutes int,
  updated_at timestamptz not null default now(),
  expires_at timestamptz
);

create table public.location_hidden_from (
  user_id uuid not null references public.profiles on delete cascade,
  hidden_from uuid not null references public.profiles on delete cascade,
  primary key (user_id, hidden_from)
);

-- Friends never read live_locations directly; this owner-privileged view applies
-- the friendship, hide-list, expiry and approximate-coarsening rules.
create or replace view public.friend_locations as
select
  l.user_id,
  l.share_mode,
  case when l.share_mode = 'approximate'
       then st_snaptogrid(l.position::geometry, 0.005)::geography
       else l.position end as position,
  l.transit_mode, l.route, l.toward, l.eta_minutes, l.updated_at
from public.live_locations l
where l.share_mode <> 'paused'
  and (l.expires_at is null or l.expires_at > now())
  and public.are_friends(auth.uid(), l.user_id)
  and not exists (select 1 from public.location_hidden_from h
                  where h.user_id = l.user_id and h.hidden_from = auth.uid());

revoke all on public.friend_locations from anon;
grant select on public.friend_locations to authenticated;

-- Plans ------------------------------------------------------------------
create type rsvp as enum ('invited', 'going', 'maybe', 'declined');
create type arrival_status as enum ('not_left', 'on_my_way', 'here');

create table public.plans (
  id uuid primary key default gen_random_uuid(),
  owner uuid not null references public.profiles on delete cascade,
  title text not null,
  symbol text not null default 'calendar',
  tint text not null default 'accent',
  place_name text,
  place geography(point, 4326),
  starts_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.plan_members (
  plan_id uuid not null references public.plans on delete cascade,
  user_id uuid not null references public.profiles on delete cascade,
  rsvp rsvp not null default 'invited',
  arrival arrival_status not null default 'not_left',
  eta_minutes int,
  primary key (plan_id, user_id)
);

create table public.plan_time_options (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.plans on delete cascade,
  starts_at timestamptz not null
);

create table public.plan_votes (
  option_id uuid not null references public.plan_time_options on delete cascade,
  user_id uuid not null references public.profiles on delete cascade,
  primary key (option_id, user_id)
);

create table public.plan_messages (
  id bigint generated always as identity primary key,
  plan_id uuid not null references public.plans on delete cascade,
  user_id uuid not null references public.profiles on delete cascade,
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);

create or replace function public.is_plan_member(p uuid, u uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from plan_members where plan_id = p and user_id = u)
      or exists (select 1 from plans where id = p and owner = u);
$$;

-- Gamification -----------------------------------------------------------
create table public.trips (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles on delete cascade,
  transit_mode text not null,
  route text,
  trip_id text,
  started_at timestamptz not null,
  ended_at timestamptz,
  distance_m int,
  verified boolean not null default false,
  plan_id uuid references public.plans on delete set null
);

create table public.xp_events (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles on delete cascade,
  amount int not null,
  reason text not null,
  trip_id uuid references public.trips on delete set null,
  created_at timestamptz not null default now()
);

create table public.badges (
  id text primary key,
  title text not null,
  symbol text not null,
  description text not null,
  goal int not null default 1
);

create table public.user_badges (
  user_id uuid not null references public.profiles on delete cascade,
  badge_id text not null references public.badges on delete cascade,
  progress int not null default 0,
  earned_at timestamptz,
  primary key (user_id, badge_id)
);

create index on public.xp_events (user_id, created_at desc);
create index on public.trips (user_id, started_at desc);
create index on public.plan_members (user_id);

-- Row Level Security -----------------------------------------------------
alter table public.profiles enable row level security;
alter table public.friendships enable row level security;
alter table public.live_locations enable row level security;
alter table public.location_hidden_from enable row level security;
alter table public.plans enable row level security;
alter table public.plan_members enable row level security;
alter table public.plan_time_options enable row level security;
alter table public.plan_votes enable row level security;
alter table public.plan_messages enable row level security;
alter table public.trips enable row level security;
alter table public.xp_events enable row level security;
alter table public.badges enable row level security;
alter table public.user_badges enable row level security;

create policy "profiles readable by signed-in users" on public.profiles
  for select to authenticated using (true);
create policy "update own profile" on public.profiles
  for update to authenticated using (id = auth.uid())
  with check (id = auth.uid());
create policy "insert own profile" on public.profiles
  for insert to authenticated with check (id = auth.uid());

create policy "see own friendships" on public.friendships
  for select to authenticated using (auth.uid() in (requester, addressee));
create policy "send friend request" on public.friendships
  for insert to authenticated with check (requester = auth.uid() and status = 'pending');
create policy "addressee responds" on public.friendships
  for update to authenticated using (addressee = auth.uid());
create policy "either side removes" on public.friendships
  for delete to authenticated using (auth.uid() in (requester, addressee));

create policy "own location full access" on public.live_locations
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "manage own hidden list" on public.location_hidden_from
  for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "members read plan" on public.plans
  for select to authenticated using (public.is_plan_member(id, auth.uid()));
create policy "create own plan" on public.plans
  for insert to authenticated with check (owner = auth.uid());
create policy "owner edits plan" on public.plans
  for update to authenticated using (owner = auth.uid());
create policy "owner deletes plan" on public.plans
  for delete to authenticated using (owner = auth.uid());

create policy "members read members" on public.plan_members
  for select to authenticated using (public.is_plan_member(plan_id, auth.uid()));
create policy "owner invites friends" on public.plan_members
  for insert to authenticated with check (
    exists (select 1 from public.plans p where p.id = plan_id and p.owner = auth.uid())
    and (user_id = auth.uid() or public.are_friends(auth.uid(), user_id))
  );
create policy "member updates own rsvp" on public.plan_members
  for update to authenticated using (user_id = auth.uid());
create policy "leave plan" on public.plan_members
  for delete to authenticated using (user_id = auth.uid());

create policy "members read options" on public.plan_time_options
  for select to authenticated using (public.is_plan_member(plan_id, auth.uid()));
create policy "members propose options" on public.plan_time_options
  for insert to authenticated with check (public.is_plan_member(plan_id, auth.uid()));

create policy "members read votes" on public.plan_votes
  for select to authenticated using (
    public.is_plan_member((select plan_id from public.plan_time_options o where o.id = option_id), auth.uid()));
create policy "vote as self" on public.plan_votes
  for insert to authenticated with check (
    user_id = auth.uid()
    and public.is_plan_member((select plan_id from public.plan_time_options o where o.id = option_id), auth.uid()));
create policy "unvote as self" on public.plan_votes
  for delete to authenticated using (user_id = auth.uid());

create policy "members read chat" on public.plan_messages
  for select to authenticated using (public.is_plan_member(plan_id, auth.uid()));
create policy "members post chat" on public.plan_messages
  for insert to authenticated with check (user_id = auth.uid() and public.is_plan_member(plan_id, auth.uid()));

create policy "read own trips" on public.trips
  for select to authenticated using (user_id = auth.uid());
create policy "read own xp" on public.xp_events
  for select to authenticated using (user_id = auth.uid());
create policy "badges catalog public" on public.badges
  for select to authenticated using (true);
create policy "read own or friends badges" on public.user_badges
  for select to authenticated using (user_id = auth.uid() or public.are_friends(auth.uid(), user_id));
-- trips / xp_events / user_badges are written only by edge functions (service role) after verification.

-- Realtime ---------------------------------------------------------------
-- Friend location updates go over Realtime Broadcast (private channels), not postgres_changes.
alter publication supabase_realtime add table public.plan_members, public.plan_votes, public.plan_messages;

-- Seed badges ------------------------------------------------------------
insert into public.badges (id, title, symbol, description, goal) values
  ('luas_legend', 'Luas Legend', 'tram.fill', 'Ride every Luas line', 2),
  ('coastliner', 'Coastliner', 'water.waves', 'Visit every DART station', 31),
  ('night_owl', 'Night Owl', 'moon.stars.fill', 'Take 10 trips after midnight', 10),
  ('streak_30', '30-Day Streak', 'flame.fill', 'Travel by transit 30 days in a row', 30),
  ('squad_goals', 'Squad Goals', 'person.3.fill', 'Arrive at 5 plans where everyone took transit', 5),
  ('century', 'Century', '100.circle.fill', 'Complete 100 verified trips', 100);
