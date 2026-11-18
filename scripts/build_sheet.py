"""Build or update the clinic leads spreadsheet.

Usage:
    python3 build_sheet.py leads.json Clinic_Leads.xlsx

leads.json is a list of objects. Keys (missing ones are left blank):
    clinic, website, specialty, doctor, email, phone, instagram, address,
    findings, opportunity, score, message_type, subject, message,
    status, sent_date, followup_date, channels, notes

Rows are sorted by score (highest first). Needs openpyxl (pip install openpyxl).
"""
import json
import sys

from openpyxl import Workbook
from openpyxl.styles import Alignment, Font, PatternFill
from openpyxl.worksheet.datavalidation import DataValidation

COLUMNS = [
    ("Clinic Name", "clinic", 24), ("Website", "website", 22), ("Specialty", "specialty", 22),
    ("Doctor/Founder", "doctor", 26), ("Email", "email", 26), ("Phone / WhatsApp", "phone", 20),
    ("Instagram", "instagram", 26), ("Address", "address", 28),
    ("Content Findings", "findings", 50), ("Content Opportunity", "opportunity", 40),
    ("Lead Score", "score", 8), ("Message Type", "message_type", 22),
    ("Email Subject", "subject", 30), ("Message", "message", 70),
    ("Status", "status", 18), ("Sent Date", "sent_date", 12), ("Follow-up Date", "followup_date", 12),
    ("Channels Sent", "channels", 14), ("Notes", "notes", 40),
]

STATUSES = ["New", "Researching", "Qualified", "Message Ready", "Email Sent", "WhatsApp Sent",
            "Contacted (Email + WhatsApp)", "Replied", "Interested", "Not Interested", "Follow Up",
            "No Contact Found", "Qualified - Hold", "Disqualified - Strong presence", "Disqualified"]


def main(src, out):
    with open(src, encoding="utf-8") as f:
        leads = json.load(f)
    leads.sort(key=lambda x: -(x.get("score") or 0))

    wb = Workbook()
    ws = wb.active
    ws.title = "Leads"
    ws.append([c[0] for c in COLUMNS])
    for cell in ws[1]:
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = PatternFill("solid", fgColor="1F3A5F")
        cell.alignment = Alignment(wrap_text=True, vertical="center")

    for lead in leads:
        row = [lead.get(key, "") for _, key, _ in COLUMNS]
        if not lead.get("status"):
            row[[c[1] for c in COLUMNS].index("status")] = "Message Ready"
        ws.append(row)

    for i, (_, _, width) in enumerate(COLUMNS, start=1):
        ws.column_dimensions[ws.cell(1, i).column_letter].width = width
    for row in ws.iter_rows(min_row=2):
        for cell in row:
            cell.alignment = Alignment(wrap_text=True, vertical="top")
    ws.freeze_panes = "B2"

    status_col = ws.cell(1, [c[1] for c in COLUMNS].index("status") + 1).column_letter
    dv = DataValidation(type="list", formula1='"' + ",".join(STATUSES) + '"', allow_blank=True)
    ws.add_data_validation(dv)
    dv.add(f"{status_col}2:{status_col}{max(ws.max_row, 2)}")

    wb.save(out)
    print(f"Wrote {len(leads)} leads to {out}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
