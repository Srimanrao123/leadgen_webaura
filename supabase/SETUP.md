# Team CRM setup (Supabase, free tier)

One person (the admin) does steps 1–4 once. Every teammate then does step 5 on their own computer.

## 1. Create the project
1. Sign in at supabase.com → **New project**. Pick region **Mumbai (ap-south-1)**, set a database password and keep it safe.
2. When it's ready, open **SQL Editor → New query**, paste all of `supabase/schema.sql`, and click **Run**. It should end with "Success".
3. Then do the same with `supabase/002_targets_leaderboard.sql` (daily targets, progress, leaderboard).
   **Already set up before targets existed?** Run only this file. It's safe to run more than once and keeps your data.

## Daily targets (admin)
Every teammate starts with a default of **10 new companies, 5 follow-ups and 2 conversations a day**. To change them:
- **Dashboard:** go to **Team targets → Set targets**, or click a teammate's row. Choose "Every day" for their default, or "One specific day" for an override such as a half day or a push day.
- **Claude / terminal:** `crm.py target Ravi --new 12 --followups 6 --conversations 3`. Add `--day 2026-11-20` for a single day.

Everyone sees their own **My day** panel (percent done and what's pending), the team's progress, and the leaderboard.

## 2. Lock down sign-ups
**Authentication → Sign In / Providers → Email**: turn **off** "Allow new users to sign up".
Teammates are added by the admin only. Even if someone did sign up, they can't see anything until the admin activates them.

## 3. Add people
**Authentication → Users → Add user → Create new user**: enter the teammate's email and a temporary password, and tick "Auto confirm user".
Do this for yourself too.

## 4. Activate people (SQL Editor)
```sql
-- yourself, as admin
update public.team set active = true, is_admin = true, name = 'Sriman'
where id = (select id from auth.users where email = 'YOUR_EMAIL');

-- each teammate
update public.team set active = true, name = 'Ravi'
where id = (select id from auth.users where email = 'TEAMMATE_EMAIL');
```
To remove someone later: `update public.team set active = false where name = 'Ravi';` (their history stays).
To change someone's daily limit: `update public.team set daily_limit = 15 where name = 'Ravi';`

## 5. Each teammate, once
Get the **Project URL** and the **publishable key** (older projects call it the "anon public" key) from **Project Settings → API Keys / Data API**, and send them to teammates privately (not in git).
Never use the `service_role` or secret key here.

Each teammate clones the repo, runs `./install.sh`, and puts the URL, key and their email in `.env` (see `.env.example`). Then:
```bash
python3 scripts/crm.py login
```
The login asks for your password and stores only a session token in `~/.config/outreach-crm/config.json` (readable only by you). It should print "Signed in as <name>. Ready."
Change the temporary password later under Supabase → Authentication, or ask the admin to reset it.

## Team dashboard
A web page with the live pipeline, targets, leaderboard and lead history. Teammates can also add leads and log contacts there. Everyone signs in with their own CRM email and password and sees only what the database allows.

### Host it on Vercel (one link for everyone, updates itself on every `git push`)
1. Sign in at **vercel.com** with your GitHub account → **Add New… → Project** → **Import** the `leadgen_webaura` repo.
2. On the configure screen, leave the framework as **Other**. The repo's `vercel.json` already sets the build.
3. Open **Environment Variables** and add these two (copy them from your `.env`):
   - `SUPABASE_URL` = `https://<your-project>.supabase.co`
   - `SUPABASE_PUBLISHABLE_KEY` = `sb_publishable_…`

   **Never** add the secret or service_role key. The build refuses it anyway.
4. Click **Deploy**. Your link looks like `https://leadgen-webaura.vercel.app`. Share it with the team and have them bookmark it, on phones too.
5. Updating it is automatic: whenever the dashboard changes and you `git push`, Vercel rebuilds in about 30 seconds.

The page contains only the project URL and the publishable key. Those are safe to publish, because the database rules protect the data and nobody sees anything without an active CRM login. Search engines are told not to index it.

Test a build on your Mac with `node scripts/build-dashboard.mjs`. It writes `public/index.html`, which is git-ignored.

Note: Vercel's free **Hobby** plan is meant for non-commercial use. For a sales team, Vercel expects the **Pro** plan. Netlify's free plan is an alternative: the same repo works with build command `node scripts/build-dashboard.mjs` and publish directory `public`.

### Or open it from your own Mac
```bash
python3 ~/.claude/skills/lead-outreach/scripts/crm.py dashboard --open
```
This writes `Outreach Dashboard.html` to your Desktop.

Add `?demo` to the end of the URL to see sample data without signing in.

## Keep the free project awake
Free projects pause after 7 days without activity. Daily outreach keeps it awake. If the team takes a break, open the dashboard once a week or run `crm.py whoami`.
If it does pause, click **Restore** in the dashboard. No data is lost.

## What the database guarantees
- A website domain, phone number, email or Instagram handle can belong to only **one** lead. Claiming a company someone else has is refused, even at the same instant.
- Only the owner (or an admin) can change a lead or log messages on it. Everyone on the team can see everything.
- A claim with no outreach expires after **3 days**, and then anyone can `reclaim` it.
- **Do Not Contact** can be set by anyone, blocks every outgoing message to that lead, and only an admin can undo it.
