import Foundation

/// Builds the standalone HTML "book" export: one page per sent prompt, a
/// fixed left table of contents, prev/next pagination, dark/light themes and
/// tool calls collapsed into `<details>`. The whole file is self-contained —
/// no external CSS, JS, fonts or images — and is produced from one reusable
/// `template`, so the design can be changed in a single place.
enum ChatHTMLBook {

    struct Chapter {
        let title: String
        let entries: [ChatExportLogic.MessageExport]
    }

    /// Input: normalized export entries. Output: chapters, one per user
    /// prompt; assistant/tool entries attach to the preceding prompt.
    /// Dependencies: none.
    static func chapters(from entries: [ChatExportLogic.MessageExport]) -> [Chapter] {
        var result: [Chapter] = []
        for entry in entries {
            if entry.role == "User" {
                result.append(Chapter(title: chapterTitle(entry.text, index: result.count + 1),
                                      entries: [entry]))
            } else if result.isEmpty {
                result.append(Chapter(title: "Chat", entries: [entry]))
            } else {
                let last = result.removeLast()
                result.append(Chapter(title: last.title, entries: last.entries + [entry]))
            }
        }
        return result
    }

    /// Input: messages + title + export date. Output: one complete HTML file.
    /// Dependencies: `ChatExportLogic.entries`, `MarkdownBookRenderer`, the
    /// template below.
    static func render(messages: [Message], title: String,
                       exportedAt: Date = Date()) -> String {
        let chapters = chapters(from: ChatExportLogic.entries(from: messages))
        let toc = chapters.enumerated().map { index, chapter in
            """
            <a class="toc-link" href="#page-\(index + 1)" data-page="\(index)" \
            onclick="show(\(index)); return false;">
            <span class="toc-number">\(index + 1)</span>\
            <span class="toc-label">\(MarkdownBookRenderer.escape(chapter.title))</span></a>
            """
        }.joined(separator: "\n")
        let pages = chapters.enumerated().map { index, chapter in
            """
            <section class="page" id="page-\(index + 1)">
            <div class="chapter-label">Prompt \(index + 1)</div>
            \(pageBody(chapter))
            </section>
            """
        }.joined(separator: "\n")
        return template
            .replacingOccurrences(of: "{{TITLE}}", with: MarkdownBookRenderer.escape(title))
            .replacingOccurrences(of: "{{EXPORTED_AT}}", with: exportedDate(exportedAt))
            .replacingOccurrences(of: "{{CHAPTER_COUNT}}", with: "\(chapters.count)")
            .replacingOccurrences(of: "{{TOC}}", with: toc)
            .replacingOccurrences(of: "{{PAGES}}", with: pages)
    }

    // MARK: - Page body

    private static func pageBody(_ chapter: Chapter) -> String {
        chapter.entries.map { entry in
            var blocks: [String] = []
            let rendered = MarkdownBookRenderer.render(entry.text)
            switch entry.role {
            case "User":
                if !rendered.isEmpty { blocks.append("<div class=\"bubble user\">\(rendered)</div>") }
            case "Assistant":
                if !rendered.isEmpty { blocks.append("<div class=\"answer\">\(rendered)</div>") }
            default:
                if !rendered.isEmpty { blocks.append("<div class=\"system\">\(rendered)</div>") }
            }
            for tool in entry.tools {
                blocks.append(toolBlock(tool))
            }
            return blocks.joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private static func toolBlock(_ tool: ChatExportLogic.ToolActivity) -> String {
        var body = "<div class=\"tool-label\">Arguments</div><pre>"
            + MarkdownBookRenderer.escape(tool.arguments) + "</pre>"
        if let result = tool.result, !result.isEmpty {
            body += "<div class=\"tool-label\">Result</div><pre>"
                + MarkdownBookRenderer.escape(result) + "</pre>"
        }
        return """
        <details class="tool"><summary>Tool · \(MarkdownBookRenderer.escape(tool.name))</summary>
        \(body)</details>
        """
    }

    private static func chapterTitle(_ text: String, index: Int) -> String {
        let firstLine = text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        var cleaned = firstLine
        while cleaned.hasPrefix("#") || cleaned.hasPrefix("-") || cleaned.hasPrefix(">") {
            cleaned.removeFirst()
            cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        }
        if cleaned.isEmpty { return "Prompt \(index)" }
        let limit = 64
        if cleaned.count <= limit { return cleaned }
        return String(cleaned.prefix(limit - 1)) + "…"
    }

    private static func exportedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Reusable template

    /// The single template used by every exported book. Placeholders:
    /// `{{TITLE}}`, `{{EXPORTED_AT}}`, `{{CHAPTER_COUNT}}`, `{{TOC}}`,
    /// `{{PAGES}}`.
    static let template = #"""
    <!DOCTYPE html>
    <html lang="en" data-theme="dark">
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>{{TITLE}}</title>
    <style>
    :root { color-scheme: dark; }
    :root[data-theme="dark"] { --bg:#0a1016; --surface:#101a23; --surface-2:#15222d; --text:#e8eef4; --muted:#8fa1b3; --border:#223342; --accent:#35c8ff; --bubble:#12303f; --code:#0b141b; }
    :root[data-theme="light"] { color-scheme: light; --bg:#f2f7fc; --surface:#ffffff; --surface-2:#e9f1f8; --text:#16222d; --muted:#5c6f80; --border:#d7e3ef; --accent:#0a84c1; --bubble:#e1f2fb; --code:#f3f6f9; }
    * { box-sizing: border-box; }
    html, body { height: 100%; }
    body { margin:0; background:var(--bg); color:var(--text); font: 15px/1.62 -apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", sans-serif; }
    a { color: var(--accent); }
    .sidebar { position:fixed; inset:0 auto 0 0; width:310px; background:var(--surface); border-right:1px solid var(--border); display:flex; flex-direction:column; padding:22px 16px; gap:14px; }
    .brand { font-size:12px; letter-spacing:.14em; text-transform:uppercase; color:var(--accent); font-weight:700; }
    .book-title { font-size:19px; font-weight:700; line-height:1.3; }
    .meta { font-size:12px; color:var(--muted); }
    .toc { overflow-y:auto; display:flex; flex-direction:column; gap:2px; margin-top:4px; }
    .toc-link { display:flex; gap:10px; align-items:flex-start; padding:8px 10px; border-radius:9px; color:var(--text); text-decoration:none; font-size:13px; }
    .toc-link:hover { background:var(--surface-2); }
    .toc-link.active { background:var(--surface-2); color:var(--accent); }
    .toc-number { color:var(--muted); font-variant-numeric:tabular-nums; min-width:18px; }
    .toc-link.active .toc-number { color:var(--accent); }
    .toc-label { overflow:hidden; display:-webkit-box; -webkit-line-clamp:2; -webkit-box-orient:vertical; }
    .content { margin-left:310px; height:100vh; overflow-y:auto; padding:28px 48px 110px; }
    .topbar { max-width:860px; margin:0 auto 22px; display:flex; justify-content:space-between; align-items:center; }
    .crumb { color:var(--muted); font-size:12px; letter-spacing:.08em; text-transform:uppercase; }
    .icon-button { border:1px solid var(--border); background:var(--surface); color:var(--text); width:36px; height:36px; border-radius:10px; cursor:pointer; font-size:16px; }
    .page { display:none; max-width:860px; margin:0 auto; }
    .page.active { display:block; animation:page-in .18s ease; }
    @keyframes page-in { from { opacity:0; transform:translateY(5px); } to { opacity:1; transform:none; } }
    .chapter-label { font-size:12px; letter-spacing:.1em; text-transform:uppercase; color:var(--muted); margin-bottom:12px; }
    .bubble { background:var(--bubble); border:1px solid var(--border); border-radius:14px 14px 14px 4px; padding:14px 18px; margin:0 0 18px; }
    .bubble p:first-child, .answer p:first-child { margin-top:0; }
    .bubble p:last-child, .answer p:last-child { margin-bottom:0; }
    .answer { padding:0 2px; }
    .answer h1,.answer h2,.answer h3,.answer h4 { line-height:1.28; margin:22px 0 10px; }
    .answer p { margin:0 0 12px; }
    .answer ul,.answer ol { margin:0 0 14px; padding-left:24px; }
    .answer li { margin:3px 0; }
    .answer blockquote { margin:0 0 14px; padding:8px 14px; border-left:3px solid var(--accent); background:var(--surface-2); border-radius:0 8px 8px 0; }
    .answer code { background:var(--code); border:1px solid var(--border); border-radius:5px; padding:1px 5px; font:12.5px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
    .answer pre { background:var(--code); border:1px solid var(--border); border-radius:10px; padding:14px 16px; overflow-x:auto; }
    .answer pre code { background:none; border:0; padding:0; font-size:12.5px; }
    .answer hr { border:0; border-top:1px solid var(--border); margin:20px 0; }
    .tool { background:var(--surface); border:1px solid var(--border); border-radius:11px; padding:10px 14px; margin:0 0 12px; }
    .tool summary { cursor:pointer; font-size:13px; font-weight:600; color:var(--accent); }
    .tool-label { font-size:11px; letter-spacing:.08em; text-transform:uppercase; color:var(--muted); margin:10px 0 4px; }
    .tool pre { margin:0; white-space:pre-wrap; word-break:break-word; font:12px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; background:var(--code); border-radius:8px; padding:10px 12px; }
    .system { color:var(--muted); font-size:13px; border-left:3px solid var(--border); padding-left:12px; margin-bottom:16px; }
    .pager { position:fixed; left:310px; right:0; bottom:0; display:flex; justify-content:center; align-items:center; gap:18px; padding:14px; background:linear-gradient(180deg, transparent, var(--bg) 35%); }
    .pager button { border:1px solid var(--border); background:var(--surface); color:var(--text); border-radius:10px; padding:8px 16px; font-size:13px; cursor:pointer; }
    .pager button:disabled { opacity:.35; cursor:default; }
    #page-counter { color:var(--muted); font-size:12px; font-variant-numeric:tabular-nums; min-width:64px; text-align:center; }
    @media (max-width: 860px) {
      .sidebar { position:static; width:auto; height:auto; max-height:42vh; border-right:0; border-bottom:1px solid var(--border); }
      .content { margin-left:0; height:auto; padding:20px 18px 110px; }
      .pager { left:0; }
    }
    @media print { .sidebar,.pager,.topbar{display:none;} .content{margin:0;height:auto;overflow:visible;padding:0;} .page{display:block !important; page-break-after:always;} }
    </style>
    </head>
    <body>
    <aside class="sidebar">
      <div class="brand">myCoder</div>
      <div class="book-title">{{TITLE}}</div>
      <div class="meta">{{CHAPTER_COUNT}} chapters · {{EXPORTED_AT}}</div>
      <nav class="toc">{{TOC}}</nav>
    </aside>
    <main class="content" id="content">
      <header class="topbar">
        <div class="crumb">Chat book</div>
        <button class="icon-button" onclick="toggleTheme()" title="Theme"><span id="theme-label">☀</span></button>
      </header>
      {{PAGES}}
    </main>
    <footer class="pager">
      <button id="prev" onclick="show(current - 1)">← Prev</button>
      <span id="page-counter"></span>
      <button id="next" onclick="show(current + 1)">Next →</button>
    </footer>
    <script>
    var current = 0;
    function show(index) {
      var pages = document.querySelectorAll('.page');
      var links = document.querySelectorAll('.toc-link');
      if (!pages.length || index < 0 || index >= pages.length) return;
      current = index;
      for (var i = 0; i < pages.length; i++) {
        pages[i].classList.toggle('active', i === index);
      }
      for (var j = 0; j < links.length; j++) {
        links[j].classList.toggle('active', j === index);
      }
      var counter = document.getElementById('page-counter');
      if (counter) counter.textContent = (index + 1) + ' / ' + pages.length;
      var prev = document.getElementById('prev');
      var next = document.getElementById('next');
      if (prev) prev.disabled = index === 0;
      if (next) next.disabled = index === pages.length - 1;
      var content = document.getElementById('content');
      if (content) content.scrollTop = 0;
    }
    function toggleTheme() {
      var root = document.documentElement;
      var next = root.getAttribute('data-theme') === 'dark' ? 'light' : 'dark';
      root.setAttribute('data-theme', next);
      try { localStorage.setItem('mycoder-book-theme', next); } catch (e) {}
      updateThemeLabel();
    }
    function updateThemeLabel() {
      var label = document.getElementById('theme-label');
      if (!label) return;
      label.textContent = document.documentElement.getAttribute('data-theme') === 'dark' ? '☀' : '☾';
    }
    (function () {
      var saved = null;
      try { saved = localStorage.getItem('mycoder-book-theme'); } catch (e) {}
      if (saved !== 'dark' && saved !== 'light') {
        saved = window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
      }
      document.documentElement.setAttribute('data-theme', saved);
      updateThemeLabel();
      show(0);
    })();
    document.addEventListener('keydown', function (event) {
      if (event.key === 'ArrowRight') show(current + 1);
      if (event.key === 'ArrowLeft') show(current - 1);
    });
    </script>
    </body>
    </html>
    """#
}
