-- Targets, progress and leaderboard. Run AFTER schema.sql (Supabase -> SQL Editor -> paste -> Run).
-- Safe to re-run.
--
-- Metrics, counted per IST day:
--   new_contacts   companies messaged for the first time ever (one per company, even if sent on 2 channels)
--   followups      companies messaged again on a later day than their first message
--   conversations  calls / meetings / demos / chat summaries logged (not "no answer")
-- Leaderboard points: new contact 1, follow-up 1, conversation 3, reached Interested 5,
--   Demo Scheduled 8, Proposal Sent 10, Won 25.

-- ---------------------------------------------------------------- default targets per person
alter table public.team add column if not exists target_new_contacts  int not null default 10 check (target_new_contacts >= 0);
alter table public.team add column if not exists target_followups     int not null default 5  check (target_followups >= 0);
alter table public.team add column if not exists target_conversations int not null default 2  check (target_conversations >= 0);

-- ---------------------------------------------------------------- per-day overrides
create table if not exists public.daily_targets (
  member_id     uuid not null references public.team(id) on delete cascade,
  day           date not null,
  new_contacts  int  not null check (new_contacts >= 0),
  followups     int  not null check (followups >= 0),
  conversations int  not null check (conversations >= 0),
  note          text,
  set_by        uuid references public.team(id) on delete set null,
  updated_at    timestamptz not null default now(),
  primary key (member_id, day)
);

-- ---------------------------------------------------------------- status history (for the leaderboard)
create table if not exists public.status_changes (
  id          bigint generated always as identity primary key,
  lead_id     bigint not null references public.leads(id) on delete cascade,
  member_id   uuid references public.team(id) on delete set null,
  from_status text,
  to_status   text not null,
  changed_at  timestamptz not null default now()
);
create index if not exists status_changes_idx on public.status_changes(to_status, changed_at);

create or replace function public.leads_status_history() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.status is distinct from old.status then
    insert into status_changes (lead_id, member_id, from_status, to_status)
    values (new.id, coalesce(auth.uid(), new.owner_id), old.status, new.status);
  end if;
  return new;
end $$;
drop trigger if exists leads_status_history on public.leads;
create trigger leads_status_history after update of status on public.leads
  for each row execute function public.leads_status_history();

-- One-time backfill: leads already past Contacted get one history row, credited to the owner.
insert into public.status_changes (lead_id, member_id, from_status, to_status, changed_at)
select l.id, l.owner_id, null, l.status, l.updated_at
from public.leads l
where l.status in ('Interested', 'Demo Scheduled', 'Proposal Sent', 'Won')
  and not exists (select 1 from public.status_changes s where s.lead_id = l.id);

-- ---------------------------------------------------------------- helpers
create or replace function public.ist_today() returns date
language sql stable as $$ select (now() at time zone 'Asia/Kolkata')::date $$;

-- Activity per active teammate between two IST dates (inclusive).
create or replace function public.member_activity(p_from date, p_to date)
returns table (member_id uuid, name text, new_contacts bigint, followups bigint, conversations bigint,
               interested bigint, demos bigint, proposals bigint, won bigint, points bigint)
language plpgsql stable security definer set search_path = public as $$
declare
  t0 timestamptz := (p_from::timestamp) at time zone 'Asia/Kolkata';
  t1 timestamptz := ((p_to + 1)::timestamp) at time zone 'Asia/Kolkata';
begin
  if not is_member() then raise exception 'Not an active team member.'; end if;
  return query
  with ok as (
    select t.lead_id, t.member_id, (t.occurred_at at time zone 'Asia/Kolkata')::date as d
    from touches t
    where t.direction = 'out' and t.result in ('sent', 'delivered', 'read', 'replied', 'auto_reply')
  ),
  firsts as (select ok.lead_id, min(ok.d) as d0 from ok group by ok.lead_id),
  days as (select distinct ok.member_id, ok.lead_id, ok.d from ok where ok.d between p_from and p_to),
  sends as (
    select days.member_id,
           count(*) filter (where days.d = f.d0) as n_new,
           count(*) filter (where days.d > f.d0) as n_fu
    from days join firsts f on f.lead_id = days.lead_id
    group by days.member_id
  ),
  convs as (
    select c.member_id, count(*) as n
    from conversations c
    where c.occurred_at >= t0 and c.occurred_at < t1 and c.outcome is distinct from 'no_answer'
    group by c.member_id
  ),
  stages as (
    select s.member_id,
           count(distinct s.lead_id) filter (where s.to_status = 'Interested')     as n_int,
           count(distinct s.lead_id) filter (where s.to_status = 'Demo Scheduled') as n_demo,
           count(distinct s.lead_id) filter (where s.to_status = 'Proposal Sent')  as n_prop,
           count(distinct s.lead_id) filter (where s.to_status = 'Won')            as n_won
    from status_changes s
    where s.changed_at >= t0 and s.changed_at < t1
    group by s.member_id
  )
  select m.id, m.name,
         coalesce(se.n_new, 0), coalesce(se.n_fu, 0), coalesce(cv.n, 0),
         coalesce(st.n_int, 0), coalesce(st.n_demo, 0), coalesce(st.n_prop, 0), coalesce(st.n_won, 0),
         coalesce(se.n_new, 0) + coalesce(se.n_fu, 0) + 3 * coalesce(cv.n, 0) + 5 * coalesce(st.n_int, 0)
           + 8 * coalesce(st.n_demo, 0) + 10 * coalesce(st.n_prop, 0) + 25 * coalesce(st.n_won, 0)
  from team m
  left join sends se on se.member_id = m.id
  left join convs cv on cv.member_id = m.id
  left join stages st on st.member_id = m.id
  where m.active;
end $$;

create or replace function public.leaderboard(p_from date, p_to date)
returns table (rank bigint, member_id uuid, name text, points bigint, new_contacts bigint, followups bigint,
               conversations bigint, interested bigint, demos bigint, proposals bigint, won bigint)
language sql stable security definer set search_path = public as $$
  select rank() over (order by a.points desc), a.member_id, a.name, a.points, a.new_contacts, a.followups,
         a.conversations, a.interested, a.demos, a.proposals, a.won
  from member_activity(p_from, p_to) a
  order by a.points desc, a.name
$$;

-- Targets vs achieved for one IST day, per active teammate.
create or replace function public.daily_progress(p_day date default null)
returns table (member_id uuid, name text, day date, custom_target boolean, target_note text,
               target_new_contacts int, target_followups int, target_conversations int,
               new_contacts bigint, followups bigint, conversations bigint,
               pending_new_contacts int, pending_followups int, pending_conversations int,
               followups_due bigint, percent int)
language plpgsql stable security definer set search_path = public as $$
declare d date := coalesce(p_day, ist_today());
begin
  if not is_member() then raise exception 'Not an active team member.'; end if;
  return query
  with tg as (
    select m.id, m.name,
           dt.member_id is not null as custom, dt.note,
           coalesce(dt.new_contacts, m.target_new_contacts)   as t_new,
           coalesce(dt.followups, m.target_followups)         as t_fu,
           coalesce(dt.conversations, m.target_conversations) as t_conv
    from team m left join daily_targets dt on dt.member_id = m.id and dt.day = d
    where m.active
  ),
  due as (
    select l.owner_id, count(*) as n from leads l
    where not l.dnc and l.next_followup <= d
      and l.status in ('Contacted', 'Replied', 'Interested', 'Demo Scheduled', 'Proposal Sent')
    group by l.owner_id
  )
  select tg.id, tg.name, d, tg.custom, tg.note, tg.t_new, tg.t_fu, tg.t_conv,
         a.new_contacts, a.followups, a.conversations,
         greatest(tg.t_new - a.new_contacts, 0)::int, greatest(tg.t_fu - a.followups, 0)::int,
         greatest(tg.t_conv - a.conversations, 0)::int,
         coalesce(due.n, 0),
         case when tg.t_new + tg.t_fu + tg.t_conv = 0 then 100
              else round(100.0 * (least(a.new_contacts, tg.t_new) + least(a.followups, tg.t_fu) + least(a.conversations, tg.t_conv))
                         / (tg.t_new + tg.t_fu + tg.t_conv))::int end
  from tg
  join member_activity(d, d) a on a.member_id = tg.id
  left join due on due.owner_id = tg.id
  order by tg.name;
end $$;

-- Admin: set someone's default daily targets (p_day null) or a target for one specific day.
create or replace function public.set_targets(p_member uuid, p_new_contacts int, p_followups int, p_conversations int,
                                              p_day date default null, p_note text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Only an admin can set targets.'; end if;
  if least(p_new_contacts, p_followups, p_conversations) < 0 then raise exception 'Targets cannot be negative.'; end if;
  if not exists (select 1 from team where id = p_member) then raise exception 'No such teammate.'; end if;
  if p_day is null then
    update team set target_new_contacts = p_new_contacts, target_followups = p_followups,
                    target_conversations = p_conversations
    where id = p_member;
    return jsonb_build_object('ok', true, 'scope', 'default');
  end if;
  insert into daily_targets (member_id, day, new_contacts, followups, conversations, note, set_by, updated_at)
  values (p_member, p_day, p_new_contacts, p_followups, p_conversations, p_note, auth.uid(), now())
  on conflict (member_id, day) do update set
    new_contacts = excluded.new_contacts, followups = excluded.followups, conversations = excluded.conversations,
    note = excluded.note, set_by = excluded.set_by, updated_at = now();
  return jsonb_build_object('ok', true, 'scope', 'day', 'day', p_day);
end $$;

create or replace function public.clear_day_target(p_member uuid, p_day date) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'Only an admin can change targets.'; end if;
  delete from daily_targets where member_id = p_member and day = p_day;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------- security
alter table public.daily_targets  enable row level security;
alter table public.status_changes enable row level security;
revoke all on public.daily_targets, public.status_changes from anon, authenticated;
grant select on public.daily_targets, public.status_changes to authenticated;

drop policy if exists daily_targets_read on public.daily_targets;
create policy daily_targets_read on public.daily_targets for select to authenticated using (is_member());
drop policy if exists status_changes_read on public.status_changes;
create policy status_changes_read on public.status_changes for select to authenticated using (is_member());

revoke all on function public.member_activity(date, date), public.leaderboard(date, date), public.daily_progress(date),
  public.set_targets(uuid, int, int, int, date, text), public.clear_day_target(uuid, date),
  public.leads_status_history() from public, anon;
grant execute on function public.member_activity(date, date), public.leaderboard(date, date), public.daily_progress(date),
  public.set_targets(uuid, int, int, int, date, text), public.clear_day_target(uuid, date), public.ist_today()
  to authenticated;
