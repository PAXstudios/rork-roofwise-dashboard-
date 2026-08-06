/*
 * Site configuration.
 *
 * Out of the box this file is empty of credentials, and the site runs in demo
 * mode: reports are stored in the browser's localStorage and a banner says so.
 * Filling in SUPABASE_URL and SUPABASE_ANON_KEY switches the whole site over to
 * the real backend — no other file needs to change.
 *
 * The anon key is designed to be public. It is safe to commit *only because*
 * the Row Level Security policies in sql/02_rls.sql restrict what it can do:
 * insert a pending report, read approved reports, nothing else. Never put the
 * service_role key in this file.
 *
 * See README.md → "Connecting Supabase" for the five-minute setup.
 */

window.LDCW_CONFIG = {
  /* ---- Backend ---------------------------------------------------------- */

  SUPABASE_URL: "",
  SUPABASE_ANON_KEY: "",

  /* Storage bucket that holds report photos. Created by sql/03_storage.sql. */
  STORAGE_BUCKET: "report-photos",

  /* ---- Submission limits ------------------------------------------------ */

  MAX_PHOTOS: 5,
  MAX_PHOTO_BYTES: 10 * 1024 * 1024, // 10 MB per file, before re-encoding
  MAX_PHOTO_DIMENSION: 2000, // px on the long edge; larger images are scaled down

  /* Anti-spam. A form filled in faster than a human could read it, or a burst
     of submissions from one browser, is almost always automated. */
  MIN_SUBMIT_SECONDS: 5,
  RATE_LIMIT_SECONDS: 60,
  RATE_LIMIT_PER_DAY: 5,

  /* ---- Map -------------------------------------------------------------- */

  /* Loudoun County, centred on the Ashburn/Sterling data center corridor. */
  MAP_CENTER: [39.03, -77.48],
  MAP_ZOOM: 11,
  MAP_MIN_ZOOM: 9,
  MAP_BOUNDS: [
    [38.8, -78.05],
    [39.35, -77.2],
  ],

  TILE_URL: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
  TILE_ATTRIBUTION:
    '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',

  /* Nominatim is free but rate-limited to roughly one request per second and
     forbids bulk use. We only ever call it on an explicit button press. */
  GEOCODE_URL: "https://nominatim.openstreetmap.org/search",
  GEOCODE_MIN_INTERVAL_MS: 1100,

  /* How far a published pin is offset from the address the resident gave, in
     metres. Protects the household while keeping the map meaningful. */
  LOCATION_JITTER_MIN_M: 100,
  LOCATION_JITTER_MAX_M: 200,

  /* ---- Contact ---------------------------------------------------------- */

  /* Shown on the site for corrections, takedowns and data requests. Replace
     with a real address before publishing. */
  CONTACT_EMAIL: "",
};
