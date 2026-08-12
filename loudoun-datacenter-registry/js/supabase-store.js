/*
 * Supabase backend.
 *
 * Activated when js/config.js carries a project URL and anon key. Talks to
 * Postgres directly from the browser; everything it is allowed to do is defined
 * by the Row Level Security policies in sql/02_rls.sql:
 *
 *   - anon may INSERT a report, and only with status = 'pending'
 *   - anon may SELECT only from the public_reports view, which excludes the
 *     reporter's name, email, phone, street address and exact coordinates
 *   - a signed-in moderator (app_metadata.role = 'admin') may do everything
 *
 * So a hostile client holding the anon key can add junk to the moderation
 * queue, but cannot read anyone's contact details or publish anything.
 */

window.LDCW = window.LDCW || {};

(function (LDCW) {
  "use strict";

  var PUBLIC_VIEW = "public_reports";
  var TABLE = "reports";

  var client = null;
  var libraryPromise = null;

  function config() {
    return window.LDCW_CONFIG || {};
  }

  /* The Supabase bundle is ~200 KB. In demo mode it is never needed, so rather
     than putting a <script> tag on every page we fetch it the first time this
     backend is actually used. */
  function loadLibrary() {
    if (window.supabase && typeof window.supabase.createClient === "function") {
      return Promise.resolve();
    }
    if (libraryPromise) return libraryPromise;

    libraryPromise = new Promise(function (resolve, reject) {
      var script = document.createElement("script");
      script.src = "vendor/supabase.js";
      script.async = true;
      script.onload = function () {
        if (window.supabase && typeof window.supabase.createClient === "function") {
          resolve();
        } else {
          reject(new Error("vendor/supabase.js loaded but exposed no client."));
        }
      };
      script.onerror = function () {
        reject(new Error("Couldn't load vendor/supabase.js."));
      };
      document.head.appendChild(script);
    });

    return libraryPromise;
  }

  /* Every public method funnels through here, so the library load and client
     construction happen exactly once and always before first use. */
  function withClient(callback) {
    return loadLibrary().then(function () {
      if (!client) {
        client = window.supabase.createClient(
          config().SUPABASE_URL,
          config().SUPABASE_ANON_KEY,
          { auth: { persistSession: true, autoRefreshToken: true } }
        );
      }
      return callback(client);
    });
  }

  /* Postgres errors are terse and often leak schema detail. Translate the ones
     a visitor can actually cause into something actionable, and keep the
     original on the error object for the console. */
  function describe(error, fallback) {
    if (!error) return new Error(fallback);

    var message = error.message || "";
    var friendly = fallback;

    if (error.code === "23514" || /violates check constraint/i.test(message)) {
      friendly = "That report didn't pass validation. Please check the highlighted fields.";
    } else if (error.code === "42501" || /row-level security/i.test(message)) {
      friendly = "This action isn't permitted. If you're a moderator, sign in first.";
    } else if (/Failed to fetch|NetworkError/i.test(message)) {
      friendly = "Couldn't reach the server. Check your connection and try again.";
    } else if (error.code === "PGRST116") {
      friendly = "That report isn't available.";
    }

    var wrapped = new Error(friendly);
    wrapped.cause = error;
    return wrapped;
  }

  /* Storage objects are private; public pages need short-lived signed URLs. */
  function signPhotoUrls(supabase, paths) {
    if (!paths || !paths.length) return Promise.resolve([]);

    return supabase.storage
      .from(config().STORAGE_BUCKET || "report-photos")
      .createSignedUrls(paths, 3600)
      .then(function (result) {
        if (result.error) return [];
        return (result.data || [])
          .filter(function (item) {
            return item && item.signedUrl;
          })
          .map(function (item) {
            return item.signedUrl;
          });
      })
      .catch(function () {
        // A broken photo link should never stop a report from rendering.
        return [];
      });
  }

  function hydrate(supabase, rows) {
    return Promise.all(
      (rows || []).map(function (row) {
        return signPhotoUrls(supabase, row.photo_paths).then(function (urls) {
          return Object.assign({}, row, { photo_urls: urls, is_demo: false });
        });
      })
    );
  }

  function applyFilter(query, filter) {
    if (!filter) return query;
    if (filter.locality) query = query.eq("locality", filter.locality);
    if (filter.facilityStatus) query = query.eq("facility_status", filter.facilityStatus);
    if (filter.minSeverity) query = query.gte("severity", Number(filter.minSeverity));
    if (filter.since) query = query.gte("created_at", new Date(filter.since).toISOString());
    if (filter.categories && filter.categories.length) {
      query = query.overlaps("categories", filter.categories);
    }
    return query;
  }

  LDCW.SupabaseStore = {
    mode: "supabase",

    isDemo: false,

    listApproved: function (filter) {
      return withClient(function (supabase) {
        var query = supabase
          .from(PUBLIC_VIEW)
          .select("*")
          .order("created_at", { ascending: false })
          .limit((filter && filter.limit) || 500);

        query = applyFilter(query, filter);

        return query.then(function (result) {
          if (result.error) throw describe(result.error, "Couldn't load reports.");
          return hydrate(supabase, result.data).then(function (rows) {
            // Free-text search isn't worth a server round trip at this scale.
            if (filter && filter.search) {
              return rows.filter(function (row) {
                return LDCW.schema.matchesFilter(row, { search: filter.search });
              });
            }
            return rows;
          });
        });
      });
    },

    /* The watchlist is computed in the database, not here.
       Counting distinct households requires reading reporter_email, and anon
       has no read on public.reports at all — by design. refresh_watchlist() in
       sql/05_parttwo.sql does the arithmetic as SECURITY DEFINER and writes
       only counts into public.watchlist, which is what this reads.

       Returning null from watchlistSource is the signal to the caller that
       there is nothing to compute client-side. */
    watchlistSource: function () {
      return Promise.resolve(null);
    },

    listWatchlist: function () {
      return withClient(function (supabase) {
        return supabase
          .from("watchlist")
          .select("*")
          .order("report_count", { ascending: false })
          .then(function (result) {
            if (result.error) {
              // A project that hasn't run 05_parttwo.sql yet has no watchlist
              // table. That's a site without the feature, not a broken site.
              if (/does not exist|schema cache/i.test(result.error.message || "")) return [];
              throw describe(result.error, "Couldn't load the watchlist.");
            }
            return result.data || [];
          });
      });
    },

    getReport: function (id) {
      return withClient(function (supabase) {
        return supabase
          .from(PUBLIC_VIEW)
          .select("*")
          .eq("id", id)
          .maybeSingle()
          .then(function (result) {
            if (result.error) throw describe(result.error, "Couldn't load that report.");
            if (!result.data) return null;
            return hydrate(supabase, [result.data]).then(function (rows) {
              return rows[0];
            });
          });
      });
    },

    submitReport: function (draft, files) {
      return withClient(function (supabase) {
        var bucket = config().STORAGE_BUCKET || "report-photos";
        var maxPhotos = config().MAX_PHOTOS || 5;
        var pending = (files || []).slice(0, maxPhotos);

        // Photos are uploaded under an unguessable prefix before the row
        // exists, then referenced by path. Anon can write here but not read
        // back, so one submitter can't browse another's pending photos.
        var prefix =
          "pending/" +
          (window.crypto && window.crypto.randomUUID
            ? window.crypto.randomUUID()
            : String(Date.now()) + "-" + Math.random().toString(36).slice(2));

        var uploads = pending.map(function (file, index) {
          var extension = (file.name.split(".").pop() || "jpg").toLowerCase().slice(0, 5);
          var path = prefix + "/" + (index + 1) + "." + extension;
          return supabase.storage
            .from(bucket)
            .upload(path, file, { contentType: file.type, upsert: false })
            .then(function (result) {
              if (result.error) {
                throw describe(result.error, "Couldn't upload " + file.name + ".");
              }
              return path;
            });
        });

        return Promise.all(uploads).then(function (paths) {
          // lat/lng are sent as given; the database trigger derives the
          // published jittered coordinates and forces status to 'pending'.
          var row = {
            reporter_name: draft.reporter_name || null,
            reporter_email: draft.reporter_email || null,
            reporter_phone: draft.reporter_phone || null,
            contact_ok: draft.contact_ok === true,
            locality: draft.locality,
            zip: draft.zip || null,
            address: draft.address || null,
            lat: Number(draft.lat),
            lng: Number(draft.lng),
            facility_name: draft.facility_name || null,
            facility_ids: draft.facility_ids || [],
            facility_operator: draft.facility_operator || null,
            facility_status: draft.facility_status || "unknown",
            categories: draft.categories || [],
            severity: Number(draft.severity),
            occurred_at: draft.occurred_at || null,
            description: (draft.description || "").trim(),
            other_notes: (draft.other_notes || "").trim() || null,
            photo_paths: paths,
            status: "pending",
          };

          return supabase
            .from(TABLE)
            .insert(row)
            .select("id")
            .single()
            .then(function (result) {
              if (result.error) throw describe(result.error, "Couldn't save your report.");
              return { id: result.data.id, status: "pending" };
            });
        });
      });
    },

    /* ---- Moderator session ------------------------------------------------ */

    signIn: function (email, password) {
      return withClient(function (supabase) {
        return supabase.auth
          .signInWithPassword({ email: email, password: password })
          .then(function (result) {
            if (result.error) {
              throw describe(result.error, "Sign-in failed. Check your email and password.");
            }
            return result.data.session;
          });
      });
    },

    signOut: function () {
      return withClient(function (supabase) {
        return supabase.auth.signOut().then(function () {
          return undefined;
        });
      });
    },

    currentUser: function () {
      return withClient(function (supabase) {
        return supabase.auth
          .getUser()
          .then(function (result) {
            return (result.data && result.data.user) || null;
          })
          .catch(function () {
            return null;
          });
      });
    },

    isAdmin: function () {
      return this.currentUser().then(function (user) {
        if (!user) return false;
        // app_metadata is server-controlled — a user cannot set this on
        // themselves, which is why the role lives there and not in user_metadata.
        return (user.app_metadata || {}).role === "admin";
      });
    },

    /* Moderators read the base table, which includes the private columns the
       public view hides — that's the point of signing in. RLS still enforces
       that only an admin gets any rows back. */
    listPending: function (options) {
      options = options || {};
      return withClient(function (supabase) {
        return supabase
          .from(TABLE)
          .select("*")
          .eq("status", options.status || "pending")
          .order("created_at", { ascending: false })
          .limit(options.limit || 200)
          .then(function (result) {
            if (result.error) {
              throw describe(result.error, "Couldn't load the moderation queue.");
            }
            return hydrate(supabase, result.data);
          });
      });
    },

    moderate: function (id, status, note) {
      return withClient(function (supabase) {
        return supabase
          .from(TABLE)
          .update({
            status: status,
            moderation_note: note || null,
            moderated_at: new Date().toISOString(),
          })
          .eq("id", id)
          .then(function (result) {
            if (result.error) throw describe(result.error, "Couldn't update that report.");
            return undefined;
          });
      });
    },
  };
})(window.LDCW);
