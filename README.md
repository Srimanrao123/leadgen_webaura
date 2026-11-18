# Outreach skill for Claude (with a shared team CRM)

Finds independent clinics or local businesses (builders and others), researches each one, writes a personal message, and sends it by email and WhatsApp after you approve the drafts.

Every lead, message, reply and call summary is stored in one shared Supabase database, so teammates never contact the same company twice. A dashboard shows the live pipeline.

**Teammates: read [TEAM-START.md](TEAM-START.md).** In short:
```bash
git clone <REPO_URL> ~/Desktop/lead-outreach && cd ~/Desktop/lead-outreach && ./install.sh
```
Then fill in `.env` and run `python3 scripts/crm.py login`.

## What's in this repo
| Path | What it is |
|---|---|
| `SKILL.md` | The instructions Claude follows (the whole process) |
| `TEAM-START.md` | Setup guide for teammates |
| `install.sh` | Links this folder into `~/.claude/skills/` and creates `.env` |
| `.env.example` | The settings each person needs (copy it to `.env`, which is git-ignored) |
| `references/` | How to research, write messages, send safely, and use the CRM |
| `scripts/crm.py` | The CRM helper: check, claim, log, follow-ups, export, dashboard |
| `scripts/build_sheet.py` | An offline spreadsheet builder (fallback only) |
| `dashboard/index.html` | The team dashboard page (template; `crm.py dashboard` fills in the project) |
| `supabase/schema.sql` | The database: run once by the admin |
| `supabase/SETUP.md` | Admin guide: create the project, add and activate teammates, host the dashboard |

## What never goes in git
`.env`, login tokens (they live in `~/.config/outreach-crm/`), passwords, the Supabase secret/service_role key, lead spreadsheets, and generated dashboards. `.gitignore` covers these. Keep the repo **private**, since it describes your sales process.

## Admin, once
Follow [supabase/SETUP.md](supabase/SETUP.md): create the Supabase project, run `schema.sql`, turn off sign-ups, then add and activate each teammate.

## Be a good sender
Contact 20 or fewer new companies a day per channel, never message personal numbers, and stop immediately if someone says no.
