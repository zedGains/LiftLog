// /i/CODE → a tiny page with link-preview tags (title, picture) for chat apps, then straight into the app.
import { inviteCard, cleanCode } from "./_card.js";
import { rankInfo } from "./_emblem.js";

export const config = { runtime: "edge" };
const esc = (t) => String(t).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

export default async function handler(req) {
  const u = new URL(req.url), code = cleanCode(u.searchParams.get("code") || u.pathname.split("/").pop());
  const info = await inviteCard(u.origin, code);
  const name = (info && info.name) || "A friend", c = info && info.card;
  const title = info ? `${name} invited you to LiftLog` : "LiftLog";
  const bits = c ? [rankInfo(c.pts || 0).full, c.streak ? `${c.streak}-week streak` : "", c.badges ? `${c.badges} badges` : ""].filter(Boolean).join(" · ") : "";
  const desc = `${bits ? bits + ". " : ""}Track your workouts, earn badges and climb the leaderboard together. Free.`;
  const img = `${u.origin}/api/og?code=${code}&v=${c ? `${c.pts || 0}-${c.badges || 0}-${c.streak || 0}-${c.helm ? 1 : 0}` : 0}`;
  const go = `/?ref=${code}`;
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>${esc(title)}</title><meta name="description" content="${esc(desc)}">
<meta property="og:type" content="website"><meta property="og:site_name" content="LiftLog"><meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(desc)}"><meta property="og:url" content="${esc(u.origin + "/i/" + code)}">
<meta property="og:image" content="${esc(img)}"><meta property="og:image:width" content="1200"><meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image"><meta name="twitter:title" content="${esc(title)}"><meta name="twitter:description" content="${esc(desc)}"><meta name="twitter:image" content="${esc(img)}">
<meta http-equiv="refresh" content="0;url=${esc(go)}"><style>body{background:#0f1114;color:#eceef0;font:16px system-ui;display:grid;place-items:center;height:100vh;margin:0}a{color:#3ecf8e}</style>
</head><body><p><a href="${esc(go)}">Open LiftLog</a></p><script>location.replace(${JSON.stringify(go)})</script></body></html>`;
  return new Response(html, { headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "public, max-age=300, s-maxage=600" } });
}
