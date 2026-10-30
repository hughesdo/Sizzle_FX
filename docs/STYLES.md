# Styles

A style is a reusable recipe for dressing a music video with Sizzle FX: which effects to reach for,
how long they last, and what the music has to be doing before they fire. When Don asks for another
video "in the ROCKS style" (or names a new style), start from the recipe here, then build on it.
Add new styles as their own section; refine a style when Don gives notes on a cut.

Every style shares the method in "Workflow" at the bottom.

---

## ROCKS (rock / Halloween music video, Don, 2026-10-30)

Born on the Halloween cut of `sizzle_3c1bd67e3305 VIDEO1.mp4` (2:37.7, 161 BPM). Don's verdict on
v3: "amazing", loved the body glows. His notes for the next cut became the rules below.

**The music video comes first, the effects are seasoning.** Every effect must earn its spot.

### Camera motion is punctuation, not a texture

- `kick-zoom`, `st-camera-shake`, `st-beat-drop-shake`, `st-bass-wobble-screen-shake` and similar
  screen movers fire ONLY on big low-end hits at a musical change (drop, section entrance, the first
  hit after a break), in short bursts: about 1 to 3 s, a handful per song.
- Prefer moments with no vocal (instrumental hits, breaks). Find them by separating the vocal
  (`python -m demucs --two-stems=vocals`) and checking vocal energy around the hit.
- Never lay a shaker across a whole section or the whole song. v3 did (kick-zoom on every kick for
  2:37) and it read as "constantly shaking".
- Same rule for wobbles and other whole-frame distortions (`st-wave-distort`, `st-liquid-splash`,
  `st-heat-distortion`, `mirror-echo`, `st-kaleidoscope-effect`): nice in spots, short.

### Light on people and things is the signature, use it all over

- Body glows are the star: `subject-aura`, `neon-outline`, `rotational-clone`, `silhouette-echo`,
  `pulse-clone`, `rgb-split-clone`, `spotlight`, `rim-light` (two-tone edge light), `subject-rays`
  (beams from behind the silhouette).
- Sprinkle them across the whole video, one look per shot or phrase (about 4 to 10 s each), changing
  colour/look with the scene. Not one look for a minute.
- Match the glow colour to the set (orange/purple in a gothic room, green/orange with pumpkins,
  blue/violet with a blue prop). Keep intensity moderate on bright backgrounds: an aura + glow on a
  light wall washed out to white in v3.
- The trippiest body moment (rotational clones + silhouette echo) goes on the biggest chorus.

### Supporting touches (moderate, scene-matched)

- `glow` / `st-light-rays` / `halation` on bright sources (sun, fire, orbs, lasers), driven by bass.
- `star-glint` (star filter, drive = hat) on candles, chandeliers, jewels, sparkle and water; lower it
  (threshold ~0.87, intensity ~0.7) when the shot is full of highlights.
- `light-leak` (warm film leaks, drive = bass) on flat or graphic shots (phone screens, close-ups).
- `slice-glitch` 0.4 s tears into the big section entrances only.
- `lightning` on a couple of hits (fire, finale), never a whole section.
- `rgb-split` / `st-chromatic-aberration` low and short; on busy footage they double the image.
- A whole-video `film-grade` (grain ~0.03, vignette ~0.28) + light `halation` ties shots together.

### Variety between cuts

Each new cut in a style should bring different light touches, not repeat the last one. v3 used
aura/outline/clones + glow; v4 added rim light, subject rays, star glint and light leaks, and cut
camera motion to 7 short punches (12.3, 48.3, 69.3, 111.9, 127.0, 140.9, 150.3 s on VIDEO1).

### Pumping is also motion (v5 note)

Even with few camera punches, v4 still felt "too constant": nearly every glow pumped on every kick and
the whole-video halation pulsed with the bass, and this song has bass hits all the way through. In v5 the
glows follow `level` (they breathe with the song) at ~40% of the old push, halation and scene glows are
steady, and kick-pumping is kept only for the two peaks (ballroom clones, coffin neon). Camera punches: 5.
Leave room for a human pass: Don tunes the hits by eye in the app (project "Halloween VIDEO1 ROCKS",
lane "CAMERA HITS").

### Compare (before/after)

Optional second cut: side-by-side "Just Sizzle | Sizzle FX" (Chiller, orange) over 16 beats of the
best body-FX moment, both full frames on a blurred, darkened FX backdrop, starting and ending on the
beat. The audio is never touched. The clean cut is the one to post.

### Deliverables

1080p master (lanczos upscale of the 1280x704 source), server render x264 `max`, then X copies with
`-crf 17 -maxrate 20M -bufsize 40M` (X caps uploads at 512 MB). Full-decode every output and md5 the
audio stream against the source.

---

## Workflow (all styles)

1. Probe; 1 fps contact sheets; scene cuts (`select='gt(scene,0.2)'`). Write a shot map.
2. Audio: librosa beats/tempo, RMS + low band per 2 s (section energy), demucs vocal stem
   (where she sings vs instrumental). Mark the big hits at section changes.
3. Make the 1080p master, open it in the app, bake RVM (people) or key (green screen).
4. Write the timeline as a generator script (`demo2/<name>/tools/make_plan.py` -> `plan.json`),
   body effects on the lowest lanes (masks line up with the untouched source), look lanes on top.
5. Audition sheets in the page (`demo2/tools/audition.js`: `loadPlan`, `sheet`), fix what's too hot.
6. Server render (`serverExport({..., preset:'max', encoder:'x264'})`), full-decode, X copies, compare cut.
