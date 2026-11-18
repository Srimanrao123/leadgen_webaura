# Sending playbook (what actually works)

Send only after the user has approved the drafts. Verify every send. Never double-send.

## Email via Gmail in Chrome (Claude in Chrome)

1. `tabs_context_mcp`, then open `https://mail.google.com/mail/u/0/#inbox` in a **new** tab.
2. **Check the account** in the tab title ("Inbox – name@gmail.com"). If it's wrong:
   - Try `/mail/u/1/`, `/u/2/` … to find the right account, or
   - The account may be in a **different Chrome profile**. Use `list_connected_browsers`, then `switch_browser` so the user clicks Connect in the right profile.
3. For each email, in one `browser_batch`:
   - navigate `…/#inbox?compose=new`, wait 2s
   - `type` the recipient address, then `key Return` (turns it into a chip; **without Return the To field may stay empty**)
   - `key Tab` → type the subject → `key Tab` → type the body
   - click the recipients row and take a screenshot to check the To chip, subject and body
4. If correct, press `cmd+Enter` (Mac) to send, then `find "Message sent"`.
5. When all are done, open `#sent` and confirm every recipient is listed once.
6. Close the tab you opened.

The From line shows which account is sending. Check it on the first email.

## WhatsApp via the desktop app (Computer use)

1. `request_access` for **WhatsApp**. Prefer the background `app_*` tools.
2. Open a chat for any number, saved or not, from the shell:
   `open "whatsapp://send?phone=91XXXXXXXXXX"` (country code, no + or spaces), then wait about 3s.
3. Take an `app_screenshot` of the **main window** (pass its `window_id`; an incoming-call popup can become the default window, and you must never touch calls).
   - Check that the chat header shows the right number. "Business account" is a good sign.
   - If a dialog says **"isn't on WhatsApp"**, click OK, record it, and skip.
4. `app_type` the message into the compose box. Target by **coordinate**, near the bottom centre of the window. Line breaks are kept.
   - **Type, then take a screenshot, then send, as separate calls.** Never batch typing and sending. WhatsApp sometimes jumps back to the previous chat (often one that just got a bot reply) while you type, and the text can land in the wrong chat's box. Before clicking send, check that the header shows the right number or name **and** that the box holds this lead's text. If the box holds the wrong text, clear it with `app_type` (mode replace, empty text, overwrite_existing) and reopen the chat.
   - If `app_type` reports it was "delivered via raw input", the start of the text may be lost. Scroll up inside the compose box and confirm the greeting is there before sending.
5. Click the green **send** button (bottom right). **The first click often doesn't send.** Wait 2–3s and take a screenshot:
   - If the text is still in the box **and the chat isn't at the top of the list**, click send once more.
   - If the bubble shows in the chat with a time and tick, it's sent. Don't click again.
6. Send long content (for example 3 scripts) as several messages: intro first, then one per item.
7. When done, `app_release`.

## WhatsApp Web alternative
If computer use is off, open `web.whatsapp.com` in Chrome (the user scans the QR code if needed), search the number in a new chat, and paste and send the same text. The same checks apply.

## Pacing and safety
- Send 20 or fewer new contacts per day per channel. WhatsApp can ban numbers that send bulk unsolicited messages.
- Never contact a number the user hasn't approved. Never send automated follow-ups without asking.
- If anyone replies "stop" or "not interested", run `crm.py dnc` right away and stop.

## After each send, log it in the CRM
Right after each verified send (or failure), run `crm.py touch ...` (see crm-guide.md). The CRM records the time, number, text and result, and sets Contacted plus a +4-day follow-up.
When a "not on WhatsApp" dialog appears, log `--result not_on_whatsapp` for that number so no teammate tries it again. Click the dialog's OK using a fresh screenshot, because its position changes.
Export a sheet with `crm.py export` whenever the user wants one. The CRM, not the sheet, is the record.
