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

Any static host. Every path in the site is relative, so it works at a domain root or under a
subpath without changes.

**Fastest, no account** — zip the *contents* of this directory (so `index.html` is at the top
level of the archive, not inside a folder) and drop it on
[app.netlify.com/drop](https://app.netlify.com/drop). Live URL in about thirty seconds.

**Netlify / Cloudflare Pages / Vercel** — point the project at this repository, set the publish
directory to `loudoun-datacenter-registry`, and leave the build command empty.

**GitHub Pages** — note that Pages only publishes from a repository root or from `/docs`; it
**cannot** serve an arbitrary subdirectory, so pointing it at `loudoun-datacenter-registry`
will not work. Two routes that do:

- *Actions* (keeps the source where it is). Set Settings → Pages → Source to "GitHub Actions"
  and add a workflow that runs `actions/upload-pages-artifact` with
  `path: loudoun-datacenter-registry`, then `actions/deploy-pages`.
- *A dedicated branch*. Push a branch whose root is this directory's contents, then
  Settings → Pages → Deploy from a branch → that branch → `/ (root)`.

Add an empty `.nojekyll` file if you use Pages, so it doesn't try to run the site through
Jekyll.

If you have connected Supabase, set its **Site URL** and redirect allow-list to the deployed
origin, or moderator sign-in will fail. Without Supabase the deployed site runs in demo mode:
it is fully browsable, but submitted reports stay in the visitor's own browser.

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

## Refreshing the news feed

```bash
python3 scripts/refresh-news.py
```

Writes `data/news.json` (the archive) and `data/news-home.json` (six headlines for the home
page, so a visitor reading five lines doesn't download a couple of hundred kilobytes).

This runs as a script rather than in the browser for one reason: **not one of these feeds sends
CORS headers.** Google News, Virginia Mercury, Cardinal News, WTOP — none of them. A `fetch()`
from the site's own JavaScript fails on every one, and the restriction is on the far end, so
there is no request shape that works. If you deploy with a backend, the same parser belongs in a
scheduled Supabase Edge Function; Appendix F of `LOVABLE-BUILD-PROMPT.md` has it in TypeScript.

Only the headline, publication, date and link are stored. No article text and no AI summary —
nobody here has read these articles, and a link is what the reporting deserves anyway.

Run it hourly, daily, or whenever. A run takes a few seconds and one dead feed does not fail it.

---

## How it fits together

```
index.html      map, headline counts, concern cards, recent reports
report.html     the submission form
reports.html    browsable list + map, sharable via ?locality=&category=&q=
report-detail.html  one report in full, at ?id= — the shareable permalink
watchlist.html  clusters meeting the threshold; ?id= for one cluster
news.html       local coverage, from data/news.json
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
js/map.js           Leaflet layers, clustering, popups, legend, marker motion
js/map-layers.js    basemaps (incl. satellite) and the parcel/district/heat overlays
js/map-tools.js     measure, radius rings, locate, fullscreen, address search
js/report-detail.js the full report record — sheet, permalink page, lightbox
js/watchlist.js     the cluster rule, the /watchlist page and the site-wide ticker
js/news.js          renders data/news.json
js/motion.js        scroll reveal, count-up, parallax, reduced-motion guard
js/hero-map.js      the animated county figure on the home page
js/ui.js            report cards, filters, icons, URL state
js/layout.js        injects the shared header and footer

css/fonts.css       @font-face for the two vendored families
css/tokens.css      every colour, size and duration
css/base.css        editorial typography, masthead, layout primitives
css/components.css  buttons, cards, map, forms, charts
css/animations.css  keyframes + the reduced-motion master switch
```

## Design

A single bright theme — white ground, near-black text, hairline rules instead of cards on a
grey field. There is deliberately **no dark mode**: a front page is printed on paper, and one
theme means one set of contrast decisions to get right rather than two.

Typography is a newspaper system: **Source Serif 4** for headlines and body, **Libre Franklin**
(an open Franklin Gothic) for kickers, labels and UI. Both are vendored as variable woff2 —
130 KB for the pair, no external requests. The New York Times' own faces (Cheltenham, Imperial,
Franklin) are proprietary and are *not* used here; this is the same typographic system, not the
same identity, and the site carries no borrowed masthead or branding.

The county silhouette in the header, the hero figure and the section watermark are all
generated from the county's own district boundaries:

```bash
python3 scripts/build-county-svg.py
```

It derives a true county outline by keeping the boundary edges that appear in exactly one
district and chaining them into a single ring — drawing all eight district shapes stacked
instead leaves hairline gaps along the shared seams. Outputs `data/county.json` (district paths
plus the projection constants, so the hero can place facility points in the same coordinate
space) and `assets/loudoun-mark.svg` (a 900-byte silhouette for the logo and favicon).

## Motion

Animation carries meaning or it doesn't ship:

- **The hero** draws the county outline, washes in the districts, then lands all 224 facility
  dots ordered **east to west** — so the viewer watches Data Center Alley fill up while the
  rural west stays empty. That ordering is the point; a static dot map doesn't say it.
- **Map markers** cascade in on first paint only (capped at 120, beyond which the tail is
  imperceptible and the map just feels slow to settle).
- **Community report pins** carry a slow pulsing ring — they are the live, human part of the
  data.
- **Filtering to one district** flies the camera there, because otherwise you have to hunt for
  the handful of remaining pins.
- **Hovering a report card** bounces its pin, so the list and the map read as one view.
- **Charts** grow from zero when scrolled into view; **stat tiles** count up.

Two rules keep this safe. Every effect animates *from* an offset *to* the real resting state,
so nothing is hidden waiting for a script — the `.reveal` class is applied by `motion.js`, never
in the HTML, so a visitor without JavaScript gets a complete static page. And
`prefers-reduced-motion` collapses all of it: `animations.css` uses `animation: none` rather
than a near-zero duration, because several effects use `both` fill mode and would otherwise
flash their from-state.

**The report form is deliberately calm.** Someone filling it in is describing losing sleep or
watching a house sale fall through; flourish there would read as tone-deaf. Motion on that page
is limited to focus states and the map picker.

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
- All motion respects `prefers-reduced-motion`; the page is complete and correct without it.
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
