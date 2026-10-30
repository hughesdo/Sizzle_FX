import { test } from "node:test";
import assert from "node:assert/strict";
import { MaskTrack, maskSize } from "../src/mask/maskTrack.js";

test("maskSize: long side 640, multiples of 32, shrinks for long videos", () => {
  const s = maskSize({ width: 1920, height: 1080, frames: 300 });
  assert.equal(s.width, 640); assert.equal(s.height, 352);
  assert.equal(s.width % 32, 0); assert.equal(s.height % 32, 0);
  const long = maskSize({ width: 1920, height: 1080, frames: 30 * 60 * 20 }); // 20 min
  assert.ok(long.width < 640 && long.width % 32 === 0, JSON.stringify(long));
  assert.ok(long.width * long.height * 30 * 60 * 20 <= 600 * 1024 * 1024 * 1.05);
});

test("MaskTrack stats: centroid/bbox in uv space with origin bottom-left", () => {
  const t = new MaskTrack({ id: "m", name: "t", provider: "key", width: 10, height: 10, frames: 2 });
  const a = new Uint8Array(100);
  // a 2x2 block at top-left in image rows (x 1..2, y 1..2 top-down)
  for (const [x, y] of [[1, 1], [2, 1], [1, 2], [2, 2]]) a[y * 10 + x] = 255;
  t.setFrame(1, a);
  const s = t.statsAt(1);
  assert.ok(Math.abs(s.centroid[0] - 0.2) < 1e-6);
  assert.ok(Math.abs(s.centroid[1] - 0.8) < 1e-6);              // near the TOP => high v
  assert.deepEqual(s.bbox.map((v) => +v.toFixed(2)), [0.1, 0.7, 0.3, 0.9]);
  assert.ok(Math.abs(s.area - 0.04) < 1e-6);
  assert.equal(t.filled, 2);
  assert.equal(t.statsAt(0).area, 0);                            // unset frame
  assert.equal(t.frame(99).length, 100);                         // clamps
});

test("MaskTrack: empty frame gives neutral stats", () => {
  const t = new MaskTrack({ id: "m", name: "t", provider: "key", width: 4, height: 4, frames: 1 });
  t.setFrame(0, new Uint8Array(16));
  assert.deepEqual(t.statsAt(0).centroid, [0.5, 0.5]);
  assert.equal(t.statsAt(0).area, 0);
});
