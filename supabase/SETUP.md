# Team CRM setup (Supabase, free tier)

One person (the admin) does steps 1–4 once. Every teammate then does step 5 on their own computer.

## 1. Create the project
1. Sign in at supabase.com → **New project**. Pick region **Mumbai (ap-south-1)**, set a database password and keep it safe.
2. When it's ready, open **SQL Editor → New query**, paste all of `supabase/schema.sql`, and click **Run**. It should end with "Success".

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
A read-only web page showing the live pipeline, follow-ups due, each person's sends today, and the full history of any lead. Everyone signs in with their own CRM email and password and sees only what the database allows.

- **On your own Mac:** run the command below. It writes `Outreach Dashboard.html` to your Desktop and opens it. Bookmark it.
  ```bash
  python3 ~/.claude/skills/lead-outreach/scripts/crm.py dashboard --open
  ```
- **One link for the whole team (free):** rename that file to `index.html`, go to https://app.netlify.com/drop, and drag the file in. Netlify gives you a link to share.
  The page contains only the project URL and the publishable key, which are safe to publish because the database rules protect the data. Nobody sees anything without an active CRM login.
  To update it later, regenerate the file and drag it in again on the same site's **Deploys** page.
- `?demo` at the end of the URL shows sample data. This is handy for checking the page without signing in.

## Keep the free project awake
Free projects pause after 7 days without activity. Daily outreach keeps it awake. If the team takes a break, open the dashboard once a week or run `crm.py whoami`.
If it does pause, click **Restore** in the dashboard. No data is lost.

## What the database guarantees
- A website domain, phone number, email or Instagram handle can belong to only **one** lead. Claiming a company someone else has is refused, even at the same instant.
- Only the owner (or an admin) can change a lead or log messages on it. Everyone on the team can see everything.
- A claim with no outreach expires after **3 days**, and then anyone can `reclaim` it.
- **Do Not Contact** can be set by anyone, blocks every outgoing message to that lead, and only an admin can undo it.
