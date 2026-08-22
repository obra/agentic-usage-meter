// Generates resources/icon.png (app icon) from the compiled PNG encoder.
// Runs after tsc in the build pipeline (imports from out/main/png.js).

import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const { appIconPNG } = await import(join(root, "out", "main", "png.js"));

mkdirSync(join(root, "resources"), { recursive: true });
writeFileSync(join(root, "resources", "icon.png"), appIconPNG(1024));
console.log("wrote resources/icon.png");
