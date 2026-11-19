-- Paged, filtered lead list for the dashboard (and crm.py find). Run AFTER schema.sql and 002.
-- Safe to re-run. Runs with the caller's permissions (row-level security applies).
--
-- lead_page(p_q, p_owner, p_category, p_status, p_limit, p_offset) returns one JSON object:
--   total          leads matching every filter (for "1–25 of 132")
--   rows           one page of pipeline rows, hottest first
--   status_counts  {status: n} for the filters EXCEPT status (for the status chips)
--   all_count      leads matching the filters except status
-- p_owner: null = everyone, 'me', 'none' (unowned), or a teammate's id.
-- p_q searches company, city, area, segment, website, owner name, and every phone/email/Instagram/domain
--   (digits-only search also matches phone numbers typed with spaces).
--
-- lead_stats() returns team-wide totals and the list of categories (for the header numbers and filters).

create or replace function public.lead_page(
  p_q text default null, p_owner text default null, p_category text default null, p_status text default null,
  p_limit int default 25, p_offset int default 0)
returns jsonb
language plpgsql stable security invoker set search_path = public as $$
declare
  q    text := nullif(trim(coalesce(p_q, '')), '');
  qd   text := regexp_replace(coalesce(p_q, ''), '\D', '', 'g');
  pat  text;
  lim  int  := least(greatest(coalesce(p_limit, 25), 1), 100);
  off  int  := greatest(coalesce(p_offset, 0), 0);
  res  jsonb;
begin
  if not is_member() then raise exception 'Not an active team member.'; end if;
  if q is not null then
    pat := '%' || replace(replace(replace(lower(q), '\', '\\'), '%', '\%'), '_', '\_') || '%';
  end if;

  with base as (
    select l.id, l.status, l.score
    from leads l
    left join team tm on tm.id = l.owner_id
    where (p_owner is null
           or (p_owner = 'me'   and l.owner_id = auth.uid())
           or (p_owner = 'none' and l.owner_id is null)
           or (p_owner not in ('me', 'none') and l.owner_id::text = p_owner))
      and (p_category is null or l.category = p_category)
      and (q is null
           or lower(l.company) like pat or lower(coalesce(l.city, '')) like pat or lower(coalesce(l.area, '')) like pat
           or lower(coalesce(l.segment, '')) like pat or lower(coalesce(l.website, '')) like pat
           or lower(coalesce(tm.name, '')) like pat
           or exists (select 1 from lead_contacts c where c.lead_id = l.id
                      and (c.value like pat or (length(qd) >= 4 and c.value like '%' || qd || '%'))))
  ),
  filtered as (select * from base where p_status is null or status = p_status),
  ranked as (
    select f.id, row_number() over (
             order by coalesce(array_position(array['Proposal Sent', 'Demo Scheduled', 'Interested', 'Replied', 'Contacted',
                        'Claimed', 'Released', 'Won', 'Not Reachable', 'Lost', 'Not Interested', 'Disqualified',
                        'Do Not Contact'], f.status), 99),
                      f.score desc nulls last, f.id) as rn
    from filtered f
  ),
  page_ids as (select id, rn from ranked order by rn limit lim offset off)
  select jsonb_build_object(
    'total', (select count(*) from filtered),
    'all_count', (select count(*) from base),
    'status_counts', coalesce((select jsonb_object_agg(status, n) from (select status, count(*) n from base group by status) s), '{}'::jsonb),
    'rows', coalesce((select jsonb_agg(to_jsonb(p) order by pi.rn) from page_ids pi join pipeline p on p.id = pi.id), '[]'::jsonb),
    'limit', lim, 'offset', off
  ) into res;
  return res;
end $$;

create or replace function public.lead_stats()
returns jsonb
language plpgsql stable security invoker set search_path = public as $$
begin
  if not is_member() then raise exception 'Not an active team member.'; end if;
  return jsonb_build_object(
    'leads', (select count(*) from leads),
    'contacted', (select count(distinct lead_id) from touches where direction = 'out' and result in ('sent', 'delivered', 'read')),
    'interested_plus', (select count(*) from leads where status in ('Interested', 'Demo Scheduled', 'Proposal Sent', 'Won')),
    'won', (select count(*) from leads where status = 'Won'),
    'categories', coalesce((select jsonb_agg(distinct category order by category) from leads where category is not null), '[]'::jsonb)
  );
end $$;

create index if not exists lead_contacts_value_idx on public.lead_contacts (value text_pattern_ops);
create index if not exists leads_category_idx on public.leads (category);
create index if not exists leads_status_idx on public.leads (status);

revoke all on function public.lead_page(text, text, text, text, int, int), public.lead_stats() from public, anon;
grant execute on function public.lead_page(text, text, text, text, int, int), public.lead_stats() to authenticated;
