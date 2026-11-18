# Start here (teammates)

This skill lets Claude find leads, write personal outreach messages, send them by email and WhatsApp after you approve them, and log everything in our **shared team CRM**. The CRM means nobody on the team contacts the same company twice.

You need about 10 minutes once.

**Shortcut:** open Claude and say *"Set me up for lead outreach using <REPO_URL> and its TEAM-START.md"*. Claude does the steps below. You only type your password at the sign-in step, and you add the details the admin sends you.

## 1. Get your login from the admin
The admin adds you in Supabase and activates you. You get an **email**, a **temporary password**, and the **project URL + publishable key** to put in `.env`.

## 2. Get the folder and install it (Terminal)
```bash
cd ~/Desktop && git clone <REPO_URL> lead-outreach
```
```bash
cd ~/Desktop/lead-outreach && ./install.sh
```
`install.sh` links the folder into `~/.claude/skills/` so Claude can use it, installs the spreadsheet library, and creates your `.env`.

## 3. Fill in `.env`
Open `~/Desktop/lead-outreach/.env` in any editor (`open -e .env`) and fill in:
```
SUPABASE_URL=...              (from the admin)
SUPABASE_PUBLISHABLE_KEY=...  (from the admin)
CRM_EMAIL=you@example.com     (your login email)
```
`.env` is private and never pushed to git.

## 4. Sign in to the CRM
```bash
python3 ~/Desktop/lead-outreach/scripts/crm.py login
```
Type your password when asked. Nothing appears while you type; that's normal. You should see **"Signed in as <your name>. Ready."**

- "not active yet": ask the admin to activate you.
- An SSL / certificate error: tell the admin. The script normally handles this by itself.

## 5. Open the team dashboard
```bash
python3 ~/Desktop/lead-outreach/scripts/crm.py dashboard --open
```
It puts **Outreach Dashboard.html** on your Desktop. Sign in with the same email and password, and bookmark it.

## 6. Set up the Claude app
- **Email:** install **Claude in Chrome** and stay signed in to the Gmail you send from (or connect a Gmail connector).
- **WhatsApp:** Claude app → **Settings → This computer → Computer use**: turn it on. Keep the **WhatsApp desktop app** logged in with the business number.
- Restart the Claude app so it picks up the skill.

## Getting updates
```bash
cd ~/Desktop/lead-outreach && git pull
```
Because the skill is linked, Claude uses the new version right away. Your `.env` and login are untouched.

## Use it: just talk to Claude
You never need to update anything yourself. Say it in your own words:

| Say | You get |
|---|---|
| **"Good morning"** | Your day: target, leaderboard spot, follow-ups due, promises you owe, today's quote and a plan |
| **"Find 10 builders in Kondapur and do the outreach"** | Research → drafts for your OK → sent → a report with your new score |
| **"Do my follow-ups"** | Follow-ups drafted from each lead's history → sent after your OK → a report |
| **"Kamala replied: send me the price"** | Logged, status updated, one-line confirmation |
| **"Called Marvel, no answer"** | Logged |
| **"Had a call with BuildHome: …notes…"** | A clean summary saved, and any promise tracked until it's done |
| **"They said stop messaging"** | Marked Do Not Contact for the whole team |
| **"How am I doing?"** | Your % of today's target and your rank |
| **"Check my replies"** | Claude reads your WhatsApp and Gmail for replies from your leads, saves them, and tells you who replied |
| **"Wrap up my day"** | Today's score, wins, what's still open, and tomorrow's plan |

Claude checks the CRM first, skips companies a teammate already has, and **always waits for your OK on drafts** before sending. Everything after that (logging, statuses, follow-up dates) happens by itself, and you get a short report at the end.

**Good to know:** replies that come to your phone don't reach Claude by themselves. Say **"check my replies"** once or twice a day, or just tell Claude what they said.

## Did something without Claude? Add it on the dashboard
- **Found a company yourself?** Click **＋ Add lead** at the top. Fill in the name and at least a phone, email, website or Instagram. It warns you right away if a teammate already has it. If you've already called or messaged them, tick **"I already contacted them"** and say how.
- **Called, met or messaged a lead from your phone?** Open the lead → **📞 Log contact**: how (WhatsApp, call, email, in person…), when, the result, and what was said.
- **Had a proper conversation?** Open the lead → **💬 Add conversation** to save the notes, next step and follow-up date.

All of it counts toward your target and the leaderboard, exactly like Claude's work.

## Team rules
- Never message a company owned by someone else. The CRM tells you who owns it.
- Log every reply and every call. Claude does it when you tell it what happened.
- If anyone says "stop" or "not interested", tell Claude straight away. It marks them **Do Not Contact** for the whole team.
- Contact at most 20 new companies a day per channel, and only use business numbers from the company's own website or listing.
