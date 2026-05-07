#!/usr/bin/env python3
"""OMyDays wiki server — local hub for project + iOS wikis.

Usage:
  python3 serve_wiki.py            # start server on port 8765
  PORT=9000 python3 serve_wiki.py  # custom port
  python3 serve_wiki.py regen      # rewrite wiki.html from WIKI.md, exit
"""
import http.server
import os
import socketserver
import sys
from pathlib import Path

import markdown

ROOT = Path(__file__).parent.resolve()
WIKI_MD = ROOT / "WIKI.md"
IOS_WIKI_MD = ROOT / "ios-app" / "WIKI.md"
WIKI_HTML = ROOT / "wiki.html"

CSS = """
body { font-family: -apple-system, system-ui, "Segoe UI", sans-serif; max-width: 920px; margin: 0 auto; padding: 24px; background: #0B0F1A; color: #e0e0e0; line-height: 1.65; }
h1, h2, h3 { color: #00D4FF; }
h1 { border-bottom: 2px solid #00D4FF; padding-bottom: 10px; letter-spacing: -0.02em; }
h2 { border-bottom: 1px solid #1E2440; padding-bottom: 8px; margin-top: 40px; }
h3 { margin-top: 28px; }
a { color: #00FF88; text-decoration: none; }
a:hover { text-decoration: underline; }
code { background: #1E2440; padding: 2px 6px; border-radius: 4px; color: #FF69B4; font-size: 0.9em; }
pre { background: #151A2E; padding: 16px; border-radius: 8px; overflow-x: auto; border: 1px solid #1E2440; }
pre code { background: none; padding: 0; color: inherit; }
table { width: 100%; border-collapse: collapse; margin: 16px 0; }
th { background: #151A2E; padding: 10px; text-align: left; color: #A855F7; border: 1px solid #1E2440; }
td { padding: 8px 10px; border: 1px solid #1E2440; }
tr:nth-child(even) { background: #0f1225; }
blockquote { border-left: 3px solid #00D4FF; padding-left: 16px; color: #999; margin: 16px 0; }
hr { border: none; border-top: 1px solid #1E2440; margin: 30px 0; }
.nav { display: flex; gap: 16px; flex-wrap: wrap; margin: 32px 0; }
.nav a { display: block; padding: 24px 28px; background: #151A2E; border: 1px solid #1E2440; border-radius: 12px; flex: 1; min-width: 280px; transition: all 0.2s; }
.nav a:hover { border-color: #00D4FF; transform: translateY(-2px); text-decoration: none; }
.nav .label { color: #00D4FF; font-size: 18px; font-weight: 600; margin-bottom: 6px; }
.nav .desc { color: #9CA3AF; font-size: 13px; }
.crumb { font-size: 13px; color: #6B7280; margin-bottom: 24px; }
.crumb a { color: #6B7280; }
"""


def render(md_text: str) -> str:
    return markdown.markdown(md_text, extensions=["tables", "fenced_code"])


def page(title: str, body: str, crumb: str = "") -> str:
    crumb_html = f'<div class="crumb">{crumb}</div>' if crumb else ""
    return (
        '<!DOCTYPE html><html><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width">'
        f"<title>{title}</title>"
        f"<style>{CSS}</style></head><body>{crumb_html}{body}</body></html>"
    )


def landing_html() -> str:
    body = (
        "<h1>OMyDays Wiki</h1>"
        "<p>Local wiki hub for the family-chore-app project.</p>"
        '<div class="nav">'
        '<a href="/project"><div class="label">Project Wiki</div>'
        '<div class="desc">Full stack — web app, AWS Lambda backend, Postgres schema, roadmap, changelog.</div></a>'
        '<a href="/ios"><div class="label">iOS App Wiki</div>'
        '<div class="desc">OMyDay iOS app — architecture, auth, screens, models, theme, build status.</div></a>'
        "</div>"
        "<hr>"
        '<p style="color:#6B7280;font-size:13px">Served live from <code>WIKI.md</code> and <code>ios-app/WIKI.md</code> — edits show up on refresh.</p>'
    )
    return page("OMyDays Wiki", body)


def project_html() -> str:
    body = render(WIKI_MD.read_text())
    return page("OMyDays — Project Wiki", body, '<a href="/">← Wiki home</a>')


def ios_html() -> str:
    body = render(IOS_WIKI_MD.read_text())
    return page("OMyDays — iOS Wiki", body, '<a href="/">← Wiki home</a>')


def regen_static():
    body = render(WIKI_MD.read_text())
    WIKI_HTML.write_text(page("OMyDays — Project Wiki", body))
    print(f"Regenerated {WIKI_HTML}")


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        try:
            if self.path == "/":
                html = landing_html()
            elif self.path == "/project":
                html = project_html()
            elif self.path == "/ios":
                html = ios_html()
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
