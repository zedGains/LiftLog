// Shared helpers for invite link previews (/i/CODE and /api/og).
export async function supaConfig(origin) {
  // Reuse the public settings the app already ships in config.js (URL + publishable key).
  const t = await (await fetch(new URL("/config.js", origin))).text();
  const url = (t.match(/supabaseUrl:\s*"([^"]+)"/) || [])[1];
  const key = (t.match(/supabaseAnonKey:\s*"([^"]+)"/) || [])[1];
  return { url, key };
}
export function cleanCode(c) { return String(c || "").replace(/[^A-Za-z0-9]/g, "").slice(0, 12).toUpperCase(); }
export async function inviteCard(origin, code) {
  if (!code) return null;
  try {
    const { url, key } = await supaConfig(origin);
    if (!url || !key) return null;
    const r = await fetch(`${url}/rest/v1/rpc/invite_card`, {
      method: "POST", headers: { apikey: key, Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
      body: JSON.stringify({ code })
    });
    if (!r.ok) return null;
    return await r.json();
  } catch (e) { return null; }
}
