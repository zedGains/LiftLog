# LiftLog

Workout log for lifters and their gym partners, with shareable trainer programs.
A plain static web app (no build step) backed by Supabase for sign-in, storage and live updates.
Installable on a phone's home screen.

**Live:** https://liftlog-snowy-pi.vercel.app

## Files
| File | What it is |
|---|---|
| `index.html` | The app |
| `shim.js` | Connects the app to Supabase (sign-in screen, data storage, live updates) |
| `config.js` | Supabase project URL + publishable key (public by design) |
| `supabase/schema.sql` | Database tables and access rules — run once in Supabase |
| `manifest.webmanifest`, `sw.js`, `icons/` | Home-screen install |
| `privacy.html`, `terms.html` | Privacy Policy and Terms of Use |
| `.github/workflows/backup.yml` | Nightly database backup (needs repo secrets, see below) |
| `vendor/supabase.js` | Supabase client library (supabase-js 2.117.2, bundled) |

## Setup
1. **Database:** Supabase → SQL Editor → paste `supabase/schema.sql` → Run.
2. **Sign-in settings:** Supabase → Authentication → URL Configuration → set **Site URL** to the app's address
   (e.g. `https://liftlog.vercel.app`) and add the same under **Redirect URLs**.
3. **Hosting:** Vercel → Add New → Project → import this repo → Framework preset **Other**, no build command → Deploy.
   Every push to `main` redeploys automatically.
4. **Admin (optional):** to moderate the community, after creating your account run in SQL Editor:
   `insert into public.admins (user_id) select id from auth.users where email = 'you@example.com';`

## Data model
One table, `public.docs`: `path` (e.g. `data/users/<uid>/_plan`), `col` (the collection part), `owner`, `data` (jsonb).
- `data/users/<uid>/*` — private to that person (plan, logs)
- `programs/<uid>` — programs that person published; readable by every signed-in user
- `social/<uid>` — that person's likes / "using" marks; readable by every signed-in user

Row-level security in `schema.sql` enforces who can read and write what.

## Plans a new person can start from
- **Starter** — generic Push / Pull / Legs built from the exercise library (in `index.html`, `STARTER_SPEC`)
- **Build my own** — no days; add them with + Add day
- **Private** — a program stored in that person's own data as `data/users/<uid>/_template`
  (used for a program a trainer wrote for one client; never shipped in the app code)

## Backups
`.github/workflows/backup.yml` runs nightly and saves `docs` and `profiles` as a downloadable
Actions artifact (kept 30 days). Add repo secrets `SUPABASE_URL` and `SUPABASE_SECRET_KEY`
(Settings → Secrets and variables → Actions). The secret key is never used by the app itself.

## Email
Sign-up confirmation is off while testing. Before a public launch: set up a custom SMTP sender
(Supabase → Authentication → Emails → SMTP) with your own domain, then turn **Confirm email** back on.
