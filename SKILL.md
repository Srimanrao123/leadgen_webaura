---
name: lead-outreach
description: Find local business leads in any industry (clinics, builders, restaurants, salons, schools and so on) in an Indian city or area, check the team's shared Supabase CRM so nobody contacts the same company twice, research and score each one, write a personalized outreach message, send it by email and WhatsApp after the user approves, log every message, reply and call summary in the CRM automatically, and report progress against daily targets and the team leaderboard. Use when the user wants to find leads, prospect businesses, do cold outreach or follow-ups, log a reply or call in plain words, get a morning briefing, day wrap-up or team report, check their target or leaderboard, see the pipeline, or sell any service (content, video, CRM, automation, websites) to local businesses.
---

# Outreach: check → claim → understand → score → personalize → send → log

You help the user sell a service to local businesses in any industry. Examples: content and video for clinics, CRM and automation for builders, websites for restaurants. Industry-specific guidance (such as the clinic rules below) applies only to that industry. Several teammates use this skill at the same time, so **the shared CRM is the single source of truth**. Work in this order and do not skip the approval step.

The goal is a **small number of well-researched leads**, not volume. Every message must make the business think: *"they actually looked at us."*

The CRM helper is `scripts/crm.py` (run it with `python3`, from this skill's folder). Command details and the conversation-summary format are in [references/crm-guide.md](references/crm-guide.md).

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
   - If it says "Not signed in", give them `python3 <skill>/scripts/crm.py login` to run **in their own terminal**. Never ask for, type or store their Supabase password, and never write keys into tracked files. Only `.env` holds them, and it's git-ignored.
   - If `active` is false, tell them an admin must activate them.
   - The team row gives the user's name for the sign-off.
2. Run `crm.py brief`. It returns their progress, 🔥 streak, rank, due follow-ups, hot leads, open promises, untouched claims and the quote of the day. When the streak is at risk, use it as the day's motivation ("hit today's target to make it 7").
   - If they opened with a greeting or "what should I do today", give the **Morning briefing** from reports.md.
   - Otherwise, open with one line on their day, e.g. *"You're at 40% of today's target: 6 more new companies, 2 follow-ups and 1 conversation to go."*
   - Plan the session to close what's pending: **overdue promises first**, then due follow-ups, then enough new companies to reach the target.
   - If `progress` in the output carries an error mentioning a missing function, the admin hasn't run `supabase/002_targets_leaderboard.sql` yet. Carry on without targets.
3. In one AskUserQuestion round or one short message, collect what is still missing:
   - **Who is sending:** the business name for the sign-off, and the email address to send from.
   - **What they sell:** one or two lines about the service.
   - **Where and what:** city or area, plus specialties or business types (default for clinics: dental, dermatology/aesthetics, hair, IVF, physiotherapy, eye).
   - **How many:** default 10. Run `crm.py quota` and keep the day at or under the user's daily limit (20 by default) per channel.
   - **Access, for both channels:**
     - **Email:** a Gmail connector, or Gmail signed in through Claude in Chrome or the in-app browser. Confirm the account shown matches their sending address before you send anything.
     - **WhatsApp:** Computer use turned on, with the WhatsApp desktop app logged in, or WhatsApp Web in Chrome.

   Tell them plainly: *"If a business has both an email and a WhatsApp number, I'll send on both. Please give me access to both now, so I don't have to stop halfway."*

## Step 1: Find candidates, then check the CRM before researching

- Search by **area plus specialty or type** ("dental clinic Jubilee Hills Hyderabad"), several in parallel.
- Directories (Practo, Justdial, MedHive and the like) are only for finding names. Find each business's **own website**: search the name, then try likely domains directly. Keep only businesses with a working website that clearly belongs to them.
- As soon as you have a name plus a website or phone, put the candidates in a JSON list and run `crm.py check list.json`.
  - **TAKEN:** drop it, and tell the user who owns it and its status. Never research, message or call a lead owned by someone else. If it's marked DO NOT CONTACT, never mention reaching out.
  - **NEW:** keep it.
- Find extra candidates if needed to reach the target count.

## Step 2: Skip businesses with a strong online presence

These usually have a marketing team already, reply rarely, and waste the user's time. For clinics, skip a clinic if ANY of these is true:

- It's a **chain or hospital group**: 3 or more branches, multiple cities, "hospital", or a 50+ bed facility (Apollo, Clove, FMS, Partha, Oliva, Kaya, DHI and the like).
- **Instagram has more than 10,000 followers** on the clinic or founder account.
- **YouTube is active**: an upload in the last 30 days and a regular cadence.
- There are signs of **in-house marketing**: hiring content or marketing roles, heavy paid ads, press releases every month.
- The doctor is a **celebrity or influencer**.

Apply the same idea to other industries (big branded groups, an obvious in-house team).

**Claim right away, including the ones you disqualify.** Run `crm.py claim leads.json` for the NEW ones you're keeping, with `"status": "Claimed"`. Do the same for disqualified ones with `"status": "Disqualified"` and the reason in `notes`, so no teammate wastes time on them. If a claim comes back TAKEN, a teammate got there first: drop it. Note the `lead_id` of each claim.

The **ideal clinic lead** is independent (1–2 branches), offers high-value treatments, has good reviews, and has **weak or inconsistent content**.

## Step 3: Research each claimed lead

Use [references/research-checklist.md](references/research-checklist.md). Never stop at the first contact you find.

When you find a new phone, email or Instagram handle, run `crm.py add-contact LEAD_ID KIND VALUE --label ...`. If it says the contact belongs to another lead, stop and tell the user: it's probably the same company under another name.

**Never invent an observation.** If you couldn't verify something, leave it out.

## Step 4: Score (0–100) and pick the angle

Score on: content gap (35), business strength and high-value services (25), ability to personalize (20), contactability (20). Hold anything under 50.

Choose one message type per lead. See [references/message-guide.md](references/message-guide.md).

## Step 5: Write the messages

Follow [references/message-guide.md](references/message-guide.md): short, with 2–3 verified specifics, never overselling AI, and one simple CTA.

Save the result on the lead with `crm.py update LEAD_ID data.json`: score, segment, contact_person, findings, opportunity, message_type, email_subject, message.

## Step 6: Show the drafts and get approval (required)

1. Run `crm.py export <Name>_Leads.xlsx --mine` for a sheet. `scripts/build_sheet.py` is only an offline fallback.
2. Show the user a short table (company, score, angle, channels) and the drafts.
3. **Wait for an explicit yes** before sending anything. The user may edit the drafts; save the edits with `update`. Approval covers only the leads and text they saw.

## Step 7: Send, and log every send immediately

Follow [references/sending-playbook.md](references/sending-playbook.md).

- **Before each lead:** run `crm.py show LEAD_ID`. It must still be yours, not DNC, and have no outgoing touch on that channel (which would mean someone already sent). Skip phones whose `whatsapp` is `not_on_whatsapp`.
- **Email:** send to every lead with a public business email. **WhatsApp:** send the same text (no subject) to its **business number from its own website or listing**. If both exist, send on both.
- **Verify each send** (Gmail Sent; the WhatsApp bubble with a tick). **Never double-send.**
- **Right after each verified send**, log it:
  `crm.py touch LEAD_ID --channel whatsapp --direction out --to "<number>" --body-file msg.txt`
  Use `--channel email --to <address> --subject "..."` for email. Log failures too, with `--result not_on_whatsapp` or `--result bounced`.

  The CRM sets the status to Contacted and the follow-up to +4 days by itself. If a log call fails, stop and tell the user before sending more.
- **When the batch is done:** run `crm.py brief` and give the **Outreach report** from reports.md. Don't ask the user to check anything.

## Step 8: Replies, calls and follow-ups

- **A reply arrives** (WhatsApp, email, or the user tells you about one): log it with `crm.py touch LEAD_ID --direction in --channel ... --body "<their exact words>"`. Use `--result auto_reply` for bots and canned intros. Then set the status with `update`: Replied, Interested, Demo Scheduled, Proposal Sent, Won, Lost or Not Interested.
- **The user had a call or meeting:** ask for the transcript or their notes. Write the structured summary from [references/crm-guide.md](references/crm-guide.md), show it to them, then save it with `crm.py convo LEAD_ID convo.json`.
  - Only record what they told you, never guesses.
  - A call recording needs the other person's consent; set `recording_consent` accordingly.
- **Anyone says stop or not interested:** run `crm.py dnc LEAD_ID "<their words>"` immediately. Nobody on the team can message them again.
- **The user wants to see the pipeline:** run `crm.py dashboard --open`. It writes the team dashboard page to the Desktop and opens it; they sign in there themselves. Hosting it for the team is covered in [supabase/SETUP.md](supabase/SETUP.md).
- **Follow-up round** ("do my follow-ups"):
  1. Run `crm.py followups`, then `crm.py show LEAD_ID` for each, so every follow-up fits that lead's history (what we sent, what they said, what we promised).
  2. Draft short follow-ups. Each one adds something new: a useful idea, an answer to their question, or the thing we promised. Never send just "following up".
  3. Show all the drafts together and send after one OK.
  4. Log each send.
  5. Give the **Follow-up report**.
- **Quick logging** from plain language: `crm.py find NAME` → `touch` or `convo` → `update` the status if it changed → a one- or two-line confirmation, plus progress if a target was just hit. If they mention a promise ("I'll send the quote Friday"), store it in the conversation's `promised` field with `next_followup`. `brief` keeps showing it until a message goes out to that lead.
- **Day wrap-up** ("wrap up my day") and **team report** ("team report", for the admin): use `brief` / `team-report` and the formats in reports.md. Send a report to anyone (a teammate, a WhatsApp group) only when the user asks and names the recipient.

## Rules that always hold

- **The CRM decides who owns a lead.** Never contact a lead you don't own, even if you found it independently. If you think a claim is stale, use `crm.py reclaim` (it only works after 3 days with no outreach) or ask the owner.
- Log every outgoing and incoming message and every call. If it isn't in the CRM, the team can't see it.
- Only public **business** contact details. No personal numbers, no guessed emails.
- No fake compliments, and no "I hope this finds you well" or "leading company".
- Respect India's DPDP Act: honour opt-outs immediately (`dnc`).
- Respect NMC rules in any clinic sample content: no promised results, no before/afters, no superlatives.
- Never send without the user's approval of the drafts in this session.
- Never put Supabase passwords, secret keys or service_role keys in files, commands or messages. Only the publishable key goes in `crm.py setup`, and the user runs `login` themselves.
