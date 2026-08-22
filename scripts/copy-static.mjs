// Copies static renderer assets (HTML/CSS) and preload scripts into out/.

import { cpSync, mkdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

const copies = [
  ["src/renderer/common.css", "out/renderer/common.css"],
  ["src/renderer/panel/index.html", "out/renderer/panel/index.html"],
  ["src/renderer/settings/index.html", "out/renderer/settings/index.html"],
  ["src/renderer/settings/settings.css", "out/renderer/settings/settings.css"],
  ["src/renderer/widget/index.html", "out/renderer/widget/index.html"],
  ["src/preload/panel.cjs", "out/preload/panel.cjs"],
  ["src/preload/settings.cjs", "out/preload/settings.cjs"],
  ["src/preload/widget.cjs", "out/preload/widget.cjs"],
];

for (const [from, to] of copies) {
  mkdirSync(dirname(join(root, to)), { recursive: true });
  cpSync(join(root, from), join(root, to));
}
console.log(`copied ${copies.length} static assets`);
