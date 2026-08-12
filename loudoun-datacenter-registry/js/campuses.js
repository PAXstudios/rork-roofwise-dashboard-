/*
 * Campuses.
 *
 * The county publishes 224 data center PARCELS. Nobody living next to one
 * thinks in parcels — they think "Beaumeade", which is nineteen of them across
 * two districts and all three build stages. So everywhere a person has to
 * name a facility, this file is what they are choosing from: 132 campuses,
 * built by grouping the county's parcels on their own name field.
 *
 * The parcel ids are kept on each campus, so a report can still be tied back
 * to exactly which ground the county record covers, and so the watchlist and
 * the map can go the other way — parcel to campus — without a second lookup.
 *
 * Nothing here invents a grouping. If the county calls two parcels the same
 * thing, they are one campus; if it doesn't, they aren't. Names that appear
 * once are campuses of one.
 */

window.LDCW = window.LDCW || {};

(function (LDCW) {
  "use strict";

  /* A stable id from the name. Used in URLs and stored on reports, so it has
     to survive a re-pull of the county data unchanged — which it does, because
     it is derived from the name and nothing else. */
  function slug(name) {
    return String(name || "")
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 60);
  }

  /* Rank the build stages so a campus that is part built and part proposed
     reports the furthest-along one. "Operational" is the answer a resident
     needs: something is running there now. */
  var STATUS_RANK = { operational: 3, under_construction: 2, proposed: 1, unknown: 0 };

  function build(facilities) {
    var byId = {};
    var order = [];

    (facilities || []).forEach(function (facility) {
      var name = (facility.name || "").trim() || "Unnamed parcel";
      var id = slug(name) || "unnamed";

      if (!byId[id]) {
        byId[id] = {
          id: id,
          name: name,
          parcels: [],
          parcelIds: [],
          districts: [],
          statuses: [],
          operators: [],
          sqft: 0,
          acres: 0,
          lat: 0,
          lng: 0,
        };
        order.push(byId[id]);
      }

      var campus = byId[id];
      campus.parcels.push(facility);
      if (facility.id) campus.parcelIds.push(facility.id);
      if (facility.district && campus.districts.indexOf(facility.district) === -1) {
        campus.districts.push(facility.district);
      }
      if (facility.status && campus.statuses.indexOf(facility.status) === -1) {
        campus.statuses.push(facility.status);
      }
      if (facility.operator && campus.operators.indexOf(facility.operator) === -1) {
        campus.operators.push(facility.operator);
      }
      campus.sqft += Number(facility.sqft) || 0;
      campus.acres += Number(facility.acres) || 0;
    });

    order.forEach(function (campus) {
      // Mean of the parcel centroids. Good enough to fly a camera to and to
      // seed a report's location; the parcels themselves carry the geometry.
      var points = campus.parcels.filter(function (parcel) {
        return isFinite(parcel.lat) && isFinite(parcel.lng);
      });
      if (points.length) {
        campus.lat =
          points.reduce(function (sum, p) {
            return sum + p.lat;
          }, 0) / points.length;
        campus.lng =
          points.reduce(function (sum, p) {
            return sum + p.lng;
          }, 0) / points.length;
      }

      campus.districts.sort();
      campus.statuses.sort(function (a, b) {
        return (STATUS_RANK[b] || 0) - (STATUS_RANK[a] || 0);
      });
      campus.status = campus.statuses[0] || "unknown";
      campus.operator = campus.operators[0] || "";
      campus.acres = Math.round(campus.acres * 100) / 100;
    });

    order.sort(function (a, b) {
      return a.name.localeCompare(b.name);
    });

    return { list: order, byId: byId };
  }

  /* Cached, because three separate things on a page ask for this and the work
     is the same every time. Keyed on the array identity: Store.loadFacilities
     hands back the same cached array, so this is a cheap and honest check. */
  var cache = { source: null, index: null };

  function index(facilities) {
    if (cache.source === facilities && cache.index) return cache.index;
    cache.source = facilities;
    cache.index = build(facilities);
    return cache.index;
  }

  /* Which campus a given parcel belongs to. */
  function forParcel(facilities, parcel) {
    if (!parcel) return null;
    return index(facilities).byId[slug(parcel.name) || "unnamed"] || null;
  }

  /* One line of context under the name in a picker or a list: where it is,
     what stage it's at, how big. */
  function summary(campus) {
    var schema = LDCW.schema;
    var bits = [];

    if (campus.districts.length) bits.push(campus.districts.join(" & "));

    if (campus.statuses.length > 1) {
      bits.push(
        campus.statuses
          .map(function (key) {
            return schema.statusLabel(key).toLowerCase();
          })
          .join(" + ")
      );
    } else if (campus.status) {
      bits.push(schema.statusLabel(campus.status));
    }

    bits.push(campus.parcels.length === 1 ? "1 parcel" : campus.parcels.length + " parcels");

    var sqft = schema.formatSqft(campus.sqft);
    if (sqft) bits.push(sqft);

    return bits.join(" · ");
  }

  LDCW.campuses = {
    index: index,
    build: build,
    forParcel: forParcel,
    summary: summary,
    slug: slug,
  };
})(window.LDCW);
