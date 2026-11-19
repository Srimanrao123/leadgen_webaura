-- Streaks: consecutive days each teammate hits 100% of their daily target. Run AFTER 002 (and 003).
-- Safe to re-run.
--
-- Rules (IST days, looking back up to 120 days):
--   hit   = that day's targets add up to more than 0 and daily_progress.percent >= 100
--   skip  = Sunday without a hit, a day whose targets are all 0, or a day before the person joined
--           (a skip never breaks a streak and never adds to it)
--   today = never breaks the streak: until it is hit, the streak is "at risk", not lost
--   miss  = any other day: the current streak goes back to 0
-- member_streaks(p_day) returns, per active teammate:
--   current_streak, best_streak, hit_today, at_risk (has a streak but today isn't hit yet), hits_last_30

create or replace function public.member_streaks(p_day date default null)
returns table (member_id uuid, name text, current_streak int, best_streak int, hit_today boolean,
               at_risk boolean, hits_last_30 int)
language plpgsql stable security definer set search_path = public as $$
declare
  d       date := coalesce(p_day, ist_today());
  start_d date;
  m       record;
  joined  date;
  run     int;
  best    int;
  hits30  int;
  today_hit boolean;
  dy      date;
  hit     boolean;
begin
  if not is_member() then raise exception 'Not an active team member.'; end if;
  start_d := greatest(d - 120, (select min((created_at at time zone 'Asia/Kolkata')::date) from team));

  for m in
    select p.member_id as mid, p.name as mname,
           array_agg(dd.day order by dd.day) as days,
           array_agg(p.percent order by dd.day) as pcts,
           array_agg(p.target_new_contacts + p.target_followups + p.target_conversations order by dd.day) as tsums
    from (select g::date as day from generate_series(start_d, d, interval '1 day') g) dd
    cross join lateral daily_progress(dd.day) p
    group by p.member_id, p.name
  loop
    select (t.created_at at time zone 'Asia/Kolkata')::date into joined from team t where t.id = m.mid;
    run := 0; best := 0; hits30 := 0; today_hit := false;
    for i in 1 .. coalesce(array_length(m.days, 1), 0) loop
      dy := m.days[i];
      continue when dy < joined;
      hit := m.tsums[i] > 0 and m.pcts[i] >= 100;
      if hit then
        run := run + 1;
        best := greatest(best, run);
        if dy > d - 30 then hits30 := hits30 + 1; end if;
        if dy = d then today_hit := true; end if;
      elsif dy = d or m.tsums[i] = 0 or extract(isodow from dy) = 7 then
        null;                      -- today pending, a day off or a Sunday: no change
      else
        run := 0;                  -- a missed working day breaks the streak
      end if;
    end loop;
    member_id := m.mid; name := m.mname; current_streak := run; best_streak := best;
    hit_today := today_hit; at_risk := (run > 0 and not today_hit); hits_last_30 := hits30;
    return next;
  end loop;
end $$;

revoke all on function public.member_streaks(date) from public, anon;
grant execute on function public.member_streaks(date) to authenticated;
