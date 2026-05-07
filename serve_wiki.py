#!/usr/bin/env python3
"""OMyDays wiki — combined docs-style site for project + iOS wikis.

Usage:
  python3 serve_wiki.py            # start server on port 8765
  PORT=9000 python3 serve_wiki.py  # custom port
  python3 serve_wiki.py regen      # rewrite index.html, exit
"""
import http.server
import os
import re
import socketserver
import sys
from pathlib import Path

import markdown

ROOT = Path(__file__).parent.resolve()
WIKI_MD = ROOT / "WIKI.md"
IOS_WIKI_MD = ROOT / "ios-app" / "WIKI.md"
INDEX_HTML = ROOT / "index.html"

# Standalone HTML files kept in sync for direct linking
WIKI_HTML = ROOT / "wiki.html"
IOS_WIKI_HTML = ROOT / "ios-app" / "wiki.html"

GITHUB_URL = "https://github.com/HHRepos/family-chore-app"


# ---------- markdown rendering ----------

def slugify(text: str) -> str:
    s = text.lower().strip()
    s = re.sub(r"[^\w\s-]", "", s)
    s = re.sub(r"[\s_]+", "-", s).strip("-")
    return s


def render_with_toc(md_text: str, prefix: str):
    """Render markdown and extract h2 sections for the sidebar nav.

    Each h2 in the source is given a stable id of the form `{prefix}-{slug}`
    so the project and iOS wikis don't collide.
    """
    md = markdown.Markdown(extensions=["tables", "fenced_code", "toc"], extension_configs={"toc": {"toc_depth": "2-3"}})
    html = md.convert(md_text)
    SKIP_NAV = {"Table of Contents"}
    sections = []
    for tok in md.toc_tokens:
        if tok["level"] != 2:
            continue
        old_id = tok["id"]
        new_id = f"{prefix}-{slugify(tok['name'])}"
        html = html.replace(f'id="{old_id}"', f'id="{new_id}"', 1)
        if tok["name"] in SKIP_NAV:
            continue
        sections.append({"id": new_id, "name": tok["name"]})
    return html, sections


# ---------- combined wiki (the new UI) ----------

CSS_COMBINED = """
:root {
  --bg: #0d1117;
  --bg-elev: #161b22;
  --bg-code: #1c2128;
  --border: #21262d;
  --border-soft: #2d333b;
  --text: #e6edf3;
  --text-muted: #8b949e;
  --text-dim: #6e7681;
  --accent: #58c6ff;
  --accent-soft: rgba(88, 198, 255, 0.12);
  --link: #79c0ff;
  --green: #3fb950;
  --purple: #d2a8ff;
  --pink: #ff7b72;
}

* { box-sizing: border-box; }

html, body {
  margin: 0;
  padding: 0;
  background: var(--bg);
  color: var(--text);
  font-family: -apple-system, "SF Pro Text", "Segoe UI", "Inter", system-ui, sans-serif;
  font-size: 15px;
  line-height: 1.65;
  scroll-behavior: smooth;
}

a { color: var(--link); text-decoration: none; }
a:hover { text-decoration: underline; }

/* ---------- Header ---------- */
.topbar {
  position: sticky;
  top: 0;
  z-index: 50;
  background: rgba(13, 17, 23, 0.85);
  backdrop-filter: saturate(180%) blur(8px);
  border-bottom: 1px solid var(--border);
  height: 56px;
  display: flex;
  align-items: center;
  padding: 0 20px;
}
.topbar .brand {
  font-weight: 700;
  font-size: 16px;
  color: var(--text);
  letter-spacing: -0.01em;
  display: flex;
  align-items: center;
  gap: 10px;
}
.topbar .brand .dot {
  width: 10px; height: 10px; border-radius: 50%;
  background: linear-gradient(135deg, #58c6ff, #d2a8ff);
}
.topbar .badge {
  margin-left: 12px;
  padding: 2px 8px;
  background: var(--bg-elev);
  border: 1px solid var(--border);
  border-radius: 999px;
  color: var(--text-muted);
  font-size: 12px;
  font-family: ui-monospace, "SF Mono", Menlo, monospace;
}
.topbar .spacer { flex: 1; }
.topbar .ext {
  color: var(--text-muted);
  font-size: 13px;
  padding: 6px 10px;
  border-radius: 6px;
}
.topbar .ext:hover { background: var(--bg-elev); color: var(--text); text-decoration: none; }
.topbar .menu {
  display: none;
  background: none;
  border: 1px solid var(--border);
  color: var(--text);
  border-radius: 6px;
  padding: 6px 10px;
  cursor: pointer;
  font-size: 14px;
}

/* ---------- Layout ---------- */
.layout {
  display: grid;
  grid-template-columns: 280px 1fr;
  max-width: 1280px;
  margin: 0 auto;
}

/* ---------- Sidebar ---------- */
.sidebar {
  position: sticky;
  top: 56px;
  height: calc(100vh - 56px);
  overflow-y: auto;
  border-right: 1px solid var(--border);
  padding: 24px 16px 48px;
}
.sidebar .group {
  margin-bottom: 24px;
}
.sidebar .group-title {
  font-size: 11px;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--text-dim);
  font-weight: 600;
  padding: 0 12px 8px;
}
.sidebar a.nav-link {
  display: block;
  padding: 6px 12px;
  font-size: 14px;
  color: var(--text-muted);
  border-radius: 6px;
  margin-bottom: 1px;
  border-left: 2px solid transparent;
}
.sidebar a.nav-link:hover {
  color: var(--text);
  background: var(--bg-elev);
  text-decoration: none;
}
.sidebar a.nav-link.active {
  color: var(--accent);
  background: var(--accent-soft);
  border-left-color: var(--accent);
  font-weight: 500;
}

/* ---------- Main content ---------- */
.main {
  padding: 32px 48px 96px;
  max-width: 880px;
  width: 100%;
}
.main h1 {
  font-size: 32px;
  font-weight: 700;
  letter-spacing: -0.02em;
  margin: 8px 0 16px;
  color: var(--text);
}
.main h2 {
  font-size: 22px;
  font-weight: 600;
  letter-spacing: -0.01em;
  margin: 48px 0 12px;
  padding-bottom: 8px;
  border-bottom: 1px solid var(--border);
  color: var(--text);
  scroll-margin-top: 80px;
}
.main h3 {
  font-size: 17px;
  font-weight: 600;
  margin: 28px 0 8px;
  color: var(--text);
  scroll-margin-top: 80px;
}
.main h2:first-of-type { margin-top: 24px; }
.main p { margin: 8px 0 12px; color: var(--text); }
.main ul, .main ol { padding-left: 24px; margin: 8px 0 16px; }
.main li { margin: 4px 0; }
.main hr { border: none; border-top: 1px solid var(--border); margin: 32px 0; }
.main code {
  background: var(--bg-code);
  padding: 1px 6px;
  border-radius: 4px;
  color: var(--pink);
  font-family: ui-monospace, "SF Mono", Menlo, monospace;
  font-size: 13px;
  border: 1px solid var(--border);
}
.main pre {
  background: var(--bg-code);
  padding: 16px;
  border-radius: 8px;
  overflow-x: auto;
  border: 1px solid var(--border);
  margin: 12px 0 18px;
}
.main pre code { background: none; padding: 0; border: none; color: var(--text); font-size: 13px; }
.main blockquote {
  border-left: 3px solid var(--accent);
  padding: 4px 0 4px 16px;
  color: var(--text-muted);
  margin: 16px 0;
  background: var(--accent-soft);
  border-radius: 0 6px 6px 0;
}
.main blockquote p { color: var(--text-muted); }
.main table {
  width: 100%;
  border-collapse: collapse;
  margin: 16px 0;
  font-size: 14px;
  border: 1px solid var(--border);
  border-radius: 6px;
  overflow: hidden;
}
.main th {
  background: var(--bg-elev);
  padding: 10px 12px;
  text-align: left;
  color: var(--purple);
  font-weight: 600;
  border-bottom: 1px solid var(--border);
}
.main td { padding: 10px 12px; border-top: 1px solid var(--border); }
.main tr:nth-child(even) td { background: var(--bg-elev); }

.main .header-meta {
  display: flex;
  gap: 12px;
  flex-wrap: wrap;
  font-size: 13px;
  color: var(--text-muted);
  margin: 4px 0 24px;
}
.main .header-meta .tag {
  background: var(--bg-elev);
  border: 1px solid var(--border);
  border-radius: 999px;
  padding: 3px 10px;
}
.main .header-meta .tag.green { color: var(--green); border-color: rgba(63,185,80,0.4); }

.section-marker {
  display: flex;
  align-items: center;
  gap: 12px;
  font-size: 12px;
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--text-dim);
  font-weight: 600;
  margin: 64px 0 8px;
}
.section-marker:first-child { margin-top: 0; }
.section-marker::after {
  content: "";
  flex: 1;
  height: 1px;
  background: var(--border);
}

/* ---------- Mobile ---------- */
@media (max-width: 900px) {
  .layout { grid-template-columns: 1fr; }
  .sidebar {
    position: fixed;
    top: 56px;
    left: 0;
    width: 280px;
    background: var(--bg);
    transform: translateX(-100%);
    transition: transform 0.2s ease;
    z-index: 40;
    border-right: 1px solid var(--border);
  }
  .sidebar.open { transform: translateX(0); }
  .main { padding: 24px 20px 96px; }
  .topbar .menu { display: block; margin-right: 12px; }
  .scrim {
    position: fixed; inset: 56px 0 0; background: rgba(0,0,0,0.5);
    z-index: 35; display: none;
  }
  .scrim.open { display: block; }
}

/* ---------- Scrollbar polish ---------- */
.sidebar::-webkit-scrollbar { width: 8px; }
.sidebar::-webkit-scrollbar-thumb { background: var(--border-soft); border-radius: 4px; }
.sidebar::-webkit-scrollbar-thumb:hover { background: var(--text-dim); }
"""

JS_COMBINED = """
(function () {
  const links = Array.from(document.querySelectorAll('.sidebar a.nav-link'));
  const headings = links
    .map(l => document.getElementById(l.getAttribute('href').slice(1)))
    .filter(Boolean);

  const setActive = id => {
    links.forEach(l => l.classList.toggle('active', l.getAttribute('href') === '#' + id));
  };

  if ('IntersectionObserver' in window && headings.length) {
    const obs = new IntersectionObserver(entries => {
      // pick the topmost intersecting heading
      const visible = entries
        .filter(e => e.isIntersecting)
        .sort((a, b) => a.target.getBoundingClientRect().top - b.target.getBoundingClientRect().top);
      if (visible.length) setActive(visible[0].target.id);
    }, { rootMargin: '-80px 0px -70% 0px', threshold: 0 });
    headings.forEach(h => obs.observe(h));
  }

  // Mobile sidebar toggle
  const sidebar = document.querySelector('.sidebar');
  const scrim = document.querySelector('.scrim');
  const menu = document.querySelector('.topbar .menu');
  const close = () => { sidebar.classList.remove('open'); scrim.classList.remove('open'); };
  if (menu) {
    menu.addEventListener('click', () => {
      const isOpen = sidebar.classList.toggle('open');
      scrim.classList.toggle('open', isOpen);
    });
  }
  if (scrim) scrim.addEventListener('click', close);
  links.forEach(l => l.addEventListener('click', () => {
    if (window.innerWidth <= 900) close();
  }));
})();
"""


def header_meta_html() -> str:
    return (
        '<div class="header-meta">'
        '<span class="tag green">iOS 1.0.1 — Build 5</span>'
        '<span class="tag">TestFlight</span>'
        '<span class="tag">Last updated 2026-05-07</span>'
        '</div>'
    )


def combined_html() -> str:
    project_html, project_sections = render_with_toc(WIKI_MD.read_text(), "project")
    ios_html, ios_sections = render_with_toc(IOS_WIKI_MD.read_text(), "ios")

    sidebar_links = ['<div class="group"><div class="group-title">Project</div>']
    for s in project_sections:
        sidebar_links.append(f'<a class="nav-link" href="#{s["id"]}">{s["name"]}</a>')
    sidebar_links.append('</div><div class="group"><div class="group-title">iOS App</div>')
    for s in ios_sections:
        sidebar_links.append(f'<a class="nav-link" href="#{s["id"]}">{s["name"]}</a>')
    sidebar_links.append('</div>')

    body = f"""
<header class="topbar">
  <button class="menu" aria-label="Toggle navigation">☰</button>
  <a href="#" class="brand"><span class="dot"></span>OMyDays Wiki</a>
  <span class="badge">v1.0.1 · Build 5</span>
  <span class="spacer"></span>
  <a class="ext" href="{GITHUB_URL}" target="_blank" rel="noopener">GitHub ↗</a>
</header>
<div class="scrim"></div>
<div class="layout">
  <aside class="sidebar">{''.join(sidebar_links)}</aside>
  <main class="main">
    <h1>OMyDays — Family Chore App</h1>
    {header_meta_html()}
    <p>AI-powered family chore management — voice onboarding, gamified rewards, smart scheduling. iOS app + AWS Lambda backend + RDS Postgres.</p>

    <div class="section-marker">Project</div>
    {project_html}

    <div class="section-marker">iOS App</div>
    {ios_html}
  </main>
</div>
<script>{JS_COMBINED}</script>
"""

    return (
        '<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '<title>OMyDays Wiki</title>'
        f'<style>{CSS_COMBINED}</style></head><body>{body}</body></html>'
    )


# ---------- legacy standalone pages (kept for direct links) ----------

CSS_LEGACY = """
body { font-family: -apple-system, system-ui, "Segoe UI", sans-serif; max-width: 920px; margin: 0 auto; padding: 24px; background: #0d1117; color: #e6edf3; line-height: 1.65; }
h1, h2, h3 { color: #e6edf3; }
h1 { border-bottom: 2px solid #21262d; padding-bottom: 10px; letter-spacing: -0.02em; }
h2 { border-bottom: 1px solid #21262d; padding-bottom: 8px; margin-top: 40px; }
h3 { margin-top: 28px; }
a { color: #79c0ff; text-decoration: none; }
a:hover { text-decoration: underline; }
code { background: #1c2128; padding: 2px 6px; border-radius: 4px; color: #ff7b72; font-size: 0.9em; border: 1px solid #21262d; }
pre { background: #1c2128; padding: 16px; border-radius: 8px; overflow-x: auto; border: 1px solid #21262d; }
pre code { background: none; padding: 0; border: none; color: inherit; }
table { width: 100%; border-collapse: collapse; margin: 16px 0; }
th { background: #161b22; padding: 10px; text-align: left; color: #d2a8ff; border: 1px solid #21262d; }
td { padding: 8px 10px; border: 1px solid #21262d; }
tr:nth-child(even) { background: #161b22; }
blockquote { border-left: 3px solid #58c6ff; padding-left: 16px; color: #8b949e; margin: 16px 0; }
hr { border: none; border-top: 1px solid #21262d; margin: 30px 0; }
.crumb { font-size: 13px; color: #6e7681; margin-bottom: 24px; }
.crumb a { color: #6e7681; }
"""


def legacy_page(title: str, body: str, crumb: str = "") -> str:
    crumb_html = f'<div class="crumb">{crumb}</div>' if crumb else ""
    return (
        '<!DOCTYPE html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width">'
        f'<title>{title}</title>'
        f'<style>{CSS_LEGACY}</style></head><body>{crumb_html}{body}</body></html>'
    )


def regen_static():
    INDEX_HTML.write_text(combined_html())
    print(f"Regenerated {INDEX_HTML}")

    project_html, _ = render_with_toc(WIKI_MD.read_text(), "project")
    WIKI_HTML.write_text(legacy_page("OMyDays — Project Wiki", project_html, '<a href="index.html">← Wiki home</a>'))
    print(f"Regenerated {WIKI_HTML}")

    ios_html, _ = render_with_toc(IOS_WIKI_MD.read_text(), "ios")
    IOS_WIKI_HTML.write_text(legacy_page("OMyDays — iOS Wiki", ios_html, '<a href="../index.html">← Wiki home</a>'))
    print(f"Regenerated {IOS_WIKI_HTML}")


# ---------- live server ----------

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            if self.path in ("/", "/index.html"):
                html = combined_html()
            elif self.path == "/project":
                project_html, _ = render_with_toc(WIKI_MD.read_text(), "project")
                html = legacy_page("OMyDays — Project Wiki", project_html, '<a href="/">← Wiki home</a>')
            elif self.path == "/ios":
                ios_html, _ = render_with_toc(IOS_WIKI_MD.read_text(), "ios")
                html = legacy_page("OMyDays — iOS Wiki", ios_html, '<a href="/">← Wiki home</a>')
            else:
                self.send_error(404)
                return
            data = html.encode()
            self.send_response(200)
            self.send_header("Content-type", "text/html; charset=utf-8")
            self.send_header("Content-length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except Exception as e:
            self.send_error(500, str(e))

    def log_message(self, fmt, *args):
        return


def main():
    if len(sys.argv) > 1 and sys.argv[1] == "regen":
        regen_static()
        return
    port = int(os.environ.get("PORT", "8765"))
    with socketserver.TCPServer(("", port), Handler) as httpd:
        httpd.allow_reuse_address = True
        print(f"OMyDays wiki at http://localhost:{port}/")
        sys.stdout.flush()
        httpd.serve_forever()


if __name__ == "__main__":
    main()
