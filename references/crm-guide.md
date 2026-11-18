# CRM guide (`scripts/crm.py`)

Run commands as `python3 <skill>/scripts/crm.py <command>`. Every command prints JSON. Files can be `-` to read from stdin.
If a command prints `Supabase error ...`, show the message to the user. Don't retry blindly.

## Check and claim
`check` and `claim` take a list (or one object):
```json
[{"company": "Example Homes", "category": "construction", "city": "Hyderabad", "area": "Kompally",
  "website": "examplehomes.in", "phones": ["+91 90000 00000 (WhatsApp)"], "emails": ["info@examplehomes.in"],
  "instagram": "@examplehomes", "segment": "Villa & house construction", "status": "Claimed"}]
```
- Phones can carry a label in brackets, and several can share one string separated by `/`.
- Duplicates are matched on website domain, any phone, any email, the Instagram handle, or the same name in the same city.
- If a genuinely different business shares a name in the same city, re-run `claim --allow-same-name`. Only do that after telling the user.
- To disqualify, use `"status": "Disqualified"` plus `"notes": "Chain, 5 branches"`.

## Updating a lead
`update LEAD_ID data.json` accepts only these fields: company, category, segment, city, area, address, website, contact_person, score, message_type, findings, opportunity, email_subject, message, status, next_followup (YYYY-MM-DD), notes.

Statuses: Claimed, Contacted, Replied, Interested, Demo Scheduled, Proposal Sent, Won, Lost, Not Interested, Not Reachable, Disqualified, Released, Do Not Contact (use `dnc` for that one).

## Logging messages (`touch`)
| Situation | Flags |
|---|---|
| WhatsApp sent | `--channel whatsapp --direction out --to "+91 ..." --body-file msg.txt` |
| Email sent | `--channel email --direction out --to a@b.com --subject "..." --body-file msg.txt` |
| Not on WhatsApp | `--channel whatsapp --direction out --to "+91 ..." --result not_on_whatsapp` |
| Email bounced | `--channel email --direction out --to a@b.com --result bounced` |
| Their reply | `--channel whatsapp --direction in --to "+91 ..." --body "Hi sure"` |
| Bot or canned intro | `--direction in ... --result auto_reply` |
| Call not answered | `--channel call --direction out --to "+91 ..." --result no_answer` |
| Something happened earlier | add `--at 2026-11-17T12:28:00+05:30` |

## Call / meeting summaries (`convo`)
Write this JSON from the user's transcript or notes. Leave a field out when it's unknown, and never guess.
```json
{
  "kind": "call",
  "occurred_at": "2026-11-18T16:30:00+05:30",
  "duration_min": 12,
  "contact_person": "Mr. Rao (owner)",
  "summary": "2-4 sentences: who we spoke to, what was discussed, where it stands.",
  "current_tools": "What they use today, e.g. 'No CRM; leads in WhatsApp + Excel'",
  "pain_points": "In their words where possible",
  "budget_timeline": "Any budget, decision maker, or timing mentioned",
  "objections": "Concerns raised",
  "promised": "What WE promised to send or do, with dates",
  "next_step": "One concrete next action",
  "next_followup": "2026-11-20",
  "outcome": "positive | neutral | negative | no_answer",
  "transcript": "Full transcript if the user gave one",
  "recording_consent": true
}
```
`kind` can be call, meeting, demo, whatsapp_thread or email_thread. A `whatsapp_thread` summary is useful when a chat goes back and forth several times.

## Reading
- `show LEAD_ID`: the lead, its contacts (with WhatsApp status), every touch and every conversation, oldest first. Read it before any follow-up so the next message fits the history.
- `mine [--status S]`: your leads.
- `followups [--all]`: due today or overdue.
- `quota`: companies you messaged today, per channel.
- `export FILE.xlsx [--mine] [--category C]`: a spreadsheet of the pipeline.

## Ownership
- `release LEAD_ID`: give a lead back so someone else can take it.
- `reclaim LEAD_ID`: take an unowned or released lead, or a claim older than 3 days with no outreach. Admins can take any lead.
- `dnc LEAD_ID "reason"`: anyone can do this. It is permanent unless an admin undoes it.

## Importing an older spreadsheet
`import-sheet FILE.xlsx --category construction --city Hyderabad --dry-run` shows what would be created. Run it again without `--dry-run` to import.

Rows already in the CRM come back as TAKEN and are not duplicated. Sent WhatsApp/email rows become touches, with the time and number read from Notes when they follow the format "WA sent 12:19 to +91 ...".
