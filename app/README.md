# RCRotations Workshop

Windows desktop app for the WoWSims rotations in RCRotations.

- Browse every bundled rotation, turn lines on or off, reorder them, add spells.
- **Save to WoW** writes the rotation into the companion addon
  `RCRotations_MyRotations` in your WoW folder. `/reload` in game and it shows in
  your rotation list as "(Workshop)".
- Rotations refresh from this repo (`app/data`, updated by the nightly WoWSims
  sync) every time the app starts; offline it uses the last download.

Build: push a tag like `app-v1.0.1` (or run the "Build Workshop app" workflow) and
GitHub builds the .exe. Local run: `npm install`, then `npm start`.
Tests: `npm test`; full window smoke run: `xvfb-run npx electron --no-sandbox test/smoke-main.js`.
