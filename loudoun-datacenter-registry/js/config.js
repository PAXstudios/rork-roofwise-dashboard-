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

  /* Basemaps offered by the switcher. Every one of these was fetched and
     returns real imagery with no API key and no billing account.

     Mind the axis order: the Esri and USGS ArcGIS tile services put y before x
     ({z}/{y}/{x}), while OpenStreetMap puts x first. Swapping them doesn't
     error — it quietly renders a map of somewhere else entirely.

     `attribution` is a licence condition on all three providers, not a credit
     we're being polite about. Leaflet swaps it automatically with the layer. */
  BASEMAPS: [
    {
      key: "streets",
      label: "Streets",
      hint: "Street names and neighbourhood context",
      url: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
      attribution:
        '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
      maxZoom: 19,
      dark: false,
    },
    {
      key: "satellite",
      label: "Satellite",
      hint: "The buildings, parking, substations and cleared land as they are",
      url:
        "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/" +
        "MapServer/tile/{z}/{y}/{x}",
      attribution:
        "Tiles &copy; Esri &mdash; Source: Esri, Maxar, Earthstar Geographics, and the GIS User Community",
      // The service advertises detail levels to 23 and serves real tiles past
      // 19. Parcel-level inspection is the whole point of the satellite view,
      // so don't cap it at the default.
      maxZoom: 21,
      dark: true,
    },
    {
      key: "topo",
      label: "Topographic",
      hint: "Terrain, watersheds and elevation",
      url:
        "https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/" +
        "MapServer/tile/{z}/{y}/{x}",
      attribution: "Tiles &copy; Esri &mdash; Source: Esri and the GIS User Community",
      maxZoom: 19,
      dark: false,
    },
    {
      key: "hillshade",
      label: "Terrain relief",
      hint: "Ridgelines and valleys — relevant to how noise carries",
      url:
        "https://server.arcgisonline.com/ArcGIS/rest/services/Elevation/World_Hillshade/" +
        "MapServer/tile/{z}/{y}/{x}",
      attribution: "Tiles &copy; Esri &mdash; Source: Esri, USGS, NOAA",
      maxZoom: 16,
      dark: false,
    },
    {
      key: "canvas",
      label: "Muted",
      hint: "Low-contrast base, so the data reads clearly",
      url:
        "https://server.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/" +
        "MapServer/tile/{z}/{y}/{x}",
      attribution: "Tiles &copy; Esri &mdash; Source: Esri, HERE, Garmin",
      maxZoom: 16,
      dark: false,
    },
    {
      key: "usgs",
      label: "USGS aerial",
      hint: "US government imagery, independent of Esri",
      url:
        "https://basemap.nationalmap.gov/arcgis/rest/services/USGSImageryOnly/" +
        "MapServer/tile/{z}/{y}/{x}",
      attribution: "Tiles courtesy of the U.S. Geological Survey",
      maxZoom: 16,
      dark: true,
    },
  ],

  /* ---- Watchlist ---------------------------------------------------------
     A location is flagged when enough independent households report problems
     near it. Both thresholds matter: five reports from one household is one
     household, not a cluster, and treating it as one would let anybody
     manufacture a public flag against a named company by using the form five
     times.

     The radius is deliberately much larger than LOCATION_JITTER_MAX_M — two
     miles is sixteen to thirty-two times the offset — so clustering the
     published pins gives the same answer as clustering real addresses without
     ever needing a real address. Shrinking it below about half a mile breaks
     that property. */
  WATCHLIST_RADIUS_M: 3219,
  WATCHLIST_MIN_REPORTS: 5,
  WATCHLIST_MIN_HOUSEHOLDS: 5,
  WATCHLIST_TICKER_MAX: 10,

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
