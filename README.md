# TheGrint World Cup Pool 2026 — Deploy Guide

Estimated time: **30–45 minutes** for a developer. No backend code to write.
Stack: **Supabase** (database + auth + realtime) · **Vercel** (hosting, free)

---

## Prerequisites

- A [Supabase](https://supabase.com) account (free)
- A [Vercel](https://vercel.com) account (free)
- [Git](https://git-scm.com) installed locally
- [Vercel CLI](https://vercel.com/docs/cli): `npm i -g vercel`

---

## Step 1 — Create Supabase Project

1. Go to https://app.supabase.com → **New project**
2. Name it `thegrint-pool`, choose a strong DB password, pick a region close to your users
3. Wait ~2 minutes for the project to spin up
4. Go to **Settings → API** and copy:
   - **Project URL** → looks like `https://abcdefgh.supabase.co`
   - **anon / public key** → long JWT string

---

## Step 2 — Run the Database Schema

1. In Supabase, go to **SQL Editor → New query**
2. Open `supabase/schema.sql` from this folder
3. Paste the entire contents and click **Run**
4. You should see: *"Success. No rows returned."*

This creates all tables, RLS policies, the leaderboard view, the scoring function,
and seeds all 48 group stage matches.

---

## Step 3 — Enable Realtime

1. In Supabase, go to **Database → Replication**
2. Under **Tables**, enable realtime for:
   - `matches`
   - `picks`
   - `bonus_picks`

This lets the standings and match scores update live for all users simultaneously.

---

## Step 4 — Configure Authentication

1. In Supabase, go to **Authentication → Providers**
2. **Email** provider is on by default — leave it enabled
3. Go to **Authentication → Email Templates** and customize the confirmation
   email with TheGrint branding if desired
4. Go to **Authentication → URL Configuration** and set:
   - **Site URL**: `https://pool.thegrint.com` (or your Vercel URL, add after Step 6)
   - **Redirect URLs**: same URL

---

## Step 5 — Add Your Supabase Credentials to index.html

Open `index.html` and find this block near the top of the `<script>` tag:

```js
const SUPABASE_URL = 'https://YOUR_PROJECT_REF.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR_ANON_KEY';
```

Replace both values with what you copied in Step 1.

---

## Step 6 — Deploy to Vercel

### Option A: Vercel CLI (fastest)
```bash
cd thegrint-pool
vercel
# Follow prompts: link to your account, deploy
# After deploy, copy the .vercel.app URL
```

### Option B: GitHub + Vercel (recommended for ongoing use)
```bash
cd thegrint-pool
git init
git add .
git commit -m "TheGrint Pool 2026 — initial deploy"
# Create a new GitHub repo at github.com/new, then:
git remote add origin https://github.com/YOUR_ORG/thegrint-pool.git
git push -u origin main
```
Then in Vercel:
1. **New Project → Import Git Repository**
2. Select your repo
3. Framework preset: **Other**
4. Click **Deploy**

Every `git push` to `main` will auto-redeploy — useful when you add knockout matches.

---

## Step 7 — Set Your Custom Domain (optional)

In Vercel → your project → **Settings → Domains**:
- Add `pool.thegrint.com` (or any subdomain)
- Add the DNS record Vercel shows you in your DNS provider
- SSL is automatic

Then update the Supabase **Site URL** (Step 4) to match.

---

## Step 8 — Make Yourself an Admin

After signing up through the app:

1. In Supabase → **Table Editor → profiles**
2. Find your row, click **Edit**
3. Set `is_admin` to `true` → **Save**

The **Admin** tab will now appear in the nav when you're signed in.

---

## Step 9 — Invite Your Team

Share the URL with your colleagues. They:
1. Click **Join Pool**
2. Enter name, email, password
3. Confirm email
4. Sign in and start submitting picks

---

## Day-to-Day Admin Tasks

### Updating a match score
1. Go to **Admin → Update match score**
2. Select the match, enter the final score
3. Click **Save & Calculate** — points are recalculated automatically for all participants

### Adding Knockout matches
As teams advance, add R16/QF/SF/Final matches via Supabase SQL Editor:
```sql
insert into public.matches (match_group, stage, team_a, flag_a, team_b, flag_b, kickoff_at)
values ('Round of 16', 'r16', 'Brazil', '🇧🇷', 'France', '🇫🇷', '2026-07-04 20:00:00+00');
```
They will appear in the app immediately.

### Awarding bonus points
Update the `bonus_picks.points` column manually via Table Editor,
or run SQL:
```sql
update public.bonus_picks set points = 30
where category = 'champion' and value = 'Brazil';
```

---

## Troubleshooting

| Issue | Fix |
|---|---|
| "Invalid API key" on load | Double-check SUPABASE_URL and SUPABASE_ANON_KEY in index.html |
| Picks not saving | Check RLS policies ran correctly in Step 2; check kickoff time hasn't passed |
| Scores not recalculating | Make sure `calculate_picks_for_match` function was created (check SQL Editor → Functions) |
| Realtime not updating | Confirm replication is enabled for `matches` and `picks` tables |
| Can't see Admin tab | Set `is_admin = true` in profiles table for your user |

---

## Architecture Overview

```
Browser (index.html)
  │
  ├── Auth: Supabase email/password
  ├── Data: Supabase REST API (matches, picks, leaderboard view)
  ├── Writes: Supabase upsert with RLS (users can only write their own picks)
  ├── Live updates: Supabase Realtime websocket subscriptions
  └── Points: Supabase server-side function (calculate_picks_for_match)

Hosting: Vercel (static, global CDN)
```

No server to maintain. Supabase free tier supports up to **50,000 monthly active users**
and **500 MB database** — more than enough for a company pool.

---

## File Reference

```
thegrint-pool/
├── index.html          ← Full app (auth + UI + Supabase client)
├── vercel.json         ← Vercel deploy config
├── supabase/
│   └── schema.sql      ← Full DB schema + seed data (run once in Supabase)
└── README.md           ← This file
```

Questions? Hand this folder to your developer — everything needed is here.
