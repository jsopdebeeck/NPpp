import Foundation

/// Page HTML de l'aperçu. Elle est chargée une fois par onglet, puis le contenu
/// est remplacé en JavaScript, ce qui conserve la position de défilement.
enum PreviewTemplate {
    static var fileURL: URL { SessionStore.directory.appendingPathComponent("preview.html") }

    static func install() {
        let page = html.replacingOccurrences(of: "/*SYNTAX*/", with: SyntaxTheme.css)
        try? page.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    static let html = #"""
<!doctype html>
<html>
<head>
<meta charset="utf-8">
<base href="">
<style>
:root {
  color-scheme: light dark;
  --bg: #ffffff; --fg: #1f2328; --muted: #59636e; --border: #d1d9e0;
  --code-bg: #f4f5f7; --accent: #0969da; --mark: #fff3a3; --row: #f6f8fa;
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #1e1e1e; --fg: #e6edf3; --muted: #9198a1; --border: #3d444d;
    --code-bg: #2a2d33; --accent: #4493f8; --mark: #6b5900; --row: #252830;
  }
}
html { background: var(--bg); }
body {
  margin: 0; padding: 36px 44px 120px;
  font: 16px/1.65 -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
  color: var(--fg); -webkit-font-smoothing: antialiased; word-wrap: break-word;
}
#c { max-width: 780px; margin: 0 auto; }
#c > :first-child { margin-top: 0; }
h1, h2, h3, h4, h5, h6 { line-height: 1.25; margin: 1.6em 0 0.6em; font-weight: 650; }
h1 { font-size: 2em; padding-bottom: .3em; border-bottom: 1px solid var(--border); }
h2 { font-size: 1.5em; padding-bottom: .3em; border-bottom: 1px solid var(--border); }
h3 { font-size: 1.25em; } h4 { font-size: 1em; } h5 { font-size: .9em; } h6 { font-size: .85em; color: var(--muted); }
p, ul, ol, blockquote, pre, .table, .callout { margin: 0 0 1em; }
a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }
a.wikilink { border-bottom: 1px dashed var(--accent); }
ul, ol { padding-left: 1.8em; }
li { margin: .25em 0; }
li > ul, li > ol { margin: .25em 0; }
li.task { list-style: none; margin-left: -1.4em; }
li.task > input { margin: 0 .45em 0 0; vertical-align: -1px; }
li.task.done { color: var(--muted); }
li.task > p:first-of-type { display: inline; }
code, pre { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: .88em; }
code { background: var(--code-bg); padding: .15em .4em; border-radius: 5px; }
pre { background: var(--code-bg); padding: 14px 16px; border-radius: 8px; overflow-x: auto; line-height: 1.5; }
pre code { background: none; padding: 0; font-size: 1em; }
pre.frontmatter { color: var(--muted); font-size: .85em; }
pre.plain { background: none; padding: 0; white-space: pre-wrap; font-size: .95em; }
pre.code { background: none; padding: 0; font-size: .92em; line-height: 1.55; }
#c:has(> pre.code:only-child) { max-width: none; }
/*SYNTAX*/
blockquote { padding: 0 1em; color: var(--muted); border-left: 4px solid var(--border); }
hr { border: 0; height: 2px; background: var(--border); margin: 2em 0; }
img { max-width: 100%; border-radius: 4px; }
mark { background: var(--mark); color: inherit; padding: 0 .15em; border-radius: 3px; }
kbd { font: .85em ui-monospace, monospace; padding: .1em .4em; border: 1px solid var(--border); border-bottom-width: 2px; border-radius: 5px; }
.table { overflow-x: auto; }
table { border-collapse: collapse; }
th, td { border: 1px solid var(--border); padding: 6px 13px; }
th { font-weight: 600; background: var(--row); }
tbody tr:nth-child(2n) { background: var(--row); }
.callout { --c: #0969da; border-left: 4px solid var(--c); background: color-mix(in srgb, var(--c) 9%, transparent); border-radius: 6px; padding: .7em 1em .1em; }
.callout-title { font-weight: 650; color: var(--c); margin-bottom: .4em; }
.callout-tip, .callout-success { --c: #1a7f37; }
.callout-important { --c: #8250df; }
.callout-warning, .callout-caution, .callout-attention { --c: #bf8700; }
.callout-danger, .callout-error, .callout-bug { --c: #cf222e; }
::selection { background: color-mix(in srgb, var(--accent) 30%, transparent); }
</style>
</head>
<body>
<div id="c"></div>
<script>
function setContent(html, base) {
  document.querySelector('base').href = base || '';
  document.getElementById('c').innerHTML = html;
}
function setScrollFraction(f) {
  const max = document.documentElement.scrollHeight - window.innerHeight;
  window.scrollTo(0, Math.max(0, f * max));
}
document.addEventListener('click', e => {
  const a = e.target.closest('a');
  if (!a) return;
  const h = a.getAttribute('href') || '';
  if (h.startsWith('#')) {
    e.preventDefault();
    const el = document.getElementById(decodeURIComponent(h.slice(1)));
    if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }
});
</script>
</body>
</html>
"""#
}
