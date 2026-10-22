// LiftLog translations. The app is written in English; this layer swaps the
// English text on screen for the chosen language as the page draws.
// Dictionaries live in i18n/<lang>.json as { "English text": "translation" }.
// Numbers are written as {0}, {1}… in keys, and {x} in pattern keys stands for a name.
(function () {
  const LANGS = [
    ["en", "English"], ["es", "Español"], ["fr", "Français"], ["pt-BR", "Português (Brasil)"],
    ["vi", "Tiếng Việt"], ["zh", "中文 (简体)"], ["ja", "日本語"], ["ko", "한국어"], ["ar", "العربية"]
  ];
  const codes = LANGS.map((l) => l[0]);
  function pick() {
    let v = null; try { v = JSON.parse(localStorage.getItem("ll.lang")); } catch (e) {}
    if (v && codes.includes(v)) return v;
    const nav = (navigator.languages || [navigator.language || "en"]).map((x) => String(x));
    for (const n of nav) {
      const l = n.toLowerCase();
      if (l.startsWith("pt")) return "pt-BR";
      const base = l.split("-")[0];
      const hit = codes.find((c) => c.toLowerCase() === base);
      if (hit) return hit;
    }
    return "en";
  }
  const lang = pick();
  document.documentElement.lang = lang === "zh" ? "zh-CN" : lang;
  if (lang === "ar") document.documentElement.dir = "rtl";

  let dict = null, pats = [];
  const NUM = /\d+(?:[.,:]\d+)*/g;
  const norm = (s) => s.replace(/\s+/g, " ").trim();
  function keyify(s) { const nums = []; let i = 0; const k = s.replace(NUM, (m) => { nums.push(m); return "{" + i++ + "}"; }); return { k, nums }; }
  function fill(t, nums) { return t.replace(/\{(\d+)\}/g, (m, i) => (nums[+i] != null ? nums[+i] : m)); }
  function look(raw) {
    const s = norm(raw); if (!s || !/[A-Za-z]/.test(s)) return null;
    if (dict[s] != null) return dict[s];
    const { k, nums } = keyify(s);
    if (dict[k] != null) return fill(dict[k], nums);
    for (const p of pats) { const m = s.match(p.re); if (m) return p.t.replace(/\{x(\d*)\}/g, (_, n) => { const v = m[n ? +n : 1] || ""; return look(v) ?? v; }); }
    return null;
  }
  const INLINE = new Set(["B", "I", "STRONG", "EM", "SMALL", "BR", "CODE", "U"]);
  function simple(el) {
    for (const c of el.childNodes) {
      if (c.nodeType === 3) continue;
      if (c.nodeType === 1 && INLINE.has(c.tagName) && !c.attributes.length && simple(c)) continue;
      return false;
    }
    return true;
  }
  const SKIP = new Set(["SCRIPT", "STYLE", "TEXTAREA", "SVG", "svg", "CODE", "OPTION_SKIP"]);
  const ATTRS = ["placeholder", "aria-label", "title"];
  const collect = window.__i18nCollect || null;
  function rec(s) { if (!collect) return; s = norm(s); if (s && /[A-Za-z]/.test(s)) collect.add(keyify(s).k); }
  function attrs(el) {
    for (const a of ATTRS) {
      const v = el.getAttribute && el.getAttribute(a); if (!v) continue;
      if (collect) { rec(v); continue; }
      if (!dict) continue;
      const done = el.__i18a || (el.__i18a = {}); if (done[a] === v) continue;
      const t = look(v); if (t != null) { el.setAttribute(a, t); done[a] = t; }
    }
  }
  function walk(n) {
    if (n.nodeType === 3) {
      if (n.__i18 === n.nodeValue) return;
      const v = n.nodeValue; if (!v || !/[A-Za-z]/.test(v)) return;
      if (collect) { rec(v); return; }
      if (!dict) return;
      const t = look(v);
      if (t != null) { const lead = v.match(/^\s*/)[0], tail = v.match(/\s*$/)[0]; n.nodeValue = lead + t + tail; }
      n.__i18 = n.nodeValue; return;
    }
    if (n.nodeType !== 1 || SKIP.has(n.tagName) || n.hasAttribute("data-noi18n")) return;
    attrs(n);
    if (n.tagName === "INPUT" && (n.type === "button" || n.type === "submit") && n.value) { if (collect) rec(n.value); else if (dict) { const t = look(n.value); if (t != null) n.value = t; } }
    const hasEl = [...n.childNodes].some((c) => c.nodeType === 1);
    if (hasEl && simple(n) && /[A-Za-z]/.test(n.textContent || "")) {
      const html = norm(n.innerHTML.replace(/<br\s*\/?>/gi, "<br>"));
      if (collect) { rec(html); }
      else if (dict && n.__i18h !== n.innerHTML) {
        const t = look(html);
        if (t != null) { n.innerHTML = t; n.__i18h = n.innerHTML; [...n.childNodes].forEach((c) => { if (c.nodeType === 3) c.__i18 = c.nodeValue; }); return; }
      }
      if (n.__i18h === n.innerHTML) return;
    }
    for (const c of [...n.childNodes]) walk(c);
  }
  function run(root) { try { walk(root || document.body); } catch (e) {} }

  const mo = new MutationObserver((ms) => {
    if (!dict && !collect) return;
    for (const m of ms) {
      if (m.type === "characterData") walk(m.target);
      else if (m.type === "attributes") { if (m.target.nodeType === 1) attrs(m.target); }
      else m.addedNodes.forEach((x) => walk(x));
    }
  });
  function start() { mo.observe(document.body, { subtree: true, childList: true, characterData: true, attributes: true, attributeFilter: ATTRS }); run(); }

  window.LIFTLOG_I18N = {
    lang, langs: LANGS, locale: lang === "en" ? undefined : (lang === "zh" ? "zh-CN" : lang),
    set(code) { try { localStorage.setItem("ll.lang", JSON.stringify(code)); } catch (e) {} location.reload(); },
    t(s) { return dict ? (look(s) ?? s) : s; },
    run
  };

  const ready = () => (document.readyState !== "loading" ? Promise.resolve() : new Promise((r) => document.addEventListener("DOMContentLoaded", r, { once: true })));
  if (collect) { ready().then(start); return; }
  if (lang === "en") return;
  const hide = document.createElement("style"); hide.textContent = "body{visibility:hidden}"; document.head.appendChild(hide);
  const unhide = () => hide.remove(); setTimeout(unhide, 2500);
  fetch("i18n/" + lang + ".json").then((r) => (r.ok ? r.json() : null)).then((d) => {
    if (!d) return;
    dict = {}; pats = [];
    Object.keys(d).forEach((k) => {
      if (/\{x\d*\}/.test(k)) {
        const esc = k.replace(/[.*+?^${}()|[\]\\]/g, "\\$&").replace(/\\\{x\d*\\\}/g, "(.+?)");
        pats.push({ re: new RegExp("^" + esc + "$"), t: d[k], keys: k });
      } else dict[k] = d[k];
    });
    pats.sort((a, b) => b.keys.length - a.keys.length);
    return ready().then(start);
  }).catch(() => {}).finally(() => ready().then(unhide));
})();
