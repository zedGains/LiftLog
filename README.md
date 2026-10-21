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
