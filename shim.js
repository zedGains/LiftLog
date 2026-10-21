/* LiftLog backend bridge.
 * The app was first built against a small runtime API: window.claude.use("db" | "user" | "downloads").
 * This file provides the same API on top of Supabase (sign-in + one Postgres table + realtime),
 * so the app code stays the same whether it runs here or as a Claude artifact.
 *
 * Storage model: one row per document in public.docs
 *   path  "data/users/<uid>/_plan", "programs/<uid>", "social/<uid>", ...
 *   col   the collection part of the path ("data/users/<uid>", "programs", "social")
 *   data  the document body (jsonb)
 * Access rules live in supabase/schema.sql (row-level security).
 */
(function () {
  "use strict";
  const CFG = window.LIFTLOG_CONFIG || {};
  const configured = !!(CFG.supabaseUrl && CFG.supabaseAnonKey && window.supabase);
  const LL_UID = "ll.uid";

  /* ---------- tiny helpers ---------- */
  const clone = (v) => (v == null ? v : JSON.parse(JSON.stringify(v)));
  const lsGet = (k) => { try { return localStorage.getItem(k); } catch (e) { return null; } };
  const lsSet = (k, v) => { try { localStorage.setItem(k, v); } catch (e) {} };
  function clearAppStorage() {
    try {
      Object.keys(localStorage).filter((k) => k.startsWith("ll.")).forEach((k) => localStorage.removeItem(k));
    } catch (e) {}
  }
  function err(code, message) { const e = new Error(message || code); e.code = code; return e; }
  function mapErr(e) {
    if (!e) return err("unknown");
    if (e.code && typeof e.code === "string" && !/^\d/.test(e.code)) return e;
    const msg = String(e.message || e);
    if (/fetch|network|Failed to|timeout|offline/i.test(msg)) return err("unavailable", msg);
    if (/row-level security|permission|42501/i.test(msg) || e.code === "42501") return err("permission_denied", msg);
    return err("unknown", msg);
  }

  /* If this device holds data from a different (or no) account, start clean so nothing leaks between people. */
  function storedSessionUid() {
    if (!configured) return null;
    try {
      const ref = new URL(CFG.supabaseUrl).hostname.split(".")[0];
      const raw = lsGet(`sb-${ref}-auth-token`);
      const s = raw && JSON.parse(raw);
      return (s && s.user && s.user.id) || null;
    } catch (e) { return null; }
  }
  if (configured) {
    const sUid = storedSessionUid();
    if (sUid && lsGet(LL_UID) !== sUid) { clearAppStorage(); lsSet(LL_UID, sUid); }
  }

  /* ---------- downloads (works without an account) ---------- */
  const downloadsApi = Object.freeze({
    save({ filename, data }) {
      return new Promise((resolve) => {
        const blob = data instanceof Blob ? data : new Blob([data], { type: /\.csv$/i.test(filename) ? "text/csv" : "text/plain" });
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url; a.download = filename || "download"; document.body.appendChild(a); a.click(); a.remove();
        setTimeout(() => URL.revokeObjectURL(url), 2000); resolve();
      });
    }
  });

  if (!configured) {
    // No backend yet: the app runs in its local (this-device-only) mode.
    window.claude = Object.freeze({ use: async (name) => (name === "downloads" ? downloadsApi : null) });
    window.LIFTLOG_ACCOUNT = null;
    document.addEventListener("DOMContentLoaded", () => showNotice());
    return;
  }

  const sb = window.supabase.createClient(CFG.supabaseUrl, CFG.supabaseAnonKey, {
    auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
  });
  window.__sb = sb;

  /* ---------- auth ---------- */
  let resolveReady; const ready = new Promise((r) => (resolveReady = r));
  let currentUser = null;

  async function ensureProfile(user) {
    const name = (user.user_metadata && user.user_metadata.name) || (user.email || "").split("@")[0];
    try { await sb.from("profiles").upsert({ id: user.id, name }, { onConflict: "id", ignoreDuplicates: true }); } catch (e) {}
  }
  function signedIn(user) {
    if (lsGet(LL_UID) !== user.id) { clearAppStorage(); lsSet(LL_UID, user.id); location.reload(); return; }
    currentUser = user;
    window.LIFTLOG_ACCOUNT = {
      email: user.email,
      name: (user.user_metadata && user.user_metadata.name) || "",
      signOut: async () => { await sb.auth.signOut(); clearAppStorage(); location.reload(); }
    };
    ensureProfile(user);
    hideAuth();
    resolveReady(user);
  }
  sb.auth.getSession().then(({ data }) => {
    if (data && data.session) signedIn(data.session.user); else showAuth("signin");
  });
  sb.auth.onAuthStateChange((event, session) => {
    if (event === "SIGNED_IN" && session && !currentUser) signedIn(session.user);
    if (event === "PASSWORD_RECOVERY") showAuth("newpass");
    if (event === "SIGNED_OUT") { currentUser = null; }
  });

  /* ---------- db ---------- */
  const listeners = new Map(); // col -> {map, cbs, channel, loaded}
  function colOf(path) { const i = path.lastIndexOf("/"); return { col: path.slice(0, i), id: path.slice(i + 1) }; }
  function emit(L) {
    if (L.scheduled) return; L.scheduled = true;
    queueMicrotask(() => {
      L.scheduled = false;
      const docs = [...L.map.entries()].map(([id, data]) => ({ id, exists: true, data: () => clone(data), metadata: { fromCache: false, hasPendingWrites: false } }));
      const snap = { docs, size: docs.length, empty: !docs.length, metadata: { fromCache: false, hasPendingWrites: false } };
      L.cbs.forEach(({ next }) => { try { next(snap); } catch (e) { console.error(e); } });
    });
  }
  async function load(col, L) {
    let from = 0; const page = 1000; const map = new Map();
    for (;;) {
      const { data, error } = await sb.from("docs").select("path,data").eq("col", col).range(from, from + page - 1);
      if (error) throw mapErr(error);
      data.forEach((r) => map.set(colOf(r.path).id, r.data));
      if (data.length < page) break; from += page;
    }
    // keep optimistic local writes that the server hasn't confirmed yet
    (L.pending || new Map()).forEach((v, id) => map.set(id, v));
    L.map = map; L.loaded = true; emit(L);
  }
  function listen(col) {
    let L = listeners.get(col);
    if (L) return L;
    L = { map: new Map(), cbs: new Set(), loaded: false, pending: new Map() };
    listeners.set(col, L);
    L.channel = sb.channel("docs:" + col)
      .on("postgres_changes", { event: "*", schema: "public", table: "docs", filter: `col=eq.${col}` }, (p) => {
        if (p.eventType === "DELETE") { const path = p.old && p.old.path; if (path) L.map.delete(colOf(path).id); }
        else if (p.new && p.new.path) { const id = colOf(p.new.path).id; if (!L.pending.has(id)) L.map.set(id, p.new.data); }
        emit(L);
      })
      .subscribe((status) => { if (status === "SUBSCRIBED" && L.loaded) load(col, L).catch(() => {}); });
    return L;
  }
  const refreshAll = () => listeners.forEach((L, col) => { if (L.cbs.size) load(col, L).catch(() => {}); });
  document.addEventListener("visibilitychange", () => { if (document.visibilityState === "visible") refreshAll(); });
  window.addEventListener("online", refreshAll);

  function docRef(path) {
    const { col, id } = colOf(path);
    return Object.freeze({
      id, path,
      async get() {
        const { data, error } = await sb.from("docs").select("data").eq("path", path).maybeSingle();
        if (error) throw mapErr(error);
        return { id, exists: !!data, data: () => (data ? clone(data.data) : undefined), metadata: { fromCache: false, hasPendingWrites: false } };
      },
      async set(body) {
        const data = clone(body);
        const L = listeners.get(col);
        if (L) { L.pending.set(id, data); L.map.set(id, data); emit(L); }
        try {
          const { error } = await sb.from("docs").upsert({ path, col, data, updated_at: new Date().toISOString() }, { onConflict: "path" });
          if (error) throw mapErr(error);
        } finally { if (L && L.pending.get(id) === data) L.pending.delete(id); }
      },
      async update(patch) { const cur = await this.get(); if (!cur.exists) throw err("invalid_argument", "missing"); return this.set({ ...cur.data(), ...patch }); },
      async delete() {
        const { error } = await sb.from("docs").delete().eq("path", path); if (error) throw mapErr(error);
        const L = listeners.get(col); if (L) { L.map.delete(id); emit(L); }
      },
      onSnapshot(next, error) {
        const L = listen(col); const h = { next: (snap) => { const d = snap.docs.find((x) => x.id === id); next(d || { id, exists: false, data: () => undefined, metadata: snap.metadata }); }, error };
        L.cbs.add(h); if (L.loaded) emit(L); else load(col, L).catch((e) => error && error(e));
        return () => L.cbs.delete(h);
      }
    });
  }
  const dbApi = Object.freeze({
    doc: (path) => docRef(path),
    collection: (col) => Object.freeze({
      path: col,
      doc: (id) => docRef(col + "/" + id),
      onSnapshot(next, error) {
        const L = listen(col); const h = { next, error }; L.cbs.add(h);
        if (L.loaded) emit(L); else load(col, L).catch((e) => error && error(e));
        return () => L.cbs.delete(h);
      },
      async get() { const L = listen(col); await load(col, L); return { docs: [...L.map.entries()].map(([id, d]) => ({ id, exists: true, data: () => clone(d) })) }; }
    })
  });

  /* ---------- user ---------- */
  const userApi = Object.freeze({
    id: async () => (currentUser ? currentUser.id : null),
    me: async () => ({ id: currentUser.id, name: window.LIFTLOG_ACCOUNT.name }),
    isOwner: async () => {
      const { data } = await sb.from("admins").select("user_id").eq("user_id", currentUser.id).maybeSingle();
      return !!data;
    },
    canEdit: async () => false,
    profiles: async (ids) => {
      ids = [].concat(ids).filter(Boolean); const out = {};
      if (!ids.length) return out;
      const { data } = await sb.from("profiles").select("id,name").in("id", ids);
      (data || []).forEach((p) => (out[p.id] = { id: p.id, name: p.name || "" }));
      ids.forEach((i) => (out[i] = out[i] || { id: i, name: "" }));
      return out;
    }
  });

  window.claude = Object.freeze({
    use: async (name) => {
      if (name === "downloads") return downloadsApi;
      if (name === "db") { await ready; return dbApi; }
      if (name === "user") { await ready; return userApi; }
      return null;
    }
  });

  /* ---------- sign-in screen ---------- */
  let authMode = "signin";
  function authEl() {
    let el = document.getElementById("auth");
    if (!el) { el = document.createElement("div"); el.id = "auth"; el.setAttribute("role", "dialog"); el.setAttribute("aria-modal", "true"); el.setAttribute("aria-labelledby", "auth-title"); document.body.appendChild(el); }
    return el;
  }
  function hideAuth() { const el = document.getElementById("auth"); if (el) el.hidden = true; }
  function showAuth(mode) {
    if (document.readyState === "loading") { document.addEventListener("DOMContentLoaded", () => showAuth(mode)); return; }
    authMode = mode || authMode; const el = authEl(); el.hidden = false;
    const up = authMode === "signup", np = authMode === "newpass", fp = authMode === "forgot";
    el.innerHTML = `<div class="authcard">
      <div class="authbrand"><div class="plate" aria-hidden="true"><span></span></div><div><div class="eyebrow">LiftLog</div><h1 id="auth-title">${np ? "New password" : fp ? "Reset password" : up ? "Create account" : "Sign in"}</h1></div></div>
      ${np || fp ? "" : `<div class="seg" role="tablist"><button class="segb ${up ? "" : "on"}" data-am="signin" role="tab" aria-selected="${!up}">Sign in</button><button class="segb ${up ? "on" : ""}" data-am="signup" role="tab" aria-selected="${up}">Create account</button></div>`}
      <form id="authform" class="cform" novalidate>
        ${up ? `<label>Your name<span class="field"><input id="a-name" autocomplete="name" placeholder="Shown on programs you share" required></span></label>` : ""}
        ${np ? "" : `<label>Email<span class="field"><input id="a-email" type="email" autocomplete="email" inputmode="email" required></span></label>`}
        ${fp ? "" : `<label>${np ? "New password" : "Password"}<span class="field"><input id="a-pass" type="password" autocomplete="${up || np ? "new-password" : "current-password"}" minlength="8" required></span></label>`}
        <p class="autherr" id="a-err" role="alert"></p>
        <button class="btn primary bigsave" type="submit" id="a-go">${np ? "Save password" : fp ? "Email me a reset link" : up ? "Create account" : "Sign in"}</button>
      </form>
      ${up || np ? "" : `<button class="linkbtn" id="a-forgot" type="button">${fp ? "Back to sign in" : "Forgot password?"}</button>`}
      <p class="savenote">Your workouts are saved to your account, so they're on any phone you sign in on.</p>
    </div>`;
    el.querySelectorAll("[data-am]").forEach((b) => (b.onclick = () => showAuth(b.dataset.am)));
    const f = el.querySelector("#a-forgot"); if (f) f.onclick = () => showAuth(fp ? "signin" : "forgot");
    const msg = (t, ok) => { const e = el.querySelector("#a-err"); e.textContent = t; e.classList.toggle("ok", !!ok); };
    el.querySelector("#authform").onsubmit = async (ev) => {
      ev.preventDefault(); const go = el.querySelector("#a-go"); go.disabled = true; msg("");
      const v = (id) => { const i = el.querySelector(id); return i ? i.value.trim() : ""; };
      const email = v("#a-email"), pass = el.querySelector("#a-pass") ? el.querySelector("#a-pass").value : "", name = v("#a-name");
      try {
        if (fp) {
          if (!email) throw new Error("Enter your email.");
          const { error } = await sb.auth.resetPasswordForEmail(email, { redirectTo: location.origin + location.pathname });
          if (error) throw error; msg("Check your email for a reset link.", true);
        } else if (np) {
          if (pass.length < 8) throw new Error("Use at least 8 characters.");
          const { error } = await sb.auth.updateUser({ password: pass }); if (error) throw error;
          const { data } = await sb.auth.getSession(); if (data.session) signedIn(data.session.user);
        } else if (up) {
          if (!name) throw new Error("Add your name.");
          if (!email) throw new Error("Enter your email.");
          if (pass.length < 8) throw new Error("Use at least 8 characters for your password.");
          const { data, error } = await sb.auth.signUp({ email, password: pass, options: { data: { name }, emailRedirectTo: location.origin + location.pathname } });
          if (error) throw error;
          if (!data.session) msg("Almost done: tap the link we emailed you, then sign in.", true);
        } else {
          const { error } = await sb.auth.signInWithPassword({ email, password: pass });
          if (error) throw error;
        }
      } catch (e) {
        const t = String((e && e.message) || e);
        msg(/Invalid login/i.test(t) ? "That email and password don't match." : /already registered/i.test(t) ? "That email already has an account. Sign in instead." : /not confirmed/i.test(t) ? "Confirm your email first: tap the link we sent you." : t);
      } finally { go.disabled = false; }
    };
    const first = el.querySelector("input"); if (first) first.focus({ preventScroll: true });
  }
  function showNotice() {
    const el = authEl(); el.hidden = false;
    el.innerHTML = `<div class="authcard"><div class="authbrand"><div class="plate" aria-hidden="true"><span></span></div><div><div class="eyebrow">LiftLog</div><h1 id="auth-title">Not connected yet</h1></div></div>
      <p>This copy isn't linked to a database yet, so anything you log stays on this device only.</p>
      <button class="btn primary bigsave" id="a-local">Use it on this device</button></div>`;
    el.querySelector("#a-local").onclick = hideAuth;
  }
})();
