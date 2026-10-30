import datetime
import io
import os
import sys

import matplotlib
from fpdf import FPDF
from pypdf import PdfReader, PdfWriter

OUT = os.path.join(os.path.dirname(__file__), '..', '..', 'ELN.Community.Tests', 'Fixtures', 'Search', 'Files')
FONT = os.path.join(os.path.dirname(matplotlib.__file__), 'mpl-data', 'fonts', 'ttf', 'DejaVuSans.ttf')

CYRILLIC_PAGES = [
    'Рентгеновская рефлектометрия многослойных зеркал',
    'Шероховатость границ раздела и толщина слоёв',
]


def build_cyrillic():
    pdf = FPDF()
    pdf.add_font('DejaVu', '', FONT)
    for line in CYRILLIC_PAGES:
        pdf.add_page()
        pdf.set_font('DejaVu', size=14)
        pdf.cell(0, 10, line)
    pdf.set_creation_date(datetime.datetime(2026, 1, 1, tzinfo=datetime.timezone.utc))
    return bytes(pdf.output())


def build_encrypted(plain):
    reader = PdfReader(io.BytesIO(plain))
    writer = PdfWriter()
    for page in reader.pages:
        writer.add_page(page)
    writer.encrypt(user_password='secret', owner_password='owner', algorithm='AES-256')
    buf = io.BytesIO()
    writer.write(buf)
    return buf.getvalue()


def main():
    os.makedirs(OUT, exist_ok=True)
    plain = build_cyrillic()
    with open(os.path.join(OUT, 'cyrillic-2pages.pdf'), 'wb') as f:
        f.write(plain)
    with open(os.path.join(OUT, 'encrypted.pdf'), 'wb') as f:
        f.write(build_encrypted(plain))


if __name__ == '__main__':
    sys.exit(main())
