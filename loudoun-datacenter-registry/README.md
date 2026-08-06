# Loudoun Data Center Watch

A community self-reporting map for data center impacts in Loudoun County, Virginia.

Loudoun holds the largest concentration of data centers on earth, and the county publishes
excellent open data about where every one of them is. What nobody publishes is the other
half — residents describing generator noise, diesel fumes, well pressure, night lighting and
stalled house sales, three minutes at a time at Board meetings. This site puts the county's
facility data and residents' accounts on the same map, and turns the accounts into figures
a supervisor or reporter can cite.

Modelled on [brockovichdatacenter.com](https://www.brockovichdatacenter.com/), scoped to one
county. **Not affiliated with Loudoun County government, Erin Brockovich, or any data center
operator.**

> **Note on this repository.** This project is unrelated to RoofWise, the SwiftUI iOS app in
> `ios/`. It is entirely self-contained in this directory and shares no code, tooling or
> dependencies with it. `CONTRIBUTING.md` at the repository root describes the RoofWise
> workflow and does not apply here.

---

## Running it

No build step, no npm, no framework. Serve the directory over HTTP:

```bash
cd loudoun-datacenter-registry
python3 -m http.server 8000
# → http://localhost:8000
```

It has to be HTTP, not `file://` — the pages `fetch()` the GeoJSON layers, and browsers block
that on `file://`.

Out of the box it runs in **demo mode**: a yellow banner appears, the reports shown are
illustrative samples rather than real submissions, and anything you submit is saved to your own
browser's local storage. Everything is functional in this state, including the moderation
queue, so you can evaluate the whole workflow before setting up a database.

---

## Connecting Supabase

Roughly five minutes.

1. Create a free project at [supabase.com](https://supabase.com/).
2. In the SQL editor, run the four files in `sql/` **in order**:
   - `01_schema.sql` — table, constraints, coordinate-jitter trigger, public view
   - `02_rls.sql` — row-level security policies and grants
   - `03_storage.sql` — private photo bucket and its policies
   - `04_admin.sql` — mostly instructions; read it, don't just run it
3. Copy your project URL and **anon** key from Settings → API into `js/config.js`:

   ```js
   SUPABASE_URL: "https://xxxxxxxx.supabase.co",
   SUPABASE_ANON_KEY: "eyJhbGciOi...",
   ```

4. Create a moderator account and grant it the `admin` role — `sql/04_admin.sql` step 2.
5. Turn **off** public sign-ups (Authentication → Providers → Email). The site never needs
   visitors to have accounts.
6. Set `CONTACT_EMAIL` in `js/config.js`. Until you do, the privacy, terms and about pages
   say plainly that no contact route is configured rather than showing a dead address.

Reload. The demo banner disappears and `LDCW.Store.mode` reads `"supabase"`.

### Is committing the anon key safe?

Yes — that is what it is for. It identifies the project, not a user, and it is designed to be
public in a browser. The protection comes from the RLS policies in `sql/02_rls.sql`, which
permit the anon role to do exactly two things: insert a report as `pending`, and read the
`public_reports` view. It cannot read the base table, so contact details and exact coordinates
are unreachable to it.

**Never** put the `service_role` key in `js/config.js` or anywhere else the browser can see.

---

## Deploying

Any static host. The site uses only relative paths, so it works from a subdirectory.

**GitHub Pages** — Settings → Pages → deploy from a branch, then point it at
`/loudoun-datacenter-registry`. Or copy this directory to a repository root and deploy that.

**Netlify / Cloudflare Pages / Vercel** — set the publish directory to
`loudoun-datacenter-registry` and leave the build command empty.

Set your Supabase project's **Site URL** and redirect allow-list to the deployed origin, or
moderator sign-in will fail.

---

## Refreshing the facility data

Every data center on the map comes from Loudoun County GIS. The county updates the parcel
layers roughly every six months:

```bash
python3 scripts/refresh-facilities.py
```

Python 3.9+, standard library only, no dependencies. It rewrites everything in `data/`.
Review the diff before committing — a large unexpected change usually means the county renamed
a field, not that fifty data centers appeared overnight. `data/PROVENANCE.md` records the
exact source URLs and every transformation applied.

Current snapshot: **224 parcels** — 103 operational, 36 under construction, 85 in the approval
pipeline — plus 271 building footprints and 8 election districts.

---

## How it fits together

```
index.html      map, headline counts, concern cards, recent reports
report.html     the submission form
reports.html    browsable list + map, sharable via ?locality=&category=&q=
stats.html      dashboard + CSV export
resources.html  how to file with the county, FAQ
about.html      what this is and isn't, full data provenance
privacy.html    what is collected, published, and never published
terms.html      submission licensing, moderation standards, disclaimers
admin.html      moderation queue (noindex; requires the admin role)

js/config.js        the only file you edit to deploy
js/schema.js        categories, statuses, validation, filter predicate, formatting
js/store.js         picks a backend, loads facility data, computes statistics
js/local-store.js   demo backend (localStorage) + sample reports
js/supabase-store.js live backend; loads vendor/supabase.js on demand
js/map.js           Leaflet layers, clustering, popups, legend
js/ui.js            report cards, filters, icons, URL state
js/layout.js        injects the shared header and footer
```

Everything that touches data goes through `js/store.js`, so the two backends are
interchangeable and no page knows which is active. There is no build step anywhere; shared
chrome is injected at runtime rather than duplicated across ten HTML files.

Leaflet, Leaflet.markercluster and supabase-js are **vendored** into `vendor/`. The site keeps
working if a CDN doesn't, and there is no third-party script to audit.

---

## Privacy model

This is the part that matters most, because the site asks people to describe things happening
at their homes.

| Information | Stored | Published |
|---|---|---|
| Name, email, phone | if provided (optional) | **never** |
| Street address | if provided (optional) | **never** |
| Exact coordinates | yes | **never** |
| Offset coordinates (100–200 m) | yes | yes — this is what the map plots |
| District, ZIP, categories, severity, description, photos | yes | after review |

Three mechanisms enforce this rather than one:

- The **`public_reports` view** simply does not select the private columns, and aliases
  `lat_public`/`lng_public` to `lat`/`lng` so no raw coordinate can escape by accident.
- **RLS grants anon no `SELECT` on the base table at all**, so the private columns are
  unreachable even if the view were changed.
- A **`BEFORE INSERT` trigger** derives the offset server-side and forces `status = 'pending'`,
  so a crafted request cannot supply its own coordinates or self-publish.

Photos are re-encoded through a `<canvas>` in the browser before upload, which discards EXIF —
including the GPS tags phones write, which would otherwise defeat the coordinate offset
entirely. If the browser can't decode an image (usually HEIC outside Safari) the upload is
refused rather than passed through unprocessed.

The demo backend mirrors all of this, so what you see locally is what happens in production.

---

## Anti-abuse

An anonymous-insert table behind a public key is spam bait. The defences, weakest to strongest:

1. **Honeypot** — an off-screen field; anything that fills it gets a fake success page.
2. **Time-to-submit** — submissions faster than 5 seconds are refused.
3. **Client rate limit** — one per minute, five per day, per browser.
4. **Database constraints** — length limits, a category allow-list, and a Loudoun bounding-box
   check on the coordinates.
5. **Moderation by default** — nothing is public until a person approves it.

Only the last two are real. A determined attacker with the anon key can still fill the
moderation queue; what they cannot do is publish anything or read anyone's details. If queue
spam ever becomes a genuine problem, the fix is an Edge Function with a CAPTCHA in front of
the insert — a contained change, because every write already goes through
`Store.submitReport`.

---

## Accessibility

- Every map is accompanied by the same records as text; the map is never the only route.
- Marker types differ by **shape as well as colour**, and the legend states both.
- Charts are CSS bars inside real `<table>` markup, so screen readers get the numbers.
- Full keyboard operation, visible focus rings, a skip link, and errors tied to inputs by
  `aria-describedby` with focus moved to the first invalid field.
- Light and dark themes, honouring `prefers-color-scheme` with a manual override.
- Mobile-first: 44 px touch targets, single-column forms, no horizontal scroll at 320 px.

---

## Verifying a deployment

With the site served locally:

- [ ] `/` — 224 facility markers, four working layer toggles, counts matching `data/summary.json`
- [ ] Filters narrow the map and the list identically; Reset restores both
- [ ] `/report.html` — location settable three ways; district auto-fills from the pin
- [ ] Submitting with fields missing highlights them and moves focus to the first one
- [ ] Filling the honeypot silently discards; submitting inside 5 s is refused
- [ ] Attaching a 6th photo, or an 11 MB file, is refused with a clear message
- [ ] A submitted report lands as `pending` and does **not** appear on the public map
- [ ] Approving it in `/admin.html` makes it appear
- [ ] `/stats.html` figures match a hand count; the CSV downloads and opens

With Supabase connected, additionally:

- [ ] `LDCW.Store.mode === "supabase"` and the demo banner is gone
- [ ] An anonymous `select * from reports` returns **zero rows** (this is the important one)
- [ ] `public_reports` contains no `reporter_*`, no `address`, and no raw `lat`/`lng`
- [ ] Plotted coordinates differ from submitted ones by roughly 100–200 m
- [ ] A signed-out visitor to `/admin.html` gets the sign-in form, not a blank page
- [ ] A signed-in non-admin is told they lack the role, and is signed back out

---

## Licence and attribution

Facility and district data © Loudoun County GIS, used under the county's open data terms.
Basemap © [OpenStreetMap](https://www.openstreetmap.org/copyright) contributors under the Open
Database License. Vendored libraries keep their own licences —
[Leaflet](https://leafletjs.com/) (BSD-2-Clause), Leaflet.markercluster (MIT),
[supabase-js](https://supabase.com/) (MIT).

Community reports are unverified first-hand accounts from residents. They are not findings of
fact, and they do not establish that any named company caused any condition described. Owner
names shown on facility pins come from public county land records and are frequently holding
companies rather than the businesses operating the buildings.
