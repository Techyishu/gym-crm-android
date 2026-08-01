#!/usr/bin/env python3
"""Register-OCR test harness.

    export NVIDIA_API_KEY=nvapi-...
    python3 tools/ocr_test.py

Opens http://localhost:8777 — drop in a photo of a gym register, see the CSV
the model returns. Throwaway rig for judging accuracy before wiring the real
Edge Function; not part of the app build.

ponytail: stdlib http.server, no deps, no framework. It serves one page to one
person on localhost.
"""
import base64
import json
import os
import ssl
import sys
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

# python.org macOS builds ship no CA store, so the default context fails to
# verify integrate.api.nvidia.com. certifi rides along with pip, use it when
# present; the alternative is making every user run Install Certificates.command.
try:
    import certifi
    SSL_CTX = ssl.create_default_context(cafile=certifi.where())
except ImportError:
    SSL_CTX = ssl.create_default_context()

API_KEY = os.environ.get("NVIDIA_API_KEY", "")
BASE_URL = os.environ.get("OCR_BASE_URL", "https://integrate.api.nvidia.com/v1")
PORT = 8777

PROMPT = """This is a photo of a gym member register.
Extract every member row you can read.

Return ONLY CSV with this exact header, no prose, no markdown fence:
name,phone,join_date,expiry_date,plan,amount

Rules:
- phone: digits only. No spaces, no +91, no dashes.
- join_date and expiry_date: copy the characters EXACTLY as printed on the page.
  Do not reformat, do not reorder, do not convert to another calendar format.
  If the page says 12/07/2026 you write 12/07/2026.
- amount: digits only, no currency symbol.
- Leave a cell EMPTY if you cannot read it clearly. Never guess a phone digit.
- One CSV row per member. Skip header rows and totals printed on the page."""

# Asking the model for YYYY-MM-DD made it guess the day/month order whenever
# both numbers were <= 12, and it guessed wrong about half the time. Verbatim
# transcription + parsing DD/MM in code scored 100% on the same image. Keep the
# conversion out of the model.

PAGE = """<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Register OCR test</title>
<style>
  :root { color-scheme: light; }
  body { font: 15px/1.5 -apple-system, system-ui, sans-serif; background: #EFECE4;
         color: #1D1B16; margin: 0; padding: 24px; }
  .wrap { max-width: 900px; margin: 0 auto; }
  h1 { font-size: 20px; margin: 0 0 4px; }
  .sub { color: #7A756A; margin: 0 0 20px; }
  .card { background: #fff; border: 1px solid #E2DED4; border-radius: 12px;
          padding: 16px; margin-bottom: 16px; }
  label { display: block; font-weight: 600; font-size: 13px; margin-bottom: 6px; }
  input[type=text] { width: 100%; box-sizing: border-box; padding: 8px 10px;
          border: 1px solid #E2DED4; border-radius: 8px; font: inherit; }
  button { background: #2C6E7A; color: #fff; border: 0; border-radius: 8px;
           padding: 10px 18px; font: inherit; font-weight: 600; cursor: pointer; }
  button:disabled { background: #A39E93; cursor: default; }
  #drop { border: 2px dashed #C9C4B8; border-radius: 12px; padding: 32px;
          text-align: center; color: #7A756A; cursor: pointer; }
  #drop.over { border-color: #2C6E7A; background: #E6EEEF; }
  #preview { max-width: 100%; border-radius: 8px; margin-top: 12px; display: none; }
  pre { background: #F6F4EE; border: 1px solid #E2DED4; border-radius: 8px;
        padding: 12px; overflow-x: auto; white-space: pre-wrap; font-size: 13px; }
  table { border-collapse: collapse; width: 100%; font-size: 13px; }
  th, td { border: 1px solid #E2DED4; padding: 6px 8px; text-align: left; }
  th { background: #F6F4EE; }
  td.empty { background: #F8DFD7; }
  .meta { color: #7A756A; font-size: 13px; margin-top: 8px; }
  .err { color: #C2492F; }
</style>
<div class="wrap">
  <h1>Register OCR test</h1>
  <p class="sub">Photo of a gym register in, CSV out. Red cells = model could not read it.</p>

  <div class="card">
    <label>Model</label>
    <input type="text" id="model" value="nvidia/nemotron-nano-12b-v2-vl">
  </div>

  <div class="card">
    <div id="drop">Click or drop a register photo here</div>
    <input type="file" id="file" accept="image/*" hidden>
    <img id="preview">
  </div>

  <div class="card">
    <button id="go" disabled>Extract</button>
    <span class="meta" id="status"></span>
  </div>

  <div class="card" id="out" style="display:none">
    <label>Parsed</label>
    <div id="table"></div>
    <label style="margin-top:16px">Raw response</label>
    <pre id="raw"></pre>
  </div>
</div>
<script>
const $ = id => document.getElementById(id);
let imageB64 = null;

$('drop').onclick = () => $('file').click();
$('drop').ondragover = e => { e.preventDefault(); $('drop').classList.add('over'); };
$('drop').ondragleave = () => $('drop').classList.remove('over');
$('drop').ondrop = e => {
  e.preventDefault(); $('drop').classList.remove('over');
  if (e.dataTransfer.files[0]) load(e.dataTransfer.files[0]);
};
$('file').onchange = e => { if (e.target.files[0]) load(e.target.files[0]); };

// Downscale to 2000px long edge. Phone photos are ~4000px, which balloons the
// payload for no accuracy gain. Going much below 2000 starts losing small
// handwriting, so tune here if faint registers read badly.
function load(file) {
  const img = new Image();
  img.onload = () => {
    const scale = Math.min(1, 2000 / Math.max(img.width, img.height));
    const c = document.createElement('canvas');
    c.width = img.width * scale;
    c.height = img.height * scale;
    c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
    const url = c.toDataURL('image/jpeg', 0.9);
    imageB64 = url.split(',')[1];
    $('preview').src = url;
    $('preview').style.display = 'block';
    $('drop').textContent = file.name + ' — ' + c.width + '×' + c.height;
    $('go').disabled = false;
  };
  img.src = URL.createObjectURL(file);
}

$('go').onclick = async () => {
  $('go').disabled = true;
  $('status').textContent = 'Extracting…';
  $('status').className = 'meta';
  const t0 = performance.now();
  try {
    const r = await fetch('/extract', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ image: imageB64, model: $('model').value })
    });
    const j = await r.json();
    if (!r.ok) throw new Error(j.error || 'request failed');
    const secs = ((performance.now() - t0) / 1000).toFixed(1);
    $('status').textContent = secs + 's · ' + (j.tokens || '?') + ' tokens';
    $('raw').textContent = j.csv;
    renderTable(j.csv);
    $('out').style.display = 'block';
  } catch (e) {
    $('status').textContent = e.message;
    $('status').className = 'meta err';
  }
  $('go').disabled = false;
};

function renderTable(csv) {
  const lines = csv.trim().split('\\n').filter(l => l.trim());
  if (!lines.length) { $('table').textContent = 'no rows'; return; }
  const rows = lines.map(l => l.split(',').map(c => c.trim()));
  let html = '<table>';
  rows.forEach((cells, i) => {
    const tag = i === 0 ? 'th' : 'td';
    html += '<tr>' + cells.map(c =>
      `<${tag}${!c && i ? ' class="empty"' : ''}>${escapeHtml(c)}</${tag}>`
    ).join('') + '</tr>';
  });
  $('table').innerHTML = html + '</table>';
  const filled = rows.slice(1).flat().filter(c => c).length;
  const total = (rows.length - 1) * rows[0].length;
  $('table').insertAdjacentHTML('beforeend',
    `<div class="meta">${rows.length - 1} rows · ${filled}/${total} cells read` +
    ` (${total ? Math.round(100 * filled / total) : 0}%)</div>`);
}

const escapeHtml = s => s.replace(/[&<>"]/g, c =>
  ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
</script>
"""


def call_model(image_b64, model):
    body = json.dumps({
        "model": model,
        "max_tokens": 4096,
        "temperature": 0,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "text", "text": PROMPT},
                {"type": "image_url",
                 "image_url": {"url": f"data:image/jpeg;base64,{image_b64}"}},
            ],
        }],
    }).encode()

    req = urllib.request.Request(
        f"{BASE_URL}/chat/completions",
        data=body,
        headers={
            "Authorization": f"Bearer {API_KEY}",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, context=SSL_CTX, timeout=180) as r:
        data = json.loads(r.read())

    text = data["choices"][0]["message"]["content"].strip()
    # Models fence the CSV despite being told not to. Strip it rather than
    # fight the prompt.
    if text.startswith("```"):
        text = "\n".join(text.split("\n")[1:])
        text = text.rsplit("```", 1)[0].strip()
    tokens = data.get("usage", {}).get("total_tokens")
    return text, tokens


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="application/json"):
        raw = body if isinstance(body, bytes) else body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        self._send(200, PAGE, "text/html; charset=utf-8")

    def do_POST(self):
        if self.path != "/extract":
            return self._send(404, json.dumps({"error": "not found"}))
        try:
            n = int(self.headers.get("Content-Length", 0))
            payload = json.loads(self.rfile.read(n))
            t0 = time.time()
            csv, tokens = call_model(payload["image"], payload["model"])
            print(f"  -> {len(csv.splitlines())} lines, {tokens} tokens, "
                  f"{time.time() - t0:.1f}s")
            self._send(200, json.dumps({"csv": csv, "tokens": tokens}))
        except urllib.error.HTTPError as e:
            detail = e.read().decode()[:500]
            print(f"  !! HTTP {e.code}: {detail}")
            self._send(e.code, json.dumps({"error": f"HTTP {e.code}: {detail}"}))
        except Exception as e:
            msg = str(e)
            if "CERTIFICATE_VERIFY_FAILED" in msg:
                msg += ("  — macOS python.org build with no cert store. Run "
                        "'/Applications/Python 3.x/Install Certificates.command' once.")
            print(f"  !! {msg}")
            self._send(500, json.dumps({"error": msg}))

    def log_message(self, fmt, *args):
        pass


def demo():
    """Self-check: the fence-stripping and CSV shape, without burning an API call."""
    fenced = '```csv\nname,phone\nRavi,9812345678\n```'
    stripped = fenced
    if stripped.startswith("```"):
        stripped = "\n".join(stripped.split("\n")[1:]).rsplit("```", 1)[0].strip()
    assert stripped == "name,phone\nRavi,9812345678", stripped
    assert PROMPT.count("name,phone,join_date,expiry_date,plan,amount") == 1
    print("self-check ok")


if __name__ == "__main__":
    if "--test" in sys.argv:
        demo()
        sys.exit(0)
    if not API_KEY:
        sys.exit("NVIDIA_API_KEY not set.\n"
                 "  Get one free at https://build.nvidia.com/settings/api-keys\n"
                 "  export NVIDIA_API_KEY=nvapi-...")
    print(f"Register OCR test → http://localhost:{PORT}")
    print(f"  model endpoint: {BASE_URL}")
    HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
