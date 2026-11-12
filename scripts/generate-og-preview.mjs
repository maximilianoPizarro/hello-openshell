/**
 * Generate docs/assets/brand/og-preview.png (1200×630) for Open Graph.
 * Official Red Hat reverse logo + NVIDIA wordmark on PatternFly dark.
 * Run: node scripts/generate-og-preview.mjs
 */
import sharp from "sharp";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const brand = join(root, "docs/assets/brand");
const logos = join(root, "docs/assets/logos");
const rhSvg = readFileSync(join(brand, "redhat-logo-on-dark.svg"));
const nvidiaSvg = readFileSync(join(logos, "nvidia-logo.svg"));

const W = 1200;
const H = 630;

const rhPng = await sharp(rhSvg, { density: 300 })
  .resize({ width: 360, fit: "inside" })
  .png()
  .toBuffer();
const nvidiaPng = await sharp(nvidiaSvg, { density: 300 })
  .resize({ width: 280, fit: "inside" })
  .png()
  .toBuffer();

const rhMeta = await sharp(rhPng).metadata();
const nvMeta = await sharp(nvidiaPng).metadata();
const rhW = rhMeta.width ?? 360;
const rhH = rhMeta.height ?? 85;
const nvW = nvMeta.width ?? 280;
const nvH = nvMeta.height ?? 52;
const rhLeft = Math.round((W - rhW) / 2);
const nvLeft = Math.round((W - nvW) / 2);
const rhTop = 88;
const nvTop = rhTop + rhH + 28;

const svgOverlay = Buffer.from(`
<svg width="${W}" height="${H}" xmlns="http://www.w3.org/2000/svg">
  <rect width="${W}" height="${H}" fill="#151515"/>
  <rect x="0" y="0" width="${W}" height="8" fill="#EE0000"/>
  <text x="600" y="390" text-anchor="middle"
        font-family="Red Hat Text, Overpass, Helvetica, Arial, sans-serif"
        font-size="44" font-weight="700" fill="#FFFFFF">hello-openshell</text>
  <text x="600" y="444" text-anchor="middle"
        font-family="Red Hat Text, Overpass, Helvetica, Arial, sans-serif"
        font-size="26" font-weight="400" fill="#C7C7C7">OpenShell 0.1.8 · sandboxed agents</text>
  <text x="600" y="520" text-anchor="middle"
        font-family="Red Hat Text, Overpass, Helvetica, Arial, sans-serif"
        font-size="20" font-weight="400" fill="#8A8D90">Developer Sandbox · OpenShift · Cloud Shell · Local</text>
  <rect x="0" y="${H - 8}" width="${W}" height="8" fill="#EE0000"/>
</svg>
`);

await sharp(svgOverlay)
  .composite([
    { input: rhPng, left: rhLeft, top: rhTop },
    { input: nvidiaPng, left: nvLeft, top: nvTop },
  ])
  .png()
  .toFile(join(brand, "og-preview.png"));

console.log("Wrote docs/assets/brand/og-preview.png (1200×630)");
