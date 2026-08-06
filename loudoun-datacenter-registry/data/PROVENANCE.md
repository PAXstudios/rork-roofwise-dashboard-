# Data provenance

Generated 2026-08-06 by `scripts/refresh-facilities.py`.

All facility data on this site comes from **Loudoun County GIS**, published as
public, unauthenticated ArcGIS services. Nothing here is scraped, guessed, or
hand-entered, and none of it is our own assessment of any facility.

## Sources

| File | Source layer | Publisher |
|---|---|---|
| `facilities.geojson` (operational, under construction) | [`Existing_Data_Center_Parcel/FeatureServer/1`](https://services1.arcgis.com/MxjRokvPm7bjslyR/arcgis/rest/services/Existing_Data_Center_Parcel/FeatureServer/1) | Loudoun County GIS |
| `facilities.geojson` (proposed) | [`Pipeline_Data_Center_Areas/FeatureServer/1`](https://services1.arcgis.com/MxjRokvPm7bjslyR/arcgis/rest/services/Pipeline_Data_Center_Areas/FeatureServer/1) | Loudoun County GIS |
| `facility-buildings.geojson` | [`Data_Center_Building_Outlines/FeatureServer/0`](https://services1.arcgis.com/MxjRokvPm7bjslyR/arcgis/rest/services/Data_Center_Building_Outlines/FeatureServer/0) | Loudoun County GIS |
| `districts.geojson`, `localities.json` | [`COL/ElectionDistricts/MapServer/8`](https://logis.loudoun.gov/gis/rest/services/COL/ElectionDistricts/MapServer/8) | Loudoun County GIS |

Basemap tiles are © [OpenStreetMap](https://www.openstreetmap.org/copyright)
contributors, used under the Open Database License.

## What we changed

The raw county data is used as-is except for these mechanical transformations:

1. **Parcel polygons reduced to points.** Each parcel's map marker sits at the
   area-weighted centroid of its largest ring. The full polygons are kept in
   `facility-outlines.geojson` for the optional overlay.
2. **Status normalized.** The county's `Built_Status` field is mapped to three
   public statuses. `BUILT` becomes *operational*; anything containing
   `UNDER CONSTRUCTION` becomes *under construction*; every pipeline record
   becomes *proposed*. Note the source contains one typo'd value
   (`BULT/UNDER CONSTRUCTION`), which is why the match is substring-based.
   The original string is preserved in `status_raw`.
3. **Text title-cased.** County fields are stored in all caps. Short all-caps
   tokens (LLC, LP, DC, II) are left alone.
4. **Geometry simplified.** Douglas-Peucker at ~4 m tolerance, coordinates
   rounded to 5 decimal places, purely to keep the committed files small.
5. **Districts assigned by point-in-polygon** for pipeline records, which do not
   carry an election-district field. Existing parcels use the county's own
   `ELECTION_DISTRICT` value.

Records whose centroid falls outside the Loudoun County bounding box are dropped.

## Current snapshot

- 224 data center parcels: 103 operational,
  36 under construction, 85 proposed
- 271 data center building footprints

## Refreshing

The county updates the parcel layers roughly every six months. To pull the
latest:

```bash
python3 scripts/refresh-facilities.py
```

It only needs Python 3.9+ and network access — no dependencies to install.
Review the diff before committing; a large unexpected change usually means the
county altered a field name rather than that 50 data centers appeared overnight.

## A note on facility ownership

The `operator` field is the property owner recorded in Loudoun County land
records. It is often a holding company rather than the brand operating the
facility, it can be out of date, and it does not establish who is responsible
for any condition a resident reports. Treat it as a pointer for further
research, not as an accusation.
