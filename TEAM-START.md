# Start here (teammates)

This skill lets Claude find leads, write personal outreach messages, send them by email and WhatsApp after you approve them, and log everything in our **shared team CRM**. The CRM means nobody on the team contacts the same company twice.

You need about 10 minutes once.

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

## Use it
In Claude, say something like:
> Find 10 builders in Kondapur, Hyderabad and do the outreach for our CRM service.

> Find 10 dental clinics in Banjara Hills and do the outreach for our video service.

> Kamala Infra replied "send me the price". Log it.

> I just had a call with BuildHome. Here are my notes: … Log it.

> What follow-ups are due today?

Claude checks the CRM first, skips companies a teammate already has, and claims the new ones for you. It shows you the drafts and **waits for your OK** before sending anything, then logs every send automatically.

## Team rules
- Never message a company owned by someone else. The CRM tells you who owns it.
- Log every reply and every call. Claude does it when you tell it what happened.
- If anyone says "stop" or "not interested", tell Claude straight away. It marks them **Do Not Contact** for the whole team.
- Contact at most 20 new companies a day per channel, and only use business numbers from the company's own website or listing.
