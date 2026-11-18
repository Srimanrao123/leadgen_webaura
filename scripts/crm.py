#!/usr/bin/env python3
"""Shared outreach CRM (Supabase) for the outreach skill. Standard library only
(openpyxl is needed for export/import-sheet).

One-time setup, run by each teammate in their own terminal:
    cp .env.example .env      # then fill SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY, CRM_EMAIL
    python3 crm.py login      # asks for the password; it is never stored
(`crm.py setup --url ... --key ...` still works instead of .env.)
Login tokens live in ~/.config/outreach-crm/config.json, never in the repo.

Everyday commands (Claude runs these):
    whoami                              who am I, am I active
    check  FILE.json|-                  which of these companies does the team already have?
    claim  FILE.json|-                  claim the new ones for me (duplicates are refused)
    update LEAD_ID FILE.json|-          change fields on my lead (score, message, status, notes ...)
    add-contact LEAD_ID KIND VALUE [--label L]     KIND = phone|email|domain|instagram
    touch  LEAD_ID --channel C --direction out|in [--to N] [--subject S] [--body-file F|--body T]
           [--result R] [--at ISO]      log a message sent or received
    convo  LEAD_ID FILE.json|-          log a call / meeting summary (see SKILL.md for fields)
    show   LEAD_ID                      everything about one lead
    mine   [--status S]                 my leads
    followups [--all]                   follow-ups due (mine, or the whole team)
    quota                               companies I messaged today per channel
    progress [--day D] [--all]          my (or everyone's) targets vs achieved, and what's pending
    leaderboard [--period today|week|month]
    target NAME --new N --followups N --conversations N [--day D --note T]   (admin) set targets
    target NAME --day D --clear                                              (admin) remove a day override
    brief                               my day in one call: progress, rank, due follow-ups, hot leads, promises, quote
    team-report                         whole team: progress, leaderboard, overdue, stale claims, promises
    find TEXT                           find a lead by name / phone / email / city
    quote                               today's motivation quote
    watchlist                           my active leads: where to look for replies + last sent / last reply logged
    dnc    LEAD_ID "reason"             nobody may contact this lead again
    release LEAD_ID | reclaim LEAD_ID
    export OUT.xlsx [--mine] [--category C]
    dashboard [OUT.html] [--open]       write the team dashboard page (default ~/Desktop/Outreach Dashboard.html)
    import-sheet FILE.xlsx --category C [--city CITY] [--dry-run]

Lead JSON for check/claim (a list, or one object):
    {"company": "...", "category": "clinic|construction|...", "city": "...", "area": "...",
     "website": "...", "phones": ["+91 ... (WhatsApp)"], "emails": ["..."], "instagram": "@handle",
     "segment": "...", "contact_person": "...", "score": 72, "status": "Claimed|Disqualified", ...}
"""
import argparse
import datetime as dt
import getpass
import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request

CONFIG = os.environ.get("OUTREACH_CRM_CONFIG", os.path.expanduser("~/.config/outreach-crm/config.json"))
IST = dt.timezone(dt.timedelta(hours=5, minutes=30))
LEAD_FIELDS = ["company", "category", "segment", "city", "area", "address", "website", "contact_person", "score",
               "message_type", "findings", "opportunity", "email_subject", "message", "status", "next_followup", "notes"]
CONVO_FIELDS = ["kind", "occurred_at", "duration_min", "contact_person", "summary", "current_tools", "pain_points",
                "budget_timeline", "objections", "promised", "next_step", "next_followup", "outcome", "transcript",
                "recording_consent"]


# ---------------------------------------------------------------- config & auth
SKILL_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))


def read_dotenv():
    """Project settings come from the environment or the skill folder's .env (see .env.example)."""
    env = {}
    path = os.path.join(SKILL_DIR, ".env")
    if os.path.exists(path):
        for line in open(path, encoding="utf-8"):
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip().strip('"').strip("'")
    for k in ("SUPABASE_URL", "SUPABASE_PUBLISHABLE_KEY", "CRM_EMAIL"):
        if os.environ.get(k):
            env[k] = os.environ[k]
    return env


def load_cfg():
    """Project URL/key: .env (or environment) wins, else `crm.py setup`. Login tokens always stay in CONFIG."""
    cfg = {}
    if os.path.exists(CONFIG):
        with open(CONFIG) as f:
            cfg = json.load(f)
    env = read_dotenv()
    url, key = env.get("SUPABASE_URL", "").rstrip("/"), env.get("SUPABASE_PUBLISHABLE_KEY", "")
    if url and key:
        if cfg.get("url") and cfg["url"] != url:   # different project: the old login is not valid there
            cfg = {}
        cfg.update(url=url, key=key)
    if not cfg.get("url") or not cfg.get("key"):
        sys.exit(f"Not set up. Copy .env.example to .env in {SKILL_DIR} and fill in SUPABASE_URL and "
                 "SUPABASE_PUBLISHABLE_KEY (or run: python3 crm.py setup --url ... --key ...).")
    if re.search(r"service_role|sb_secret_", cfg["key"]):
        sys.exit("SUPABASE_PUBLISHABLE_KEY looks like a secret/service_role key. Use the publishable (anon) key.")
    return cfg


def save_cfg(cfg):
    os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
    tmp = CONFIG + ".tmp"
    with open(os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600), "w") as f:
        json.dump(cfg, f, indent=2)
    os.replace(tmp, CONFIG)


_SSL_CTX = None


def ssl_context():
    """python.org builds on macOS ship without CA certificates. Fall back to certifi, then the Mac's system roots."""
    global _SSL_CTX
    if _SSL_CTX:
        return _SSL_CTX
    import ssl
    import subprocess
    paths = ssl.get_default_verify_paths()
    if os.environ.get("SSL_CERT_FILE") or (paths.cafile and os.path.exists(paths.cafile)) or \
            (paths.openssl_cafile and os.path.exists(paths.openssl_cafile)):
        _SSL_CTX = ssl.create_default_context()
        return _SSL_CTX
    try:
        import certifi
        _SSL_CTX = ssl.create_default_context(cafile=certifi.where())
        return _SSL_CTX
    except ImportError:
        pass
    if sys.platform == "darwin":
        pem = os.path.join(os.path.dirname(CONFIG), "macos-roots.pem")
        if not os.path.exists(pem):
            os.makedirs(os.path.dirname(pem), exist_ok=True)
            certs = subprocess.run(["security", "find-certificate", "-a", "-p",
                                    "/System/Library/Keychains/SystemRootCertificates.keychain"],
                                   capture_output=True, text=True).stdout
            if "BEGIN CERTIFICATE" in certs:
                with open(pem, "w") as f:
                    f.write(certs)
        if os.path.exists(pem):
            _SSL_CTX = ssl.create_default_context(cafile=pem)
            return _SSL_CTX
    _SSL_CTX = ssl.create_default_context()
    return _SSL_CTX


def http(method, url, key, token=None, body=None, headers=None):
    h = {"apikey": key, "Content-Type": "application/json", "Accept": "application/json"}
    if token:
        h["Authorization"] = "Bearer " + token
    h.update(headers or {})
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=30, context=ssl_context()) as r:
            raw = r.read()
            return json.loads(raw) if raw else None
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try:
            err = json.loads(raw)
            msg = err.get("message") or err.get("msg") or err.get("error_description") or err.get("error") or raw
            if err.get("hint"):
                msg += f" (hint: {err['hint']})"
        except ValueError:
            msg = raw
        sys.exit(f"Supabase error {e.code}: {msg}")
    except urllib.error.URLError as e:
        sys.exit(f"Cannot reach Supabase: {e.reason}")


def auth_token(cfg, grant, body):
    res = http("POST", f"{cfg['url']}/auth/v1/token?grant_type={grant}", cfg["key"], body=body)
    cfg.update(access_token=res["access_token"], refresh_token=res["refresh_token"],
               expires_at=int(res.get("expires_at") or (dt.datetime.now().timestamp() + res.get("expires_in", 3600))),
               user_id=res["user"]["id"], email=res["user"].get("email"))
    save_cfg(cfg)
    return cfg


def session():
    cfg = load_cfg()
    if not cfg.get("refresh_token"):
        sys.exit("Not signed in. Run in your terminal: python3 crm.py login --email you@example.com")
    if cfg.get("expires_at", 0) - 60 < dt.datetime.now().timestamp():
        auth_token(cfg, "refresh_token", {"refresh_token": cfg["refresh_token"]})
    return cfg


class Api:
    def __init__(self):
        self.cfg = session()

    def rpc(self, fn, **args):
        return http("POST", f"{self.cfg['url']}/rest/v1/rpc/{fn}", self.cfg["key"], self.cfg["access_token"], args)

    def get(self, table, **params):
        q = urllib.parse.urlencode(params)
        return http("GET", f"{self.cfg['url']}/rest/v1/{table}?{q}", self.cfg["key"], self.cfg["access_token"])

    def insert(self, table, row):
        return http("POST", f"{self.cfg['url']}/rest/v1/{table}", self.cfg["key"], self.cfg["access_token"], row,
                    {"Prefer": "return=representation"})

    def patch(self, table, filters, row):
        q = urllib.parse.urlencode(filters)
        return http("PATCH", f"{self.cfg['url']}/rest/v1/{table}?{q}", self.cfg["key"], self.cfg["access_token"], row,
                    {"Prefer": "return=representation"})

    @property
    def uid(self):
        return self.cfg["user_id"]


# ---------------------------------------------------------------- helpers
def read_json(src):
    text = sys.stdin.read() if src == "-" else open(src, encoding="utf-8").read()
    return json.loads(text)


def out(obj):
    print(json.dumps(obj, indent=2, ensure_ascii=False, default=str))


def split_phones(value):
    """'+91 84848 45566 (Hyd) / 89888 95566 (Blr)' -> [('+91 84848 45566', 'Hyd'), ('89888 95566', 'Blr')]"""
    res = []
    for part in re.split(r"\s*[/,;]\s*|\s+or\s+", str(value or "")):
        label = ", ".join(re.findall(r"\(([^)]*)\)", part)) or None
        num = re.sub(r"\([^)]*\)", "", part).strip()
        if len(re.sub(r"\D", "", num)) >= 10:
            res.append((num, label))
    return res


def to_payload(item):
    """Accept friendly keys (phones/emails/instagram) and build the contacts list the DB expects."""
    p = {k: v for k, v in item.items() if k not in ("phones", "phone", "emails", "email", "instagram") and v not in (None, "")}
    contacts = list(item.get("contacts") or [])
    phones = item.get("phones") or item.get("phone") or []
    for ph in ([phones] if isinstance(phones, str) else phones):
        for num, label in split_phones(ph):
            contacts.append({"kind": "phone", "value": num, "label": label})
    emails = item.get("emails") or item.get("email") or []
    for em in ([emails] if isinstance(emails, str) else emails):
        for e in re.findall(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+", str(em)):
            contacts.append({"kind": "email", "value": e})
    ig = item.get("instagram")
    if ig:
        m = re.search(r"@?([A-Za-z0-9._]{2,30})", str(ig).replace("instagram.com/", ""))
        if m and "#" not in str(ig):
            contacts.append({"kind": "instagram", "value": m.group(1)})
    p["contacts"] = contacts
    if p.get("score") not in (None, ""):
        p["score"] = int(p["score"])
    return p


def as_list(data):
    return data if isinstance(data, list) else [data]


def describe_dups(dups):
    seen, lines = set(), []
    for d in dups:
        key = d["lead_id"]
        if key in seen:
            continue
        seen.add(key)
        how = [f"{x['matched_on']}={x['matched_value']}" for x in dups if x["lead_id"] == key]
        flag = " [DO NOT CONTACT]" if d.get("dnc") else ""
        lines.append(f"lead {key} '{d['company']}' owned by {d.get('owner_name') or 'nobody'}, "
                     f"status {d['status']}{flag} (matched {', '.join(how)})")
    return lines


# ---------------------------------------------------------------- commands
def cmd_setup(a):
    cfg = {}
    if os.path.exists(CONFIG):
        cfg = load_cfg()
    url = a.url.rstrip("/")
    if not re.match(r"^https://[a-z0-9-]+\.supabase\.(co|in)$", url) and not a.any_url:
        sys.exit("URL should look like https://abcdefgh.supabase.co (use --any-url for a self-hosted Supabase).")
    if cfg.get("url") != url:
        cfg = {}
    cfg.update(url=url, key=a.key.strip())
    save_cfg(cfg)
    print(f"Saved to {CONFIG}. Now run: python3 {sys.argv[0]} login --email you@example.com")


def cmd_login(a):
    if not a.email:
        sys.exit("Give --email you@example.com, or set CRM_EMAIL in .env")
    cfg = load_cfg()
    pw = getpass.getpass(f"Supabase password for {a.email}: ")
    auth_token(cfg, "password", {"email": a.email, "password": pw})
    api = Api()
    me = api.get("team", id=f"eq.{api.uid}", select="name,active,is_admin,daily_limit")
    if not me:
        print("Signed in, but there is no team row yet. Ask the admin to run the activation SQL in SETUP.md.")
    elif not me[0]["active"]:
        print(f"Signed in as {me[0]['name']}, but not active yet. Ask the admin to activate you.")
    else:
        print(f"Signed in as {me[0]['name']}{' (admin)' if me[0]['is_admin'] else ''}. Ready.")


def cmd_whoami(a):
    api = Api()
    me = api.get("team", id=f"eq.{api.uid}", select="name,active,is_admin,daily_limit")
    out({"email": api.cfg.get("email"), "user_id": api.uid, **(me[0] if me else {"team_row": None})})


def cmd_check(a):
    api = Api()
    items = [to_payload(x) for x in as_list(read_json(a.file))]
    for i, p in enumerate(items):
        p.setdefault("ref", str(i + 1))
    rows = api.rpc("check_batch", p=items)
    res = []
    for r in rows:
        dups = r["duplicates"]
        res.append({"ref": r["ref"], "company": r["company"], "result": "TAKEN" if dups else "NEW",
                    "details": describe_dups(dups)})
    out(res)


def cmd_claim(a):
    api = Api()
    results = []
    for item in as_list(read_json(a.file)):
        p = to_payload(item)
        if a.allow_same_name:
            p["allow_same_name"] = True
        r = api.rpc("claim_lead", p=p)
        if r.get("ok"):
            results.append({"company": p["company"], "result": "CLAIMED", "lead_id": r["lead_id"]})
        else:
            results.append({"company": p["company"], "result": "TAKEN", "details": describe_dups(r.get("duplicates", []))})
    out(results)


def cmd_update(a):
    api = Api()
    data = read_json(a.file)
    bad = [k for k in data if k not in LEAD_FIELDS]
    if bad:
        sys.exit(f"Unknown or protected fields: {bad}. Allowed: {LEAD_FIELDS}")
    rows = api.patch("leads", {"id": f"eq.{a.lead_id}"}, data)
    if not rows:
        sys.exit(f"Nothing updated: lead {a.lead_id} does not exist or is not yours.")
    out({k: rows[0][k] for k in ("id", "company", "status", "score", "next_followup")})


def cmd_add_contact(a):
    out(Api().rpc("add_contact", p_lead_id=a.lead_id, p_kind=a.kind, p_value=a.value, p_label=a.label))


def cmd_touch(a):
    api = Api()
    body = open(a.body_file, encoding="utf-8").read() if a.body_file else a.body
    row = {"lead_id": a.lead_id, "member_id": api.uid, "channel": a.channel, "direction": a.direction,
           "contact_value": a.to, "subject": a.subject, "body": body,
           "result": a.result or ("replied" if a.direction == "in" else "sent")}
    if a.at:
        row["occurred_at"] = a.at
    r = api.insert("touches", {k: v for k, v in row.items() if v is not None})[0]
    lead = api.get("leads", id=f"eq.{a.lead_id}", select="company,status,next_followup")[0]
    out({"touch_id": r["id"], "logged": f"{a.direction} {a.channel} {r['result']}", **lead})


def cmd_convo(a):
    api = Api()
    data = read_json(a.file)
    bad = [k for k in data if k not in CONVO_FIELDS]
    if bad:
        sys.exit(f"Unknown fields: {bad}. Allowed: {CONVO_FIELDS}")
    if not data.get("summary"):
        sys.exit("A conversation needs a 'summary'.")
    r = api.insert("conversations", {"lead_id": a.lead_id, "member_id": api.uid, **data})[0]
    out({"conversation_id": r["id"], "lead_id": a.lead_id, "next_followup": r.get("next_followup")})


def cmd_show(a):
    api = Api()
    lead = api.get("pipeline", id=f"eq.{a.lead_id}")
    if not lead:
        sys.exit(f"No lead {a.lead_id}")
    touches = api.get("touches", lead_id=f"eq.{a.lead_id}", order="occurred_at",
                      select="occurred_at,channel,direction,contact_value,result,subject,body,team(name)")
    convos = api.get("conversations", lead_id=f"eq.{a.lead_id}", order="occurred_at", select="*,team(name)")
    out({"lead": lead[0], "touches": touches, "conversations": convos})


SUMMARY_COLS = "id,company,category,city,status,score,owner_name,last_touch_at,next_followup,dnc,contacts"


def cmd_mine(a):
    api = Api()
    params = {"owner_id": f"eq.{api.uid}", "select": SUMMARY_COLS, "order": "next_followup.asc.nullslast,score.desc.nullslast"}
    if a.status:
        params["status"] = f"eq.{a.status}"
    out(api.get("pipeline", **params))


def cmd_followups(a):
    api = Api()
    params = {"select": SUMMARY_COLS, "order": "next_followup.asc"}
    if not a.all:
        params["owner_id"] = f"eq.{api.uid}"
    out(api.get("followups_due", **params))


def cmd_quota(a):
    out(Api().rpc("my_quota"))


def ist_today():
    return dt.datetime.now(IST).date()


def cmd_progress(a):
    api = Api()
    rows = api.rpc("daily_progress", p_day=a.day or str(ist_today()))
    if not a.all:
        rows = [r for r in rows if r["member_id"] == api.uid]
    out(rows)


def cmd_leaderboard(a):
    t = ist_today()
    start = {"today": t, "week": t - dt.timedelta(days=t.weekday()), "month": t.replace(day=1)}[a.period]
    out(Api().rpc("leaderboard", p_from=str(start), p_to=str(t)))


def cmd_target(a):
    api = Api()
    team = api.get("team", select="id,name,active", active="eq.true")
    match = [m for m in team if m["name"].lower() == a.name.lower()]
    if len(match) != 1:
        sys.exit(f"No single active teammate named '{a.name}'. Team: {', '.join(m['name'] for m in team)}")
    mid = match[0]["id"]
    if a.clear:
        if not a.day:
            sys.exit("--clear needs --day YYYY-MM-DD")
        out(api.rpc("clear_day_target", p_member=mid, p_day=a.day))
        return
    if None in (a.new, a.followups, a.conversations):
        sys.exit("Give --new, --followups and --conversations (numbers).")
    out(api.rpc("set_targets", p_member=mid, p_new_contacts=a.new, p_followups=a.followups,
                p_conversations=a.conversations, p_day=a.day, p_note=a.note))


# ---------------------------------------------------------------- reports (Claude turns these into plain-language summaries)
def load_quotes():
    with open(os.path.join(SKILL_DIR, "dashboard", "quotes.json"), encoding="utf-8") as f:
        return json.load(f)


def quote_of_day(day=None):
    """Same pick as the dashboard: days since 1970-01-01 (IST date) modulo the list length."""
    quotes = load_quotes()
    day = day or ist_today()
    return quotes[(day - dt.date(1970, 1, 1)).days % len(quotes)]


def soft(fn):
    """Run an API call; on error return {'error': ...} instead of exiting (so one missing piece doesn't kill a report)."""
    try:
        return fn()
    except SystemExit as e:
        return {"error": str(e)}


def standing(board, uid):
    if not isinstance(board, list) or not board:
        return None
    mine = next((r for r in board if r["member_id"] == uid), None)
    if not mine:
        return None
    i = board.index(mine)
    res = {"rank": mine["rank"], "of": len(board), "points": mine["points"]}
    if i > 0:
        above = board[i - 1]
        res.update(next_above=above["name"], points_to_pass=above["points"] - mine["points"] + 1)
    elif len(board) > 1:
        res.update(leading_by=mine["points"] - board[1]["points"], second=board[1]["name"])
    return res


def open_promises(api, member_id=None, days=14):
    """Things we promised in a logged conversation with no outgoing message to that lead since."""
    since = (dt.datetime.now(IST) - dt.timedelta(days=days)).isoformat()
    params = {"promised": "not.is.null", "occurred_at": f"gte.{since}", "order": "occurred_at.desc",
              "select": "lead_id,promised,next_step,next_followup,occurred_at,member_id,leads(company,status,owner_id,dnc)"}
    if member_id:
        params["member_id"] = f"eq.{member_id}"
    convos = api.get("conversations", **params)
    latest = {}
    for c in convos:
        latest.setdefault(c["lead_id"], c)
    if not latest:
        return []
    ids = ",".join(str(i) for i in latest)
    outs = api.get("touches", lead_id=f"in.({ids})", direction="eq.out", select="lead_id,occurred_at",
                   result="in.(sent,delivered,read)")
    last_out = {}
    for t in outs:
        last_out[t["lead_id"]] = max(last_out.get(t["lead_id"], ""), t["occurred_at"])
    res = []
    for lid, c in latest.items():
        lead = c.get("leads") or {}
        if lead.get("dnc") or lead.get("status") in ("Won", "Lost", "Not Interested"):
            continue
        if last_out.get(lid, "") > c["occurred_at"]:
            continue
        res.append({"lead_id": lid, "company": lead.get("company"), "promised": c["promised"], "promised_on": c["occurred_at"],
                    "next_step": c.get("next_step"), "follow_up": c.get("next_followup")})
    return res


def cmd_brief(a):
    """Everything for a start-of-day briefing or an end-of-task report, for the signed-in user."""
    api = Api()
    t = ist_today()
    week0 = t - dt.timedelta(days=t.weekday())
    prog = soft(lambda: api.rpc("daily_progress", p_day=str(t)))
    lb_today = soft(lambda: api.rpc("leaderboard", p_from=str(t), p_to=str(t)))
    lb_week = soft(lambda: api.rpc("leaderboard", p_from=str(week0), p_to=str(t)))
    mine = next((r for r in prog if r["member_id"] == api.uid), None) if isinstance(prog, list) else None
    hot = api.get("pipeline", owner_id=f"eq.{api.uid}", status='in.(Replied,Interested,"Demo Scheduled","Proposal Sent")',
                  select="id,company,status,next_followup,last_touch_at", order="last_touch_at.desc.nullslast")
    due = api.get("followups_due", owner_id=f"eq.{api.uid}", select="id,company,status,next_followup,last_touch_at",
                  order="next_followup.asc")
    claimed = api.get("pipeline", owner_id=f"eq.{api.uid}", status="eq.Claimed", select="id,company,claimed_at", order="claimed_at")
    out({
        "date": str(t),
        "quote": quote_of_day(t),
        "progress": mine if mine else (prog if isinstance(prog, dict) else None),
        "rank_today": standing(lb_today, api.uid),
        "rank_week": standing(lb_week, api.uid),
        "followups_due": due,
        "hot_leads": hot,
        "open_promises": open_promises(api, api.uid),
        "claimed_not_contacted": claimed,
    })


def cmd_team_report(a):
    """Team overview for the admin: progress vs targets, leaderboard, overdue work, stale claims, open promises."""
    api = Api()
    t = ist_today()
    week0 = t - dt.timedelta(days=t.weekday())
    stale_before = (dt.datetime.now(IST) - dt.timedelta(days=2)).isoformat()
    due = api.get("followups_due", select="id,company,owner_name,next_followup,status", order="next_followup.asc")
    overdue = {}
    for d in due:
        overdue.setdefault(d["owner_name"] or "Unowned", []).append(d["company"])
    stale = api.get("pipeline", status="eq.Claimed", claimed_at=f"lt.{stale_before}", select="id,company,owner_name,claimed_at")
    out({
        "date": str(t),
        "quote": quote_of_day(t),
        "progress_today": soft(lambda: api.rpc("daily_progress", p_day=str(t))),
        "leaderboard_today": soft(lambda: api.rpc("leaderboard", p_from=str(t), p_to=str(t))),
        "leaderboard_week": soft(lambda: api.rpc("leaderboard", p_from=str(week0), p_to=str(t))),
        "followups_due_by_person": overdue,
        "claimed_over_2_days_no_outreach": stale,
        "open_promises": open_promises(api),
        "hot_leads": api.get("pipeline", status='in.(Interested,"Demo Scheduled","Proposal Sent")',
                             select="id,company,status,owner_name,next_followup", order="next_followup.asc.nullslast"),
    })


def cmd_find(a):
    """Find leads by (part of) company name, city, phone, email or website, so plain-language logging can resolve a lead."""
    api = Api()
    rows = api.get("pipeline", select="id,company,status,owner_id,owner_name,city,next_followup,dnc,contacts")
    q = a.text.lower().strip()
    qd = re.sub(r"\D", "", q)
    words = [w for w in re.split(r"\W+", q) if w]
    hits = []
    for r in rows:
        hay = " ".join([r["company"] or "", r["city"] or ""] + [c["value"] for c in (r.get("contacts") or [])]).lower()
        score = 3 if q in (r["company"] or "").lower() else 0
        score += sum(1 for w in words if w in hay)
        if len(qd) >= 6 and qd in re.sub(r"\D", "", hay):
            score += 5
        if score:
            hits.append((score, r))
    hits.sort(key=lambda x: -x[0])
    out([{**r, "mine": r["owner_id"] == api.uid} for _, r in hits[:8]])


def cmd_watchlist(a):
    """My active leads with where to look for replies (WhatsApp numbers, emails) and what's already logged,
    so a 'check my replies' run only logs messages newer than the last logged one."""
    api = Api()
    leads = api.get("pipeline", owner_id=f"eq.{api.uid}", dnc="eq.false",
                    status='in.(Contacted,Replied,Interested,"Demo Scheduled","Proposal Sent")',
                    select="id,company,status,contacts,next_followup", order="last_touch_at.desc.nullslast")
    if not leads:
        out([])
        return
    ids = ",".join(str(l["id"]) for l in leads)
    touches = api.get("touches", lead_id=f"in.({ids})", select="lead_id,direction,channel,contact_value,result,body,occurred_at",
                      order="occurred_at.desc")
    res = []
    for l in leads:
        ts = [t for t in touches if t["lead_id"] == l["id"]]
        last_out = next((t for t in ts if t["direction"] == "out" and t["result"] in ("sent", "delivered", "read")), None)
        last_in = next((t for t in ts if t["direction"] == "in"), None)
        cs = l.get("contacts") or []
        res.append({
            "lead_id": l["id"], "company": l["company"], "status": l["status"], "next_followup": l["next_followup"],
            "whatsapp_numbers": [c["value"] for c in cs if c["kind"] == "phone" and c.get("whatsapp") != "not_on_whatsapp"],
            "emails": [c["value"] for c in cs if c["kind"] == "email"],
            "last_sent": last_out and {"at": last_out["occurred_at"], "channel": last_out["channel"], "to": last_out["contact_value"]},
            "last_reply_logged": last_in and {"at": last_in["occurred_at"], "channel": last_in["channel"],
                                              "text": (last_in["body"] or "")[:160]},
        })
    out(res)


def cmd_quote(a):
    out(quote_of_day())


def cmd_dnc(a):
    out(Api().rpc("mark_dnc", p_lead_id=a.lead_id, p_reason=a.reason))


def cmd_release(a):
    out(Api().rpc("release_lead", p_lead_id=a.lead_id))


def cmd_reclaim(a):
    out(Api().rpc("reclaim_lead", p_lead_id=a.lead_id))


def cmd_export(a):
    from openpyxl import Workbook
    from openpyxl.styles import Alignment, Font, PatternFill
    api = Api()
    params = {"select": "*", "order": "score.desc.nullslast"}
    if a.mine:
        params["owner_id"] = f"eq.{api.uid}"
    if a.category:
        params["category"] = f"eq.{a.category}"
    rows = api.get("pipeline", **params)
    cols = [("ID", "id", 6), ("Company", "company", 26), ("Category", "category", 12), ("Segment", "segment", 20),
            ("City", "city", 12), ("Owner", "owner_name", 12), ("Status", "status", 14), ("Score", "score", 7),
            ("Website", "website", 24), ("Phones", "_phones", 22), ("Emails", "_emails", 28), ("Instagram", "_ig", 20),
            ("Last touch", "last_touch_at", 18), ("Next follow-up", "next_followup", 12), ("Sent", "messages_sent", 6),
            ("Received", "messages_received", 8), ("Calls/meetings", "conversations", 8), ("DNC", "dnc", 5),
            ("Findings", "findings", 50), ("Message", "message", 60), ("Notes", "notes", 40)]
    wb = Workbook()
    ws = wb.active
    ws.title = "Pipeline"
    ws.append([c[0] for c in cols])
    for cell in ws[1]:
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = PatternFill("solid", fgColor="1F3A5F")
    for r in rows:
        cs = r.get("contacts") or []
        pick = lambda k: "\n".join(
            c["value"] + (f" ({c['label']})" if c.get("label") else "") +
            (" [not on WhatsApp]" if c.get("whatsapp") == "not_on_whatsapp" else "") for c in cs if c["kind"] == k)
        r.update(_phones=pick("phone"), _emails=pick("email"), _ig=pick("instagram"))
        ws.append([("" if r.get(k) is None else str(r.get(k))[:32000]) for _, k, _ in cols])
    for i, (_, _, w) in enumerate(cols, start=1):
        ws.column_dimensions[ws.cell(1, i).column_letter].width = w
    for row in ws.iter_rows(min_row=2):
        for cell in row:
            cell.alignment = Alignment(wrap_text=True, vertical="top")
    ws.freeze_panes = "C2"
    wb.save(a.out)
    print(f"Exported {len(rows)} leads to {a.out}")


def cmd_dashboard(a):
    """Write the dashboard page with this project's URL and publishable key filled in (no tokens, no passwords)."""
    cfg = load_cfg()
    if re.search(r"service_role|sb_secret_", cfg["key"]):
        sys.exit("The configured key looks like a secret key. Use the publishable (anon) key: crm.py setup ...")
    template = os.path.join(SKILL_DIR, "dashboard", "index.html")
    html = open(template, encoding="utf-8").read()
    block = re.compile(r"/\*CONFIG\*/.*?/\*END CONFIG\*/", re.S)
    qblock = re.compile(r"/\*QUOTES\*/.*?/\*END QUOTES\*/", re.S)
    if not block.search(html) or not qblock.search(html):
        sys.exit("Dashboard template is missing its CONFIG or QUOTES block.")
    filled = block.sub(lambda m: "/*CONFIG*/const CONFIG = " + json.dumps({"url": cfg["url"], "key": cfg["key"]}) + ";/*END CONFIG*/", html)
    filled = qblock.sub(lambda m: "/*QUOTES*/const QUOTES = " + json.dumps(load_quotes(), ensure_ascii=False) + ";/*END QUOTES*/", filled)
    path = os.path.abspath(os.path.expanduser(a.out))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(filled)
    print(f"Wrote {path}")
    if a.open:
        import subprocess
        subprocess.run(["open" if sys.platform == "darwin" else "xdg-open", path])


# Map the skill's older spreadsheets into the DB.
SHEET_MAP = {
    "company": ["company name", "clinic name", "company", "clinic"], "website": ["website"],
    "segment": ["type", "specialty"], "contact_person": ["founder/contact", "doctor/founder", "contact"],
    "email": ["email"], "phone": ["phone / whatsapp", "phone"], "instagram": ["instagram"], "address": ["address"],
    "findings": ["findings (lead handling)", "content findings", "findings"],
    "opportunity": ["crm / automation opportunity", "content opportunity", "opportunity"], "score": ["lead score", "score"],
    "message_type": ["message type"], "email_subject": ["email subject"], "message": ["message"], "status": ["status"],
    "sent_date": ["sent date"], "channels": ["channels sent"], "notes": ["notes"],
}
STATUS_MAP = {"interested": "Interested", "replied": "Replied", "not interested": "Not Interested",
              "disqualified": "Disqualified", "disqualified - strong presence": "Disqualified"}


def cmd_import_sheet(a):
    from openpyxl import load_workbook
    ws = load_workbook(a.file, data_only=True).active
    header = [str(c.value or "").strip().lower() for c in ws[1]]
    idx = {}
    for key, names in SHEET_MAP.items():
        for n in names:
            if n in header:
                idx[key] = header.index(n)
                break
    if "company" not in idx:
        sys.exit(f"No company column found in {header}")
    plans = []
    for row in ws.iter_rows(min_row=2, values_only=True):
        g = lambda k: row[idx[k]] if k in idx and row[idx[k]] not in (None, "") else None
        if not g("company"):
            continue
        status_raw = str(g("status") or "").strip()
        lead = {"company": g("company"), "category": a.category, "city": a.city, "website": g("website"),
                "segment": g("segment"), "contact_person": None if str(g("contact_person") or "").lower() == "not named" else g("contact_person"),
                "phones": [g("phone")] if g("phone") else [], "emails": [g("email")] if g("email") else [],
                "instagram": g("instagram"), "address": g("address"), "findings": g("findings"),
                "opportunity": g("opportunity"), "score": g("score"), "message_type": g("message_type"),
                "email_subject": g("email_subject"), "message": g("message"),
                "notes": g("notes"), "status": "Disqualified" if status_raw.lower().startswith("disqualified") else "Claimed"}
        later_status = STATUS_MAP.get(status_raw.lower())
        touch = None
        channels = str(g("channels") or "").lower()
        sent = g("sent_date")
        if sent and not channels.startswith("planned") and ("whatsapp" in channels or "email" in channels):
            note = str(g("notes") or "")
            m = re.search(r"sent (\d{1,2}):(\d{2}) to (\+?[\d ]{10,16}\d)", note)
            day = sent if isinstance(sent, dt.date) else dt.date.fromisoformat(str(sent)[:10])
            if isinstance(day, dt.datetime):
                day = day.date()
            at = dt.datetime(day.year, day.month, day.day, int(m.group(1)) if m else 12, int(m.group(2)) if m else 0, tzinfo=IST)
            touch = {"channel": "whatsapp" if "whatsapp" in channels else "email", "direction": "out",
                     "to": m.group(3) if m else None, "body": g("message"), "at": at.isoformat(),
                     "subject": None if "whatsapp" in channels else g("email_subject")}
        plans.append({"lead": lead, "touch": touch, "then_status": later_status})
    if a.dry_run:
        out([{"company": p["lead"]["company"], "contacts": to_payload(p["lead"])["contacts"],
              "touch": p["touch"] and {k: v for k, v in p["touch"].items() if k != "body"}, "then_status": p["then_status"]}
             for p in plans])
        return
    api = Api()
    report = []
    for p in plans:
        r = api.rpc("claim_lead", p=to_payload(p["lead"]))
        if not r.get("ok"):
            report.append({"company": p["lead"]["company"], "result": "TAKEN", "details": describe_dups(r.get("duplicates", []))})
            continue
        lid = r["lead_id"]
        if p["touch"]:
            t = p["touch"]
            api.insert("touches", {k: v for k, v in {
                "lead_id": lid, "member_id": api.uid, "channel": t["channel"], "direction": "out",
                "contact_value": t["to"], "subject": t["subject"], "body": t["body"], "result": "sent",
                "occurred_at": t["at"]}.items() if v is not None})
        if p["then_status"]:
            api.patch("leads", {"id": f"eq.{lid}"}, {"status": p["then_status"]})
        report.append({"company": p["lead"]["company"], "result": "IMPORTED", "lead_id": lid,
                       "touch": bool(p["touch"]), "status": p["then_status"] or ("Contacted" if p["touch"] else p["lead"]["status"])})
    out(report)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sp = ap.add_subparsers(dest="cmd", required=True)
    s = sp.add_parser("setup"); s.add_argument("--url", required=True); s.add_argument("--key", required=True)
    s.add_argument("--any-url", action="store_true"); s.set_defaults(f=cmd_setup)
    s = sp.add_parser("login"); s.add_argument("--email", default=read_dotenv().get("CRM_EMAIL"))
    s.set_defaults(f=cmd_login)
    sp.add_parser("whoami").set_defaults(f=cmd_whoami)
    s = sp.add_parser("check"); s.add_argument("file"); s.set_defaults(f=cmd_check)
    s = sp.add_parser("claim"); s.add_argument("file"); s.add_argument("--allow-same-name", action="store_true")
    s.set_defaults(f=cmd_claim)
    s = sp.add_parser("update"); s.add_argument("lead_id", type=int); s.add_argument("file"); s.set_defaults(f=cmd_update)
    s = sp.add_parser("add-contact"); s.add_argument("lead_id", type=int)
    s.add_argument("kind", choices=["phone", "email", "domain", "instagram"]); s.add_argument("value")
    s.add_argument("--label"); s.set_defaults(f=cmd_add_contact)
    s = sp.add_parser("touch"); s.add_argument("lead_id", type=int)
    s.add_argument("--channel", required=True, choices=["email", "whatsapp", "call", "instagram", "linkedin", "in_person", "other"])
    s.add_argument("--direction", required=True, choices=["out", "in"]); s.add_argument("--to")
    s.add_argument("--subject"); s.add_argument("--body"); s.add_argument("--body-file")
    s.add_argument("--result", choices=["sent", "delivered", "read", "replied", "auto_reply", "failed", "bounced",
                                        "not_on_whatsapp", "no_answer", "wrong_number"])
    s.add_argument("--at", help="ISO time, e.g. 2026-11-17T12:28:00+05:30 (default now)"); s.set_defaults(f=cmd_touch)
    s = sp.add_parser("convo"); s.add_argument("lead_id", type=int); s.add_argument("file"); s.set_defaults(f=cmd_convo)
    s = sp.add_parser("show"); s.add_argument("lead_id", type=int); s.set_defaults(f=cmd_show)
    s = sp.add_parser("mine"); s.add_argument("--status"); s.set_defaults(f=cmd_mine)
    s = sp.add_parser("followups"); s.add_argument("--all", action="store_true"); s.set_defaults(f=cmd_followups)
    sp.add_parser("quota").set_defaults(f=cmd_quota)
    s = sp.add_parser("progress"); s.add_argument("--day"); s.add_argument("--all", action="store_true")
    s.set_defaults(f=cmd_progress)
    s = sp.add_parser("leaderboard"); s.add_argument("--period", choices=["today", "week", "month"], default="today")
    s.set_defaults(f=cmd_leaderboard)
    s = sp.add_parser("target"); s.add_argument("name"); s.add_argument("--new", type=int)
    s.add_argument("--followups", type=int); s.add_argument("--conversations", type=int)
    s.add_argument("--day", help="YYYY-MM-DD; omit to change the default"); s.add_argument("--note")
    s.add_argument("--clear", action="store_true"); s.set_defaults(f=cmd_target)
    sp.add_parser("brief").set_defaults(f=cmd_brief)
    sp.add_parser("team-report").set_defaults(f=cmd_team_report)
    s = sp.add_parser("find"); s.add_argument("text"); s.set_defaults(f=cmd_find)
    sp.add_parser("quote").set_defaults(f=cmd_quote)
    sp.add_parser("watchlist").set_defaults(f=cmd_watchlist)
    s = sp.add_parser("dnc"); s.add_argument("lead_id", type=int); s.add_argument("reason"); s.set_defaults(f=cmd_dnc)
    s = sp.add_parser("release"); s.add_argument("lead_id", type=int); s.set_defaults(f=cmd_release)
    s = sp.add_parser("reclaim"); s.add_argument("lead_id", type=int); s.set_defaults(f=cmd_reclaim)
    s = sp.add_parser("export"); s.add_argument("out"); s.add_argument("--mine", action="store_true")
    s.add_argument("--category"); s.set_defaults(f=cmd_export)
    s = sp.add_parser("dashboard"); s.add_argument("out", nargs="?", default="~/Desktop/Outreach Dashboard.html")
    s.add_argument("--open", action="store_true"); s.set_defaults(f=cmd_dashboard)
    s = sp.add_parser("import-sheet"); s.add_argument("file"); s.add_argument("--category", required=True)
    s.add_argument("--city"); s.add_argument("--dry-run", action="store_true"); s.set_defaults(f=cmd_import_sheet)
    a = ap.parse_args()
    a.f(a)


if __name__ == "__main__":
    main()
