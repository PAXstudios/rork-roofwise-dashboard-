# Building Loudoun Data Center Watch in Lovable

A complete handoff for rebuilding this site inside an AI website builder.

Written for **Lovable** (React + Vite + Tailwind + shadcn/ui + its native Supabase
integration). Appendix C covers what changes for v0, Bolt or Replit.

---

## How to use this file

**Do not paste the whole thing.** Lovable produces much better results from a sequence of
focused prompts than from one wall of text — it builds, you look, you correct, then you move on.

Work through Prompts 1 → 9 in order. After each one, check it did what you asked before
continuing. Appendices A and B are things you paste when a prompt tells you to.

Rough timing: Prompts 1–4 get you a working map, which is about an hour. The whole sequence
including Supabase is half a day.

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

---

## A last word on scope

The hardest part of this project is not the code. It is that the site collects accounts about
where people live, publishes them, and names the companies whose parcels sit nearby. The
coordinate jitter, the moderation queue, the EXIF stripping and the careful wording of the
disclaimers are not polish — they are what make it responsible to run at all.

If you cut something for time, cut an animation.
