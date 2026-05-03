# Add LiDAR mesh, ARKit planes, and persistent 3D damage anchors to RoofWise

## What the inspection gets

- **Real roof measurements on LiDAR iPhones/iPads**: Captures the actual 3D shape of the roof using the device's LiDAR scanner. The square footage shown in the report comes from the real scanned surface (not a guess), and the roof pitch is read straight from the scanned surface angle (not the gyroscope).
- **Smart surface detection**: The app only shows the shingle grid overlay on real surfaces it has confirmed are roof, wall, or angled floor — no more floating overlays in empty space.
- **Damage pinned in 3D space**: Every damage spot the AI finds gets a colored sphere placed at its real-world location on the roof — red for hail, orange for wind, yellow for cracks, purple for missing shingles. The spheres glow with a gentle pulse and stay locked in place as you walk around or move the phone.
- **3D AR Report export**: A new "Export 3D Report" button on the results screen saves the scanned roof and all damage spheres as a 3D file, then opens it in Apple's built-in AR viewer so it can be shared, viewed, or shown to a customer/adjuster in full augmented reality.
- **Graceful fallback for older devices**: On iPhones without LiDAR, the existing camera + AI flow keeps working exactly as it does today. A small subtitle says "LiDAR not available — using camera mode" so the user knows what to expect.

## How it looks

- The live camera view gains a quiet, subtle mesh shimmer over detected roof surfaces when LiDAR is active, fading in only after a real surface is found.
- Damage spheres are small (about the size of a marble in real-world scale), softly emissive, and gently pulse so they read as "live data" without feeling busy.
- The "Export 3D Report" button sits in the results screen alongside existing actions, styled to match the current results card.
- The 3D viewer is Apple's native QuickLook AR — same gesture set users already know (pinch, rotate, place in room).

## Screens touched

- **Quick Inspection (capture screen)**: Gains LiDAR-aware overlay; only renders shingle grid on detected roof/wall/floor planes; shows live damage spheres anchored in 3D.
- **Inspection Results screen**: Gains an "Export 3D Report" button that opens the scanned roof + damage spheres in Apple's AR QuickLook.
- **Non-LiDAR devices**: Show a subtle "LiDAR not available — using camera mode" subtitle on the capture screen; everything else unchanged.

## Scope

Only the items above. No filter chips, no zoom controls, no manual marker tools, no other UI additions. Build will be verified to pass on simulator and device.