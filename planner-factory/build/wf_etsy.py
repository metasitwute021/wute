"""Etsy Connect: get a refresh token, a shop id and the right taxonomy id.

Three things have to exist before the factory can publish, and none of them can
be typed from memory:

* a refresh token - Etsy mandates PKCE on the authorisation-code flow, and
  n8n's generic OAuth2 credential does not send a code_challenge, so it cannot
  complete the handshake. The PKCE dance is done here, in plain JavaScript.
* the numeric shop id, which is not the shop name.
* the taxonomy id for "Calendars & Planners". Etsy rejects a listing filed
  under the wrong one, and the number is not guessable - the previous system
  used a single hardcoded guess for eight different product types.

Run this once. It prints all three on a web page, ready to paste into the
Planner Config node.
"""

from __future__ import annotations

from nodes import (
    CONFIG_NODE, RETRY, T_CODE, T_HTTP, T_IF, T_RESPOND, T_WEBHOOK, Workflow,
    cfg, code, etsy_http, if_true, pos,
)

SCOPES = "listings_r listings_w listings_d shops_r"

JS_ROUTE = r"""
// One webhook serves both legs of the handshake: the first visit has no code,
// the redirect back from Etsy does.
const query = $input.first().json.query || {};
return [{ json: { ...$input.first().json, has_code: Boolean(query.code),
                  code: query.code || null, state: query.state || null,
                  etsy_error: query.error || null } }];
"""

JS_AUTH_URL = r"""
// Leg 1: build the authorisation URL, including the PKCE challenge.
const cfg = $('""" + CONFIG_NODE + r"""').first().json.cfg;
const apiKey = String(cfg.ETSY_API_KEY || '').trim();
if (!apiKey) {
  throw new Error('Put your Etsy API key (keystring) into ETSY_API_KEY in the ' +
    'Planner Config node first, then open this URL again.');
}

const webhookUrl = $execution.customData ? null : null;   // not used; kept explicit
const redirectUri = $input.first().json.webhookUrl
  || `${$input.first().json.headers['x-forwarded-proto'] || 'https'}://` +
     `${$input.first().json.headers.host}${$input.first().json.path || ''}`;

// PKCE: a random verifier, and its SHA-256 as the challenge. The verifier has
// to survive until Etsy redirects back, so it lives in workflow static data.
const bytes = require('crypto').randomBytes(48);
const b64url = (buf) => Buffer.from(buf).toString('base64')
  .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
const verifier = b64url(bytes);
const challenge = b64url(require('crypto').createHash('sha256').update(verifier).digest());
const state = b64url(require('crypto').randomBytes(12));

const store = $getWorkflowStaticData('global');
store.code_verifier = verifier;
store.state = state;
store.redirect_uri = redirectUri;

const url = `${cfg.ETSY_API_BASE}/oauth/connect?` + [
  'response_type=code',
  `redirect_uri=${encodeURIComponent(redirectUri)}`,
  `scope=${encodeURIComponent('""" + SCOPES + r"""')}`,
  `client_id=${encodeURIComponent(apiKey)}`,
  `state=${encodeURIComponent(state)}`,
  `code_challenge=${encodeURIComponent(challenge)}`,
  'code_challenge_method=S256',
].join('&');

return [{ json: { auth_url: url, redirect_uri: redirectUri } }];
"""

JS_AUTH_PAGE = r"""
// A page with one button, because a raw URL in an n8n output panel is easy to
// truncate and hard to click.
const data = $input.first().json;
return [{ json: { html: `<!doctype html>
<html lang="th"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>เชื่อมต่อ Etsy</title>
<style>
 body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
      max-width:640px;margin:40px auto;padding:0 20px;line-height:1.7;color:#1a1a1a}
 a.btn{display:inline-block;background:#f1641e;color:#fff;padding:14px 28px;
       border-radius:24px;text-decoration:none;font-weight:600;margin:20px 0}
 code{background:#f4f4f4;padding:2px 6px;border-radius:4px;font-size:13px}
</style></head><body>
<h1>เชื่อมต่อร้าน Etsy</h1>
<p>กดปุ่มข้างล่างเพื่ออนุญาตให้โรงงานเข้าถึงร้านของคุณ
   หลังกดอนุญาต Etsy จะพากลับมาที่หน้านี้พร้อมค่าที่ต้องใช้</p>
<p><a class="btn" href="${data.auth_url}">อนุญาตให้เข้าถึงร้าน Etsy</a></p>
<p style="color:#666;font-size:14px">redirect_uri ที่ใช้: <code>${data.redirect_uri}</code><br>
ค่านี้ต้องตรงกับที่ตั้งไว้ในหน้า App ของ Etsy เป๊ะ ๆ ไม่งั้นจะขึ้น error</p>
</body></html>` } }];
"""

JS_TOKEN_BODY = r"""
// Leg 2: swap the code for tokens, using the verifier we stashed.
const cfg = $('""" + CONFIG_NODE + r"""').first().json.cfg;
const incoming = $('Route Request').first().json;
const store = $getWorkflowStaticData('global');

if (incoming.etsy_error) {
  throw new Error(`Etsy refused the authorisation: ${incoming.etsy_error}`);
}
if (!store.code_verifier) {
  throw new Error('No PKCE verifier is stored. Open the webhook URL without ' +
    'parameters first to start the handshake, then approve on Etsy.');
}
if (store.state && incoming.state && store.state !== incoming.state) {
  throw new Error('The state value came back different from the one sent. ' +
    'Start again rather than trusting this response.');
}

return [{
  json: {
    token_body: {
      grant_type: 'authorization_code',
      client_id: String(cfg.ETSY_API_KEY || '').trim(),
      redirect_uri: store.redirect_uri,
      code: incoming.code,
      code_verifier: store.code_verifier,
    },
  },
}];
"""

JS_TAXONOMY = r"""
// Find the taxonomy id for planners instead of guessing it. Etsy's tree is
// public, so this is an exact lookup rather than a number in a comment.
const nodes = $input.first().json.results || [];
const flat = [];
const walk = (list, path) => {
  for (const node of list) {
    const here = path ? `${path} > ${node.name}` : node.name;
    flat.push({ id: node.id, path: here, level: node.level });
    if (Array.isArray(node.children) && node.children.length) walk(node.children, here);
  }
};
walk(nodes, '');

const wanted = /calendar|planner/i;
const matches = flat.filter((n) => wanted.test(n.path))
  .sort((a, b) => b.level - a.level);

// The deepest match under Paper is the one Etsy expects for a planner PDF.
const best = matches.find((n) => /paper/i.test(n.path)) || matches[0] || null;

return [{
  json: {
    taxonomy_best: best,
    taxonomy_candidates: matches.slice(0, 12),
    taxonomy_total: flat.length,
  },
}];
"""

JS_RESULT_PAGE = r"""
// Everything the user has to copy, on one page, labelled in Thai.
const token = $('Etsy: Exchange Code').first().json;
const shops = $('Etsy: My Shops').first().json;
const tax = $input.first().json;

const shop = (shops.results && shops.results[0]) || shops || {};
const rows = [
  ['ETSY_REFRESH_TOKEN', token.refresh_token, 'ใช้ต่ออายุการเข้าถึงอัตโนมัติ (อายุ 90 วัน)'],
  ['ETSY_SHOP_ID', shop.shop_id, `ร้าน: ${shop.shop_name || '(ไม่ทราบชื่อ)'}`],
  ['ETSY_TAXONOMY_ID', tax.taxonomy_best ? tax.taxonomy_best.id : '',
   tax.taxonomy_best ? tax.taxonomy_best.path : 'หาไม่พบ - ดูรายการข้างล่าง'],
];

const esc = (s) => String(s === undefined || s === null ? '' : s)
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

const candidates = (tax.taxonomy_candidates || [])
  .map((c) => `<tr><td><code>${c.id}</code></td><td>${esc(c.path)}</td></tr>`).join('');

return [{ json: { html: `<!doctype html>
<html lang="th"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>เชื่อมต่อ Etsy สำเร็จ</title>
<style>
 body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;
      max-width:820px;margin:40px auto;padding:0 20px;line-height:1.7;color:#1a1a1a}
 table{border-collapse:collapse;width:100%;margin:16px 0}
 td,th{border:1px solid #e0e0e0;padding:10px;text-align:left;vertical-align:top;font-size:14px}
 th{background:#fafafa}
 code{background:#f4f4f4;padding:3px 7px;border-radius:4px;
      font-family:ui-monospace,Menlo,monospace;font-size:13px;word-break:break-all}
 .warn{background:#fff6e5;border-left:4px solid #f1a01e;padding:12px 16px;margin:20px 0}
</style></head><body>
<h1>เชื่อมต่อสำเร็จ</h1>
<p>ก๊อป 3 ค่านี้ไปวางใน node <strong>Planner Config</strong> ของ workflow
   <strong>Planner Factory</strong></p>
<table><tr><th>ตั้งค่าชื่อ</th><th>ค่าที่ต้องวาง</th><th>คืออะไร</th></tr>
${rows.map(([k, v, note]) =>
  `<tr><td><strong>${k}</strong></td><td><code>${esc(v)}</code></td><td>${esc(note)}</td></tr>`
).join('')}</table>
<div class="warn">เก็บหน้านี้ไว้จนกว่าจะวางค่าครบ - refresh token จะแสดงครั้งเดียว
ถ้าทำหาย ต้องเริ่มขั้นตอนใหม่ทั้งหมด</div>
<h2>หมวดหมู่อื่นที่เข้าข่าย</h2>
<p style="color:#666;font-size:14px">ถ้าหมวดที่เลือกอัตโนมัติไม่ตรง เลือกจากรายการนี้แทนได้
(ค้นจากทั้งหมด ${tax.taxonomy_total} หมวด)</p>
<table><tr><th>id</th><th>เส้นทางหมวดหมู่</th></tr>${candidates}</table>
</body></html>` } }];
"""


def build() -> dict:
    wf = Workflow("02", "Etsy Connect")

    wf.add("Open This URL", T_WEBHOOK, pos(0, 0),
           {"path": "etsy-connect", "responseMode": "responseNode",
            "options": {"rawBody": False}},
           notes="เปิด URL ของ webhook นี้ในเบราว์เซอร์เพื่อเริ่มเชื่อมต่อ Etsy",
           webhookId="planner-etsy-connect")
    wf.add(CONFIG_NODE, T_CODE, pos(1, 0), code(_config_body()),
           notes="อ่านค่า ETSY_API_KEY - ต้องใส่ก่อนใช้หน้านี้")
    wf.add("Route Request", T_CODE, pos(2, 0), code(JS_ROUTE),
           notes="แยกว่าเป็นการเปิดครั้งแรก หรือ Etsy ส่งกลับมาพร้อม code")
    wf.add("Has Code?", T_IF, pos(3, 0), if_true("={{ $json.has_code }}"),
           notes="มี code = ขากลับ, ไม่มี = ขาไป")

    wf.link("Open This URL", CONFIG_NODE)
    wf.chain(CONFIG_NODE, "Route Request", "Has Code?")

    # -- leg 1: send the user to Etsy -------------------------------------
    wf.add("Build Auth URL", T_CODE, pos(4, 1), code(JS_AUTH_URL),
           notes="สร้าง URL อนุญาตสิทธิ์ พร้อม PKCE (n8n OAuth2 ปกติทำไม่ได้)")
    wf.add("Show Auth Page", T_CODE, pos(5, 1), code(JS_AUTH_PAGE),
           notes="หน้าเว็บที่มีปุ่มเดียว - กดแล้วไป Etsy")
    wf.add("Send Auth Page", T_RESPOND, pos(6, 1),
           {"respondWith": "text", "responseBody": "={{ $json.html }}",
            "options": {"responseHeaders": {"entries": [
                {"name": "Content-Type", "value": "text/html; charset=utf-8"}]}}},
           notes="ส่งหน้าเว็บกลับไปที่เบราว์เซอร์")

    wf.link("Has Code?", "Build Auth URL", 1)
    wf.chain("Build Auth URL", "Show Auth Page", "Send Auth Page")

    # -- leg 2: exchange, then look everything up --------------------------
    wf.add("Build Token Request", T_CODE, pos(4, -1), code(JS_TOKEN_BODY),
           notes="ประกอบคำขอแลก token พร้อม code_verifier ที่เก็บไว้ตอนขาไป")
    wf.add("Etsy: Exchange Code", T_HTTP, pos(5, -1), {
        "method": "POST",
        "url": "={{ " + cfg("ETSY_API_BASE") + " }}/v3/public/oauth/token",
        "authentication": "none",
        "sendBody": True,
        "specifyBody": "json",
        "jsonBody": "={{ JSON.stringify($json.token_body) }}",
        "options": {"timeout": 30000},
    }, notes="แลก code เป็น access token + refresh token", **RETRY)
    wf.add("Etsy: My Shops", T_HTTP, pos(6, -1),
           etsy_http("GET",
                     "={{ " + cfg("ETSY_API_BASE") + " }}/v3/application/users/me/shops",
                     token_from="Etsy: Exchange Code"),
           notes="หา shop_id ที่เป็นตัวเลข (ไม่ใช่ชื่อร้าน)", **RETRY)
    wf.add("Etsy: Taxonomy Tree", T_HTTP, pos(7, -1),
           etsy_http("GET",
                     "={{ " + cfg("ETSY_API_BASE")
                     + " }}/v3/application/seller-taxonomy/nodes",
                     token_from="Etsy: Exchange Code"),
           notes="ดึงหมวดหมู่ทั้งต้นจาก Etsy", **RETRY)
    wf.add("Find Planner Category", T_CODE, pos(8, -1), code(JS_TAXONOMY),
           notes="ค้นหมวด Calendars & Planners จริง ๆ แทนการเดาเลข")
    wf.add("Show Result Page", T_CODE, pos(9, -1), code(JS_RESULT_PAGE),
           notes="หน้าสรุป 3 ค่าที่ต้องก๊อปไปใส่ Planner Config")
    wf.add("Send Result Page", T_RESPOND, pos(10, -1),
           {"respondWith": "text", "responseBody": "={{ $json.html }}",
            "options": {"responseHeaders": {"entries": [
                {"name": "Content-Type", "value": "text/html; charset=utf-8"}]}}},
           notes="ส่งหน้าสรุปกลับไปที่เบราว์เซอร์")

    wf.link("Has Code?", "Build Token Request", 0)
    wf.chain("Build Token Request", "Etsy: Exchange Code", "Etsy: My Shops",
             "Etsy: Taxonomy Tree", "Find Planner Category", "Show Result Page",
             "Send Result Page")

    return wf.to_dict()


def _config_body() -> str:
    from nodes import config_js
    return config_js()
