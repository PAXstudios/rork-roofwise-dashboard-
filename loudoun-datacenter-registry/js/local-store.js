/*
 * Demo backend — localStorage.
 *
 * Used whenever js/config.js has no Supabase credentials, so a fresh clone of
 * this repository is fully explorable without setting anything up. Reports
 * submitted in this mode live in one browser and nowhere else.
 *
 * The seed rows below are ILLUSTRATIVE EXAMPLES, not real submissions. They
 * exist so the map, list and statistics pages have something to render. Every
 * one carries is_demo: true, the UI badges them as samples, and connecting a
 * Supabase project makes them disappear entirely.
 */

window.LDCW = window.LDCW || {};

(function (LDCW) {
  "use strict";

  var STORAGE_KEY = "ldcw:reports";
  var RATE_KEY = "ldcw:submissions";

  /* ---- Seed data ---------------------------------------------------------
     Coordinates sit in the residential areas bordering the Sterling, Ashburn
     and Leesburg data center clusters. Descriptions paraphrase the categories
     of concern documented in Loudoun County board meetings and local news
     coverage; they are not quotes from, or attributable to, any real person. */

  function daysAgo(days) {
    return new Date(Date.now() - days * 86400000).toISOString();
  }

  function dateDaysAgo(days) {
    return new Date(Date.now() - days * 86400000).toISOString().slice(0, 10);
  }

  var SEED = [
    {
      locality: "Sterling",
      zip: "20166",
      lat_public: 39.0246,
      lng_public: -77.4012,
      facility_name: "Campus off Shaw Road",
      facility_status: "operational",
      categories: ["noise", "health"],
      severity: 5,
      occurred_at: dateDaysAgo(4),
      created_at: daysAgo(3),
      description:
        "Constant low hum from the cooling equipment, day and night. It changed about a year ago and now it carries into the bedrooms at the back of the house. We sleep with a fan running to mask it and still wake up at 3am most nights.",
      other_notes: "Worst on still, humid evenings.",
    },
    {
      locality: "Sterling",
      zip: "20164",
      lat_public: 39.0318,
      lng_public: -77.3928,
      facility_name: null,
      facility_status: "operational",
      categories: ["air_quality", "noise", "health"],
      severity: 5,
      occurred_at: dateDaysAgo(11),
      created_at: daysAgo(10),
      description:
        "Generator testing ran for most of a morning. The noise was loud enough that we could not hold a conversation in the back yard, and there was a strong diesel smell that lingered for hours afterwards. My daughter has asthma and we kept her inside all day.",
      other_notes: "Happens roughly monthly, usually on a weekday morning.",
    },
    {
      locality: "Broad Run",
      zip: "20147",
      lat_public: 39.0421,
      lng_public: -77.4655,
      facility_name: "Beaumeade area",
      facility_status: "operational",
      categories: ["noise"],
      severity: 3,
      occurred_at: dateDaysAgo(20),
      created_at: daysAgo(19),
      description:
        "Steady mechanical hum audible from the yard whenever the wind comes from the north. Not unbearable inside the house with the windows shut, but it has taken away sitting outside in the evening, which is why we bought here.",
      other_notes: null,
    },
    {
      locality: "Ashburn",
      zip: "20148",
      lat_public: 39.0075,
      lng_public: -77.5116,
      facility_name: null,
      facility_status: "under_construction",
      categories: ["traffic", "light", "noise"],
      severity: 4,
      occurred_at: dateDaysAgo(8),
      created_at: daysAgo(7),
      description:
        "Construction traffic starts before 6am and the site floodlights stay on all night. Our street was not built for this many heavy trucks and the shoulder is breaking up where they turn in. The lighting is bright enough to read by in our upstairs bedroom.",
      other_notes: "Have raised it with the site office twice with no change.",
    },
    {
      locality: "Leesburg",
      zip: "20175",
      lat_public: 39.0691,
      lng_public: -77.5442,
      facility_name: null,
      facility_status: "proposed",
      categories: ["property", "wildlife"],
      severity: 4,
      occurred_at: dateDaysAgo(35),
      created_at: daysAgo(33),
      description:
        "A proposal has gone in for the parcel that backs onto our subdivision. The tree line that screens us would come out. Two neighbours who were preparing to sell have taken their houses off the market until they know what happens with the application.",
      other_notes: "Zoning case number is on the county pipeline map.",
    },
    {
      locality: "Sterling",
      zip: "20166",
      lat_public: 39.0159,
      lng_public: -77.4106,
      facility_name: null,
      facility_status: "operational",
      categories: ["water"],
      severity: 3,
      occurred_at: dateDaysAgo(48),
      created_at: daysAgo(46),
      description:
        "Our well pressure has dropped noticeably over the last two summers. I have no way to prove a connection to anything nearby, but I am recording it here because several people on our road have described the same change over the same period.",
      other_notes: "Well was drilled in 2004 and had been stable until recently.",
    },
    {
      locality: "Dulles",
      zip: "20166",
      lat_public: 38.9885,
      lng_public: -77.4693,
      facility_name: null,
      facility_status: "under_construction",
      categories: ["traffic", "wildlife"],
      severity: 3,
      occurred_at: dateDaysAgo(26),
      created_at: daysAgo(24),
      description:
        "Clearing work took out a mature tree line along the property boundary in a single week. Since then the runoff after heavy rain crosses the road instead of soaking away, and there is standing water at the bottom of the field that was never there before.",
      other_notes: null,
    },
    {
      locality: "Broad Run",
      zip: "20147",
      lat_public: 39.0502,
      lng_public: -77.4507,
      facility_name: null,
      facility_status: "operational",
      categories: ["power"],
      severity: 2,
      occurred_at: dateDaysAgo(15),
      created_at: daysAgo(14),
      description:
        "Short flickers and two brief outages in the last month, which we did not use to get. Nothing long enough to spoil food, but enough to reset every clock in the house and drop the home office connection mid-call.",
      other_notes: null,
    },
    {
      locality: "Sterling",
      zip: "20164",
      lat_public: 39.0288,
      lng_public: -77.3855,
      facility_name: null,
      facility_status: "operational",
      categories: ["noise", "health", "property"],
      severity: 4,
      occurred_at: dateDaysAgo(6),
      created_at: daysAgo(5),
      description:
        "Measured 61 dB in the back garden on a phone app at 11pm on a weeknight. I know a phone is not a calibrated meter, which is why I am logging it here rather than making a claim about the legal limit. It is a real change from a few years ago.",
      other_notes: "Happy to be contacted if anyone is collecting proper measurements.",
    },
    {
      locality: "Little River",
      zip: "20105",
      lat_public: 38.9612,
      lng_public: -77.5488,
      facility_name: null,
      facility_status: "proposed",
      categories: ["water", "wildlife", "traffic"],
      severity: 3,
      occurred_at: dateDaysAgo(55),
      created_at: daysAgo(52),
      description:
        "Application filed for a site upstream of the creek that runs through our property. The concern raised at the community meeting was runoff and the volume of construction traffic on a road with no shoulder and a school bus stop.",
      other_notes: null,
    },
    {
      locality: "Ashburn",
      zip: "20147",
      lat_public: 39.0338,
      lng_public: -77.4881,
      facility_name: null,
      facility_status: "operational",
      categories: ["light"],
      severity: 2,
      occurred_at: dateDaysAgo(41),
      created_at: daysAgo(39),
      description:
        "Security lighting on the perimeter points outward rather than down, so it throws light straight across the road into the front of the houses opposite. Blackout curtains have mostly solved it for us but it should not be necessary.",
      other_notes: null,
    },
    {
      locality: "Sterling",
      zip: "20166",
      lat_public: 39.0203,
      lng_public: -77.3971,
      facility_name: null,
      facility_status: "operational",
      categories: ["air_quality", "health"],
      severity: 4,
      occurred_at: dateDaysAgo(2),
      created_at: daysAgo(1),
      description:
        "Diesel smell strong enough to notice indoors with the windows closed, lasting most of the afternoon. Both of us had headaches by the evening. I do not know which site it came from, only the direction the wind was blowing.",
      other_notes: null,
    },
    {
      locality: "Leesburg",
      zip: "20176",
      lat_public: 39.1204,
      lng_public: -77.5291,
      facility_name: null,
      facility_status: "under_construction",
      categories: ["noise", "traffic"],
      severity: 3,
      occurred_at: dateDaysAgo(18),
      created_at: daysAgo(17),
      description:
        "Pile driving and grading noise from roughly 7am, six days a week. It is construction so we expect it to end eventually, but nobody told the neighbourhood how long the schedule runs and calls to the county have not produced an answer.",
      other_notes: null,
    },
    {
      locality: "Broad Run",
      zip: "20147",
      lat_public: 39.0466,
      lng_public: -77.4402,
      facility_name: null,
      facility_status: "operational",
      categories: ["property"],
      severity: 3,
      occurred_at: dateDaysAgo(70),
      created_at: daysAgo(66),
      description:
        "Two prospective buyers walked out of viewings after hearing the noise from the garden. The agent now advises us to schedule viewings for mid-morning when it is quieter. The house has been on the market for four months.",
      other_notes: null,
    },

    /* The five below sit within about a mile of each other in Ashburn. They
       exist so the demo shows a second watchlist cluster forming, which is the
       behaviour the site is actually for — one household is an anecdote, five
       within two miles is a pattern worth a look. Illustrative like the rest of
       this seed, and labelled Sample everywhere it appears. */
    {
      locality: "Ashburn",
      zip: "20147",
      lat_public: 39.0432,
      lng_public: -77.4871,
      facility_name: null,
      facility_status: "under_construction",
      categories: ["noise", "traffic"],
      severity: 4,
      occurred_at: dateDaysAgo(12),
      created_at: daysAgo(11),
      description:
        "Construction traffic starts on our road before six in the morning. It is not the work itself so much as the queue of trucks idling at the junction waiting for the site to open. We have asked about a staging area away from the houses and been told it is being looked at.",
      other_notes: "Counted 22 trucks between 5:50 and 6:40 on a Tuesday.",
    },
    {
      locality: "Ashburn",
      zip: "20147",
      lat_public: 39.0489,
      lng_public: -77.4802,
      facility_name: null,
      facility_status: "operational",
      categories: ["noise"],
      severity: 3,
      occurred_at: dateDaysAgo(9),
      created_at: daysAgo(8),
      description:
        "A steady hum on still evenings that was not there two years ago. It is not loud but it does not stop, and once you have noticed it you cannot stop noticing it. Worse when the wind is from the east.",
      other_notes: null,
    },
    {
      locality: "Ashburn",
      zip: "20148",
      lat_public: 39.0361,
      lng_public: -77.4795,
      facility_name: null,
      facility_status: "operational",
      categories: ["power", "noise"],
      severity: 4,
      occurred_at: dateDaysAgo(6),
      created_at: daysAgo(5),
      description:
        "Our lights dipped four times in one evening last week. The utility said there was no fault on our line. I do not know what causes it and I am not claiming to, but I have started writing down the dates because several neighbours have mentioned the same thing.",
      other_notes: "Dates so far: the 2nd, 4th, 9th and 11th.",
    },
    {
      locality: "Ashburn",
      zip: "20147",
      lat_public: 39.0524,
      lng_public: -77.4913,
      facility_name: null,
      facility_status: "proposed",
      categories: ["light", "wildlife"],
      severity: 3,
      occurred_at: dateDaysAgo(20),
      created_at: daysAgo(18),
      description:
        "The security lighting on the site behind us stays on all night and washes across the back of the house. We used to see deer crossing the field at dusk and have not seen them since the spring.",
      other_notes: "Blackout blinds fitted in two bedrooms in March.",
    },
    {
      locality: "Ashburn",
      zip: "20148",
      lat_public: 39.0398,
      lng_public: -77.4736,
      facility_name: null,
      facility_status: "under_construction",
      categories: ["water", "traffic"],
      severity: 2,
      occurred_at: dateDaysAgo(28),
      created_at: daysAgo(26),
      description:
        "The stream at the bottom of the common land runs brown after heavy rain now, which it did not before the clearing work started upstream. I have photographed it twice. It clears within a day or so each time.",
      other_notes: null,
    },
  ];

  function buildSeed() {
    return SEED.map(function (row, index) {
      return Object.assign({}, row, {
        id: "demo-" + String(index + 1).padStart(3, "0"),
        photo_urls: [],
        status: "approved",
        is_demo: true,
      });
    });
  }

  /* ---- Storage ----------------------------------------------------------- */

  function readAll() {
    var raw;
    try {
      raw = localStorage.getItem(STORAGE_KEY);
    } catch (err) {
      // Storage blocked (private mode, embedded browser). Fall back to seed
      // data held in memory for this page view.
      return buildSeed();
    }

    if (!raw) {
      var seeded = buildSeed();
      writeAll(seeded);
      return seeded;
    }

    try {
      var parsed = JSON.parse(raw);
      return Array.isArray(parsed) ? parsed : buildSeed();
    } catch (err) {
      return buildSeed();
    }
  }

  function writeAll(rows) {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(rows));
    } catch (err) {
      /* Over quota or blocked — the submission stays in memory only. */
    }
  }

  function sortNewestFirst(rows) {
    return rows.slice().sort(function (a, b) {
      return new Date(b.created_at) - new Date(a.created_at);
    });
  }

  /* ---- Rate limiting -----------------------------------------------------
     Only a speed bump — a browser-side limit can be cleared by anyone who
     wants to. Moderation is what actually protects the public data. */

  function recentSubmissions() {
    try {
      var raw = localStorage.getItem(RATE_KEY);
      var list = raw ? JSON.parse(raw) : [];
      var dayAgo = Date.now() - 86400000;
      return (Array.isArray(list) ? list : []).filter(function (ts) {
        return ts > dayAgo;
      });
    } catch (err) {
      return [];
    }
  }

  function recordSubmission() {
    try {
      var list = recentSubmissions();
      list.push(Date.now());
      localStorage.setItem(RATE_KEY, JSON.stringify(list));
    } catch (err) {
      /* Not fatal. */
    }
  }

  function checkRateLimit() {
    var config = window.LDCW_CONFIG || {};
    var list = recentSubmissions();

    if (list.length >= (config.RATE_LIMIT_PER_DAY || 5)) {
      throw new Error(
        "You've submitted several reports today. Please come back tomorrow, or email us if you have more to add."
      );
    }

    var last = list[list.length - 1];
    var gap = (config.RATE_LIMIT_SECONDS || 60) * 1000;
    if (last && Date.now() - last < gap) {
      var wait = Math.ceil((gap - (Date.now() - last)) / 1000);
      throw new Error("Please wait " + wait + " more seconds before submitting another report.");
    }
  }

  /* ---- Photos ------------------------------------------------------------
     Demo mode keeps photos as data URLs so previews survive a page reload,
     but caps how many to avoid blowing the ~5 MB localStorage quota. */

  function fileToDataUrl(file) {
    return new Promise(function (resolve, reject) {
      var reader = new FileReader();
      reader.onload = function () {
        resolve(reader.result);
      };
      reader.onerror = function () {
        reject(new Error("Could not read " + file.name));
      };
      reader.readAsDataURL(file);
    });
  }

  /* ---- Public interface --------------------------------------------------
     Mirrors supabase-store.js exactly. */

  LDCW.LocalStore = {
    mode: "local",

    isDemo: true,

    listApproved: function (filter) {
      var schema = LDCW.schema;
      // toPublicReport is what makes the demo backend behave like the Supabase
      // public_reports view: it drops anything private and surfaces the
      // jittered coordinates as plain lat/lng, which is what the map reads.
      var rows = readAll()
        .filter(function (row) {
          return row.status === "approved";
        })
        .map(schema.toPublicReport)
        .filter(function (row) {
          return schema.matchesFilter(row, filter);
        });
      return Promise.resolve(sortNewestFirst(rows));
    },

    getReport: function (id) {
      var found = readAll().filter(function (row) {
        return row.id === id && row.status === "approved";
      })[0];
      return Promise.resolve(found ? LDCW.schema.toPublicReport(found) : null);
    },

    /* ---- Watchlist source ---------------------------------------------------
       The watchlist needs to count distinct *households*, not distinct reports,
       and that means touching the reporter's email — which is exactly what the
       public shape strips out.

       In demo mode every record already lives in this browser, so the
       computation runs here. In production it cannot: anon holds no read on the
       base table at all, so the same arithmetic runs inside the database as
       refresh_watchlist() and the browser only ever reads the aggregate. See
       sql/05_parttwo.sql.

       What leaves this function is a household *key*, never an address. The
       key is the lower-cased email where one was given, and the report's own id
       where it wasn't — so a report submitted without contact details counts
       toward the report total but cannot, on its own, stand in for a
       neighbour. */
    watchlistSource: function () {
      var schema = LDCW.schema;
      var rows = readAll()
        .filter(function (row) {
          return row.status === "approved";
        })
        .map(function (row) {
          var email = (row.reporter_email || "").trim().toLowerCase();
          var pub = schema.toPublicReport(row);
          // The fourteen seed reports are written as fourteen different
          // residents and carry no email, so each stands in for its own
          // household. Real submissions without an email do too — but see
          // hasContact below, which is what the strict count uses.
          pub.household_key = email || row.id;
          pub.has_contact = Boolean(email) || row.is_demo === true;
          return pub;
        });
      return Promise.resolve(rows);
    },

    submitReport: function (draft, files) {
      try {
        checkRateLimit();
      } catch (err) {
        return Promise.reject(err);
      }

      var pending = (files || []).slice(0, (window.LDCW_CONFIG || {}).MAX_PHOTOS || 5);

      return Promise.all(pending.map(fileToDataUrl)).then(function (urls) {
        var jittered = LDCW.schema.jitterCoordinates(Number(draft.lat), Number(draft.lng));
        var id = "local-" + Date.now().toString(36);

        var row = {
          id: id,
          created_at: new Date().toISOString(),
          locality: draft.locality,
          zip: draft.zip || null,
          lat_public: jittered.lat,
          lng_public: jittered.lng,
          facility_name: draft.facility_name || null,
          facility_ids: draft.facility_ids || [],
          facility_operator: draft.facility_operator || null,
          facility_status: draft.facility_status || "unknown",
          categories: draft.categories || [],
          severity: Number(draft.severity),
          occurred_at: draft.occurred_at || null,
          description: (draft.description || "").trim(),
          other_notes: (draft.other_notes || "").trim() || null,
          photo_urls: urls,
          // Submissions start pending here too, so demo mode demonstrates the
          // real moderation behaviour rather than a shortcut.
          status: "pending",
          is_demo: false,
        };

        // Contact details are deliberately not persisted in demo mode. There is
        // no moderator to read them and no reason to leave them in a browser.

        var rows = readAll();
        rows.push(row);
        writeAll(rows);
        recordSubmission();

        return { id: id, status: "pending" };
      });
    },

    /* ---- Moderation (demo mode lets you try the queue without an account) */

    signIn: function () {
      return Promise.reject(
        new Error(
          "Demo mode has no accounts. Connect a Supabase project to enable moderator sign-in."
        )
      );
    },

    signOut: function () {
      return Promise.resolve();
    },

    currentUser: function () {
      return Promise.resolve(null);
    },

    listPending: function (options) {
      var wanted = (options && options.status) || "pending";
      var rows = readAll()
        .filter(function (row) {
          return row.status === wanted;
        })
        .map(function (row) {
          // Moderators see the full row, plus lat/lng in the shape the map and
          // cards expect.
          return Object.assign({}, row, {
            lat: row.lat_public,
            lng: row.lng_public,
            photo_urls: row.photo_urls || [],
          });
        });
      return Promise.resolve(sortNewestFirst(rows));
    },

    moderate: function (id, status, note) {
      var rows = readAll();
      var changed = false;
      rows.forEach(function (row) {
        if (row.id === id) {
          row.status = status;
          row.moderation_note = note || null;
          row.moderated_at = new Date().toISOString();
          changed = true;
        }
      });
      if (!changed) return Promise.reject(new Error("Report not found."));
      writeAll(rows);
      return Promise.resolve();
    },

    /* ---- Utilities --------------------------------------------------------- */

    reset: function () {
      try {
        localStorage.removeItem(STORAGE_KEY);
        localStorage.removeItem(RATE_KEY);
      } catch (err) {
        /* Nothing to do. */
      }
      return Promise.resolve();
    },
  };
})(window.LDCW);
