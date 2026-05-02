# AR Roof Inspection Mode — LiDAR heatmap, 3D markers, pitch & virtual chalking

## What you'll be able to do

Tap a new **AR Mode** toggle inside the live camera of Quick Inspection. If your iPhone has LiDAR, the camera turns into a 3D inspection scanner of the roof. If it doesn't, you'll see a friendly "LiDAR-equipped iPhone Pro required" message and stay in regular camera mode.

### Features in AR Mode
- **Tap-to-place 3D damage markers** — tap any spot on the roof to drop a colored 3D pin (Hail / Wind-Lifted / Crease / Granule Loss / Other). Markers stay locked to the exact shingle as you walk around.
- **Virtual 10×10 ft test square** — point at a roof slope, tap "Place Test Square," and a glowing 10' × 10' grid anchors onto the surface for HAAG-compliant hit counting.
- **Automatic pitch & slope readout** — a floating label shows live roof pitch (e.g. "6:12") as you aim at a slope, computed from the detected plane and device motion.
- **LiDAR pitting heatmap** — a translucent heat map overlays the roof surface, highlighting depressed/pitted areas in red/orange where shingles have been physically dented.
- **Virtual chalking** — drag your finger to draw circles around suspected hits, just like real chalk, but non-destructive.
- **"Scan Now" Gemini analysis** — tap a button to capture the current AR frame + camera transform, send to Gemini, and unproject every returned damage coordinate back into 3D space as permanent world-anchored markers.
- **Real-time damage overlay** — Gemini findings appear as floating callouts on the actual shingles in 3D, not flat 2D dots.
- **Save to inspection** — markers, chalk strokes, pitch reading, and an AR snapshot photo are saved to the current inspection record. HAAG hit count is auto-derived from marker count inside the 10×10 square.

## Design & feel

- **Entry**: Subtle "AR" pill button in the camera HUD (top-right, ember-orange when active). Smooth crossfade between regular camera and AR mode.
- **Markers**: Floating 3D pins with a pulsing ring at base, color-coded (hail = ember orange, wind = electric blue, crease = amber, granule = teal). Each marker shows a small label that always faces the camera.
- **Test square**: Translucent white grid lines on a faintly tinted plane, with corner brackets and a "10' × 10'" label floating above one corner.
- **Heatmap**: Soft, gradient-blended overlay (cool blue = flat → red = deep pit), only drawn on detected roof mesh, fades at edges so it never feels clinical.
- **Pitch label**: Glassy floating capsule near top-center: large pitch number, small "rise:run" subtitle, gentle bob animation.
- **Chalk**: Bright yellow stroke that fades in with a chalky texture, can be undone with a swipe.
- **Bottom HUD**: Compact toolbar — Marker mode / Chalk mode / Place Square / Scan with Gemini / Save. Springy haptics on each tap.
- **Empty state**: "Aim at a roof slope to begin" hint with an animated reticle until a plane is detected.

## Screens

- **Quick Inspection (existing)** — gains an AR toggle in the camera HUD. On non-LiDAR devices, the toggle is disabled with a tooltip explaining the requirement.
- **AR Inspection Overlay (new, in-place)** — full-screen ARKit/RealityKit experience layered over the current capture flow, with HUD, tool palette, pitch readout, and Gemini scan button.
- **AR Results Drawer (new, slides up from bottom)** — after a Gemini scan, shows the list of detected damages with thumbnails, "tap to focus" on each 3D marker, and a "Keep / Discard" decision per finding.
- **Inspection Detail (existing)** — gains an "AR Snapshot" section: the final AR photo, marker list with 3D coordinates, pitch, and hit-count derived from the 10×10 square.

## Things to note

- Cloud simulator has no LiDAR, so AR mode will show the standard "Install via the Rork App on a Pro device" placeholder during preview. Real device testing required.
- Gemini still does the visual damage detection — AR adds spatial anchoring, depth, and measurement on top.
- The existing photo-based analysis flow stays intact and unchanged for users without LiDAR.