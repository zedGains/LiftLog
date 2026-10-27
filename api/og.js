// /api/og?code=XXXXXX → 1200×630 PNG of someone's player card, used as the link preview image.
import { ImageResponse } from "@vercel/og";
import { rankInfo, rankFrame, helmEmblem, initialsOf, RANKS } from "./_emblem.js";
import { inviteCard, cleanCode } from "./_card.js";

export const config = { runtime: "edge" };

const h = (type, style, children) => ({ type, props: { style: { display: "flex", ...style }, children } });
const svgSrc = (svg) => "data:image/svg+xml;base64," + btoa(unescape(encodeURIComponent(svg.replace("<svg ", '<svg xmlns="http://www.w3.org/2000/svg" '))));
let fontCache = null;
async function fonts() {
  if (fontCache) return fontCache;
  try {
    const get = (w) => fetch(`https://cdn.jsdelivr.net/npm/@fontsource/barlow-condensed@5.0.13/files/barlow-condensed-latin-${w}-normal.woff`).then((r) => r.arrayBuffer());
    const [b7, b8] = await Promise.all([get(700), get(800)]);
    fontCache = [{ name: "Barlow Condensed", data: b7, weight: 700, style: "normal" }, { name: "Barlow Condensed", data: b8, weight: 800, style: "normal" }];
  } catch (e) { fontCache = []; }
  return fontCache;
}

export default async function handler(req) {
  const u = new URL(req.url), code = cleanCode(u.searchParams.get("code"));
  const info = await inviteCard(u.origin, code);
  const name = (info && info.name) || "LiftLog";
  const c = (info && info.card) || null;
  const r = rankInfo(c ? c.pts || 0 : 0), P = RANKS[r.i] || RANKS[0];
  const emblem = c && c.helm ? helmEmblem(r, "") : rankFrame(r, { ini: "" }, "");
  const stat = (v, l) => h("div", { flexDirection: "column", marginRight: 44 }, [
    h("div", { fontSize: 64, fontWeight: 800, color: "#fff", lineHeight: 1 }, String(v)),
    h("div", { fontSize: 26, fontWeight: 700, color: "#9aa3ae", textTransform: "uppercase", letterSpacing: 2, marginTop: 6 }, l)]);
  const tree = h("div", { width: 1200, height: 630, background: `radial-gradient(circle at 25% 45%, ${P[3]}55 0%, ${P[2]}22 30%, #0b0e13 65%)`, backgroundColor: "#0b0e13", fontFamily: "Barlow Condensed", color: "#fff", padding: "56px 70px", flexDirection: "column" }, [
    h("div", { alignItems: "center", fontSize: 40, fontWeight: 800, letterSpacing: 4 }, [h("div", { width: 18, height: 18, borderRadius: 9, background: "#3ECF8E", marginRight: 14 }, []), "LIFTLOG"]),
    h("div", { flex: 1, alignItems: "center" }, [
      h("div", { position: "relative", width: 360, height: 380, marginRight: 50 }, [
        { type: "img", props: { src: svgSrc(emblem), width: 360, height: 380 } },
        c && c.helm ? h("div", {}, []) : h("div", { position: "absolute", left: 0, top: 0, width: 360, height: 404, alignItems: "center", justifyContent: "center", fontSize: 92, fontWeight: 800, color: "#fff" }, initialsOf(name))
      ]),
      h("div", { flexDirection: "column", flex: 1 }, [
        h("div", { fontSize: 34, fontWeight: 700, color: "#3ECF8E", textTransform: "uppercase", letterSpacing: 3 }, info ? "Join me on LiftLog" : "Track. Lift. Rank up."),
        h("div", { fontSize: 104, fontWeight: 800, lineHeight: 1, textTransform: "uppercase", marginTop: 6 }, name.slice(0, 18)),
        h("div", { fontSize: 44, fontWeight: 800, color: P[3], textTransform: "uppercase", letterSpacing: 2, marginTop: 10 }, c ? r.full : "Workout log & leaderboard"),
        c ? h("div", { marginTop: 34 }, [stat(c.lvl || 1, "Level"), stat(c.badges || 0, "Badges"), stat(c.streak || 0, "Week streak")]) : h("div", {}, [])
      ])
    ]),
    h("div", { fontSize: 28, fontWeight: 700, color: "#9aa3ae" }, "Free workout log · badges · ranks · leaderboard")
  ]);
  return new ImageResponse(tree, { width: 1200, height: 630, fonts: await fonts(), headers: { "Cache-Control": "public, max-age=600, s-maxage=3600" } });
}
