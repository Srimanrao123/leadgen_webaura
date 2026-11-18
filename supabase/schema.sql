-- Outreach CRM schema for Supabase.
-- Run once in Supabase: Dashboard -> SQL Editor -> New query -> paste this file -> Run.
-- Safe to re-run: it only creates what is missing and replaces functions, views and policies.
--
-- Tables
--   team           one row per teammate (linked to a Supabase Auth user)
--   leads          one row per company; owner = who is working it
--   lead_contacts  every website domain / phone / email / Instagram handle, UNIQUE -> no duplicates
--   touches        every message sent or received (email, WhatsApp, call attempt ...)
--   conversations  calls / meetings / demos with a structured summary and optional transcript
--
-- All writes that need checks go through functions (claim_lead, add_contact, mark_dnc ...),
-- so duplicates are refused by the database itself, even if two people claim at the same moment.

-- ---------------------------------------------------------------- team
create table if not exists public.team (
  id          uuid primary key references auth.users(id) on delete cascade,
  name        text not null,
  daily_limit int  not null default 20,
  is_admin    boolean not null default false,
  active      boolean not null default false,   -- an admin switches this on for each teammate
  created_at  timestamptz not null default now()
);

create or replace function public.is_member() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from team where id = auth.uid() and active)
$$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from team where id = auth.uid() and active and is_admin)
$$;

-- New Auth users get an INACTIVE team row. Nobody can read anything until an admin activates them.
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into team (id, name)
  values (new.id, coalesce(nullif(new.raw_user_meta_data->>'name', ''), split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Backfill users that existed before this script ran.
insert into public.team (id, name)
select u.id, coalesce(nullif(u.raw_user_meta_data->>'name', ''), split_part(u.email, '@', 1))
from auth.users u
on conflict (id) do nothing;

-- ---------------------------------------------------------------- normalisation
-- One place that decides what counts as "the same" phone / email / website / Instagram.
create or replace function public.norm_contact(p_kind text, p_value text) returns text
language plpgsql immutable set search_path = public as $$
declare
  v text := lower(trim(coalesce(p_value, '')));
  d text;
  host text;
  seg text;
begin
  if v = '' then return null; end if;

  if p_kind = 'phone' then
    d := regexp_replace(v, '\D', '', 'g');
    if length(d) = 11 and left(d, 1) = '0' then d := substr(d, 2); end if;   -- 0XXXXXXXXXX
    if length(d) = 12 and left(d, 2) = '00' then d := substr(d, 3); end if;
    if length(d) = 10 then d := '91' || d; end if;                            -- Indian default
    if length(d) < 11 or length(d) > 15 then return null; end if;
    if left(d, 2) = '91' and length(d) <> 12 then return null; end if;      -- e.g. template "+91 (123) 456-789"
    return d;

  elsif p_kind = 'email' then
    v := regexp_replace(v, '^mailto:', '');
    if v ~ '^[^@\s]+@[^@\s]+\.[a-z]{2,}$' and v !~ '@(example|domain|email)\.' then return v; end if;
    return null;

  elsif p_kind = 'instagram' then
    v := regexp_replace(v, '^(https?://)?(www\.)?instagram\.com/', '');
    v := regexp_replace(v, '^@', '');
    v := split_part(split_part(split_part(v, '/', 1), '?', 1), '#', 1);
    if v ~ '^[a-z0-9._]{1,30}$' and v not in ('p', 'reel', 'reels', 'explore', 'stories') then return v; end if;
    return null;

  elsif p_kind = 'domain' then
    v := regexp_replace(v, '^[a-z][a-z0-9+.-]*://', '');
    v := split_part(split_part(v, '?', 1), '#', 1);
    host := regexp_replace(split_part(v, '/', 1), '^www\.', '');
    host := regexp_replace(host, ':\d+$', '');
    host := rtrim(host, '.');
    if host !~ '^[a-z0-9.-]+\.[a-z]{2,}$' then return null; end if;
    -- Shared platforms: the path identifies the business, not the host.
    if host ~ '(^|\.)(sites\.google\.com|google\.com|linktr\.ee|facebook\.com|instagram\.com|practo\.com|justdial\.com|wixsite\.com|business\.site|wa\.me)$' then
      seg := split_part(v, '/', 2);
      if seg = '' then return null; end if;      -- bare platform URL tells us nothing
      if seg in ('view', 's', 'pages', 'pg', 'p', 'people') and split_part(v, '/', 3) <> '' then
        seg := seg || '/' || split_part(v, '/', 3);
      end if;
      return host || '/' || seg;
    end if;
    return host;
  end if;

  return null;
end $$;

create or replace function public.name_key(p text) returns text
language sql immutable as $$ select nullif(regexp_replace(lower(coalesce(p, '')), '[^a-z0-9]', '', 'g'), '') $$;

-- ---------------------------------------------------------------- leads
create table if not exists public.leads (
  id             bigint generated always as identity primary key,
  company        text not null,
  name_key       text generated always as (public.name_key(company)) stored,
  category       text not null default 'clinic',   -- clinic, construction, ...
  segment        text,                              -- specialty / type of business
  city           text,
  area           text,
  address        text,
  website        text,
  contact_person text,
  score          int check (score between 0 and 100),
  message_type   text,
  findings       text,
  opportunity    text,
  email_subject  text,
  message        text,                              -- the approved draft
  status         text not null default 'Claimed' check (status in (
                   'Claimed', 'Contacted', 'Replied', 'Interested', 'Demo Scheduled', 'Proposal Sent',
                   'Won', 'Lost', 'Not Interested', 'Not Reachable', 'Disqualified', 'Released', 'Do Not Contact')),
  owner_id       uuid references public.team(id) on delete set null,
  claimed_at     timestamptz not null default now(),
  last_touch_at  timestamptz,
  next_followup  date,
  dnc            boolean not null default false,
  dnc_reason     text,
  notes          text,
  created_by     uuid references public.team(id) on delete set null,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index if not exists leads_owner_idx on public.leads(owner_id);
create index if not exists leads_name_idx on public.leads(name_key);
create index if not exists leads_followup_idx on public.leads(next_followup) where not dnc;

create table if not exists public.lead_contacts (
  id              bigint generated always as identity primary key,
  lead_id         bigint not null references public.leads(id) on delete cascade,
  kind            text not null check (kind in ('domain', 'phone', 'email', 'instagram')),
  value           text not null,
  label           text,                    -- 'WhatsApp', 'Hyderabad office', 'website' ...
  whatsapp_status text not null default 'unknown' check (whatsapp_status in ('unknown', 'on_whatsapp', 'not_on_whatsapp')),
  created_at      timestamptz not null default now(),
  unique (kind, value)
);
create index if not exists lead_contacts_lead_idx on public.lead_contacts(lead_id);

-- ---------------------------------------------------------------- touches & conversations
create table if not exists public.touches (
  id            bigint generated always as identity primary key,
  lead_id       bigint not null references public.leads(id) on delete cascade,
  member_id     uuid not null default auth.uid() references public.team(id),
  channel       text not null check (channel in ('email', 'whatsapp', 'call', 'instagram', 'linkedin', 'in_person', 'other')),
  direction     text not null check (direction in ('out', 'in')),
  contact_value text,                      -- number / address used (normalised automatically)
  subject       text,
  body          text,
  result        text not null default 'sent' check (result in (
                  'sent', 'delivered', 'read', 'replied', 'auto_reply', 'failed', 'bounced',
                  'not_on_whatsapp', 'no_answer', 'wrong_number')),
  occurred_at   timestamptz not null default now(),
  created_at    timestamptz not null default now()
);
create index if not exists touches_lead_idx on public.touches(lead_id, occurred_at);
create index if not exists touches_member_idx on public.touches(member_id, occurred_at);

create table if not exists public.conversations (
  id                bigint generated always as identity primary key,
  lead_id           bigint not null references public.leads(id) on delete cascade,
  member_id         uuid not null default auth.uid() references public.team(id),
  kind              text not null default 'call' check (kind in ('call', 'meeting', 'demo', 'whatsapp_thread', 'email_thread')),
  occurred_at       timestamptz not null default now(),
  duration_min      int,
  contact_person    text,
  summary           text not null,
  current_tools     text,     -- what they use today (CRM, Excel, WhatsApp only ...)
  pain_points       text,
  budget_timeline   text,
  objections        text,
  promised          text,     -- what WE promised to do
  next_step         text,
  next_followup     date,
  outcome           text check (outcome in ('positive', 'neutral', 'negative', 'no_answer')),
  transcript        text,
  recording_consent boolean,
  created_at        timestamptz not null default now()
);
create index if not exists conversations_lead_idx on public.conversations(lead_id, occurred_at);

-- ---------------------------------------------------------------- triggers
create or replace function public.leads_before_update() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.status = 'Do Not Contact' then new.dnc := true; end if;
  if old.dnc and (not new.dnc or new.status <> 'Do Not Contact') and not is_admin() then
    raise exception 'This lead is marked Do Not Contact. Only an admin can change that.';
  end if;
  new.updated_at := now();
  return new;
end $$;
drop trigger if exists leads_before_update on public.leads;
create trigger leads_before_update before update on public.leads
  for each row execute function public.leads_before_update();

create or replace function public.touches_before_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare l leads;
begin
  select * into l from leads where id = new.lead_id;
  if l.dnc and new.direction = 'out' then
    raise exception 'Lead % (%) is marked Do Not Contact: %', l.id, l.company, coalesce(l.dnc_reason, '');
  end if;
  new.contact_value := coalesce(
    norm_contact(case when new.channel in ('whatsapp', 'call') then 'phone'
                      when new.channel = 'email' then 'email'
                      when new.channel = 'instagram' then 'instagram' end, new.contact_value),
    new.contact_value);
  return new;
end $$;
drop trigger if exists touches_before_insert on public.touches;
create trigger touches_before_insert before insert on public.touches
  for each row execute function public.touches_before_insert();

create or replace function public.touches_after_insert() returns trigger
language plpgsql security definer set search_path = public as $$
declare delivered boolean := new.result in ('sent', 'delivered', 'read', 'replied', 'auto_reply');
begin
  update leads set
    last_touch_at = greatest(coalesce(last_touch_at, new.occurred_at), new.occurred_at),
    status = case
      when new.direction = 'out' and delivered and status in ('Claimed', 'Released') then 'Contacted'
      when new.direction = 'in' and new.result <> 'auto_reply' and status in ('Claimed', 'Contacted', 'Released') then 'Replied'
      else status end,
    next_followup = case
      when new.direction = 'out' and delivered then greatest(coalesce(next_followup, '-infinity'::date), (new.occurred_at at time zone 'Asia/Kolkata')::date + 4)
      else next_followup end
  where id = new.lead_id;

  if new.channel = 'whatsapp' and new.contact_value is not null then
    update lead_contacts set whatsapp_status = case when new.result = 'not_on_whatsapp' then 'not_on_whatsapp' else 'on_whatsapp' end
    where lead_id = new.lead_id and kind = 'phone' and value = new.contact_value
      and (new.result = 'not_on_whatsapp' or delivered or new.direction = 'in');
  end if;
  return new;
end $$;
drop trigger if exists touches_after_insert on public.touches;
create trigger touches_after_insert after insert on public.touches
  for each row execute function public.touches_after_insert();

create or replace function public.conversations_after_insert() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  update leads set
    last_touch_at = greatest(coalesce(last_touch_at, new.occurred_at), new.occurred_at),
    next_followup = coalesce(new.next_followup, next_followup),
    status = case when new.outcome is distinct from 'no_answer' and status in ('Claimed', 'Contacted', 'Released') then 'Replied' else status end
  where id = new.lead_id;
  return new;
end $$;
drop trigger if exists conversations_after_insert on public.conversations;
create trigger conversations_after_insert after insert on public.conversations
  for each row execute function public.conversations_after_insert();

-- ---------------------------------------------------------------- functions the skill calls
create or replace function public._norm_contacts(p jsonb)
returns table (kind text, value text, label text)
language sql immutable set search_path = public as $$
  select distinct on (x.k, x.v) x.k, x.v, x.l
  from (
    select c->>'kind' as k, norm_contact(c->>'kind', c->>'value') as v, c->>'label' as l
    from jsonb_array_elements(coalesce(p->'contacts', '[]'::jsonb)) c
    union all
    select 'domain', norm_contact('domain', p->>'website'), 'website'
  ) x
  where x.v is not null and x.k in ('domain', 'phone', 'email', 'instagram')
  order by x.k, x.v, x.l nulls last
$$;

-- Who already has this company? Matches on any contact, or the same name in the same city.
create or replace function public.find_duplicates(p jsonb)
returns table (lead_id bigint, company text, owner_name text, status text, dnc boolean,
               matched_on text, matched_value text, last_touch_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_member() then raise exception 'Not an active team member. Ask an admin to activate your account.'; end if;
  return query
    select l.id, l.company, tm.name, l.status, l.dnc, c.kind, c.value, l.last_touch_at
    from _norm_contacts(p) n
    join lead_contacts c on c.kind = n.kind and c.value = n.value
    join leads l on l.id = c.lead_id
    left join team tm on tm.id = l.owner_id
    union
    select l.id, l.company, tm.name, l.status, l.dnc, 'name', l.company, l.last_touch_at
    from leads l
    left join team tm on tm.id = l.owner_id
    where l.name_key = name_key(p->>'company')
      and coalesce(lower(trim(l.city)), '') = coalesce(lower(trim(p->>'city')), '');
end $$;

-- Check a whole batch at once: p = [{ref, company, city, website, contacts:[...]}, ...]
create or replace function public.check_batch(p jsonb)
returns table (ref text, company text, duplicates jsonb)
language sql stable security definer set search_path = public as $$
  select coalesce(e->>'ref', e->>'company'), e->>'company',
         coalesce((select jsonb_agg(to_jsonb(d)) from find_duplicates(e) d), '[]'::jsonb)
  from jsonb_array_elements(p) e
$$;

-- Claim a new company for the caller. Refuses (ok=false) if anyone already has it.
create or replace function public.claim_lead(p jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  dups jsonb;
  lid  bigint;
  st   text := coalesce(nullif(p->>'status', ''), 'Claimed');
begin
  if not is_member() then raise exception 'Not an active team member. Ask an admin to activate your account.'; end if;
  if coalesce(trim(p->>'company'), '') = '' then raise exception 'company is required'; end if;
  if not exists (select 1 from _norm_contacts(p)) then
    raise exception 'Give at least one website, phone, email or Instagram handle for "%" so duplicates can be checked.', p->>'company';
  end if;
  if st not in ('Claimed', 'Disqualified') then raise exception 'A new lead starts as Claimed or Disqualified, not %', st; end if;

  select coalesce(jsonb_agg(to_jsonb(d)), '[]'::jsonb) into dups
  from find_duplicates(p) d
  where d.matched_on <> 'name' or not coalesce((p->>'allow_same_name')::boolean, false);
  if jsonb_array_length(dups) > 0 then
    return jsonb_build_object('ok', false, 'company', p->>'company', 'duplicates', dups);
  end if;

  insert into leads (company, category, segment, city, area, address, website, contact_person, score,
                     message_type, findings, opportunity, email_subject, message, notes, status,
                     owner_id, created_by)
  values (trim(p->>'company'), coalesce(nullif(p->>'category', ''), 'clinic'), p->>'segment', p->>'city', p->>'area',
          p->>'address', p->>'website', p->>'contact_person', (p->>'score')::int,
          p->>'message_type', p->>'findings', p->>'opportunity', p->>'email_subject', p->>'message', p->>'notes', st,
          auth.uid(), auth.uid())
  returning id into lid;

  insert into lead_contacts (lead_id, kind, value, label)
  select lid, n.kind, n.value, n.label from _norm_contacts(p) n;

  return jsonb_build_object('ok', true, 'company', p->>'company', 'lead_id', lid);
exception when unique_violation then
  -- Someone claimed it in the same instant.
  return jsonb_build_object('ok', false, 'company', p->>'company',
    'duplicates', (select coalesce(jsonb_agg(to_jsonb(d)), '[]'::jsonb) from find_duplicates(p) d));
end $$;

create or replace function public.add_contact(p_lead_id bigint, p_kind text, p_value text, p_label text default null)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v text := norm_contact(p_kind, p_value); other record;
begin
  if not exists (select 1 from leads where id = p_lead_id and (owner_id = auth.uid() or is_admin())) then
    raise exception 'You can only add contacts to your own leads.';
  end if;
  if v is null then raise exception 'Not a valid %: %', p_kind, p_value; end if;
  select l.id, l.company into other from lead_contacts c join leads l on l.id = c.lead_id where c.kind = p_kind and c.value = v;
  if found then
    if other.id = p_lead_id then return jsonb_build_object('ok', true, 'already', true); end if;
    return jsonb_build_object('ok', false, 'error', format('%s %s already belongs to lead %s (%s)', p_kind, v, other.id, other.company));
  end if;
  insert into lead_contacts (lead_id, kind, value, label) values (p_lead_id, p_kind, v, p_label);
  return jsonb_build_object('ok', true, 'value', v);
end $$;

-- Take over a lead: unowned / released, a claim older than 3 days with no outreach, or any lead for admins.
create or replace function public.reclaim_lead(p_lead_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare l record;
begin
  if not is_member() then raise exception 'Not an active team member.'; end if;
  select le.*, tm.name as owner_name into l from leads le left join team tm on tm.id = le.owner_id where le.id = p_lead_id;
  if not found then raise exception 'No lead %', p_lead_id; end if;
  if l.dnc then raise exception 'Lead % is Do Not Contact.', p_lead_id; end if;
  if l.owner_id = auth.uid() then return jsonb_build_object('ok', true, 'already_yours', true); end if;
  if l.owner_id is null or l.status = 'Released' or is_admin()
     or (l.status = 'Claimed' and l.claimed_at < now() - interval '3 days'
         and not exists (select 1 from touches t where t.lead_id = p_lead_id and t.direction = 'out')) then
    update leads set owner_id = auth.uid(), claimed_at = now(),
                     status = case when status = 'Released' then 'Claimed' else status end
    where id = p_lead_id;
    return jsonb_build_object('ok', true, 'lead_id', p_lead_id, 'previous_owner', l.owner_name);
  end if;
  return jsonb_build_object('ok', false, 'error',
    format('Lead %s (%s) belongs to %s, status %s, claimed %s.', l.id, l.company, coalesce(l.owner_name, 'nobody'), l.status, l.claimed_at::date));
end $$;

create or replace function public.release_lead(p_lead_id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  update leads set owner_id = null, status = case when status = 'Claimed' then 'Released' else status end
  where id = p_lead_id and (owner_id = auth.uid() or is_admin());
  if not found then raise exception 'You can only release your own leads.'; end if;
  return jsonb_build_object('ok', true);
end $$;

-- Anyone on the team can stop all contact with a lead (opt-out / DPDP).
create or replace function public.mark_dnc(p_lead_id bigint, p_reason text) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if not is_member() then raise exception 'Not an active team member.'; end if;
  update leads set dnc = true, dnc_reason = p_reason, status = 'Do Not Contact', next_followup = null where id = p_lead_id;
  if not found then raise exception 'No lead %', p_lead_id; end if;
  return jsonb_build_object('ok', true);
end $$;

-- How many new companies the caller has messaged today, per channel (IST day).
create or replace function public.my_quota()
returns table (channel text, companies_today bigint, daily_limit int)
language sql stable security definer set search_path = public as $$
  select t.channel, count(distinct t.lead_id), (select daily_limit from team where id = auth.uid())
  from touches t
  where t.member_id = auth.uid() and t.direction = 'out'
    and t.occurred_at >= (date_trunc('day', now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata')
  group by t.channel
$$;

-- ---------------------------------------------------------------- views
create or replace view public.pipeline with (security_invoker = true) as
select l.id, l.company, l.category, l.segment, l.city, l.area, l.status, l.score,
       l.owner_id, tm.name as owner_name, l.claimed_at, l.last_touch_at, l.next_followup,
       l.dnc, l.dnc_reason, l.website, l.contact_person, l.message_type, l.email_subject, l.message,
       l.findings, l.opportunity, l.notes,
       (select jsonb_agg(jsonb_build_object('kind', c.kind, 'value', c.value, 'label', c.label, 'whatsapp', c.whatsapp_status) order by c.kind, c.id)
          from lead_contacts c where c.lead_id = l.id) as contacts,
       (select count(*) from touches t where t.lead_id = l.id and t.direction = 'out') as messages_sent,
       (select count(*) from touches t where t.lead_id = l.id and t.direction = 'in') as messages_received,
       (select count(*) from conversations cv where cv.lead_id = l.id) as conversations
from leads l
left join team tm on tm.id = l.owner_id;

create or replace view public.followups_due with (security_invoker = true) as
select * from public.pipeline
where not dnc and next_followup <= (now() at time zone 'Asia/Kolkata')::date
  and status in ('Contacted', 'Replied', 'Interested', 'Demo Scheduled', 'Proposal Sent');

-- ---------------------------------------------------------------- security
alter table public.team          enable row level security;
alter table public.leads         enable row level security;
alter table public.lead_contacts enable row level security;
alter table public.touches       enable row level security;
alter table public.conversations enable row level security;

revoke all on public.team, public.leads, public.lead_contacts, public.touches, public.conversations from anon;
revoke all on public.pipeline, public.followups_due from anon;
revoke all on public.team, public.leads, public.lead_contacts, public.touches, public.conversations from authenticated;

grant select on public.team, public.leads, public.lead_contacts, public.touches, public.conversations to authenticated;
grant select on public.pipeline, public.followups_due to authenticated;
grant update (name) on public.team to authenticated;
grant update (company, category, segment, city, area, address, website, contact_person, score, message_type,
              findings, opportunity, email_subject, message, status, next_followup, notes)
  on public.leads to authenticated;
grant insert, update, delete on public.touches, public.conversations to authenticated;

drop policy if exists team_read on public.team;
create policy team_read on public.team for select to authenticated using (is_member() or id = auth.uid());
drop policy if exists team_update_self on public.team;
create policy team_update_self on public.team for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists leads_read on public.leads;
create policy leads_read on public.leads for select to authenticated using (is_member());
drop policy if exists leads_update_owner on public.leads;
create policy leads_update_owner on public.leads for update to authenticated
  using (is_member() and (owner_id = auth.uid() or is_admin()))
  with check (owner_id = auth.uid() or is_admin());

drop policy if exists contacts_read on public.lead_contacts;
create policy contacts_read on public.lead_contacts for select to authenticated using (is_member());

drop policy if exists touches_read on public.touches;
create policy touches_read on public.touches for select to authenticated using (is_member());
drop policy if exists touches_insert on public.touches;
create policy touches_insert on public.touches for insert to authenticated
  with check (is_member() and member_id = auth.uid()
              and exists (select 1 from leads l where l.id = lead_id and (l.owner_id = auth.uid() or is_admin())));
drop policy if exists touches_modify_own on public.touches;
create policy touches_modify_own on public.touches for update to authenticated
  using (member_id = auth.uid()) with check (member_id = auth.uid());
drop policy if exists touches_delete_own on public.touches;
create policy touches_delete_own on public.touches for delete to authenticated using (member_id = auth.uid());

drop policy if exists conversations_read on public.conversations;
create policy conversations_read on public.conversations for select to authenticated using (is_member());
drop policy if exists conversations_insert on public.conversations;
create policy conversations_insert on public.conversations for insert to authenticated
  with check (is_member() and member_id = auth.uid()
              and exists (select 1 from leads l where l.id = lead_id and (l.owner_id = auth.uid() or is_admin())));
drop policy if exists conversations_modify_own on public.conversations;
create policy conversations_modify_own on public.conversations for update to authenticated
  using (member_id = auth.uid()) with check (member_id = auth.uid());
drop policy if exists conversations_delete_own on public.conversations;
create policy conversations_delete_own on public.conversations for delete to authenticated using (member_id = auth.uid());

revoke all on function public.find_duplicates(jsonb), public.check_batch(jsonb), public.claim_lead(jsonb),
  public.add_contact(bigint, text, text, text), public.reclaim_lead(bigint), public.release_lead(bigint),
  public.mark_dnc(bigint, text), public.my_quota(), public.is_member(), public.is_admin(),
  public._norm_contacts(jsonb), public.handle_new_user()
  from public, anon;
grant execute on function public.find_duplicates(jsonb), public.check_batch(jsonb), public.claim_lead(jsonb),
  public.add_contact(bigint, text, text, text), public.reclaim_lead(bigint), public.release_lead(bigint),
  public.mark_dnc(bigint, text), public.my_quota(), public.is_member(), public.is_admin(),
  public._norm_contacts(jsonb)
  to authenticated;

-- ---------------------------------------------------------------- first admin
-- After you create your own user (Authentication -> Users -> Add user), run once with your email:
--   update public.team set active = true, is_admin = true, name = 'Sriman'
--   where id = (select id from auth.users where email = 'you@example.com');
-- For each teammate: add the user, then
--   update public.team set active = true, name = 'Their Name' where id = (select id from auth.users where email = '...');
