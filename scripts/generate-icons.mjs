// Rasterise the app icons from static/favicon.svg (#103).
//
// Run when the mark changes — NOT part of the build. The outputs are committed,
// so a normal install/build needs none of this.
//
//   npm i --no-save @resvg/resvg-js && node scripts/generate-icons.mjs
//
// Why a script rather than a design export: the icons are a *derivation* of the
// favicon (flattened, recoloured, padded into a maskable safe zone) and every
// one of those steps is a decision worth keeping next to the result.
//
// The three transforms, and why each one:
//
// 1. Drop the blurred duplicate (`opacity="0.55"` + a feGaussianBlur filter).
//    It is a glow behind the mark. At a 48px launcher size it is most of the
//    pixels and it reads as a smudge.
// 2. Drop every filter reference (a drop shadow). Same reason, plus Android
//    already composites its own shadow under the icon.
// 3. Paint the mark flat white on solid cold-base. The favicon's
//    purple→orange gradient muddies into brown once it is under ~64px, and a
//    dark tile vanishes entirely against a dark wallpaper. Solid brand purple
//    holds its edge at every size and compresses to a few KB.
//
// The mark is scaled to a fraction of the tile so it sits inside the maskable
// safe zone (the inner 80% circle), which is what lets ONE file serve both
// `purpose: "any"` and `purpose: "maskable"` — a launcher that crops to a
// circle, a squircle or a rounded square never cuts into the glyph.

import { readFileSync, writeFileSync } from 'node:fs';
import { Resvg } from '@resvg/resvg-js';

const BG = '#6C04FF'; // cold-base
const SRC = 'static/favicon.svg';

// frac = how much of the tile the 200x200 artboard occupies.
// 0.62 keeps the glyph inside the maskable safe zone. apple-touch-icon is never
// masked (iOS applies its own corner radius to the full square), so it can
// afford to sit larger.
const TARGETS = [
	{ out: 'static/icon-192.png', size: 192, frac: 0.62 },
	{ out: 'static/icon-512.png', size: 512, frac: 0.62 },
	{ out: 'static/apple-touch-icon.png', size: 180, frac: 0.72 }
];

const raw = readFileSync(SRC, 'utf8');

// 1. the blurred duplicate: <g opacity="0.55" filter=...> ... </g>
let inner = raw.replace(/<g opacity="0\.55"[^>]*>[\s\S]*?<\/g>/, '');
// 2. every remaining filter reference
inner = inner.replace(/\s+filter="url\(#[^)]*\)"/g, '');
// 3. flat white — drop gradient fills and their partial opacities
inner = inner.replace(/\s+fill="url\(#[^)]*\)"/g, ' fill="#FFFFFF"');
inner = inner.replace(/\s+fill-opacity="[^"]*"/g, '');

// Strip the <svg> wrapper and the now-unused <defs>; we supply our own root.
const body = inner
	.replace(/^[\s\S]*?<svg[^>]*>/, '')
	.replace(/<\/svg>\s*$/, '')
	.replace(/<defs>[\s\S]*?<\/defs>/g, '');

for (const { out, size, frac } of TARGETS) {
	// The source artboard is 200x200; centre it at `frac` scale.
	const off = (200 - 200 * frac) / 2;
	const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${size}" height="${size}" viewBox="0 0 200 200">
<rect width="200" height="200" fill="${BG}"/>
<g transform="translate(${off} ${off}) scale(${frac})">${body}</g>
</svg>`;
	const png = new Resvg(svg, { fitTo: { mode: 'width', value: size } }).render().asPng();
	writeFileSync(out, png);
	console.log(`${out}  ${size}x${size}  ${png.length} bytes`);
}
