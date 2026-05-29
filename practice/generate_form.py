"""
Generate a TOUGH flat (non-interactive) PDF form for fillable-PDF practice.

The output PDF intentionally contains NO AcroForm fields. Your job (the
practice task) is to add interactive form fields on top of it:
text fields, comb fields, checkboxes, radio groups, dropdowns,
multi-line text areas and signature fields.

Run:  python3 generate_form.py
Out:  Employment_Tax_Benefits_Form.pdf  (3 pages)
"""

from reportlab.lib.pagesizes import A4
from reportlab.lib.units import mm
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor

PAGE_W, PAGE_H = A4
MARGIN = 15 * mm

INK = HexColor("#1a1a1a")
GREY = HexColor("#666666")
LIGHT = HexColor("#bbbbbb")
HEAD_BG = HexColor("#dfe6ee")
BAND_BG = HexColor("#2c3e50")


def header(c, page_no, total):
    c.setFillColor(BAND_BG)
    c.rect(0, PAGE_H - 26 * mm, PAGE_W, 26 * mm, fill=1, stroke=0)
    c.setFillColor(HexColor("#ffffff"))
    c.setFont("Helvetica-Bold", 15)
    c.drawString(MARGIN, PAGE_H - 13 * mm, "MERIDIAN GLOBAL SERVICES (PVT.) LTD.")
    c.setFont("Helvetica", 9)
    c.drawString(MARGIN, PAGE_H - 18.5 * mm,
                 "Employment, Tax & Benefits Registration Form  -  Confidential")
    c.setFont("Helvetica", 8)
    c.drawRightString(PAGE_W - MARGIN, PAGE_H - 13 * mm, "Form No. MGS/HR/RF-204")
    c.drawRightString(PAGE_W - MARGIN, PAGE_H - 18.5 * mm,
                      "Page %d of %d" % (page_no, total))

    c.setFillColor(GREY)
    c.setFont("Helvetica", 7.5)
    c.drawString(MARGIN, 8 * mm,
                 "For office use only. Do not write outside the marked boxes. "
                 "All fields marked * are mandatory.")
    c.drawRightString(PAGE_W - MARGIN, 8 * mm, "v2.4  /  rev. 2026-01")


def section(c, y, title):
    c.setFillColor(HEAD_BG)
    c.rect(MARGIN, y - 6.5 * mm, PAGE_W - 2 * MARGIN, 6.5 * mm, fill=1, stroke=0)
    c.setFillColor(INK)
    c.setFont("Helvetica-Bold", 10)
    c.drawString(MARGIN + 2 * mm, y - 4.7 * mm, title)
    return y - 6.5 * mm


def label(c, x, y, text, bold=False, size=8.5, color=INK):
    c.setFillColor(color)
    c.setFont("Helvetica-Bold" if bold else "Helvetica", size)
    c.drawString(x, y, text)


def box(c, x, y, w, h):
    c.setStrokeColor(LIGHT)
    c.setLineWidth(0.7)
    c.rect(x, y, w, h, fill=0, stroke=1)


def underline(c, x, y, w):
    c.setStrokeColor(LIGHT)
    c.setLineWidth(0.7)
    c.line(x, y, x + w, y)


def comb(c, x, y, cells, cell_w=5.2 * mm, h=6.5 * mm):
    """A row of individual character boxes (e.g. dates, IDs, phone)."""
    c.setStrokeColor(GREY)
    c.setLineWidth(0.7)
    for i in range(cells):
        c.rect(x + i * cell_w, y, cell_w, h, fill=0, stroke=1)
    return x + cells * cell_w


def checkbox(c, x, y, s=3.5 * mm):
    c.setStrokeColor(INK)
    c.setLineWidth(0.8)
    c.rect(x, y, s, s, fill=0, stroke=1)


def radio(c, x, y, r=1.8 * mm):
    c.setStrokeColor(INK)
    c.setLineWidth(0.8)
    c.circle(x + r, y + r, r, fill=0, stroke=1)


# ---------------------------------------------------------------- PAGE 1
def page1(c):
    header(c, 1, 3)
    y = PAGE_H - 32 * mm

    y = section(c, y, "SECTION A  -  PERSONAL DETAILS")
    y -= 8 * mm
    label(c, MARGIN, y, "Title *")
    for i, t in enumerate(["Mr.", "Mrs.", "Ms.", "Dr.", "Other"]):
        rx = MARGIN + 18 * mm + i * 24 * mm
        radio(c, rx, y - 0.8 * mm)
        label(c, rx + 5 * mm, y, t)

    y -= 9 * mm
    label(c, MARGIN, y, "First Name *")
    box(c, MARGIN + 24 * mm, y - 2 * mm, 50 * mm, 7 * mm)
    label(c, MARGIN + 80 * mm, y, "Middle")
    box(c, MARGIN + 95 * mm, y - 2 * mm, 35 * mm, 7 * mm)
    label(c, MARGIN + 135 * mm, y, "Last *")
    box(c, MARGIN + 145 * mm, y - 2 * mm, 33 * mm, 7 * mm)

    y -= 12 * mm
    label(c, MARGIN, y, "Date of Birth *  (D D / M M / Y Y Y Y)")
    end = comb(c, MARGIN + 60 * mm, y - 2 * mm, 8)
    label(c, end + 4 * mm, y, "Gender *")
    for i, g in enumerate(["M", "F", "X"]):
        rx = end + 22 * mm + i * 12 * mm
        radio(c, rx, y - 1 * mm)
        label(c, rx + 5 * mm, y, g)

    y -= 11 * mm
    label(c, MARGIN, y, "National ID / Passport No. *")
    comb(c, MARGIN + 52 * mm, y - 2 * mm, 14, cell_w=6.5 * mm)

    y -= 11 * mm
    label(c, MARGIN, y, "Marital Status")
    for i, s in enumerate(["Single", "Married", "Divorced", "Widowed"]):
        cx = MARGIN + 30 * mm + i * 32 * mm
        checkbox(c, cx, y - 1 * mm)
        label(c, cx + 5 * mm, y, s)

    y -= 11 * mm
    label(c, MARGIN, y, "Nationality")
    box(c, MARGIN + 24 * mm, y - 2 * mm, 55 * mm, 7 * mm)
    label(c, MARGIN + 79 * mm + 4 * mm, y, "Blood Group")
    box(c, MARGIN + 110 * mm, y - 2 * mm, 28 * mm, 7 * mm)
    label(c, MARGIN + 142 * mm, y, "(select)")

    # Section B - contact
    y -= 12 * mm
    y = section(c, y, "SECTION B  -  CONTACT & ADDRESS")
    y -= 9 * mm
    label(c, MARGIN, y, "Mobile *")
    comb(c, MARGIN + 18 * mm, y - 2 * mm, 11, cell_w=6 * mm)
    y -= 10 * mm
    label(c, MARGIN, y, "Alt. Phone")
    comb(c, MARGIN + 22 * mm, y - 2 * mm, 11, cell_w=6 * mm)

    y -= 11 * mm
    label(c, MARGIN, y, "Email *")
    box(c, MARGIN + 18 * mm, y - 2 * mm, 100 * mm, 7 * mm)

    y -= 12 * mm
    label(c, MARGIN, y, "Present Address *")
    box(c, MARGIN, y - 16 * mm, PAGE_W - 2 * MARGIN, 14 * mm)
    # ruled lines inside the address box
    for k in range(1, 3):
        underline(c, MARGIN + 2 * mm, y - 16 * mm + k * 4.6 * mm,
                  PAGE_W - 2 * MARGIN - 4 * mm)

    y -= 22 * mm
    label(c, MARGIN, y, "Permanent same as present?")
    checkbox(c, MARGIN + 52 * mm, y - 1 * mm)
    label(c, MARGIN + 57 * mm, y, "Yes")
    label(c, MARGIN + 70 * mm, y, "Post Code")
    comb(c, MARGIN + 90 * mm, y - 2 * mm, 6, cell_w=6 * mm)


# ---------------------------------------------------------------- PAGE 2
def page2(c):
    header(c, 2, 3)
    y = PAGE_H - 32 * mm

    y = section(c, y, "SECTION C  -  EMPLOYMENT HISTORY (most recent first)")
    y -= 6 * mm
    # table
    cols = [("Employer / Organisation", 58),
            ("Job Title", 32),
            ("From (MM/YYYY)", 28),
            ("To (MM/YYYY)", 26),
            ("Gross Salary", 26)]
    x0 = MARGIN
    th = 7 * mm
    c.setFillColor(HEAD_BG)
    c.rect(x0, y - th, PAGE_W - 2 * MARGIN, th, fill=1, stroke=0)
    c.setFillColor(INK)
    cx = x0
    for name, w in cols:
        c.setFont("Helvetica-Bold", 7.5)
        c.drawString(cx + 1.5 * mm, y - 4.6 * mm, name)
        cx += w * mm
    # 5 empty rows
    rh = 9 * mm
    c.setStrokeColor(LIGHT)
    c.setLineWidth(0.7)
    for r in range(5):
        ry = y - th - (r + 1) * rh
        c.rect(x0, ry, PAGE_W - 2 * MARGIN, rh, fill=0, stroke=1)
        cx = x0
        for _, w in cols[:-1]:
            cx += w * mm
            c.line(cx, ry, cx, ry + rh)
    y = y - th - 5 * rh - 8 * mm

    y = section(c, y, "SECTION D  -  TAX & BANKING")
    y -= 9 * mm
    label(c, MARGIN, y, "Tax Identification No. (TIN) *")
    comb(c, MARGIN + 54 * mm, y - 2 * mm, 12, cell_w=6.5 * mm)

    y -= 11 * mm
    label(c, MARGIN, y, "Annual Income Bracket *")
    brackets = ["< 3L", "3L - 6L", "6L - 12L", "12L - 25L", "> 25L"]
    for i, b in enumerate(brackets):
        rx = MARGIN + 50 * mm + i * 27 * mm
        radio(c, rx, y - 1 * mm)
        label(c, rx + 5 * mm, y, b, size=8)

    y -= 11 * mm
    label(c, MARGIN, y, "Bank Name")
    box(c, MARGIN + 22 * mm, y - 2 * mm, 60 * mm, 7 * mm)
    label(c, MARGIN + 86 * mm, y, "Branch")
    box(c, MARGIN + 102 * mm, y - 2 * mm, 36 * mm, 7 * mm)

    y -= 11 * mm
    label(c, MARGIN, y, "Account No. *")
    comb(c, MARGIN + 26 * mm, y - 2 * mm, 16, cell_w=6.2 * mm)

    y -= 11 * mm
    label(c, MARGIN, y, "Routing No.")
    comb(c, MARGIN + 24 * mm, y - 2 * mm, 9, cell_w=6.2 * mm)
    label(c, MARGIN + 90 * mm, y, "Payment Mode")
    for i, m in enumerate(["Bank", "Cheque", "Cash"]):
        cx = MARGIN + 118 * mm + i * 22 * mm
        checkbox(c, cx, y - 1 * mm)
        label(c, cx + 5 * mm, y, m, size=8)

    # Benefits
    y -= 12 * mm
    y = section(c, y, "SECTION E  -  BENEFITS ELECTION (tick all that apply)")
    y -= 9 * mm
    benefits = ["Health Insurance", "Life Insurance", "Provident Fund",
                "Gratuity", "Transport", "Mobile Allowance",
                "Housing", "Meal Card", "Stock Options"]
    for i, b in enumerate(benefits):
        col = i % 3
        row = i // 3
        cx = MARGIN + col * 60 * mm
        cy = y - row * 9 * mm
        checkbox(c, cx, cy - 1 * mm)
        label(c, cx + 5 * mm, cy, b)


# ---------------------------------------------------------------- PAGE 3
def page3(c):
    header(c, 3, 3)
    y = PAGE_H - 32 * mm

    y = section(c, y, "SECTION F  -  DECLARATION QUESTIONNAIRE")
    y -= 8 * mm
    label(c, MARGIN, y, "Please answer every item.", color=GREY, size=8)
    # Yes / No / N/A column headers
    qx = PAGE_W - MARGIN - 60 * mm
    label(c, qx, y, "Yes", bold=True, size=8)
    label(c, qx + 22 * mm, y, "No", bold=True, size=8)
    label(c, qx + 42 * mm, y, "N/A", bold=True, size=8)

    questions = [
        "1. Have you been previously employed by this company?",
        "2. Do you have any pending legal proceedings?",
        "3. Are you currently bound by a non-compete agreement?",
        "4. Do you require a work visa / sponsorship?",
        "5. Have you declared all sources of income above?",
        "6. Do you consent to a background verification check?",
        "7. Are you related to any current employee?",
    ]
    y -= 8 * mm
    for q in questions:
        label(c, MARGIN, y, q, size=8.5)
        for j in range(3):
            radio(c, qx + j * 22 * mm, y - 1 * mm)
        underline(c, MARGIN, y - 3.5 * mm, PAGE_W - 2 * MARGIN)
        y -= 9 * mm

    y -= 2 * mm
    y = section(c, y, "SECTION G  -  ADDITIONAL REMARKS")
    y -= 4 * mm
    box(c, MARGIN, y - 28 * mm, PAGE_W - 2 * MARGIN, 28 * mm)
    for k in range(1, 6):
        underline(c, MARGIN + 2 * mm, y - 28 * mm + k * 4.6 * mm,
                  PAGE_W - 2 * MARGIN - 4 * mm)
    y -= 36 * mm

    y = section(c, y, "SECTION H  -  DECLARATION & SIGNATURES")
    y -= 7 * mm
    c.setFillColor(GREY)
    c.setFont("Helvetica", 7.8)
    text = c.beginText(MARGIN, y)
    decl = ("I hereby declare that the information provided in this form is true, "
            "complete and accurate to the best of my knowledge. I understand that "
            "any false statement may result in disqualification or termination.")
    # simple wrap
    words = decl.split()
    line = ""
    for w in words:
        if c.stringWidth(line + " " + w, "Helvetica", 7.8) < (PAGE_W - 2 * MARGIN):
            line = (line + " " + w).strip()
        else:
            text.textLine(line)
            line = w
    text.textLine(line)
    c.drawText(text)

    y -= 22 * mm
    # signature blocks
    underline(c, MARGIN, y, 60 * mm)
    label(c, MARGIN, y - 5 * mm, "Applicant Signature", size=8)
    label(c, MARGIN, y - 9 * mm, "Date: D D / M M / Y Y Y Y", size=7.5, color=GREY)

    underline(c, PAGE_W - MARGIN - 60 * mm, y, 60 * mm)
    label(c, PAGE_W - MARGIN - 60 * mm, y - 5 * mm, "Authorised Officer", size=8)
    label(c, PAGE_W - MARGIN - 60 * mm, y - 9 * mm, "Seal & Date", size=7.5,
          color=GREY)

    y -= 24 * mm
    label(c, MARGIN, y, "Witness Name")
    box(c, MARGIN + 24 * mm, y - 2 * mm, 60 * mm, 7 * mm)
    label(c, MARGIN + 90 * mm, y, "Witness Sign")
    underline(c, MARGIN + 116 * mm, y, 45 * mm)


def main():
    out = "Employment_Tax_Benefits_Form.pdf"
    c = canvas.Canvas(out, pagesize=A4)
    c.setTitle("Employment, Tax & Benefits Registration Form")
    page1(c); c.showPage()
    page2(c); c.showPage()
    page3(c); c.showPage()
    c.save()
    print("Created:", out)


if __name__ == "__main__":
    main()
