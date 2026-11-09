#!/usr/bin/env python3
"""Split a filled Statement of Work into fixed A4 pages, one Design artboard each.

Usage:
  python3 -I paginate.py SOW.dc.html PROJECT_DIR --title "Client - Title - SOW"
      [--font-400 F --font-500 F --font-600 F] [--chrome PATH] [--no-measure]

SOW.dc.html is the template with every token filled in (one long document).
The script writes PROJECT_DIR/Main.dc.html, Page2.dc.html, ... and
PROJECT_DIR/canvas.json, then prints a JSON report of what went on each page.

How pages are chosen: each block (a data-block section) is measured in
headless Chrome, then blocks are packed in order, a block moving to the next
page only when it doesn't fit on the current one. So no page ends with a gap
the next block would have fitted in. Blocks are never split; the footer stays
with the block before it. The finished pages are measured again, and any page
whose content overflows A4 fails the run.

Measurement needs the three PP Mori woff2 files (--font-*): a fallback font
sets far shorter (about 170px less on a full page), so its numbers can't be
trusted. --no-measure uses the default breaks instead (after "included" and
before "payment") without checking that the pages fit.
"""

import argparse
import datetime
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

PAGE_H = 1123  # A4 at 96 px/in
PAGE_W = 794
FIRST_PAD = (24, 56)  # content padding top/bottom on page 1, under the header
REST_PAD = (56, 56)  # content padding top/bottom on later pages
GAP = 26  # gap between blocks
MARGIN = 24  # spare px kept on each page, for rendering differences
KEEP_WITH_PREVIOUS = {"footer"}
DEFAULT_BREAK_BEFORE = {"excluded", "payment"}

ROOT_RE = re.compile(r'<div data-sow="root" style="([^"]*)">')
CONTENT_RE = re.compile(r'<div data-sow="content" style="([^"]*)">')
BLOCK_RE = re.compile(r'(?=<(?:section|footer) data-block=")')
NAME_RE = re.compile(r'^<(?:section|footer) data-block="([a-z0-9_-]+)"')
FONT_RE = re.compile(r"@font-face\{font-family:'PP Mori';src:url\(([^)]*)\) format\('woff2'\);font-weight:(\d+);")


def fail(msg):
    print(f"paginate: {msg}", file=sys.stderr)
    sys.exit(1)


def parse(doc):
    if "[[" in doc or "<!--" in doc:
        fail("the document still has [[TOKENS]] or <!-- markers; fill the template first")
    root = ROOT_RE.search(doc)
    content = CONTENT_RE.search(doc)
    if not root or not content:
        fail('no data-sow="root"/"content" wrapper; build from the current template')
    end = doc.index("</x-dc>")
    inner = doc[content.end():end].rstrip()
    for _ in range(2):  # content </div>, then root </div>
        if not inner.endswith("</div>"):
            fail("unexpected markup after the last block")
        inner = inner[: -len("</div>")].rstrip()
    blocks = [b.strip() for b in BLOCK_RE.split(inner) if b.strip()]
    named = []
    for b in blocks:
        m = NAME_RE.match(b)
        if not m:
            fail(f"content holds markup outside a data-block: {b[:80]!r}")
        named.append((m.group(1), b))
    return {
        "head": doc[: root.start()],
        "root_style": root.group(1),
        "header": doc[root.end(): content.start()],
        "content_style": content.group(1),
        "blocks": named,
        "tail": doc[end:],
    }


def find_chrome(explicit):
    candidates = [explicit, os.environ.get("CHROME"),
                  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                  "/Applications/Chromium.app/Contents/MacOS/Chromium",
                  shutil.which("google-chrome"), shutil.which("chromium"),
                  shutil.which("chromium-browser")]
    return next((c for c in candidates if c and os.path.exists(c)), None)


def static_html(doc, fonts):
    """The .dc.html as a plain page Chrome can render without the Design runtime."""
    doc = doc.replace('<script src="./support.js"></script>', "")
    doc = re.sub(r'<script type="text/x-dc".*?</script>', "", doc, flags=re.S)
    for tag in ("<helmet>", "</helmet>", "<x-dc>", "</x-dc>"):
        doc = doc.replace(tag, "")

    def font(m):
        path = fonts.get(m.group(2))
        if not path:
            return ""  # drop the face: the fallback stack takes over
        return m.group(0).replace(m.group(1), "file://" + os.path.abspath(path))

    doc = FONT_RE.sub(font, doc)
    doc = re.sub(r"@font-face\{[^}]*\}\n?", lambda m: m.group(0) if "file://" in m.group(0) else "", doc)
    return doc


MEASURE_JS = """<script>
document.fonts.ready.then(() => {
  const h = e => e ? Math.ceil(e.getBoundingClientRect().height) : 0;
  const content = document.querySelector('[data-sow="content"]');
  const out = {
    root: h(document.querySelector('[data-sow="root"]')),
    header: h(document.querySelector('[data-sow="root"] > header')),
    blocks: [...content.children].map(e => [e.dataset.block, h(e)]),
    fonts: [...document.fonts].filter(f => f.status === 'loaded').map(f => f.weight)
  };
  document.getElementById('sow-measure').textContent = JSON.stringify(out);
});
</script><pre id="sow-measure"></pre></body>"""


def measure(chrome, doc, fonts, workdir, name):
    page = static_html(doc, fonts).replace("height: 1123px; overflow: hidden; ", "")
    page = page.replace("</body>", MEASURE_JS, 1)
    path = os.path.join(workdir, name + ".html")
    with open(path, "w") as f:
        f.write(page)
    cmd = [chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars",
           f"--user-data-dir={os.path.join(workdir, 'profile')}",
           f"--window-size={PAGE_W},{PAGE_H}", "--virtual-time-budget=5000",
           "--dump-dom", "file://" + path]
    run = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    m = re.search(r'<pre id="sow-measure">(.*?)</pre>', run.stdout, re.S)
    if not m or not m.group(1).strip():
        fail(f"Chrome returned no measurement for {name} (exit {run.returncode}): {run.stderr[-400:]}")
    return json.loads(html.unescape(m.group(1)))


def capacity(first, header_h):
    top, bottom = FIRST_PAD if first else REST_PAD
    return PAGE_H - (header_h if first else 0) - top - bottom


def groups_of(blocks):
    groups = []
    for name, markup in blocks:
        if name in KEEP_WITH_PREVIOUS and groups:
            groups[-1].append((name, markup))
        else:
            groups.append([(name, markup)])
    return groups


def pack(groups, heights, header_h, margin):
    pages, current, used = [], [], 0
    for g in groups:
        h = sum(heights[n] for n, _ in g) + GAP * (len(g) - 1)
        cap = capacity(not pages, header_h) - margin
        extra = h + (GAP if current else 0)
        if current and used + extra > cap:
            pages.append(current)
            current, used = [], 0
            cap = capacity(False, header_h) - margin
            extra = h
        if extra > cap:
            fail(f"block {'+'.join(n for n, _ in g)} is {h}px, taller than a page ({cap}px usable); shorten it")
        current += g
        used += extra
    pages.append(current)
    return pages


def default_pages(groups):
    pages, current = [], []
    for g in groups:
        if current and g[0][0] in DEFAULT_BREAK_BEFORE:
            pages.append(current)
            current = []
        current += g
    pages.append(current)
    return pages


def page_file(n):
    return "Main.dc.html" if n == 0 else f"Page{n + 1}.dc.html"


def render_page(parts, n, blocks, count):
    first = n == 0
    root_style = f"width: {PAGE_W}px; height: {PAGE_H}px; overflow: hidden; " + \
        parts["root_style"].replace(f"width: {PAGE_W}px; ", "")
    content_style = parts["content_style"]
    if not first:
        content_style = content_style.replace(f"padding: {FIRST_PAD[0]}px ", f"padding: {REST_PAD[0]}px ", 1)
    head = re.sub(r"<title>(.*?)</title>",
                  lambda m: f"<title>{m.group(1)} - page {n + 1} of {count}</title>", parts["head"], count=1)
    tail = re.sub(r'"\$preview":\{"width":\d+,"height":\d+\}',
                  f'"$preview":{{"width":{PAGE_W},"height":{PAGE_H}}}', parts["tail"])
    body = "".join(markup + "\n" for _, markup in blocks)
    header = parts["header"] if first else "\n"
    return (f'{head}<div data-sow="root" style="{root_style}">{header}'
            f'<div data-sow="content" style="{content_style}">{body}</div>\n</div>\n{tail}')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sow")
    ap.add_argument("project_dir")
    ap.add_argument("--title", required=True)
    ap.add_argument("--chrome")
    ap.add_argument("--no-measure", action="store_true")
    for w in ("400", "500", "600"):
        ap.add_argument(f"--font-{w}")
    a = ap.parse_args()

    with open(a.sow) as f:
        doc = f.read()
    parts = parse(doc)
    groups = groups_of(parts["blocks"])
    fonts = {w: getattr(a, f"font_{w}") for w in ("400", "500", "600") if getattr(a, f"font_{w}")}
    for w, p in fonts.items():
        if not os.path.exists(p):
            fail(f"font file for weight {w} not found: {p}")

    chrome = None
    if not a.no_measure:
        if len(fonts) != 3:
            fail("pass --font-400, --font-500 and --font-600 (PP Mori), or --no-measure for the default breaks")
        chrome = find_chrome(a.chrome)
        if not chrome:
            fail("no Chrome or Chromium found; pass --chrome PATH, or --no-measure for the default breaks")
    workdir = tempfile.mkdtemp(prefix="sow-paginate-")
    report = {"measured": bool(chrome)}
    if chrome:
        m = measure(chrome, doc, fonts, workdir, "whole")
        loaded = {str(w) for w in m["fonts"]}
        if not {"400", "500", "600"} <= loaded:
            fail(f"PP Mori didn't load in Chrome (loaded weights: {sorted(loaded)}); check the font files")
        pages = pack(groups, dict(m["blocks"]), m["header"], MARGIN)
    else:
        report["note"] = "default breaks; page fit not checked"
        pages = default_pages(groups)

    os.makedirs(a.project_dir, exist_ok=True)
    for old in os.listdir(a.project_dir):
        if re.fullmatch(r"Page\d+\.dc\.html", old):
            os.remove(os.path.join(a.project_dir, old))
    files = []
    for n, blocks in enumerate(pages):
        name = page_file(n)
        page = render_page(parts, n, blocks, len(pages))
        with open(os.path.join(a.project_dir, name), "w") as f:
            f.write(page)
        entry = {"file": name, "blocks": [b for b, _ in blocks]}
        if chrome:
            pm = measure(chrome, page, fonts, workdir, name)
            entry["spare_px"] = PAGE_H - pm["root"]
            if pm["root"] > PAGE_H:
                fail(f"{name} overflows A4 by {pm['root'] - PAGE_H}px: {entry['blocks']}")
        files.append(entry)
    report["pages"] = files

    gap_x = 80
    canvas = {
        "v": 3,
        "createdOnFiles": {"v": 1, "at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")},
        "title": a.title,
        "launch": {"view": "canvas"},
        "pages": [],
        "boards": {e["file"]: {"x": i * (PAGE_W + gap_x), "y": 0, "w": PAGE_W, "h": PAGE_H,
                               "title": f"Page {i + 1}"} for i, e in enumerate(files)},
        "order": [e["file"] for e in files],
        "notes": {},
        "designSystems": [],
    }
    with open(os.path.join(a.project_dir, "canvas.json"), "w") as f:
        json.dump(canvas, f, separators=(",", ":"))
    shutil.rmtree(workdir, ignore_errors=True)
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
