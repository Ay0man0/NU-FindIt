# NU FindIt — Progressive Web App starter

A mobile-first campus lost-and-found PWA based on the supplied NU FindIt clickable HTML prototype.

## What's included

- Installable PWA shell (manifest, service worker, app icons, offline shell cache)
- Responsive mobile UI with Home, Search, Report, Chats, and Profile
- Lost/found reports with category, campus location, description, and optional photo
- Sensitive ID-card handling: public listing is anonymized and ID photos are not uploaded
- Ownership request workflow; a private chat is shown only after approval
- Demo mode with browser-local persistence
- Optional Supabase integration for authentication, database, storage, and RLS-protected chat
- SQL schema and row-level security policies in `supabase/schema.sql`

## Sign-up & identity verification (new)

The very first screen is now a sign-up / sign-in gate. Nobody can see or post anything until they verify.

**Sign up** asks for full name, university email and NU ID. A one-time code is then sent to that email, and the account is only created once the code is entered.

**How "is this a real NU member?" is enforced**

1. **Email ownership**: the one-time code proves the person controls the inbox.
2. **Official records match** (Supabase mode): `supabase/schema.sql` adds a `nu_directory` table (NU ID + email). A database trigger refuses to create any account whose NU ID and email don't match a row there. This runs on the server, so it can't be bypassed by editing the front end.
3. **One ID = one account**: `student_identities.nu_id` is unique.
4. **Privacy**: NU IDs are stored in a private table (own-row read only) and are never shown to other users. The profile page shows only a masked ID.

**Setup checklist for real verification**

- Get an export of valid NU members (NU ID, email, name) from the registrar / NU IT and import it into `nu_directory` (Supabase → Table Editor → Import CSV). **Until this table has rows, nobody can sign up.** For testing, insert your own row.
- In `config.js`, set `campusEmailDomain` and change `nuIdPattern` to the real NU ID format.
- In Supabase → Authentication → Email Templates, edit the **Magic Link** (and **Confirm signup**) template so it includes `{{ .Token }}` (the 6-digit code), e.g. `Your NU FindIt code: {{ .Token }}`.
- Authentication → Rate Limits: keep email OTP limits on.

**Demo mode** (no Supabase): the same screens work, but verification is simulated on this device. The code is shown on screen and nothing is sent or checked against any records. Do not treat demo mode as verification.

## Run locally

A PWA requires HTTPS or localhost. From this directory run:

```bash
python -m http.server 8000
```

Then open http://localhost:8000. You can install it from a supported browser. Demo mode works without a backend and stores its data in this browser's local storage.

## Connect Supabase

1. Create a Supabase project.
2. In the Supabase SQL Editor, run `supabase/schema.sql`.
3. In Authentication → URL Configuration, add your local/deployed app URL to the allowed redirect URLs.
4. In Authentication → Providers, enable Email OTP/magic links.
5. Copy the Project URL and anon/public key into `config.js`:

```js
window.NU_FINDIT_CONFIG = {
  supabaseUrl: 'https://YOUR-PROJECT.supabase.co',
  supabaseAnonKey: 'YOUR_SUPABASE_ANON_KEY',
  campusEmailDomain: ''
};
```

6. Replace `campusEmailDomain` only after Nile University confirms its official student/staff email domain.
7. Deploy the folder to an HTTPS static host (e.g. Netlify, Vercel, or Cloudflare Pages).

**Never put a Supabase `service_role` key in browser code.** The anon key is designed for client use when RLS is enabled.

## Important prototype boundaries

- The current suggested-match panel is deliberately conservative: it identifies a possible category-level candidate only. It is not AI image recognition and does not claim an ownership match.
- Email OTP is the current authentication option. Restricting access to verified Nile University accounts requires the official email domain and, ideally, coordination with NU IT/SSO.
- The SQL policies are a starter baseline and should be reviewed with NU IT/security before real student data is used.
- Do not upload ID-card photos, student ID numbers, faces, phone numbers, or other personal data. ID-card reports are anonymized in the interface and photo upload is suppressed for that category.
- Push notifications, production AI/OCR, moderation, abuse reporting, admin review, and university SSO are not implemented yet.

## Project structure

- `index.html` — app shell
- `styles.css` — responsive UI
- `app.js` — app logic and optional Supabase client
- `config.js` — public Supabase project configuration
- `manifest.webmanifest` — install metadata
- `sw.js` — offline app shell cache
- `supabase/schema.sql` — database schema and RLS
- `assets/` — generated app icon assets

## Test the ownership handover in demo mode

1. Open the app and use the account button to select **Demo Student A (owner)**.
2. Create a **Found** report with a memorable ownership-check question.
3. Use the account button to switch to **Demo Student B (claimant)**.
4. Open the report and submit an ownership request with a distinguishing detail.
5. Switch back to **Demo Student A**, open Notifications, and approve the request.
6. Switch to **Demo Student B** and open Chats. A private thread is now available.

Demo data stays in the current browser's local storage. Use the same browser to switch between test identities.
