# Fix Gemini AI damage analysis accuracy

## Problem

When inspecting a shingle with obvious hail strikes, the AI did not detect the real
strikes and the UI showed markers where there was no damage.

Root cause: `GeminiAnalysisService.analyzeFull` silently falls back to
`InspectionMock.damageMarkers` and `mockFindings(...)` whenever the API call
fails OR the JSON can't be parsed. Those mock markers are then written onto the
real photo via `capturedPhotos[i].damageMarkers = result.markers` and rendered
as if they were real AI detections.

## Fixes

- [x] Stop returning mock markers/findings on API failure — return empty results plus an "Analysis unavailable" finding so the UI is honest.
- [x] Strip ```json fences before parsing (Gemini sometimes wraps even with `responseMimeType`).
- [x] Upgrade model to `gemini-2.5-flash` for better fine-detail vision (hail strike detection on shingles).
- [x] Resize huge images to 2048px max edge before upload — keeps strike detail, avoids slow uploads.
- [x] Add `failed` flag to `AnalysisResult` so callers can leave `analyzed = false` on failure instead of falsely marking photos as analyzed.
- [x] Log Gemini errors / non-2xx responses to the console for debugging.
