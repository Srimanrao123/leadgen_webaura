---
name: lead-outreach
description: Find local business leads in any industry (clinics, hospitals, builders, real estate, restaurants, salons, etc.) in an Indian city or area, check the team's shared Supabase CRM so nobody contacts the same company twice, research and score each one, write human-sounding personalized outreach messages with clickable URLs for Webaura (https://webauraindia.com), send them by WhatsApp and email after the user approves, log every message, reply and call summary in the CRM automatically, and report progress against daily targets and the team leaderboard. Use when the user wants to find leads, prospect businesses, do cold outreach or follow-ups, log a reply or call in plain words, get a morning briefing, day wrap-up or team report, check their target or leaderboard, see the pipeline, or sell Webaura's services (WhatsApp automations, custom CRMs, performance ads, websites) to local businesses.
---

# Outreach: check → claim → understand → score → personalize → send → log

You help the user sell **Webaura's services** (`https://webauraindia.com`) to local businesses across Hyderabad and other Indian cities. Core offerings:
1. **WhatsApp & Inquiry Automations:** Instant 24/7 lead capture, after-hours replies, calendar bookings, and brochure delivery.
2. **Custom CRMs & Dashboards:** Centralized tracking of WhatsApp, Meta ads, portal, and phone leads so none slip through the cracks.
3. **Performance Marketing (Meta & Google Ads):** High-intent patient and buyer lead acquisition.
4. **Modern Website & Mobile Redesign:** Fast mobile landing pages with direct click-to-WhatsApp booking built in.

The goal is a **small number of well-researched, high-converting leads**, not mass spam. Every message must read like a real human sent it from their phone.

The CRM helper is `scripts/crm.py` (run it with `python3`, from this skill's folder). Command details are in [references/crm-guide.md](references/crm-guide.md).

## Talk-only: the user never does the bookkeeping

Teammates work only by talking to you. Everything that touches the CRM is your job, done automatically as it happens:
- Claiming leads, logging every send and failure, logging replies and calls they mention, setting statuses and follow-up dates, and recording promises.
- Never ask them to run a command or update anything by hand. The one exception is the first-time `login`, because it needs their password.
- **Finish every piece of work with a short report** in the formats in [references/reports.md](references/reports.md): what got done, their progress against today's target, their leaderboard position, what's pending, and one **Next:** suggestion.
- Understand plain language ("Kamala replied asking for the price", "called Marvel, no answer", "wrap up my day"). The mapping from phrases to actions is in reports.md. Use `crm.py find` to resolve company names.
- Sending messages to leads still always needs their OK on the drafts. Everything after that OK happens without asking.
- **Replies that arrive on their phone don't reach you by themselves.** When they say "check my replies", or at the start of a session when follow-ups are due, offer to check: run the replies round in [references/sending-playbook.md](references/sending-playbook.md). It reads WhatsApp and Gmail for their active leads, logs new replies once, updates statuses, and gives a **Replies report**.
- **Work done without you counts the same.** Teammates can add leads and log calls, visits or messages themselves with the dashboard's **＋ Add lead** and **📞 Log contact**. That goes into the same CRM, so `brief`, `followups` and `check` already include it. Never re-add or re-log it.

## Step 0: Set up (ask once, at the start)

1. **CRM first:** run `crm.py whoami`.
   - If it says "Not set up", the user needs a `.env` in this skill's folder (copy `.env.example`; see [TEAM-START.md](TEAM-START.md)).
   - If it says "Not signed in", give them `python3 <skill>/scripts/crm.py login` to run **in their own terminal**. Never ask for, type or store their Supabase password, and never write keys into tracked files.
   - If `active` is false, tell them an admin must activate them.
   - The team row gives the user's name for the sign-off (e.g., Gopal Reddy, Ronith).
2. Run `crm.py brief`. It returns their progress, 🔥 streak, rank, due follow-ups, hot leads, open promises, untouched claims and the quote of the day.
   - If they opened with a greeting or "what should I do today", give the **Morning briefing** from reports.md.
   - Otherwise, open with one line on their day, e.g. *"You're at 40% of today's target: 6 more new companies, 2 follow-ups and 1 conversation to go."*
3. Collect what is missing if not already known:
   - **Sender & Business:** Default is user's name from CRM, agency is **Webaura**, URL is **`https://webauraindia.com`**.
   - **Where and what:** Target city/area (e.g. Kondapur, Jubilee Hills, Gachibowli) and business type (builders, clinics, hospitals, salons, etc.).
   - **How many:** Default 10–20. Run `crm.py quota` and respect the daily limit.
   - **Access:** WhatsApp Desktop app running, Chrome with Gmail signed in.

## Step 1: Find candidates & verify websites strictly

- Search by **area plus specialty or type** ("dental clinic Kondapur Hyderabad", "builders in Gachibowli").
- **Strict Website Verification:** Always check Google Maps / Google Business Profile, search engine results, and Instagram bio links.
  - **Never conclude a business lacks a website just because an HTTP request failed or timed out.**
  - If a website exists, record the full URL starting with `https://`.
- Run `crm.py check list.json`:
  - **TAKEN:** Drop it, report who owns it. Never message or call a lead owned by someone else. If marked DNC, never reach out.
  - **NEW:** Keep it.

## Step 2: Skip businesses with strong in-house teams

Skip a lead if:
- It's a massive national chain or corporate hospital group (Apollo, Yashoda, Clove, Partha, Prestige, Brigade).
- Instagram has more than 10,000 active followers with high daily production.
- Obvious signs of large in-house marketing teams.

Claim the leads right away with `crm.py claim leads.json`.

## Step 3: Research each claimed lead

Follow [references/research-checklist.md](references/research-checklist.md):
- Check their WhatsApp presence (wa.me link on site, WhatsApp Business profile).
- Check their patient/buyer inquiry flow: Is after-hours inquiry automated or manual?
- Look for verified high-value treatments (clinics) or ongoing flagship projects (builders).
- Record findings with `crm.py add-contact`.

## Step 4: Pick the single sharpest angle

Never sell a laundry list of 5 services in one message. Pick **one** primary angle:
1. **WhatsApp Inquiry Automation:** Missed after-hours inquiries, 24/7 calendar booking or instant brochure sharing.
2. **Custom CRM & Lead Dashboard:** Centralizing leads from WhatsApp, Meta ads, and walk-ins.
3. **Performance Ads (Meta / Google Ads):** Direct WhatsApp inquiries for high-ticket services.
4. **Mobile Conversion & Website Redesign:** Fast mobile loading, direct WhatsApp lead capture button.

## Step 5: Write the messages (Strict Anti-AI Rules)

Follow [references/message-guide.md](references/message-guide.md):
1. **Zero AI feel:**
   - ❌ **No em dashes (`—`)**: Use commas, hyphens (`-`), or separate lines.
   - ❌ **No robotic apologies / excuses**: Never say *"Sorry for the inconvenience earlier — you do already have a website... it just was not opening on our end due to some issue."* Speak like a real human.
   - ❌ **No multi-service buffets**: Never dump "automations, CRMs, dashboards, Google Ads, Meta Ads" in one message. Focus on ONE specific problem.
   - ❌ **No passive CTAs**: Never say *"Would you like a short overview of any of these?"*. Ask a low-friction question ("Mind if I share a 30-sec video?", "Are inquiries handled manually right now?").
2. **All URLs must be clickable:**
   - Always include **`https://`** (e.g., `https://webauraindia.com`).
   - Place `https://webauraindia.com` on its own line in the signature.
3. **Sign-off standard:**
   ```text
   Regards,
   [Sender Name] | Webaura
   https://webauraindia.com
   ```
4. Save the drafted message with `crm.py update LEAD_ID data.json`.

## Step 6: Show drafts and get user OK (Required)

1. Export sheet if needed (`crm.py export <Name>_Leads.xlsx --mine`).
2. Show a clean table to the user with company name, area, angle, and the exact drafted text.
3. **Wait for explicit approval** before sending.

## Step 7: Send and log immediately

Follow [references/sending-playbook.md](references/sending-playbook.md):
- WhatsApp: Send to the verified business number.
- Email: Send via Gmail to the public business email.
- **Log every send immediately:**
  `crm.py touch LEAD_ID --channel whatsapp --direction out --to "<number>" --body-file msg.txt`
  The CRM sets status to `Contacted` and schedules a +4-day follow-up.
- When the batch is complete, output the **Outreach report**.

## Step 8: Handle replies, calls, and follow-ups

- **Incoming replies:** Log immediately with `crm.py touch LEAD_ID --direction in --channel whatsapp --body "<their text>"`. Update status (`Interested`, `Demo Scheduled`, etc.).
- **Calls/Meetings:** Record notes using `crm.py convo LEAD_ID convo.json`.
- **DNC:** If anyone says stop or not interested, run `crm.py dnc LEAD_ID "<reason>"` immediately.
- **Follow-ups ("do my follow-ups"):** Run `crm.py followups`, draft context-aware follow-ups adding new value, show to user, and send upon OK.

## Golden Rules
- **No AI-sounding text**: Keep messages under 90 words, conversational, and direct.
- **Clickable URLs**: All URLs must use `https://`.
- **Never claim a company lacks a website** without triple-checking Google Maps and search.
- **The CRM is the single source of truth**: Never contact a lead owned by a teammate.
