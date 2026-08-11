# Building Loudoun Data Center Watch in Lovable

A complete handoff for rebuilding this site inside an AI website builder — the community
reporting map in Part One, and the watchdog hub built on top of it in Part Two.

Written for **Lovable** (React + Vite + Tailwind + shadcn/ui + its native Supabase
integration). Appendix C covers what changes for v0, Bolt or Replit.

Every external data source named in this document was fetched while writing it, and the SQL was
run against PostgreSQL 16 before it was written down. Appendix G records what came back from
each source, including which ones a browser cannot reach.

---

## How to use this file

**Do not paste the whole thing.** Lovable produces much better results from a sequence of
focused prompts than from one wall of text — it builds, you look, you correct, then you move on.

The document is in two parts.

**Part One (Prompts 1–9) is the site.** The map, the report form, the moderation pipeline, the
statistics. It is a pure browser app plus Supabase, and at the end of it you have something
worth publishing. Work through it in order and check each prompt did what you asked before
continuing.

**Part Two (Prompts 10–18) is the watchdog hub.** Satellite mapping, full report records, a
watchlist ticker, an automated local news feed, a facts-and-myths library, profiles of every
elected official who votes on these applications, an AI letter writer, and the county meetings
calendar. Part Two adds a small server — four Supabase Edge Functions — for reasons explained at
the top of it. Build Part One first; every prompt in Part Two assumes it exists.

Appendices are things you paste when a prompt tells you to. A and B belong to Part One, E and F
to Part Two. **Appendix G lists every data source with its verified CORS status** and is the one
to check first when a fetch fails. **Appendix H is the build order** if you cannot build
everything.

Rough timing: Prompts 1–4 get you a working map, which is about an hour. Part One including
Supabase is half a day. Part Two is as long as you want it to be — Appendix H orders it so that
stopping anywhere still leaves you with a coherent site.

### The one thing that matters most

Loudoun County publishes its data center locations as open GIS services, and I have verified
those services send permissive CORS headers — so a browser app on a `lovable.app` domain can
fetch them directly. **Prompt 2 makes the app pull the real 224 parcels.**

If you skip Prompt 2 and just ask for "a map of data centers in Loudoun County", the builder
will invent plausible-looking facilities at made-up coordinates. A civic site built on
fabricated locations is worse than no site at all — it discredits the real reports on it. Do
not let it guess.

---

## Prompt 1 — Project brief and design system

> I'm building **Loudoun Data Center Watch**, a community self-reporting site for Loudoun
> County, Virginia. Residents log how nearby data centers affect them — noise, air quality,
> water, power, property values — and those reports appear on a map alongside the county's own
> data on where every data center is.
>
> Loudoun has the largest concentration of data centers on earth. The county publishes
> excellent open data on the facilities. Nobody publishes the human half, so residents'
> accounts are scattered across board meetings and neighbourhood groups. This site puts both on
> one screen so the pattern is visible and citable.
>
> **Stack:** React + Vite + Tailwind + shadcn/ui. React Router for pages. `react-leaflet` for
> the map with OpenStreetMap tiles (no API key). Supabase for storage — I'll set that up later,
> so for now use a data adapter with a localStorage implementation behind it.
>
> **Non-negotiables. Build these in from the start, don't retrofit them:**
>
> 1. This site is **not affiliated** with Loudoun County government, with Erin Brockovich or
>    her data center project, or with any data center owner or operator. Every page footer must
>    say so.
> 2. Community reports are **unverified first-hand accounts, not findings of fact**. They never
>    establish that a named company caused anything.
> 3. A reporter's **name, email, phone and street address are never published** — not on the
>    site, not in any export.
> 4. Report pins on the map are plotted at a **random 100–200 m offset** from the address given,
>    so a pin can never identify a household.
> 5. Nothing appears publicly until a **moderator approves it**.
>
> **Design — a newspaper front page, not a dashboard.** One bright theme, no dark mode.
>
> Colours:
> - Page background `#ffffff`; a warm off-white `#f7f7f4` for alternating section bands
> - Text `#121212`; muted `#5a5a55`; subtle `#6b6b64`
> - Hairline rules `#dcdcd5`; heavy rules are 3px solid `#121212`
> - Accent / links `#1c4f8f`
> - Status colours, which carry meaning on the map: operational `#1a56b0`, under construction
>   `#8a5000`, proposed `#6b28c9`, community report `#b3231b`
>
> Type — load from Google Fonts:
> - **Source Serif 4** for headlines and body copy
> - **Libre Franklin** for kickers, labels, nav, buttons and data
> - Headline sizes are fluid: `clamp(2.75rem, 1.5rem + 5.5vw, 5rem)` for the hero, tight
>   letter-spacing (`-0.032em`), line-height `0.98`
> - Body 17px, line-height 1.55
>
> Layout rules:
> - Separate sections with **hairline rules and whitespace**, not cards on a grey field. Almost
>   nothing has a shadow. Border radius is 2–4px at most.
> - Every section gets a **kicker**: a small uppercase Libre Franklin label with wide letter
>   spacing (`0.09em`) and a hairline rule trailing off to the right.
> - Mobile-first. 44px minimum touch targets. No horizontal scroll at 320px.
>
> Accessibility is a requirement, not a nice-to-have: WCAG AA contrast throughout, full keyboard
> operation, visible focus rings, and every map accompanied by the same data as text.
>
> Start with the design system, the shared header (nav: Map, Reports, Statistics, Resources,
> About, plus a "Report an issue" button) and the footer with the disclaimer. Build the page
> shells as empty routes for now.

---

## Prompt 2 — The county data layer

**This is the important one.** Paste it exactly; the URLs and field names are precise.

> Now the facility data. It comes from Loudoun County's public ArcGIS services — do **not**
> invent, estimate or hardcode any facility. I have verified these endpoints allow
> cross-origin browser requests.
>
> Create `src/lib/countyData.ts` that fetches and normalizes three layers.
>
> **Layer 1 — existing parcels (139 features):**
> ```
> https://services1.arcgis.com/MxjRokvPm7bjslyR/arcgis/rest/services/Existing_Data_Center_Parcel/FeatureServer/1/query?where=1%3D1&outFields=*&outSR=4326&f=geojson
> ```
> Fields to keep: `Project` (name), `Owner`, `Built_Status`, `Overall_SQ_FT`,
> `ELECTION_DISTRICT`, `PA_GIS_ACRE`, `ZONING`, `Zoning_Case_Number`, `PA_MCPI` (parcel id),
> `POLICY_AREA`.
>
> **Layer 2 — pipeline / proposed parcels (85 features):**
> ```
> https://services1.arcgis.com/MxjRokvPm7bjslyR/arcgis/rest/services/Pipeline_Data_Center_Areas/FeatureServer/1/query?where=1%3D1&outFields=*&outSR=4326&f=geojson
> ```
> Fields: `Application`, `FIRST_Status`, `FIRST_Subdivision` (use as the name),
> `FIRST_Zoning_Case_Num`, `FIRST_Overall_SQ_FT`, `SUM_Pipeline_Acres`.
>
> **Layer 3 — the eight election districts (used for filtering and the map outline):**
> ```
> https://logis.loudoun.gov/gis/rest/services/COL/ElectionDistricts/MapServer/8/query?where=1%3D1&outFields=EL_NAME,EL_POP2020&outSR=4326&f=geojson
> ```
>
> **Normalization rules — follow these exactly:**
>
> 1. **Every feature is a polygon, and the map needs points.** Compute the area-weighted
>    centroid of the largest ring of each feature. Use the shoelace formula; do not use the
>    bounding-box centre, which lands outside L-shaped parcels.
>
> 2. **Status mapping.** From layer 1's `Built_Status`:
>    - contains `UNDER CONSTRUCTION` → `under_construction`
>    - otherwise contains `BUILT` → `operational`
>
>    Match by **substring, case-insensitively**. One real county record contains the typo
>    `BULT/UNDER CONSTRUCTION`, so an exact-match lookup silently drops it. Every layer-2
>    feature is `proposed` regardless of its `FIRST_Status`.
>
> 3. **Text is stored in ALL CAPS.** Title-case it for display, but keep `LLC`, `LP`, `LC`,
>    `DC`, `VA`, `USA`, `II`, `III`, `IV` upper-case, and leave anything containing a digit
>    alone. Beware: a naive "keep short words upper-case" rule turns `BROAD RUN` into
>    `Broad RUN`.
>
> 4. **Assign a district to every facility.** Layer 1 has `ELECTION_DISTRICT`; layer 2 does not,
>    so run a point-in-polygon test against layer 3.
>
> 5. **Drop anything outside Loudoun County** — latitude 38.8–39.4, longitude −78.05 to −77.2.
>
> Cache the result in memory so it's fetched once per session, and show a loading state — the
> three layers are about 800 KB together.
>
> **Check your work.** When it runs you must get exactly **224 facilities: 103 operational, 36
> under construction, 85 proposed**, across 6 districts holding facilities (Sterling 108, Broad
> Run 52, Dulles 23, Leesburg 19, Little River 13, Ashburn 9; Algonkian and Catoctin have
> none). If your numbers differ, the normalization is wrong — fix it before moving on.

---

## Prompt 3 — Home page and the county hero

> Build the home page.
>
> **Hero**, two columns on desktop, stacked on mobile:
> - Kicker: "LOUDOUN COUNTY, VIRGINIA" with a 3px `#b3231b` rule under it
> - Headline: **"The data centers are mapped. The people living beside them are not."**
> - Standfirst: "Loudoun County holds the largest concentration of data centers on earth. The
>   county publishes where every one of them is. Nobody publishes what it is like to live next
>   to one — those accounts are scattered across board meetings, neighbourhood groups and local
>   news. This map puts both on the same screen."
> - Buttons: "Report an issue" (dark fill) and "See the map" (outline)
>
> **Right column — an SVG map of Loudoun County.** Build it from the district geometry fetched
> in the last step, not from an image:
> - Project lat/lng equirectangularly with a `cos(latitude)` correction on x, taken at the
>   bounding box's centre latitude. Without that correction the county looks noticeably squashed
>   — a degree of longitude here is only about 0.78 of a degree of latitude.
> - Draw the 8 districts filled `#f7f7f4` with hairline strokes, and the county's outer boundary
>   as a heavier `#121212` stroke.
> - Plot all 224 facilities as dots coloured by status.
> - Label each district in small uppercase Libre Franklin, with a **white halo**
>   (`paint-order: stroke fill`, 4px white stroke) — the eastern labels sit under a dense
>   cluster of dots and are unreadable without it.
> - Caption underneath: "**224 data center parcels in Loudoun County** — 103 operational, 36
>   under construction, 85 in the approval pipeline. Source: Loudoun County GIS."
>
> **Below the hero:** a four-tile stat row separated by hairline rules — Operational 103, Under
> construction 36, Proposed 85, Community reports (live count). Big Source Serif numerals in the
> status colours.
>
> Then a section listing the nine issue categories as a three-column broadsheet layout, each
> linking to the reports page filtered to that category. Then the six most recent reports. Then
> a closing call to action.

---

## Prompt 4 — The interactive map

> Build the main map with `react-leaflet` and OpenStreetMap tiles.
>
> Centre `[39.03, -77.48]`, zoom 11, min zoom 9, bounded to Loudoun.
>
> **Four toggleable layers**, each with its own colour *and its own marker shape*, so the map is
> readable without colour vision — state both in the legend:
> - Operational — blue `#1a56b0` **circle**
> - Under construction — amber `#8a5000` **square**
> - Proposed — violet `#6b28c9` **diamond** (a square rotated 45°)
> - Community reports — red `#b3231b` **teardrop**, with a slowly pulsing ring
>
> Use `react-leaflet-cluster` for clustering. Each toggle shows a live count.
>
> **Filters** above the map: district, issue category, and a free-text search. They must drive
> the map and the list from **one shared predicate function** — if you write the filtering twice
> the two views will drift apart. Reflect filters in the URL query string so a filtered view can
> be shared.
>
> **Popups:** for facilities, name, status badge, property owner, district, floor area, parcel
> acreage, zoning case, and the line "Source: Loudoun County GIS. Ownership is the recorded
> property owner, which is often a holding company." For reports, category badges, severity,
> truncated description, relative date, and "Location shown is approximate".
>
> **Accessibility:** the map must never be the only route to the data. Every page with a map
> also lists the same records as text. Give the container `role="application"` and a label
> saying an equivalent list follows.

---

## Prompt 5 — The report form

> Build the report form at `/report`. This page carries the most risk on the whole site, so
> follow the privacy rules exactly.
>
> **Open with the privacy promise, before asking for anything:**
>
> > **What gets published, and what never does.** Published: your district, ZIP, the kind of
> > issue, how much it affects you, your description, and any photos. Never published: your
> > name, email, phone, or street address. Your pin is plotted 100–200 m away from the location
> > you give, so it can never identify a household. Every report is read by a person before it
> > appears.
>
> **Five numbered sections:**
>
> **1. Where.** Three ways to set the location, because the person may be standing in their
> garden on a phone or sitting at a desk: a "Use my location" button (`navigator.geolocation`),
> tapping a mini-map to drop a draggable pin, and an address search. Setting a location
> auto-fills the district by point-in-polygon against the district geometry. Also a ZIP field.
>
> For the address search use Nominatim
> (`https://nominatim.openstreetmap.org/search?format=jsonv2`). Their policy allows about one
> request per second and forbids bulk use, so call it **only on an explicit button press, never
> as the user types**, and fall back to pin-drop if it fails. The pin is what's required; the
> typed address is optional.
>
> **2. Which facility.** Name, owner, and a "is it built yet?" radio — all optional, defaulting
> to "I'm not sure". Plenty of people can hear or smell a facility without knowing which one.
>
> **3. What you're experiencing.** Multi-select of these ten categories — use these exact keys,
> they end up in the database:
>
> | key | label | hint |
> |---|---|---|
> | `noise` | Noise | Constant hum, fans, chillers, generator testing |
> | `air_quality` | Air quality & diesel fumes | Generator exhaust, smells, visible haze |
> | `water` | Water | Supply, wells, runoff, stream or pond changes |
> | `power` | Electricity & grid | Outages, flicker, transmission lines, bills |
> | `health` | Health | Sleep loss, headaches, breathing, stress |
> | `property` | Property values & views | Sale prices, buyers walking, loss of outlook |
> | `light` | Light pollution | Floodlights, security lighting at night |
> | `traffic` | Traffic & construction | Trucks, road damage, dust, work hours |
> | `wildlife` | Wildlife & land | Tree loss, habitat, farmland, streams |
> | `other` | Something else | Anything not covered above |
>
> Then a 1–5 severity scale labelled: 1 Barely noticeable, 2 Noticeable, 3 Disruptive, 4 Hard to
> live with, 5 Severe. Then a description textarea, minimum 20 characters, max 5000, with the
> help text: "When does it happen, what does it sound, smell or look like, and how does it
> affect your household? Concrete detail is far more useful than strong language." Optional date
> and free-text notes.
>
> **4. Photos.** Up to 5, 10 MB each. **Re-encode every image through a `<canvas>` before
> upload.** This strips EXIF, which is essential: phone photos carry GPS coordinates, and
> publishing those would completely defeat the 100–200 m pin offset. Cap the long edge at
> 2000px. If the browser can't decode an image — usually HEIC outside Safari — **refuse it** and
> ask for JPG or PNG; passing the original through would carry its GPS tags with it.
>
> **5. You.** Name, email, phone — all optional, none ever published, present only so a
> moderator can come back with a question. A "share my contact details with local community
> groups" checkbox, **off by default**. A required checkbox confirming the account is first-hand
> and giving permission to publish the non-private parts.
>
> **Anti-spam, layered:**
> - A honeypot field positioned off-screen (not `display:none`, so bots still fill it). If it
>   has a value, show the success page but save nothing.
> - Reject submissions made less than 5 seconds after the form loaded.
> - Rate limit in localStorage: one per minute, five per day.
>
> **Validation:** show inline errors, move focus to the first invalid field, and don't clear
> what the user typed.
>
> **Keep this page visually calm.** No scroll animations, no flourishes. Someone filling this in
> is describing losing sleep or a house sale falling through; movement here reads as tone-deaf.
>
> On success, replace the form with a confirmation explaining it's in the moderation queue and
> may take a day or two, plus a reminder to **also** file with the county directly, because this
> site is not a channel the county monitors.

---

## Prompt 6 — Reports list and statistics

> **Reports page** (`/reports`): the same records as the map, as text. Filter bar (district,
> category, search) and a sort control (newest, oldest, highest impact), sharing the exact
> filter predicate the map uses. Each report shows district and ZIP as a serif heading, relative
> date, category badges, severity, the description, and any photos. Include the map above the
> list; hovering a card should highlight its pin.
>
> Show a banner: "These are unverified first-hand accounts from residents, not findings of fact.
> Names, addresses and contact details are never shown, and map pins are deliberately offset
> from the reported location."
>
> **Statistics page** (`/stats`), computed client-side from approved reports:
> - Headline tiles: total reports, districts represented (of 8), distinct ZIPs, last 30 days
> - Ranked bars by issue category, by district, by severity (1–5), and top 10 ZIPs
> - A 12-month timeline
> - Then a separate section of **county** figures — 103 operational, 36 under construction, 85
>   proposed, 114.4M sq ft total floor area — plus a table of all 8 districts with 2020
>   population against facility counts and report counts:
>
>   | District | Population 2020 | Operational | Under construction | Proposed |
>   |---|---|---|---|---|
>   | Sterling | 50,383 | 55 | 16 | 37 |
>   | Broad Run | 52,953 | 37 | 5 | 10 |
>   | Dulles | 53,777 | 4 | 5 | 14 |
>   | Leesburg | 53,780 | 3 | 5 | 11 |
>   | Little River | 54,858 | 3 | 3 | 7 |
>   | Ashburn | 50,607 | 1 | 2 | 6 |
>   | Algonkian | 51,613 | 0 | 0 | 0 |
>   | Catoctin | 52,988 | 0 | 0 | 0 |
>
>   Say plainly that these come from the county, not from this site's reports — they're there so
>   the resident accounts can be read against the scale of what's built and what's coming.
>
> Build the charts as **CSS-width bars inside real `<table>` markup**, not a charting library: a
> screen reader then reads the numbers, it prints correctly, and there's no dependency to keep
> up to date. A zero value must draw **no bar at all** — a minimum-width stub reads as "a small
> amount" rather than "none".
>
> Add a "Download CSV" button exporting only the public columns. Prefix any cell starting with
> `=`, `+`, `-` or `@` with an apostrophe so spreadsheets don't execute report text as a formula.

---

## Prompt 7 — Supabase

> Connect Supabase. I have the schema already — run the SQL in Appendix A **exactly as written**
> in the SQL editor, in order. Do not redesign it.
>
> Then point the data adapter at it:
> - Public pages read the **`public_reports` view** — never the `reports` table. The view omits
>   reporter name, email, phone, street address and the exact coordinates by construction.
> - Submissions insert into `reports`. Send `lat`/`lng` as given; a database trigger derives the
>   published offset coordinates and forces `status` to `'pending'`.
> - Photos upload to the private `report-photos` bucket under a `pending/<uuid>/` prefix, and
>   public pages render them through short-lived signed URLs.
> - Moderators sign in with email + password. The admin check reads
>   `app_metadata.role === 'admin'` — **not** `user_metadata`, which users can write to
>   themselves.
>
> Build a moderation page at `/admin` (noindex): a queue of pending reports showing the private
> fields clearly labelled "never published", with approve and reject buttons.
>
> Turn off public sign-ups in Supabase Auth — visitors never need accounts.
>
> **Verify the security actually works** before trusting it. As an anonymous client:
> - `select * from reports` must return **zero rows or permission denied**
> - `select * from public_reports` must return only approved reports
> - inserting with `status: 'approved'` must still store the row as `pending`
> - the published lat/lng must differ from the submitted ones by roughly 100–200 m

---

## Prompt 8 — Content pages

> Build four content pages. Use the copy in Appendix B verbatim — it's been written carefully
> and the legal wording matters.
>
> - `/resources` — how to file with Loudoun County, plus nine FAQs
> - `/about` — what this is and isn't, and full data provenance
> - `/privacy` — what's collected, published and never published
> - `/terms` — submission licensing, moderation standards, disclaimers
>
> Also a 404 page linking to the main sections.
>
> Set these as long-form editorial pages: max 68 characters per line, hairline rules above each
> `h2`, and a drop cap on the About page's opening paragraph.

---

## Prompt 9 — Animation

> Add motion. Two rules: it carries meaning or it doesn't ship, and it must never leave content
> stranded.
>
> - **Hero:** the county outline draws itself via `stroke-dashoffset`, districts wash in, then
>   the 224 dots land staggered and **ordered east to west** — so the viewer watches Data Center
>   Alley fill up while the rural west stays empty. That ordering is the entire point; a static
>   dot map doesn't make the argument.
> - **Map:** markers cascade in on first paint only, capped at about 120 (past that the tail is
>   imperceptible and the map just feels slow). Filtering to a single district flies the camera
>   there. Report pins pulse slowly.
> - **Page:** sections fade up on scroll, stat tiles count up, chart bars grow from zero.
>
> Two things to get right:
>
> 1. Every effect animates **from** an offset **to** the real resting state. Never hide content
>    waiting for a script — if the animation doesn't run, the page must still be complete.
> 2. `prefers-reduced-motion: reduce` collapses all of it. Use `animation: none`, not a
>    near-zero duration: effects with `both` fill mode would otherwise flash their start state.
>
> **A warning from building this the first time.** If you drive scroll reveals with
> `IntersectionObserver`, its callback is asynchronous and gets coalesced during a fast scroll.
> When that happens the element keeps its `opacity: 0` and is stranded invisible permanently —
> content silently lost. Either use a throttled scroll handler with `getBoundingClientRect`, or
> keep the observer but add a timeout that reveals everything after a few seconds regardless.
> Test it by scrolling fast to the bottom and back, then checking nothing is still transparent.

---

---

# PART TWO — The watchdog hub

Part One builds the map and the reporting loop. Part Two turns it into somewhere people come
back to: a proper investigation map, full report records, a watchlist that surfaces clusters,
an automated local news feed, an evidence library, profiles of the officials who decide these
applications, and tools for acting on all of it.

**Build Part One first and confirm it works.** Every prompt below assumes it exists.

## Read this before you start Part Two

Part One is a pure browser app. Part Two is not, and there are exactly three reasons:

1. **News and calendar feeds do not send CORS headers.** I tested every feed in this document.
   Loudoun County's calendar, Google News, Cardinal News, Virginia Mercury, WTOP — none of them
   send `access-control-allow-origin`. A browser `fetch()` to any of them fails, and no amount
   of prompting fixes it, because the restriction is on the far end. These have to be fetched
   server-side.
2. **The Anthropic API key must never reach the browser.** Anything with an API key in client
   JavaScript is a key you have published.
3. **The watchlist needs data the browser is not allowed to see.** Counting *distinct
   households* near a cluster requires reading reporter email addresses, which is exactly what
   the privacy model forbids the browser from doing.

All three are solved the same way: **Supabase Edge Functions**. Appendix F has the four
functions and their deployment commands. Several prompts below tell you to deploy one — do it
when the prompt says to, not at the end.

Everything else in Part Two still runs in the browser.

---

## Prompt 10 — Map upgrades: satellite and real tools

> Upgrade the map. Right now it has one basemap and four marker layers; it needs to be a proper
> investigation tool.
>
> **Basemap switcher.** Add a control to switch between these. I have tested every one of these
> tile URLs — they all return real imagery with **no API key and no billing account**:
>
> | Basemap | Tile URL template | Why it's here |
> |---|---|---|
> | Streets | `https://tile.openstreetmap.org/{z}/{x}/{y}.png` | Default. Street names and context. |
> | **Satellite** | `https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}` | See the actual buildings, parking, substations, tree loss. |
> | Topographic | `https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}` | Terrain and watersheds. |
> | Hillshade | `https://server.arcgisonline.com/ArcGIS/rest/services/Elevation/World_Hillshade/MapServer/tile/{z}/{y}/{x}` | Ridgelines — relevant to how noise carries. |
> | Light canvas | `https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}` | Muted, so data overlays read clearly. |
> | USGS imagery | `https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/MapServer/tile/{z}/{y}/{x}` | US government aerial, independent of Esri. |
>
> **Note the axis order.** The Esri and USGS ArcGIS tile services use `{z}/{y}/{x}`, while OSM
> and CARTO use `{z}/{x}/{y}`. Getting this wrong gives you a map of the wrong hemisphere, and
> it is the single most common mistake with these services.
>
> **Attribution is a licence condition, not decoration.** Show the right one for whichever
> basemap is active:
> - Esri layers: `Tiles © Esri — Source: Esri, Maxar, Earthstar Geographics, and the GIS User Community`
> - USGS: `Tiles courtesy of the U.S. Geological Survey`
> - OSM: `© OpenStreetMap contributors`
>
> **Overlays**, each independently toggleable:
> - Data center **parcel boundaries** as polygons, not just centroid pins. You already fetch the
>   full polygon geometry in Prompt 2 and throw it away after computing the centroid — keep it.
>   On satellite this shows the real footprint against the neighbourhood, which is the single
>   most persuasive thing the map can do.
> - **Election district** boundaries with labels.
> - A **heat layer** of community reports, so clusters are visible at county scale.
> - **Data center building outlines** — you already load these for the statistics page.
>
> **Tools:**
> - **Measure distance** — click points, get feet and metres. "How far is that from my house" is
>   the question people actually arrive with.
> - **Radius rings** — drop a point, draw 0.25 / 0.5 / 1 / 2 mile rings, and list every facility
>   inside each.
> - **Address search** — find my address on the map. Use Nominatim
>   (`https://nominatim.openstreetmap.org/search?format=json&countrycodes=us&q=...`), on button
>   press only, at most one request per second, with a descriptive `User-Agent`. Their usage
>   policy requires all three; ignoring it gets the whole site blocked, not just one user.
> - **Use my location**, **fullscreen**, and a **scale bar**.
> - **Split / swipe compare** between satellite and streets if it is not much extra work — it
>   makes the scale of a campus obvious in a way a single view does not.
>
> Keep the four data layers and their shape-plus-colour encoding exactly as they are. The
> basemap switcher must not change what the markers mean, and markers must stay legible on
> satellite — dark imagery needs a light stroke around each marker.
>
> On mobile, collapse the controls into a single sheet. Do not stack six buttons over the map.

---

## Prompt 11 — Full report detail with photos

> Right now clicking a community report gives a small popup. Make each report a real record.
>
> **Clicking a report pin** opens a detail panel — a side sheet on desktop, a bottom sheet on
> mobile — showing everything published about that report:
> - District and ZIP as the heading, with the date submitted and how long ago
> - Every issue category as a badge, and the severity with its label ("4 — Hard to live with")
> - The **full description**, not truncated
> - Any "anything else" notes
> - The facility the reporter named, if they named one, and its status
> - **All photos**, in a gallery — click to open full-size in a lightbox with keyboard
>   navigation, swipe on touch, and Escape to close
> - A note that the location shown is approximate
> - A **permalink** and a copy-link button
>
> **Every report also gets its own page** at `/reports/:id` with its own title and description
> meta tags, so a link previews properly when shared. The detail panel and the page render from
> the same component.
>
> From the detail view, offer:
> - "Show nearby reports" — other reports within half a mile
> - "Show nearby facilities" — what is actually around that pin
> - "I'm experiencing this too" → the report form, pre-filled with the same district and
>   categories. **Do not** let this submit a duplicate silently; it goes through the normal form
>   and normal moderation like everything else.
> - A quiet "Report a problem with this report" link for factual disputes and takedown requests
>
> **Keep the privacy rules exactly as they are.** The detail view shows more of what the reporter
> *wrote*. It must never show anything about *who they are*. No name, no contact, no street
> address, no exact coordinates — not in the DOM, not in the API response, not in the page
> source. The `public_reports` view is still the only thing the browser reads.
>
> Photos are served through short-lived signed URLs. Add `loading="lazy"` and real alt text.

---

## Prompt 12 — The watchlist and the ticker

This is the feature that makes the site feel alive, and it is also the one with the most
editorial risk. Read the framing note after the prompt before you build it.

> Add a **watchlist**: locations where enough independent residents have reported problems that
> the cluster is worth flagging.
>
> **The rule.** A location goes on the watchlist when **five or more approved reports from five
> or more distinct households** fall within a **2-mile radius** of it. Both halves matter — five
> reports from one angry household is not a cluster, it is one household.
>
> Cluster around two kinds of anchor:
> - **A named facility.** Count approved reports within 2 miles of a data center from the county
>   layer. This is the common case and the one people expect.
> - **An emergent location** with no facility at its centre. Grid the county into roughly
>   half-mile cells, count reports within 2 miles of each cell centre, keep cells over the
>   threshold, and merge overlapping ones into a single entry named for the nearest place. These
>   are the interesting ones — a cluster with no obvious cause is exactly what a watchdog site
>   exists to surface.
>
> **Compute this in the database, not the browser.** Distinct-household counting requires reading
> reporter email addresses, which the browser must never receive. Appendix E has the SQL: a
> `SECURITY DEFINER` function that reads the base table, counts
> `count(distinct lower(reporter_email))`, and writes to a `watchlist` table exposing only
> aggregate numbers. Refresh it on a schedule and whenever a moderator approves a report.
>
> **The ticker.** Put a single-line ticker directly under the site header on **every page**.
> - Each item reads like: **`⚠ Sterling — 14 reports within 2 miles · noise, vibration`**
> - Items scroll horizontally, continuously, right to left
> - **Pause on hover and on keyboard focus**, and give it a visible pause/play button
> - **Honour `prefers-reduced-motion`**: if set, do not scroll at all — render a static
>   horizontally scrollable strip instead
> - Each item is a real link to `/watchlist/:id`
> - Do **not** use `<marquee>`. It is deprecated, it is not keyboard accessible, and screen
>   readers handle it badly. Use a CSS `transform: translateX()` animation on a duplicated track,
>   inside a container with `aria-label="Community report watchlist"`.
> - If the watchlist is empty, hide the ticker entirely. Never show an empty or placeholder bar.
> - Dismissible, remembered for the session — but it comes back when a **new** entry appears,
>   which you detect by storing the highest watchlist entry ID the visitor has dismissed.
> - Cap it at the top 10 entries by report count so it does not become noise.
>
> **A `/watchlist` page** listing every entry, sortable by report count, most recent report, or
> district. Each entry gets a detail page showing the cluster on the map with its 2-mile radius
> drawn, the count over time, the category breakdown, every report in the cluster, the facilities
> inside the radius, and the supervisor for that district with a link to write to them.
>
> **Wording — this part is not optional.** A watchlist entry is a statement about *reports*, never
> about a company. Write it as "**14 residents have reported problems within 2 miles of this
> location**", never as "this facility is causing problems". Put this line on every watchlist
> page:
>
> > Watchlist entries reflect the number and proximity of resident reports. They are not findings
> > of fact and do not establish that any facility caused any condition.
>
> Do not let the AI features generate watchlist prose. Template it.

**Why the rule is shaped that way.** Three details in it are load-bearing:

- **Only approved reports count.** If pending reports counted, anyone could manufacture a
  watchlist entry — and therefore a public accusation against a named company — by filling in the
  form five times. Moderation is what stands between the ticker and defamation.
- **Distinct households, not distinct reports.** Same reason, one step subtler.
- **2 miles is safely larger than the coordinate jitter.** Published pins are offset 100–200 m
  from the real address. A 2-mile radius is 3,218 m — sixteen to thirty-two times the jitter — so
  clustering on published coordinates gives the same answer as clustering on real ones, and never
  requires exposing a real one. If you ever shrink the radius below about half a mile, that stops
  being true and you would be trading residents' privacy for map precision. Don't.

---

## Prompt 13 — Local news, pulled automatically

> Add a **News** section that pulls recent local coverage of data centers and AI infrastructure
> and lists it as **headline → source → date → link**.
>
> **This cannot be done from the browser.** I tested every feed below and **none** of them send
> `access-control-allow-origin`. A client-side `fetch()` gets a CORS error every time. Build it as
> a Supabase Edge Function that fetches and parses the feeds server-side, writes into a
> `news_items` table, and let the browser read that table. Appendix F has the function.
>
> **Primary source — Google News RSS.** No key, no quota, and it aggregates outlets that have no
> usable feed of their own. Query by URL:
>
> ```
> https://news.google.com/rss/search?q=<QUERY>&hl=en-US&gl=US&ceid=US:en
> ```
>
> Run these queries and tag each result with the topic:
>
> | Topic | Query (URL-encode it) |
> |---|---|
> | Loudoun | `"data center" Loudoun` |
> | Virginia | `"data center" Virginia when:30d` |
> | Power and the grid | `data center electricity Dominion Virginia` |
> | Water | `data center water usage Virginia` |
> | AI buildout | `AI data center construction Virginia` |
> | Loudoun Now | `site:loudounnow.com "data center"` |
> | Loudoun Times-Mirror | `site:loudountimes.com "data center"` |
>
> Also poll these outlets' own feeds directly, which are current and reliable:
> `https://virginiamercury.com/feed/` · `https://cardinalnews.org/feed/` · `https://wtop.com/feed/`
> — then keep only items whose title or description matches `data cent|datacent|AI infrastructure|hyperscale`.
>
> **Parsing Google News, precisely.** Three quirks, all of which will bite:
> - `<title>` is `Headline - Publication`. Split on the **last** `" - "` to separate them, and use
>   the `<source>` element when it is present, which is more reliable.
> - `<link>` is a `news.google.com/rss/articles/...` redirect, not the publisher's URL. Store it
>   as-is and let the click resolve. Do not try to unwrap it; the encoding is undocumented and
>   changes.
> - `<description>` is an HTML fragment, not a summary. Do not render it.
>
> **What to display.** Headline, publication, relative date, and a link. **That is all.** Do not
> store or display article body text, and do not summarise the article with AI — you have not
> read the article, only its headline. Headline-plus-link is both the copyright-safe pattern and
> the honest one.
>
> **Behaviour:**
> - Refresh hourly. Cache in `news_items`; never fetch a feed on page load.
> - De-duplicate on a normalised title — lower-cased, punctuation stripped, publication suffix
>   removed. The same wire story appears under many mastheads.
> - Drop anything older than 90 days.
> - Links open in a new tab with `rel="noopener noreferrer nofollow"`.
> - Filter chips by topic; a search box over headlines.
> - Show the **five most recent Loudoun items on the home page**, under the map, with a "More
>   news" link.
> - If the last refresh failed, show the cached items with a quiet "last updated <time>" note.
>   Never show an error page because a third-party feed was down.
>
> **Label it honestly.** Put this under the section heading:
>
> > Headlines are collected automatically from public news feeds. Inclusion is not endorsement,
> > and this project has no relationship with any outlet listed.
>
> Give moderators a hide button per item, because automated feeds occasionally surface press
> releases and SEO spam dressed as news.

---

## Prompt 14 — Facts and myths, by topic

> Build a **Facts** section: the claims people actually meet about data centers, sorted into what
> the evidence supports and what it does not, organised by topic.
>
> Ten topics, each its own page at `/facts/:topic` with a landing page at `/facts`:
>
> | Topic | What it covers |
> |---|---|
> | Electricity | Grid load, who pays for transmission, ratepayer impact |
> | Water | Cooling water withdrawal and consumption, closed-loop vs evaporative |
> | Noise | Chillers and generators, low-frequency noise, ordinance limits |
> | Air quality | Diesel backup generators, permitted testing hours, emissions |
> | Land and trees | Acreage, tree canopy loss, stormwater, buffers |
> | Property values | What the research does and does not show |
> | Taxes and jobs | Computer-equipment tax revenue, permanent employment numbers |
> | Health | What is documented, what is claimed, what is unstudied |
> | Zoning and process | By-right vs special exception, where the public gets a say |
> | AI and the buildout | What AI demand actually changes about siting and load |
>
> **The format for every card.** Each entry is a claim, a verdict, and a source:
>
> - **The claim**, worded the way people actually say it
> - **A verdict badge**: `Supported` · `Mostly true` · `Mixed` · `Misleading` · `Unsupported` ·
>   `Unresolved`
> - **What the evidence shows**, in two or three sentences of plain English
> - **Sources** — at least one, each a link to a primary document: a state report, a utility
>   filing, a county staff report, a peer-reviewed paper. Show the publisher and the year on the
>   face of the card, not hidden in a footnote.
> - **Last checked**, as a date
>
> **`Unresolved` is a real verdict and you should expect to use it often.** Several of the most
> emotionally charged questions here — long-term health effects of chronic low-frequency noise
> near residential areas is the clearest example — do not have a good answer in the literature
> yet. Saying so is more credible than picking a side, and a site that only ever finds against
> data centers will be dismissed as advocacy by exactly the audience it needs to persuade.
>
> **Include claims that cut against this site's angle.** If a common criticism is overstated, say
> so and show the source. That is the entire currency of a project like this.
>
> **Do not generate this content with AI.** Every card needs a real citation to a real document
> that a real person has opened. An AI-written fact-check with hallucinated sources is worse than
> no fact-check, because it is confidently wrong and it discredits everything else on the site.
> Build the UI now and let a human fill the cards. Ship with eight well-sourced cards rather than
> sixty unsourced ones.
>
> Each card is individually linkable and individually shareable, with its own Open Graph image
> showing the claim and the verdict. Add a "suggest a correction" link on every card that opens a
> form pre-filled with the card ID.

---

## Prompt 15 — The elected officials hub

This is the largest feature in Part Two and the one most likely to draw a complaint from
someone's office. Everything in it must be sourced to a primary document. Read the note on
scoring after the prompt.

> Build an **Officials** section covering everyone who votes on, funds or regulates data center
> development affecting Loudoun County — from county supervisors up to the US Senate.
>
> **Where the data comes from.** Loudoun County publishes an authoritative elected
> representatives layer, and I have verified it sends `access-control-allow-origin: *`, so the
> browser can fetch it directly:
>
> ```
> https://services1.arcgis.com/MxjRokvPm7bjslyR/arcgis/rest/services/ElectedReps_Data/FeatureServer/{layer}/query
>   ?where=1%3D1&outFields=*&outSR=4326&f=geojson
> ```
>
> | Layer | Contents |
> |---|---|
> | `0` — `ELREP_LOUDOUN` | Eight district polygons carrying supervisor name, party, first election year, official page URL and photo URL; plus the at-large Board Chair, School Board member and at-large member, Sheriff, Commonwealth's Attorney, Commissioner of the Revenue, Treasurer and Clerk of Court |
> | `1` — `ELREP_VAHOUSE` | Five Virginia House districts (26, 27, 28, 29, 30) with delegate name, party, email, Richmond and district office addresses and phones, official URL, photo |
> | `2` — `ELREP_VASENATE` | Two Virginia Senate districts (31, 32) with the same fields |
>
> Because these are polygons, an address lookup is a point-in-polygon test against all three
> layers at once — that is how "who represents me" works, and it needs no third-party service.
>
> For Congress use `https://unitedstates.github.io/congress-legislators/legislators-current.json`
> (also CORS-open). Loudoun County is covered by **VA-10** and **VA-11** in the House, plus both
> Virginia senators. Filter that file rather than hard-coding names — members change.
>
> **Never hard-code the roster.** Names, parties and photos all come from the live layers. A
> hard-coded list is wrong the day after an election and nobody notices for a year.
>
> **Each official gets a profile page** at `/officials/:slug`:
> - Photo, name, office, party, district, first elected, term end
> - Every published contact route: office email, Richmond and district phone, mailing address,
>   web contact form, official site
> - **Which of this site's watchlist clusters and community reports fall in their district**, with
>   counts — this is the link that makes the hub matter rather than being a phone book
> - The data center facilities in their district: operational, under construction, proposed
> - **Voting record** on data center and related matters (below)
> - **Campaign finance** (below)
> - "Write to this official" → the letter writer in Prompt 16
> - A "correct this profile" link on every page, above the fold, not buried in a footer
>
> **Voting record.** Be straight about what is available, and note that the obvious place to look
> is the wrong one:
> - **Loudoun Board of Supervisors votes have no API, and Granicus has no minutes.** The county's
>   Granicus portal (`loudoun.granicus.com`) publishes agendas and video, and
>   `GeneratedAgendaViewer.php` returns a full structured agenda with land-use case numbers inline
>   — but `MinutesViewer.php` serves a stub for Board of Supervisors clips. There are no minutes
>   there to parse.
> - The actual vote record is a per-meeting **"Action Report" PDF** in the county's Laserfiche
>   portal at `lfportal.loudoun.gov`. That portal has an undocumented, cookie-free RSS index —
>   `https://lfportal.loudoun.gov/LFPortalinternet/rss/dbid/0/folder/{folderId}/feed.rss` returns
>   one item per meeting with its folder id, no session cookie and no special User-Agent required.
>   Everything else in that portal does need a cookie and two redirects.
> - **Votes are English prose, not roll-call tables.** They read
>   `The motion passed 5-3-1: Supervisors Briskman, TeKrony, and Umstattd opposed; Supervisor
>   Letourneau absent.` Some meetings do record a formal roll call and say so; most do not. Any
>   regex over this is a parsing problem, not a data feed — and a naive one silently drops the
>   `The motion, as amended, passed …` form, which is exactly the form the interesting
>   data-center votes tend to take.
> - **PDF text extraction corrupts case numbers.** Line-wrap hyphens vanish, so `SPEX-2025-0023`
>   comes out as `SPEX2025-0023` in roughly one case number in twelve — intermittently, which
>   makes it easy to miss. If you join votes to GIS records on the case number, normalise both
>   sides first or the join silently loses rows.
> - Given all of that: build the UI as a **hand-curated table** — motion, date, vote, link to the
>   Action Report PDF and the video timestamp — and enter the data-center-relevant votes by hand.
>   Twenty accurate hand-entered votes beat two hundred scraped ones with an error rate, and this
>   is a page where an error rate is a correction notice about a named person.
> - There is **no Legistar API** for Loudoun. `webapi.legistar.com/v1/loudoun/bodies` returns a 500
>   saying the connection string is not configured. Do not build against it.
> - **Virginia General Assembly** bills and votes are published by the Legislative Information
>   System at `https://lis.virginia.gov` and are far more tractable, though also not CORS-open.
> - **Congress** — use `https://api.congress.gov` (free key from `api.congress.gov/sign-up`) or
>   the roll-call XML the House and Senate publish per vote.
> - Every vote row links to the primary record. A vote with no link does not get displayed.
>
> **Campaign finance.** Virginia publishes itemised contributions as bulk CSV — no key, no
> scraping, no third-party aggregator:
>
> ```
> https://apps.elections.virginia.gov/SBE_CSV/CF/{YYYY_MM}/Report.csv       ~2 MB   committees and candidates
> https://apps.elections.virginia.gov/SBE_CSV/CF/{YYYY_MM}/ScheduleA.csv    ~41 MB  itemised contributions
> https://apps.elections.virginia.gov/SBE_CSV/CF/{YYYY_MM}/ScheduleD.csv    ~8 MB   expenditures
> ```
>
> `ScheduleA` gives contributor name, employer, occupation or type of business, city, state, ZIP,
> an `IsIndividual` flag, date and amount, joined to `Report.csv` on `ReportId` to get the
> committee and candidate. Ingest it server-side into Supabase on a monthly schedule; it is far
> too large to fetch in a browser. For federal candidates use the FEC's OpenFEC API
> (`https://api.open.fec.gov/v1/`, free key from `api.data.gov`). Link out to VPAP for context but
> do **not** scrape it — it blocks automated requests, and it is a small non-profit whose work
> deserves traffic rather than extraction.
>
> **Three things about that data that will produce a wrong number if you ignore them:**
>
> 1. **Virginia files large contributions twice.** A big cheque appears immediately on a "Large
>    Contribution Report" and again inside the next periodic report — under a *different*
>    `ScheduleAId`, so de-duplicating on that column removes nothing. In one month I checked, 125
>    contributions worth about $4M appeared in both, which was 43% of that month's large-
>    contribution rows. De-duplicate on contributor plus date plus amount plus committee, and say
>    on the methodology page how you did it.
> 2. **`IsLocal` does not mean local, and `IsGeneralAssembly` is unpopulated.** Hundreds of House
>    of Delegates and state Senate committees carry `IsLocal = True`, and `IsGeneralAssembly` was
>    `False` on every row of the file I checked. Filter to Loudoun officials by your hand-verified
>    `CommitteeCode` list, never by these flags.
> 3. **A PAC funding its own PAC is not money to an official.** The largest "Dominion" rows in
>    that data are Dominion Energy Inc. transferring to the Dominion Energy PAC. Publishing that
>    on a page about money to officials would be materially false, and counting both it and the
>    PAC's later disbursements double-counts the same dollars.
>
> **One privacy trap:** `Report.csv` carries `SubmitterEmail` and `SubmitterPhone` — the personal
> contact details of the person who filed the report. Drop those columns at ingest. A site whose
> entire promise is that it does not publish contact details should not import a spreadsheet of
> them by accident.
>
> **Two matching problems you must handle explicitly, because both produce libel if you get them
> wrong:**
>
> 1. **Matching committees to candidates.** Name matching fails badly. In the January 2026 file
>    there is a "Kelly L Glass" committee that has nothing to do with Supervisor Sylvia Glass, and
>    a "Kelvin E Turner for Portsmouth City Council" that has nothing to do with Supervisor
>    Michael Turner. Match once, by hand, on `CommitteeCode`, store the mapping, and never match
>    by name at runtime.
> 2. **Deciding what counts as "data center money".** Substring matching is worse than useless
>    here. That same file contains "Dominion Energy PAC" — a genuine utility PAC — and "Dominion
>    Floor Covering, Inc" of Yorktown, a flooring company. Maintain an explicit, versioned list of
>    donor entities with a category each (`operator`, `utility`, `developer`, `construction`,
>    `land`, `law firm`, `trade association`), match on exact normalised entity name, and
>    **publish the list on the site** so a reader can see precisely why a donor was counted.
>
> Display finance as: total raised in the cycle · total from listed data-center-related entities ·
> that as a percentage · the top ten such contributions itemised with dates and amounts · a link
> to the filing each came from. Every number traceable to a document.
>
> **The scorecard.** Give each official a **Data Center Accountability Score** built from
> published, checkable components — not from a language model's opinion:
>
> | Component | Weight | Source |
> |---|---|---|
> | Votes on data center applications and related ordinances | 40% | Meeting minutes, roll calls |
> | Positions taken in public statements and hearings | 20% | Video, minutes, press releases |
> | Share of funding from listed data-center-related entities | 20% | The finance data above |
> | Support for disclosure, setbacks, noise limits, ratepayer protection | 20% | Bill sponsorship, motions |
>
> Show the component scores, not just the total. Make every component expandable to the evidence
> behind it. Give officials with insufficient public record an **Insufficient data** badge rather
> than a low score — absence of evidence is not evidence.
>
> **The AI button is a summariser, not a judge.** "Explain this record" sends *only the sourced
> rows already on the page* to the model and asks for a neutral two-paragraph summary of what
> those rows show. It must not browse, must not recall anything about the person from training,
> must not produce a rating, and must not add a fact that is not in the rows it was given. Label
> the output "AI summary of the sourced record on this page" and put the model name next to it.
> Details in Prompt 16 and Appendix F.
>
> **Methodology page.** One page at `/officials/methodology` giving the full scoring formula, the
> donor classification list, the update schedule, the corrections process, and a plain statement
> of what the score does and does not mean. Link it from every profile. If you cannot write that
> page honestly, do not ship the score — ship the underlying facts without a number on top.

**On the ranking you asked for.** You asked for a button that runs an AI analysis and ranks each
official good or bad on data centers. I have built the ranking, and I have deliberately not built
it that way, for reasons that are practical rather than squeamish:

A language model asked to rate a named living person will produce a confident answer whether or
not it knows anything. It will attribute votes to the wrong supervisor, invent a quote, or repeat
a training-data claim that was never true — and it will do it in a sentence that reads perfectly.
You cannot cite it, you cannot defend it, and one demonstrably invented vote is enough for an
opposing press office to discredit the entire site, including the resident reports, which are the
part that actually matters.

The scorecard above gets you the same thing and survives contact with a hostile reader. When
someone objects to a score, you open the page and show them the roll call. The AI still does the
work it is genuinely good at — turning twelve rows of votes and donations into two readable
paragraphs — but the verdict comes from the record, and the record is on the page.

---

## Prompt 16 — The AI letter writer

> Add a tool that helps a resident write to their elected officials — and make it produce a
> letter that sounds like the person who sent it, because a hundred identical AI letters are
> worth less to a supervisor's office than five real ones.
>
> **Flow:**
> 1. Enter an address (or pick a district). Point-in-polygon against the three `ElectedReps_Data`
>    layers to find the supervisor, delegate and state senator, plus the congressional district.
> 2. Choose who to write to — one, several, or all — with each official's actual contact route
>    shown.
> 3. Pick a topic: noise, water, electricity rates, tree loss, traffic, an application at a
>    specific address, a scheduled hearing, or something else.
> 4. Say what is happening in your own words. Two sentences is fine. **Prefill this from the
>    person's own community report if they have one** — that is the highest-value shortcut in the
>    whole feature.
> 5. Choose a tone: measured · concerned · formal · brief.
> 6. Generate. Show the draft in an editable box, never send it automatically.
> 7. Copy, download as `.txt`, or open a `mailto:` link with subject and body pre-filled.
>
> **What the model is given:** the resident's own words, the official's name, office and district,
> the facility and report counts near that address from data already on the site, and any relevant
> upcoming meeting. Nothing else.
>
> **What the model is told:** write in first person as this resident; use only the facts supplied;
> invent nothing; do not attribute intent or blame to any company; do not state legal conclusions;
> keep it under 350 words; open with the writer's connection to the district; make one specific,
> actionable ask. The full system prompt is in Appendix F.
>
> **What must be true of the output:**
> - The resident sees and can edit every word before it goes anywhere.
> - Nothing is sent from this site. A `mailto:` link or a copy button — the message leaves from
>   the resident's own mail client, from their own address, as their own words.
> - A note under the box: "Officials' offices can tell form letters from real ones. Edit this so
>   it sounds like you — a specific detail about your street is worth more than a page of
>   argument."
> - Rate-limited per session. This must not become a mass-mail tool; that is how a site like this
>   gets its mail filtered to junk county-wide.
>
> **The key stays server-side.** The Anthropic API key lives in a Supabase Edge Function secret
> and never appears in client code, in a `VITE_`-prefixed variable, or in the network tab.
> Anything prefixed `VITE_` is compiled into the bundle and is public. Appendix F has the
> function, the exact request shape, and the deployment commands.
>
> **Also build the two smaller AI features**, through the same function with different system
> prompts:
> - **Explain this application** — turn a zoning case (`ZMAP-2018-0015`, 1.2 M sq ft, SPEX,
>   approved 2019) into two plain sentences. Input is the county record only.
> - **Explain this record** — the officials summariser from Prompt 15. Input is the sourced rows
>   on the page only.
>
> Every AI-generated block on the site carries a visible label naming the model, and every one of
> them is editable or dismissible by the person reading it.

---

## Prompt 17 — Meetings, deadlines and the resources library

> Build a **Meetings** section so residents know when decisions are actually made, and expand
> Resources into a real library.
>
> **The calendar.** Loudoun County publishes an events RSS feed:
>
> ```
> https://www.loudoun.gov/RSSFeed.aspx?ModID=58&CID=All-calendar.xml
> ```
>
> It returns real, current entries — board and commission meetings, each linking to
> `loudoun.gov/Calendar.aspx?EID=<id>` for agenda and location. **It does not send CORS headers**,
> so fetch it in the same Edge Function as the news feed and cache it in a `meetings` table.
>
> Show meetings for the bodies that decide these applications — Board of Supervisors, Planning
> Commission, Board of Zoning Appeals, and the relevant standing committees — and mark any whose
> title or agenda mentions a data center, a zoning case number, or a rezoning.
>
> Each meeting shows date and time, body, location with a map link, agenda link, live-stream and
> archive links, and **whether public comment is taken and how to sign up**, which is the single
> most useful thing on the page and the thing residents most often miss. Add "Add to calendar"
> generating a proper `.ics` file.
>
> Put the **next three meetings on the home page**. Add a countdown for any public-comment
> deadline inside 14 days.
>
> **Resources, expanded** — one page per group, not one long list:
> - **Report a problem now** — the county's own channels, with the direct numbers already in
>   Appendix B. This stays first. This site is not a complaint channel and must never be mistaken
>   for one.
> - **Understand your rights** — noise ordinance, zoning process, how special exceptions work,
>   what by-right development means and why it matters, how to speak at a hearing, how to request
>   records under Virginia FOIA.
> - **Document library** — county staff reports, state studies (JLARC's data center report is the
>   obvious anchor), utility filings, ordinances, peer-reviewed papers. Each with publisher, date,
>   a plain-English note on what it actually found, and a link to the original. Include documents
>   that cut against this site's angle.
> - **Organisations** — local and state groups working on this, each described neutrally, each
>   linked. Say plainly that listing is not affiliation.
> - **Doing your own research** — how to look up a parcel in county GIS, find a zoning case, read
>   a staff report, and check who owns a property. Teaching this is more valuable than any single
>   fact the site can publish.
> - **For journalists** — the data exports, the methodology pages, the corrections policy, and a
>   contact route.

---

## Prompt 18 — The rest of the watchdog toolkit

> These are the things that turn a map into something people return to. Build as many as you can;
> they are roughly in order of value.
>
> **1. "What's near me"** — the question everyone arrives with. Enter an address and get: every
> facility within 0.5, 1 and 2 miles split by status; how many are proposed rather than built;
> every community report nearby; whether the address falls inside a watchlist cluster; and **which
> officials represent it** — supervisor, delegate, state senator, US representative — each linking
> to their profile and to the letter writer.
>
> **2. Alerts.** Email subscription to: new applications within N miles of an address; new reports
> in a district; a new watchlist entry nearby; a meeting with a data center item on the agenda; an
> upcoming public-comment deadline. This is what converts a visitor into a participant. Confirmed
> opt-in, unsubscribe link in every email, and store the subscriber's location as coordinates plus
> a radius rather than as a street address.
>
> **3. Application tracker.** The county pipeline layer carries real application numbers
> (`EPLAN-2023-0083`) and zoning case numbers (`ZMAP-2018-0015`), and a separate county layer
> lists approved applications with their type (`SPEX`, `ZMAP`, `ZCPA`, `ZMOD`, `ZRTD`, `SPMI`) and
> approval date. Give each case a page: where it is, how big, current status, district,
> supervisor, nearby reports, and status changes over time.
>
> **4. Change detection.** The county refreshes its parcel data every few months. Snapshot each
> pull and show the diff: "**12 new applications since March**, 3 approved, 1 withdrawn". A diff
> is more newsworthy than a total, and it gives people a reason to come back.
>
> **5. A structured noise and impact log.** The site already tells people that a log kept over
> weeks is far more persuasive than one vivid description. Give them the tool: a fast repeat-entry
> form (date, time, duration, what they observed, optional decibel reading), private to that
> person, exporting as a formatted PDF they can attach to a county complaint. Be honest in the UI
> that a phone decibel app is not a calibrated meter — recording that limitation is what makes the
> rest of the log credible.
>
> **6. Open data out.** Public CSV and JSON export of published reports, plus a read-only API.
> Journalists and researchers are a large part of who this is for, and making their job easy
> multiplies the site's reach. Same privacy rules as everywhere else: the export is the
> `public_reports` view, nothing more.
>
> **7. An embeddable map widget.** A single `<iframe>` snippet local news sites and community
> groups can paste. Every embed is a link back.
>
> **8. Share cards.** An Open Graph image per report, per watchlist entry and per statistic, so a
> link posted to social media shows the map and the number rather than a bare URL.
>
> **9. Spanish translation.** Sterling and the eastern districts — the areas with by far the
> heaviest data center concentration — have large Spanish-speaking populations. An English-only
> site systematically excludes the households most affected. At minimum translate the report form,
> the privacy promise, the resources page and the ticker.
>
> **10. A timeline.** How Loudoun got here: the key rezonings, the votes, the moment "Data Center
> Alley" became the county's tax base. Anchored to sourced events, not narrative.
>
> **11. Archive search.** Reports stay findable — full-text search over report text, date-range
> filter, pagination rather than truncation.

---

## Appendix A — The database schema

Run these in the Supabase SQL editor in order. They are the security model — the coordinate
jitter, the moderation default, and the row-level security are all here, and an AI builder will
not invent any of them.

### A1 — Schema

```sql
create extension if not exists "pgcrypto";

do $$
begin
  if not exists (select 1 from pg_type where typname = 'facility_status') then
    create type facility_status as enum
      ('operational', 'under_construction', 'proposed', 'unknown');
  end if;
  if not exists (select 1 from pg_type where typname = 'report_status') then
    create type report_status as enum ('pending', 'approved', 'rejected');
  end if;
end
$$;

create table if not exists public.reports (
  id                uuid primary key default gen_random_uuid(),
  created_at        timestamptz not null default now(),

  -- Reporter contact. All optional, and never published.
  reporter_name     text        check (char_length(reporter_name)  <= 200),
  reporter_email    text        check (char_length(reporter_email) <= 320),
  reporter_phone    text        check (char_length(reporter_phone) <= 50),
  contact_ok        boolean     not null default false,

  -- Where. `address` and the raw lat/lng are private; the _public pair is
  -- what the map plots.
  locality          text        not null check (char_length(locality) between 2 and 80),
  zip               text        check (zip ~ '^[0-9]{5}$'),
  address           text        check (char_length(address) <= 300),

  lat               double precision not null check (lat between 38.8  and 39.4),
  lng               double precision not null check (lng between -78.05 and -77.2),
  lat_public        double precision not null,
  lng_public        double precision not null,

  facility_name     text        check (char_length(facility_name)     <= 200),
  facility_operator text        check (char_length(facility_operator) <= 200),
  facility_status   facility_status not null default 'unknown',

  categories        text[] not null check (cardinality(categories) between 1 and 10),
  severity          smallint not null check (severity between 1 and 5),
  occurred_at       date     check (occurred_at <= (now() + interval '1 day')::date),
  description       text     not null
                      check (char_length(description) between 20 and 5000),
  other_notes       text     check (char_length(other_notes) <= 2000),

  photo_paths       text[] not null default '{}'
                      check (cardinality(photo_paths) <= 5),

  status            report_status not null default 'pending',
  moderation_note   text          check (char_length(moderation_note) <= 2000),
  moderated_at      timestamptz,
  moderated_by      uuid references auth.users (id) on delete set null
);

alter table public.reports drop constraint if exists reports_categories_known;
alter table public.reports add constraint reports_categories_known check (
  categories <@ array[
    'noise', 'air_quality', 'water', 'power', 'health',
    'property', 'light', 'traffic', 'wildlife', 'other'
  ]::text[]
);

create index if not exists reports_status_created_idx
  on public.reports (status, created_at desc);
create index if not exists reports_locality_idx
  on public.reports (locality) where status = 'approved';
create index if not exists reports_categories_idx
  on public.reports using gin (categories);

-- Who is making this change? Read straight from the JWT rather than calling
-- auth.uid(): this trigger runs as the caller, and depending on the caller
-- holding USAGE on the auth schema makes the update fail with "permission
-- denied for schema auth" on any project where that grant is absent.
create or replace function public.current_actor()
returns uuid language plpgsql stable as $$
declare claim text;
begin
  claim := nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub';
  if claim is null then return null; end if;
  return claim::uuid;
exception when others then
  return null;
end;
$$;

-- Derive the published coordinates, and force new rows to 'pending'.
create or replace function public.reports_before_insert()
returns trigger language plpgsql as $$
declare
  distance_m double precision;
  bearing    double precision;
begin
  -- A random offset of 100-200 m, so a pin can never be walked back to a house.
  distance_m := 100 + random() * 100;
  bearing    := random() * 2 * pi();

  new.lat_public := round((new.lat + (distance_m * cos(bearing)) / 111320.0)::numeric, 6);
  new.lng_public := round(
    (new.lng + (distance_m * sin(bearing))
      / greatest(111320.0 * cos(radians(new.lat)), 1.0))::numeric, 6);

  -- Nothing self-publishes, whatever the client sent.
  new.status          := 'pending';
  new.moderation_note := null;
  new.moderated_at    := null;
  new.moderated_by    := null;
  new.created_at      := now();
  return new;
end;
$$;

drop trigger if exists reports_before_insert on public.reports;
create trigger reports_before_insert
  before insert on public.reports
  for each row execute function public.reports_before_insert();

-- Re-jitter if a moderator corrects the location, so the offset is never
-- derivable by comparing an edited row against its published pin.
create or replace function public.reports_before_update()
returns trigger language plpgsql as $$
declare
  distance_m double precision;
  bearing    double precision;
begin
  if new.lat is distinct from old.lat or new.lng is distinct from old.lng then
    distance_m := 100 + random() * 100;
    bearing    := random() * 2 * pi();
    new.lat_public := round((new.lat + (distance_m * cos(bearing)) / 111320.0)::numeric, 6);
    new.lng_public := round(
      (new.lng + (distance_m * sin(bearing))
        / greatest(111320.0 * cos(radians(new.lat)), 1.0))::numeric, 6);
  end if;

  if new.status is distinct from old.status then
    new.moderated_at := now();
    new.moderated_by := public.current_actor();
  end if;
  return new;
end;
$$;

drop trigger if exists reports_before_update on public.reports;
create trigger reports_before_update
  before update on public.reports
  for each row execute function public.reports_before_update();

-- The public view. This is the ONLY thing the anon role can read.
-- security_invoker is left off (the default) so the view runs as its owner and
-- can read the base table despite RLS — which is exactly why it must not select
-- reporter_name, reporter_email, reporter_phone, address, lat or lng.
drop view if exists public.public_reports;

create view public.public_reports as
select
  id, created_at, locality, zip,
  lat_public  as lat,      -- deliberately aliased: no raw coordinate escapes
  lng_public  as lng,
  facility_name, facility_operator, facility_status,
  categories, severity, occurred_at, description, other_notes, photo_paths
from public.reports
where status = 'approved';
```

### A2 — Row-level security

The threat model: the anon key ships inside a public web app, so treat it as fully public.
These policies are the only thing between a stranger and the reporters' contact details.

```sql
alter table public.reports enable row level security;
-- Applies the policies to the table owner too. Without this, anything running
-- as the owner silently bypasses every rule below.
alter table public.reports force row level security;

-- The role is read from app_metadata, NOT user_metadata. user_metadata is
-- writable by the user themselves, so putting the role there would let anyone
-- who can sign up promote themselves to moderator.
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb
      -> 'app_metadata' ->> 'role', ''
  ) = 'admin';
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

drop policy if exists reports_anon_insert on public.reports;
drop policy if exists reports_admin_all   on public.reports;

create policy reports_anon_insert
  on public.reports for insert to anon, authenticated
  with check (status = 'pending');

-- Moderators get full access. There is deliberately no SELECT policy for anon:
-- with RLS on and no policy, a select returns zero rows rather than an error.
create policy reports_admin_all
  on public.reports for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

revoke all on public.reports from anon, authenticated;
grant insert on public.reports to anon, authenticated;
grant select, update, delete on public.reports to authenticated;
grant select on public.public_reports to anon, authenticated;
```

### A3 — Photo storage

```sql
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('report-photos', 'report-photos', false, 10485760,
        array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'])
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "report photos: anon upload to pending" on storage.objects;
drop policy if exists "report photos: admin read"   on storage.objects;
drop policy if exists "report photos: admin write"  on storage.objects;
drop policy if exists "report photos: admin delete" on storage.objects;

-- Write-only for the public, and only under pending/. The client generates an
-- unguessable UUID prefix per submission, so paths cannot be enumerated.
create policy "report photos: anon upload to pending"
  on storage.objects for insert to anon, authenticated
  with check (bucket_id = 'report-photos'
              and (storage.foldername(name))[1] = 'pending');

create policy "report photos: admin read"
  on storage.objects for select to authenticated
  using (bucket_id = 'report-photos' and public.is_admin());

create policy "report photos: admin write"
  on storage.objects for update to authenticated
  using (bucket_id = 'report-photos' and public.is_admin())
  with check (bucket_id = 'report-photos' and public.is_admin());

create policy "report photos: admin delete"
  on storage.objects for delete to authenticated
  using (bucket_id = 'report-photos' and public.is_admin());

-- Housekeeping. The privacy policy promises rejected reports and their photos
-- are deleted within 90 days; this is what implements that promise. Run it
-- periodically, or schedule it with pg_cron if the extension is enabled.
create or replace function public.purge_rejected_photos(older_than interval default '90 days')
returns integer language plpgsql security definer set search_path = public as $$
declare removed integer := 0;
begin
  with doomed as (
    select unnest(photo_paths) as path
      from public.reports
     where status = 'rejected'
       and coalesce(moderated_at, created_at) < now() - older_than
  )
  delete from storage.objects
   where bucket_id = 'report-photos'
     and name in (select path from doomed);

  get diagnostics removed = row_count;

  update public.reports
     set photo_paths = '{}'
   where status = 'rejected'
     and coalesce(moderated_at, created_at) < now() - older_than
     and cardinality(photo_paths) > 0;

  return removed;
end;
$$;

revoke all on function public.purge_rejected_photos(interval) from public, anon;
```

A note on signed URLs: `createSignedUrls()` runs in the Storage API rather than as the caller,
so an anonymous visitor can be issued a link to an approved photo even though they hold no
select policy of their own. If you'd rather not rely on that, the alternative is a second public
bucket holding only approved images, with the moderator copying files across on approval. The
single private bucket is simpler and keeps unreviewed photos strictly out of reach, which is the
more important property.

### A4 — Making yourself a moderator

`is_admin()` checks `app_metadata.role = 'admin'`. `app_metadata` cannot be written by the user
themselves — that's the whole point. If the role lived in `user_metadata`, anyone who could sign
up could promote themselves and read every reporter's contact details.

1. Supabase dashboard → Authentication → Users → Add user.
2. Select the user → edit **App Metadata** (not User Metadata) → set `{ "role": "admin" }`.
3. Sign out and back in — the role is read from the JWT, which is issued at sign-in.
4. Turn off public sign-ups: Authentication → Providers → Email → disable "Enable sign ups".

Never put the `service_role` key anywhere the browser can see it.

---

## Appendix B — Page copy

### B1 — Footer disclaimer (every page)

> **This is an independent community project.** It is not affiliated with, endorsed by, or
> operated by Loudoun County government, Erin Brockovich, or any data center owner or operator.
> Community reports are unverified first-hand accounts submitted by residents. They are not
> findings of fact, and they do not establish that any named company caused any condition
> described.
>
> Facility data © Loudoun County GIS. Basemap © OpenStreetMap contributors.

### B2 — Resources: filing with the county

Lead with this warning:

> **Reporting here is not a substitute for filing with the county.** Loudoun County does not
> monitor this site. A report here becomes part of a public record that residents, reporters and
> officials can look at — but only an official complaint creates an obligation for anyone to
> investigate. Please do both.

Then four cards. **These are real, verified contacts — use them exactly:**

| Situation | Channel |
|---|---|
| Noise audible indoors, happening right now | Sheriff's Office non-emergency: **703-777-1021**. Must be reported while it's happening so it can be witnessed. |
| Recurring noise, or any zoning issue | [Report a zoning violation](https://www.loudoun.gov/1751/Reporting-Zoning-Violations). Zoning Enforcement: **703-777-0246**, 1 Harrison Street SE, 3rd Floor, PO Box 7000, Leesburg, VA 20177. Loudoun enforces zoning **by complaint** — nothing is investigated unless somebody files. |
| Anything else — potholes, runoff, dust, traffic | [Loudoun Express Request (LEx)](https://www.loudoun.gov/3055/Report-an-Issue). Gives you a tracking number, worth keeping. |
| Policy and decisions | [Board of Supervisors](https://www.loudoun.gov/bos) — each of the 8 districts elects a supervisor. |

Reference links: [noise ordinance](https://www.loudoun.gov/4718/Noise-Ordinance) ·
[data center standards](https://www.loudoun.gov/5990/Data-Center-Standards-Locations) ·
[the county's own data center map](https://experience.arcgis.com/experience/0c2021535c3f47589d1a10d6d0e2948c) ·
[GeoHub open data](https://geohub-loudoungis.opendata.arcgis.com/) ·
[Virginia DEQ](https://www.deq.virginia.gov/) for air permits including generators.

### B3 — Making a report that carries weight

- **Write down the specifics.** Date, time, how long it lasted, wind direction, what you were
  doing when you noticed. A log kept over weeks is far more persuasive than one vivid
  description, because it shows a pattern.
- **Describe, don't characterise.** "A low hum I can hear in the back bedroom with the window
  shut, most nights after 11pm" does more work than "unbearable noise".
- **Be honest about what you don't know.** If you don't know which facility it is, say so. If
  your decibel reading came from a phone app, say that too — being upfront about its limits
  protects the credibility of everything else you say.
- **Talk to your neighbours.** Several independent reports from one street are much harder to
  dismiss than one.

### B4 — The nine FAQs

**Will my name or address appear anywhere?**
No. Your name, email, phone and street address are never published, never shown to other
visitors, and are not included in the data export. Only your district, ZIP code, the categories
you pick, your impact rating, your description and any photos are made public. Your map pin is
also deliberately placed 100–200 m away from the location you give, so nobody can work backwards
from the map to a house.

**Do I have to give my contact details?**
No — every field in that section is optional. They exist only so a moderator can come back to
you with a question before publishing. If you leave them blank and your report needs
clarification, it may be rejected rather than published, simply because there is no way to ask.

**Why doesn't my report show up straight away?**
Every report is read by a person before it is published. That is what keeps this map worth
looking at — without it, an open submission form on a public site fills with spam and abuse
within days. Expect a day or two.

**What gets a report rejected?**
Reports are not published if they name or identify a private individual; make an allegation of
illegality against a named company; are second-hand rather than your own experience; are outside
Loudoun County; or are abusive, automated or duplicated. Disagreeing with data center
development is not grounds for rejection. Describing a real experience in strong terms is not
either.

**Is this Erin Brockovich's project?**
No. This site is independent and unaffiliated. It is modelled on the approach taken by
brockovichdatacenter.com, which collects data center reports nationally, but it is not run by,
endorsed by or connected to that project or to Erin Brockovich. This one covers Loudoun County
only, and uses Loudoun County's own GIS data for the facility layer.

**Is this run by Loudoun County?**
No. It is an independent community project. The facility data comes from the county's public GIS
services, but the county does not operate this site, review it, or monitor what is submitted to
it. Filing here does not file anything with the county.

**Can I get my report removed?**
Yes, at any time and without giving a reason. Contact us with the reference number shown when
you submitted, or with the email address you used.

**Does a report here mean a company did something wrong?**
No. Reports are unverified first-hand accounts of what residents are experiencing. They are not
investigated, not corroborated, and not findings of fact. Ownership shown on facility pins comes
straight from public county land records and is frequently a holding company rather than the
business operating the site.

**I'm a journalist or researcher — can I use this data?**
Yes. There is a CSV export on the statistics page. Please describe it accurately: it is a
self-selected sample of resident-submitted accounts, not a survey, and should not be treated as
representative of the county.

### B5 — Privacy policy

**The short version.** Your name, email, phone number and street address are never published,
never shown to other visitors, and never included in the data export. Your map pin is
deliberately placed 100–200 m away from the location you give. Photos have their metadata
stripped in your browser before upload. You can have everything deleted at any time, without
giving a reason.

| Information | Stored | Published |
|---|---|---|
| Name, email, phone | Yes, if provided — all optional | **Never** |
| Street address | Yes, if provided — optional | **Never** |
| Exact coordinates | Yes | **Never** |
| Offset coordinates (100–200 m away) | Yes | Yes — this is what the map shows |
| District and ZIP code | Yes | Yes |
| Categories, impact rating, dates | Yes | Yes, after review |
| Description and notes | Yes | Yes, after review — as you wrote it |
| Photos | Yes, metadata removed | Yes, after review |

**Why the map pin is not where you are.** A map of exact addresses where people have complained
about their neighbours would be a liability for the people on it. So every report is plotted at
a random offset of roughly 100 to 200 metres in a random direction from the location you gave.
The offset is generated once, when the report is created, and the true coordinates are never
sent to anyone's browser. This is enough to keep the map accurate at the scale that matters —
which street, which neighbourhood, which side of a facility — while making it impossible to work
back from a pin to a household.

**Photos and hidden location data.** Phone cameras write GPS coordinates into photo files.
Publishing those would undo the offset entirely. Every image is therefore re-encoded in your own
browser before upload, which discards all embedded metadata. The original file never leaves your
device. If your browser cannot read an image — usually a HEIC on a non-Apple browser — the upload
is refused rather than passed through unprocessed. That is deliberate.

**What this site does not do.** No analytics, no tracking pixels, no advertising, no third-party
scripts. No cookies for tracking. Nothing sold, rented or shared with data brokers. Map tiles are
requested from OpenStreetMap, which necessarily sees your IP address, as it does for any site
using their tiles.

**How long things are kept.** Published reports are kept indefinitely — the value of this record
is that it builds up over years. Contact details are kept while the report is live and removed if
you ask. Rejected reports and their photos are deleted within 90 days.

**Your rights.** At any time and without giving a reason you can have your report removed; have
just your contact details removed, leaving the report published; ask for a copy of everything
held about you; or correct anything wrong. Requests are actioned within 30 days and usually much
sooner.

**Children.** This site is not intended for use by children, and reports should not be submitted
by anyone under 16.

### B6 — Terms of use

**What this site is.** An independent, volunteer-run project that maps data center facilities in
Loudoun County, Virginia using the county's public GIS data, and collects first-hand accounts
from residents about how those facilities affect them. It is **not** affiliated with, endorsed by
or operated by Loudoun County government, Erin Brockovich or the Brockovich Data Center Reporting
project, or any data center owner, operator or tenant.

**Community reports are unverified accounts.** Reports are submitted by members of the public
describing their own experiences. They are moderated for the standards below, but they are **not
investigated, measured, corroborated or verified**. A report is not a finding of fact. It does not
establish that any condition exists, that any company caused it, or that anyone has broken any law
or permit condition. Anyone relying on this data should treat it as a self-selected sample of
resident accounts and describe it that way.

**Facility information.** Locations, statuses, floor areas, zoning and ownership come directly
from Loudoun County GIS. Ownership fields reflect the recorded property owner in county land
records, which is frequently a holding company rather than the business operating the facility,
and which may be out of date. The presence of a facility on this map, next to a community report,
does not assert any connection between the two.

**Submitting a report.** By submitting you confirm that you are describing your own first-hand
experience; that what you have written is true to the best of your knowledge; that you own or have
permission to submit any photographs; that you are not identifying any private individual or
alleging illegal conduct by a named company; and that you are 16 or older.

**Permission to publish.** You keep ownership of everything you submit. You give this project a
non-exclusive, royalty-free permission to publish, display and distribute the non-private parts of
your report — description, categories, impact rating, district, ZIP, approximate location and
photographs. You are **not** giving permission to publish your name, contact details, street
address or exact location. You can withdraw this permission at any time by asking us to remove
your report.

**Using data from this site.** Published report data may be reused for journalism, research,
advocacy and civic purposes, provided it is attributed and described accurately as unverified
resident-submitted accounts. Do not use it to identify, contact or harass any individual or
household. Facility data belongs to Loudoun County GIS. Map tiles are © OpenStreetMap
contributors under the Open Database License.

**No warranty, no liability.** Provided as-is, by volunteers, with no warranty of accuracy,
completeness or availability. Nothing here is legal, medical, environmental or financial advice.

**Not an emergency service.** Nobody monitors this site in real time. If there is an immediate
risk to health or safety, call 911. For noise happening right now, call the Loudoun County
Sheriff's Office non-emergency line on 703-777-1021.

### B7 — About: data provenance

| Layer | Shown as | Source |
|---|---|---|
| Existing data center parcels | Operational · Under construction | Loudoun County GIS `Existing_Data_Center_Parcel/FeatureServer/1` |
| Pipeline data center areas | Proposed | Loudoun County GIS `Pipeline_Data_Center_Areas/FeatureServer/1` |
| Election districts | District filter & boundaries | Loudoun County GIS `COL/ElectionDistricts/MapServer/8` |
| Basemap tiles | The map itself | OpenStreetMap contributors |

The county refreshes the parcel layers roughly every six months; the current snapshot is dated
1 March 2026.

**A note on facility ownership.** Owner names are the property owner recorded in Loudoun County
land records. That is very often a holding company rather than the brand operating the building,
it can be out of date, and it says nothing about who is responsible for any condition a resident
reports. Treat it as a starting point for research, not as an accusation.

---

## Appendix C — Using a different builder

The prompts work nearly unchanged elsewhere; these are the differences worth knowing.

**v0 (Vercel).** Strongest at UI, weakest at data plumbing. It defaults to Next.js App Router
and shadcn/ui, so Prompt 1 works as-is. Leaflet needs `dynamic(() => import(...), { ssr: false })`
or it breaks on the server render. There's no built-in Supabase integration, so after Prompt 6
you'll wire `@supabase/supabase-js` by hand.

**Bolt.new.** Closest to Lovable. It runs the code in-browser via WebContainers, so you'll see
the real fetch to the county services succeed or fail immediately — useful for Prompt 2. Has
Supabase integration via StackBlitz.

**Replit Agent.** Best if you want a backend. Handles multi-step builds well but is slower.
Consider having it fetch the county layers server-side on a schedule and cache them, rather than
fetching in the browser each visit.

**Any of them.** Prompt 2 is the one that decides whether the project is real or fiction. Verify
the 224/103/36/85 counts before building anything on top.

---

## Appendix D — Gotchas

Things that went wrong building this the first time. Each one costs an hour if you meet it cold.

**Data**

- Both facility layers return **polygons, not points**. Compute area-weighted centroids of the
  largest ring — a bounding-box centre lands outside L-shaped parcels.
- One county record has the typo **`BULT/UNDER CONSTRUCTION`**. Match status by substring or you
  will silently drop it.
- County text is ALL CAPS. A "keep short words upper-case" title-casing rule turns **`BROAD RUN`
  into `Broad RUN`**. Use an explicit allow-list of initialisms instead.
- The pipeline layer has **no district field** — assign districts by point-in-polygon.
- Layer 3 is at `MapServer/8`, and the parcel layers are at `FeatureServer/1`, **not `/0`**.
  Requesting `/0` returns "layer not found".

**Map**

- Without a `cos(latitude)` correction on x, the county renders noticeably squashed.
- District labels in eastern Loudoun sit under a dense dot cluster. Give them a white halo via
  `paint-order: stroke fill`.
- Cap the marker entry cascade at ~120. Staggering all 224 makes the map feel slow to settle.

**Animation**

- `IntersectionObserver` callbacks get coalesced during fast scrolling. If a reveal sets
  `opacity: 0` and the callback is missed, that content is **stranded invisible permanently**.
  Use a throttled scroll + `getBoundingClientRect` check, or add a timeout failsafe.
- Under `prefers-reduced-motion`, use `animation: none` rather than a 0.01ms duration —
  animations with `both` fill mode otherwise flash their start state.

**Charts**

- A zero value must draw **no bar element at all**. Setting `width: 0` isn't enough if the bar
  has a `min-width`; the stub reads as "a small amount" rather than "none".

**Security**

- Put the moderator role in **`app_metadata`**, never `user_metadata` — users can write the
  latter themselves.
- Give anon **no SELECT policy on `reports` at all**. With RLS enabled and no policy, a select
  returns zero rows rather than an error, which is what you want.
- Test the security as an anonymous client, not as yourself in the dashboard. The dashboard uses
  the service role and bypasses everything.

**Part Two**

- **`overlaps` is a reserved word in PostgreSQL.** Declaring a plpgsql variable with that name
  fails with a syntax error pointing at the assignment, several lines away from the declaration
  that actually caused it. `natural`, `end`, `order` and `limit` bite the same way.
- **`cross join lateral unnest(categories)` multiplies rows.** A report with three categories
  becomes three rows, so `count(*)` over that join reports three times the real number of
  reports. Use `count(distinct r.id)`. This one is dangerous rather than merely wrong: it
  silently inflates every watchlist entry past the threshold.
- **The insert trigger forces `status = 'pending'`, including on your test fixtures.** Seeding
  approved reports directly gives you an empty watchlist and a confusing hour. Insert, then
  update, the way a moderator would.
- **`security definer` functions need `set search_path`.** Without it the function resolves
  names against the caller's path, which is the standard way these get exploited.
- **Nothing that reads `reporter_email` may return it.** `refresh_watchlist()` reads emails to
  count households and writes only an integer. Keep that property when you change it.
- **`marquee` is not an option for the ticker.** It is deprecated, unpausable and inaccessible.
  A CSS `translateX` animation on a duplicated track, with `prefers-reduced-motion` honoured and
  a real pause control, is barely more work.
- **`hidden` loses to any class that sets `display`.** The browser's own rule is
  `[hidden] { display: none }` at specificity (0,1,0), so `<div class="ticker" hidden>` where
  `.ticker { display: flex }` stays on screen — the dismiss button appears to do nothing, and an
  empty banner renders as a bar of whitespace. Add `[hidden] { display: none !important; }`
  once, globally. This is the case that keyword exists for.
- **Pause-on-`:focus-within` scoped to the whole ticker breaks the Play button.** Clicking Play
  leaves focus on the button, which is inside the ticker, so it stays paused until the reader
  clicks elsewhere. Scope the focus rule to the scrolling viewport, not the container.
- **Markers swallow map clicks.** With a measure or radius tool armed, a click that lands on a
  pin or a cluster never reaches the map — and in eastern Loudoun most of the map is pins. Set
  `pointer-events: none` on the marker and overlay panes while a tool is active.
- **A live region that collapses when empty shifts the layout every time it speaks.** Give the
  measure/radius readout a `min-height` of about one line.
- **Google News `<link>` values are redirect URLs**, not publisher URLs, and the encoding is
  undocumented. Store them as-is; do not try to unwrap them.
- **`VITE_`-prefixed environment variables are compiled into the client bundle.** An API key in
  one is a published API key. Edge Function secrets are a different mechanism and are not
  exposed.
- **A dead feed must not fail the refresh run.** Wrap each fetch in its own `try`; partial
  results beat none, and third-party feeds go down regularly.

**Numbers to check the build against**

| Check | Expected |
|---|---|
| Total facilities | 224 |
| Operational / under construction / proposed | 103 / 36 / 85 |
| Districts with facilities | 6 of 8 (Algonkian and Catoctin have none) |
| Sterling / Broad Run | 108 / 52 |
| Total floor area | ~114.4M sq ft |
| Jitter distance, measured over many inserts | 100–200 m, never 0 |
| Anon `select * from reports` | 0 rows or permission denied |
| Horizontal scroll at 320px | none, on every page |
| Elected representative layers | 8 county districts, 5 VA House, 2 VA Senate |
| Watchlist: 6 reports from 6 households | exactly 1 entry |
| Watchlist: 7 reports from 1 household | 0 entries |
| Watchlist: 6 unmoderated reports | 0 entries |
| Anon calling `refresh_watchlist()` | permission denied |

---


## Appendix E — The Part Two database schema

Run this after `01_schema.sql`, `02_rls.sql` and `03_storage.sql`. It adds the four tables
Part Two needs and the function that computes the watchlist.

I ran this file against PostgreSQL 16 with a Supabase-shaped shim before writing it down, and
checked the behaviour rather than the syntax: a cluster of six reports from six households
produces exactly one watchlist entry named after the facility at its centre; seven reports
from one household produce none; six approved-looking but unmoderated reports produce none;
four households produce none. `anon` can read the watchlist, cannot call the refresh
function, cannot read `public.reports`, and cannot insert a fake entry.

```sql
-- =============================================================================
-- Loudoun Data Center Watch — Part Two schema
--
-- Run after 01_schema.sql, 02_rls.sql and 03_storage.sql.
--
-- Adds the four tables Part Two needs — facilities, watchlist, news_items,
-- meetings — and the function that computes the watchlist.
--
-- The privacy model is unchanged and this file is careful not to weaken it.
-- refresh_watchlist() is the only thing here that reads public.reports, it is
-- SECURITY DEFINER for exactly one reason (counting distinct households needs
-- reporter_email), and it writes nothing but counts. anon can read the output
-- tables and nothing else.
-- =============================================================================

-- ---- Distance ---------------------------------------------------------------
-- Haversine in plain SQL. PostGIS would be the obvious tool, but it is a large
-- dependency for one function and the earthdistance extension needs cube, which
-- some managed setups restrict. This is accurate to a few metres over county
-- distances, which is far below the 100-200 m jitter already in the data.

create or replace function public.meters_between(
  lat1 double precision, lng1 double precision,
  lat2 double precision, lng2 double precision
) returns double precision
language sql immutable parallel safe as $$
  select 6371008.8 * 2 * asin(sqrt(
      power(sin(radians(lat2 - lat1) / 2), 2)
    + cos(radians(lat1)) * cos(radians(lat2))
    * power(sin(radians(lng2 - lng1) / 2), 2)
  ));
$$;

-- ---- Facilities -------------------------------------------------------------
-- A mirror of the county GIS layers, refreshed server-side. Part One reads
-- facilities from a static GeoJSON in the browser and that still works; this
-- table exists so the watchlist can name a cluster after the facility at its
-- centre, and so change detection has something to diff against.

create table if not exists public.facilities (
  id            text primary key,              -- county PIN or application number
  name          text not null,
  operator      text,
  status        facility_status not null default 'unknown',
  locality      text,
  lat           double precision not null,
  lng           double precision not null,
  sq_ft         bigint,
  application   text,                          -- EPLAN-2023-0083, ZMAP-2018-0015
  source_layer  text not null,
  first_seen_at timestamptz not null default now(),
  last_seen_at  timestamptz not null default now(),
  retired_at    timestamptz                    -- set when it drops out of the county layer
);

create index if not exists facilities_latlng_idx on public.facilities (lat, lng);
create index if not exists facilities_status_idx on public.facilities (status)
  where retired_at is null;

-- ---- Watchlist --------------------------------------------------------------

create table if not exists public.watchlist (
  id               uuid primary key default gen_random_uuid(),
  kind             text not null check (kind in ('facility', 'area')),
  label            text not null check (char_length(label) between 2 and 160),
  locality         text,
  facility_id      text references public.facilities (id) on delete set null,

  -- Cluster centre. For a facility cluster this is the facility. For an area
  -- cluster it is the published (jittered) location of the anchor report, which
  -- is deliberate: no exact address is ever the centre of a published circle.
  lat              double precision not null,
  lng              double precision not null,
  radius_m         integer not null default 3219,   -- 2 miles

  report_count     integer not null check (report_count     >= 0),
  household_count  integer not null check (household_count  >= 0),
  categories       text[]  not null default '{}',
  top_severity     smallint,

  first_report_at  timestamptz,
  latest_report_at timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create index if not exists watchlist_rank_idx on public.watchlist (report_count desc);

-- Thresholds live in one place so the rule can be changed without hunting.
-- 5 reports from 5 distinct households within 2 miles. Both halves matter:
-- one household filing five times is not a cluster.
create or replace function public.watchlist_config()
returns table (radius_m integer, min_reports integer, min_households integer)
language sql immutable as $$ select 3219, 5, 5 $$;

-- =============================================================================
-- refresh_watchlist()
--
-- SECURITY DEFINER because counting distinct households requires reading
-- reporter_email from public.reports, which no client role may do. Nothing it
-- writes contains an email, an exact coordinate, or any other private field.
--
-- Candidate centres are the reports themselves rather than a fixed grid: every
-- real cluster contains at least one report at its core, so scanning reports
-- finds the same clusters as a grid without inventing centres in empty fields.
-- Candidates are then taken strongest-first, and any candidate within one
-- radius of an already-accepted centre is dropped, so the output does not
-- contain five overlapping entries describing one cluster.
-- =============================================================================

create or replace function public.refresh_watchlist()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  cfg          record;
  candidate    record;
  accepted     integer := 0;
  centres      jsonb   := '[]'::jsonb;
  centre       jsonb;
  is_duplicate     boolean;
  near_facility record;
begin
  select * into cfg from public.watchlist_config();

  create temp table _candidates on commit drop as
  select
      anchor.id                                as anchor_id,
      anchor.lat_public                        as lat,
      anchor.lng_public                        as lng,
      anchor.locality                          as locality,
      count(distinct near.id)                  as report_count,
      count(distinct lower(trim(near.reporter_email)))
        filter (where near.reporter_email is not null and trim(near.reporter_email) <> '')
                                               as household_count,
      array_agg(distinct cat)                  as categories,
      max(near.severity)                       as top_severity,
      min(near.created_at)                     as first_report_at,
      max(near.created_at)                     as latest_report_at
    from public.reports anchor
    join public.reports near
      on near.status = 'approved'
     and public.meters_between(anchor.lat_public, anchor.lng_public,
                               near.lat_public,   near.lng_public) <= cfg.radius_m
    cross join lateral unnest(near.categories) as cat
   where anchor.status = 'approved'
   group by anchor.id, anchor.lat_public, anchor.lng_public, anchor.locality
  having count(distinct near.id) >= cfg.min_reports;

  delete from public.watchlist;

  for candidate in
    select * from _candidates
     where household_count >= cfg.min_households
     order by report_count desc, latest_report_at desc, anchor_id
  loop
    -- Drop candidates that describe a cluster already accepted.
    is_duplicate := false;
    for centre in select * from jsonb_array_elements(centres) loop
      if public.meters_between(candidate.lat, candidate.lng,
                               (centre ->> 'lat')::double precision,
                               (centre ->> 'lng')::double precision) <= cfg.radius_m then
        is_duplicate := true;
        exit;
      end if;
    end loop;
    continue when is_duplicate;

    -- Name it after the facility at its centre when there is one.
    select f.id, f.name, f.locality
      into near_facility
      from public.facilities f
     where f.retired_at is null
       and public.meters_between(candidate.lat, candidate.lng, f.lat, f.lng) <= cfg.radius_m
     order by public.meters_between(candidate.lat, candidate.lng, f.lat, f.lng)
     limit 1;

    insert into public.watchlist (
      kind, label, locality, facility_id, lat, lng, radius_m,
      report_count, household_count, categories, top_severity,
      first_report_at, latest_report_at
    ) values (
      case when near_facility.id is null then 'area' else 'facility' end,
      coalesce(near_facility.name, 'Near ' || coalesce(candidate.locality, 'Loudoun County')),
      coalesce(candidate.locality, near_facility.locality),
      near_facility.id,
      candidate.lat, candidate.lng, cfg.radius_m,
      candidate.report_count, candidate.household_count,
      candidate.categories, candidate.top_severity,
      candidate.first_report_at, candidate.latest_report_at
    );

    centres  := centres || jsonb_build_object('lat', candidate.lat, 'lng', candidate.lng);
    accepted := accepted + 1;
  end loop;

  return accepted;
end;
$$;

revoke all on function public.refresh_watchlist() from public, anon;

-- ---- News -------------------------------------------------------------------
-- Written only by the Edge Function, using the service role. Headline, source,
-- date and link. No article body: the site links to journalism, it does not
-- republish it.

create table if not exists public.news_items (
  id             uuid primary key default gen_random_uuid(),
  title          text not null check (char_length(title) between 3 and 400),
  url            text not null check (url ~ '^https?://'),
  source         text not null check (char_length(source) <= 120),
  topic          text not null default 'loudoun',
  published_at   timestamptz not null,
  fetched_at     timestamptz not null default now(),
  hidden         boolean not null default false,
  -- Normalised title, used to collapse the same wire story across mastheads.
  dedupe_key     text generated always as (
                   regexp_replace(lower(title), '[^a-z0-9]+', '', 'g')
                 ) stored,
  unique (dedupe_key)
);

create index if not exists news_recent_idx
  on public.news_items (published_at desc) where hidden = false;

-- ---- Meetings ---------------------------------------------------------------

create table if not exists public.meetings (
  id               text primary key,            -- the county EID
  title            text not null,
  body             text,                        -- Board of Supervisors, Planning Commission...
  starts_at        timestamptz not null,
  location         text,
  detail_url       text,
  agenda_url       text,
  stream_url       text,
  data_center_flag boolean not null default false,
  public_comment   boolean,
  fetched_at       timestamptz not null default now()
);

create index if not exists meetings_upcoming_idx on public.meetings (starts_at);

-- ---- RLS --------------------------------------------------------------------
-- Everything here is published aggregate or public-record data, so anon may
-- read it. Nothing here is writable by anon; the Edge Functions write with the
-- service role, which bypasses RLS.

alter table public.facilities  enable row level security;
alter table public.watchlist   enable row level security;
alter table public.news_items  enable row level security;
alter table public.meetings    enable row level security;

drop policy if exists "facilities: public read" on public.facilities;
drop policy if exists "watchlist: public read"  on public.watchlist;
drop policy if exists "news: public read"       on public.news_items;
drop policy if exists "meetings: public read"   on public.meetings;

create policy "facilities: public read" on public.facilities
  for select to anon, authenticated using (retired_at is null);

create policy "watchlist: public read" on public.watchlist
  for select to anon, authenticated using (true);

create policy "news: public read" on public.news_items
  for select to anon, authenticated using (hidden = false);

create policy "meetings: public read" on public.meetings
  for select to anon, authenticated using (true);

grant select on public.facilities, public.watchlist, public.news_items, public.meetings
  to anon, authenticated;

-- ---- Scheduling -------------------------------------------------------------
-- With pg_cron enabled (Database → Extensions in the Supabase dashboard):
--
--   select cron.schedule('watchlist-refresh', '17 * * * *',
--                        $cron$ select public.refresh_watchlist() $cron$);
--
-- Also call refresh_watchlist() from the moderation UI right after a report is
-- approved, so the ticker reflects a decision immediately rather than up to an
-- hour later.
--
-- Without pg_cron, invoke it from the same scheduled Edge Function that
-- refreshes news and meetings.
```

---

## Appendix F — The four Edge Functions

Part Two needs a server. Not much of one — four Supabase Edge Functions, which are Deno
TypeScript files you deploy with one command each and never think about again.

They exist because of three hard constraints, none of which prompting can talk its way around:

| Constraint | Why it forces a server |
|---|---|
| News and calendar feeds send no CORS headers | A browser `fetch()` to any of them fails, always |
| The Anthropic API key must stay secret | Anything in client JS, or in a `VITE_`-prefixed variable, is compiled into the bundle and public |
| Counting distinct households needs reporter emails | The browser must never receive them |

**Set the secrets once:**

```bash
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
# SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.
```

The service role key bypasses RLS. It belongs in Edge Function secrets and **nowhere else** —
not in `.env` in the repo, not in Lovable's environment variables panel if that panel feeds the
client bundle, not in a comment.

---

### F1 — `refresh-news`

Fetches the feeds, parses them, writes `news_items`. Run it hourly.

```ts
// supabase/functions/refresh-news/index.ts
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const GOOGLE_NEWS = 'https://news.google.com/rss/search'

// Each entry becomes one Google News query. Tag drives the topic filter chips.
const QUERIES: Array<{ topic: string; q: string }> = [
  { topic: 'loudoun',  q: '"data center" Loudoun' },
  { topic: 'virginia', q: '"data center" Virginia when:30d' },
  { topic: 'power',    q: 'data center electricity Dominion Virginia' },
  { topic: 'water',    q: 'data center water usage Virginia' },
  { topic: 'ai',       q: 'AI data center construction Virginia' },
  { topic: 'loudoun',  q: 'site:loudounnow.com "data center"' },
  { topic: 'loudoun',  q: 'site:loudountimes.com "data center"' },
]

// Outlets with their own working feeds. Filtered by keyword after fetching,
// because these are general news feeds, not data center feeds.
const DIRECT_FEEDS = [
  { topic: 'virginia', url: 'https://virginiamercury.com/feed/' },
  { topic: 'virginia', url: 'https://cardinalnews.org/feed/' },
  { topic: 'regional', url: 'https://wtop.com/feed/' },
]
const RELEVANT = /data\s?cent|datacent|hyperscale|AI infrastructure/i

const tag = (xml: string, name: string) => {
  // RSS uses CDATA about half the time. Handle both without a DOM parser —
  // Deno has no DOMParser for XML and pulling one in for four tags is silly.
  const m = xml.match(new RegExp(`<${name}[^>]*>([\\s\\S]*?)</${name}>`, 'i'))
  if (!m) return ''
  return m[1].replace(/^<!\[CDATA\[/, '').replace(/\]\]>$/, '').trim()
}

const decode = (s: string) =>
  s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
   .replace(/&#39;/g, "'").replace(/&nbsp;/g, ' ').replace(/&amp;/g, '&')

function parseItems(xml: string, topic: string) {
  const out = []
  for (const block of xml.match(/<item>[\s\S]*?<\/item>/gi) ?? []) {
    const rawTitle = decode(tag(block, 'title'))
    const link     = tag(block, 'link')
    const pubDate  = tag(block, 'pubDate')
    if (!rawTitle || !link) continue

    // Google News formats titles as "Headline - Publication". The <source>
    // element is more reliable when present, so prefer it.
    let title  = rawTitle
    let source = decode(tag(block, 'source'))
    const cut  = rawTitle.lastIndexOf(' - ')
    if (cut > 20) {
      title = rawTitle.slice(0, cut).trim()
      if (!source) source = rawTitle.slice(cut + 3).trim()
    }

    const published = pubDate ? new Date(pubDate) : new Date()
    if (isNaN(published.getTime())) continue

    out.push({
      title,
      url: link,
      source: source || 'Unknown',
      topic,
      published_at: published.toISOString(),
    })
  }
  return out
}

Deno.serve(async () => {
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
  )

  const items = []

  for (const { topic, q } of QUERIES) {
    const url = `${GOOGLE_NEWS}?q=${encodeURIComponent(q)}&hl=en-US&gl=US&ceid=US:en`
    try {
      const res = await fetch(url, { headers: { 'User-Agent': 'loudoun-dc-watch/1.0' } })
      if (res.ok) items.push(...parseItems(await res.text(), topic))
    } catch (err) {
      // One dead feed must not fail the run. Partial results beat none.
      console.error('feed failed', q, err)
    }
  }

  for (const { topic, url } of DIRECT_FEEDS) {
    try {
      const res = await fetch(url, { headers: { 'User-Agent': 'loudoun-dc-watch/1.0' } })
      if (res.ok) {
        items.push(...parseItems(await res.text(), topic).filter((i) => RELEVANT.test(i.title)))
      }
    } catch (err) {
      console.error('feed failed', url, err)
    }
  }

  // dedupe_key is a generated column with a unique index, so the same wire
  // story under three mastheads collapses to one row. ignoreDuplicates keeps
  // the first-seen version rather than churning the row on every run.
  const { error } = await supabase
    .from('news_items')
    .upsert(items, { onConflict: 'dedupe_key', ignoreDuplicates: true })

  const cutoff = new Date(Date.now() - 90 * 864e5).toISOString()
  await supabase.from('news_items').delete().lt('published_at', cutoff)

  return Response.json({ fetched: items.length, error: error?.message ?? null })
})
```

```bash
supabase functions deploy refresh-news --no-verify-jwt
```

Schedule it hourly with pg_cron:

```sql
select cron.schedule('news-refresh', '9 * * * *', $cron$
  select net.http_post(
    url     := 'https://<project-ref>.supabase.co/functions/v1/refresh-news',
    headers := '{"Authorization": "Bearer <anon-key>"}'::jsonb
  );
$cron$);
```

---

### F2 — `refresh-meetings`

Same shape, one feed:

```
https://www.loudoun.gov/RSSFeed.aspx?ModID=58&CID=All-calendar.xml
```

Parse `<item>` the same way. The `<link>` is `loudoun.gov/Calendar.aspx?EID=<id>` — use that
`EID` as the primary key so re-runs update rather than duplicate. Set `data_center_flag` when
the title or description matches `/data\s?cent|ZMAP|ZCPA|SPEX|rezon/i`. Upsert on `id`.

Run it every six hours; a county calendar does not change by the minute.

---

### F3 — `ai-assist`

One function, three modes. The key never leaves it.

```ts
// supabase/functions/ai-assist/index.ts
const MODEL = 'claude-opus-5'

const SYSTEM: Record<string, string> = {
  letter: `You help a Loudoun County, Virginia resident write to an elected official about data
center development near their home.

Write in the first person, as the resident, in plain language.

Absolute rules:
- Use ONLY the facts given to you in the user message. Invent nothing.
- Do not attribute intent, motive or blame to any company or person.
- Do not state legal conclusions or allege that anyone broke a law or permit.
- Do not cite studies, statistics or news the user did not supply.
- Under 350 words.

Structure: open with the writer's connection to the district; describe what they are
experiencing in their own words; make one specific, actionable ask; close politely. Return only
the letter body, with no preamble, no subject line, and no placeholders in brackets.`,

  application: `You explain a Loudoun County land-use application to a resident with no planning
background. Two to three sentences. Use only the record supplied. State what is proposed, how
large, and what stage it is at. Do not speculate about impacts, and do not characterise the
application as good or bad.`,

  record: `You summarise an elected official's public record on data center issues.

You will be given rows of sourced facts — votes, public statements, campaign contributions —
already published on the page. Summarise ONLY those rows in two short, neutral paragraphs.

Absolute rules:
- Add no fact that is not in the rows provided.
- Use nothing you may recall about this person from training. If the rows are thin, say the
  record is limited.
- Do not rate, rank, score or judge the official. Do not say they are good or bad on this issue.
- Attribute contributions as reported filings, not as influence.`,
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors })

  const { mode, facts } = await req.json()
  const system = SYSTEM[mode]
  if (!system) return Response.json({ error: 'unknown mode' }, { status: 400, headers: cors })

  const res = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'x-api-key': Deno.env.get('ANTHROPIC_API_KEY')!,
      'anthropic-version': '2023-06-01',
      'content-type': 'application/json',
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 1500,
      system,
      messages: [{ role: 'user', content: facts }],
      // Adaptive thinking is the current form. `budget_tokens` is rejected
      // outright on Opus 5, as are temperature, top_p and top_k.
      thinking: { type: 'adaptive' },
    }),
  })

  if (!res.ok) {
    console.error('anthropic error', res.status, await res.text())
    return Response.json({ error: 'generation failed' }, { status: 502, headers: cors })
  }

  const data = await res.json()
  const text = data.content
    .filter((b: { type: string }) => b.type === 'text')
    .map((b: { text: string }) => b.text)
    .join('')

  return Response.json({ text, model: MODEL }, { headers: cors })
})

const cors = {
  'Access-Control-Allow-Origin': '*',   // tighten to your domain in production
  'Access-Control-Allow-Headers': 'authorization, content-type',
}
```

Two things about that response parsing: with `thinking` enabled the `content` array contains
`thinking` blocks as well as `text` blocks, so filtering on `type === 'text'` is required, not
tidiness. And letters are short — if you raise `max_tokens` substantially, add `stream: true`
and read the SSE, or long requests will time out.

```bash
supabase functions deploy ai-assist
```

Rate-limit it. A table of `(ip_hash, minute, count)` checked at the top of the function is
enough, and it is the difference between an API bill you expected and one you did not.

---

### F4 — `refresh-county`

Pulls the four county GIS layers server-side, upserts `facilities`, sets `retired_at` on
anything that has dropped out of the source, and calls `refresh_watchlist()`. Run daily.

This is the same normalisation as Prompt 2 — the centroid maths, the `BULT/UNDER CONSTRUCTION`
substring match, the title-casing allow-list — just running on a schedule instead of on page
load. It is what makes change detection (Prompt 18.4) possible, because you cannot diff data you
never stored.

---

## Appendix G — Every data source, verified

Every URL in this document was fetched while writing it. This table records what came back, so
that when something breaks later you can tell whether it is your code or the source.

**CORS matters more than availability.** A source marked "no" cannot be fetched from the browser
at all, no matter how the request is written.

| Source | Endpoint | CORS | Notes |
|---|---|---|---|
| Data center parcels (existing) | `services1.arcgis.com/MxjRokvPm7bjslyR/.../Existing_Data_Center_Parcel/FeatureServer/1` | **yes** | 139 parcels |
| Data center parcels (pipeline) | `.../Pipeline_Data_Center_Areas/FeatureServer/1` | **yes** | 85 proposed |
| Building outlines | `.../Data_Center_Building_Outlines/FeatureServer/0` | **yes** | 271 buildings |
| By-right parcels | `.../ByRight_Data_Center_Parcels/FeatureServer/0` | **yes** | No public hearing required — newsworthy in itself |
| Approved applications | `.../Aprpoved_Applications_No_DC_Permits/FeatureServer/0` | **yes** | Application number, name, type, approval date. The typo in the layer name is the county's |
| Election districts | `logis.loudoun.gov/gis/rest/services/COL/ElectionDistricts/MapServer/8` | **yes** | Eight districts |
| **Land-use applications** | `logis.loudoun.gov/gis/rest/services/Projects/LOLA_DATA/MapServer/0` | **yes** | `LOLA_PLANS_POLY`. 20,299 cases; 476 with `DATA CENTER` in `PlanDescription`. Carries `PlanNumber`, `PlanType`, `PlanStatus`, `PlanApplicationDate`. This is the application tracker's source — but it also carries `AssignedTo`/`AssignedEmail` for county planners, which you should not republish |
| BOS meeting index | `loudoun.granicus.com/ViewPublisherRSS.php?view_id=92&mode=podcast` | **no** | Agendas and video only, capped at 100 items |
| BOS vote records | `lfportal.loudoun.gov/LFPortalinternet/rss/dbid/0/folder/{id}/feed.rss` | **no** | The RSS index is cookie-free; the PDFs behind it are not |
| **Elected representatives** | `.../ElectedReps_Data/FeatureServer/{0,1,2}` | **yes** | Layer 0 county, 1 VA House, 2 VA Senate. Names, parties, emails, phones, photos |
| Members of Congress | `unitedstates.github.io/congress-legislators/legislators-current.json` | **yes** | Filter to VA-10, VA-11 and both senators |
| Address geocoding | `nominatim.openstreetmap.org/search` | **yes** | 1 req/sec, descriptive User-Agent required |
| VA campaign finance | `apps.elections.virginia.gov/SBE_CSV/CF/{YYYY_MM}/ScheduleA.csv` | n/a | 41 MB bulk CSV. Server-side ingest only |
| County meeting calendar | `loudoun.gov/RSSFeed.aspx?ModID=58&CID=All-calendar.xml` | **no** | Edge Function required |
| Google News | `news.google.com/rss/search?q=...` | **no** | Edge Function required |
| Virginia Mercury | `virginiamercury.com/feed/` | **no** | Edge Function required |
| Cardinal News | `cardinalnews.org/feed/` | **no** | Edge Function required |
| WTOP | `wtop.com/feed/` | **no** | Edge Function required |
| VPAP | `vpap.org` | — | Blocks automated requests. Link to it; do not scrape it |

Two that look usable and are not:

- **`loudounnow.com/feed/` returns 404**, and `?feed=rss2` returns a 200 with no items. Reach
  Loudoun Now through the Google News `site:` query instead.
- **The Loudoun Times-Mirror `?f=rss` search feed works but is unfiltered**, and adding `q=`
  returns mostly SEO spam. Use the Google News `site:` query for that outlet too.

### Who currently holds each office

From the county's live layer at the time of writing. **Do not hard-code this** — read the layer.
It is here so you can tell at a glance whether your lookup is returning sense.

| District | Supervisor | Party | First elected |
|---|---|---|---|
| At-large (Chair) | Phyllis J. Randall | Democrat | 2015 |
| Algonkian | Juli E. Briskman | Democrat | 2019 |
| Ashburn | Michael R. Turner | Democrat | 2011 |
| Broad Run | Sylvia R. Glass | Democrat | 2019 |
| Catoctin | Caleb A. Kershner | Republican | 2019 |
| Dulles | Matthew F. Letourneau | Republican | 2011 |
| Leesburg | Kristen C. Umstattd | Democrat | 2015 |
| Little River | Laura A. TeKrony | Democrat | 2023 |
| Sterling | Koran T. Saines | Democrat | 2015 |

Virginia House districts 26 (JJ Singh), 27 (Atoosa R. Reaser), 28 (David A. Reid), 29 (Fernando
J. "Marty" Martinez) and 30 (John Chilton McAuliff). Virginia Senate districts 31 (Russet W.
Perry) and 32 (Kannan Srinivasan). US House VA-10 (Suhas Subramanyam) and VA-11 (James R.
Walkinshaw); Senators Mark R. Warner and Tim Kaine.

---

## Appendix H — Build order

If you cannot build everything, this is the order that produces a useful site soonest.

| Order | Feature | Why here |
|---|---|---|
| 1 | Map satellite and overlays (Prompt 10) | Biggest visible upgrade, no new data dependencies |
| 2 | Report detail and permalinks (Prompt 11) | Makes every report shareable — this is how the site spreads |
| 3 | Watchlist and ticker (Prompt 12) | Needs only reports you already have; makes the site feel alive |
| 4 | News feed (Prompt 13) | Your first Edge Function. Small, self-contained, gives people a reason to return |
| 5 | Meetings calendar (Prompt 17) | Reuses the same function and parser. High civic value for little work |
| 6 | "What's near me" (Prompt 18.1) | Uses data you already have; answers the question everyone arrives with |
| 7 | Facts and myths (Prompt 14) | No APIs. Bounded only by how fast a human can source the cards |
| 8 | Officials hub (Prompt 15) | The most work and the most editorial risk. Do it once the rest is solid |
| 9 | AI letter writer (Prompt 16) | Depends on the officials hub to know who to write to |
| 10 | Alerts (Prompt 18.2) | Needs email infrastructure and a scheduled job |

Two notes on that ordering.

**The watchlist is third for a reason.** It is the feature most likely to make someone open the
site a second time, and it costs you no new data source — it is a query over reports you already
have. Build it early.

**The officials hub is eighth for a reason.** It is the feature most likely to attract a
complaint from a press office. Build it when you have time to source every claim properly, not
in the same rush as everything else. If you find yourself about to publish a scorecard component
you cannot link to a document, ship the profiles without the score. Names, districts, contact
routes and the reports in their district are useful on their own, and none of it can be
contested.

---

## A last word on scope

The hardest part of this project is not the code. It is that the site collects accounts about
where people live, publishes them, and names the companies whose parcels sit nearby. The
coordinate jitter, the moderation queue, the EXIF stripping and the careful wording of the
disclaimers are not polish — they are what make it responsible to run at all.

Part Two raises the same question in a sharper form. A watchlist entry names a place and says
five households reported problems near it. An officials scorecard puts a number next to a living
person's name. Both are defensible — but only for as long as every one of them is traceable to a
moderated report or a primary document, and only for as long as the wording describes the record
rather than assigning blame. That is why the watchlist counts distinct households and only
approved reports, why the officials score is composed of sourced components rather than produced
by a language model, and why the AI features are confined to summarising material already on the
page.

If you cut something for time, cut an animation. If you cut something under pressure, cut the
scorecard before you cut the sourcing.
