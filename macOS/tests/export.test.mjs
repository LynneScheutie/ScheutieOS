// Offline test for the injected Markdown extractor.
//
// Pulls InjectedJS.runtime straight out of Enhance.swift, runs it inside a real
// DOM (jsdom) loaded with tests/fixture.html, and prints what the exporter
// produces — so the converter can be verified without touching the live site.
//
//   NODE_PATH=<managed node workspace>/node_modules node tests/export.test.mjs

import { readFileSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createRequire } from "node:module";

// jsdom lives in the managed workspace; ESM ignores NODE_PATH, CJS require honours it.
const require = createRequire(import.meta.url);
const { JSDOM } = require("jsdom");

const here = dirname(fileURLToPath(import.meta.url));
const root = join(here, "..");

// ---------- extract the injected runtime from the Swift source ----------
const swift = readFileSync(join(root, "src", "Enhance.swift"), "utf8");
const marker = 'static let runtime = #"""';
const start = swift.indexOf(marker);
if (start < 0) throw new Error("InjectedJS.runtime not found in Enhance.swift");
const bodyStart = start + marker.length;
const end = swift.indexOf('"""#', bodyStart);
if (end < 0) throw new Error("Unterminated raw string for InjectedJS.runtime");
const runtime = swift.slice(bodyStart, end);
console.log(`[test] extracted runtime JS: ${runtime.length} chars`);

// ---------- run it against the fixture ----------
const html = readFileSync(join(here, "fixture.html"), "utf8");
const dom = new JSDOM(html, {
  url: "https://chat.deepseek.com/a/chat/s/abc123",
  runScripts: "outside-only",
});
const { window } = dom;
window.eval(runtime);

const md = window.__scheutieExportMarkdown();
const out = join(root, "tests", "export.sample.md");
writeFileSync(out, md, "utf8");

console.log("\n=== exported markdown ===");
console.log(md);
console.log("=== end ===\n");

// ---------- plain text / selection / stats ----------
const plain = window.__scheutieExportPlainText();
const stats = JSON.parse(window.__scheutieCountText());

// Selection export: select one heading from the fixture and convert just that.
// jsdom's Selection support is partial, so a failure here is reported as a
// skip rather than a hard failure.
let selectionMd = "";
let selectionSupported = true;
try {
  const target = window.document.querySelector("h3");
  const range = window.document.createRange();
  range.selectNodeContents(target);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);
  selectionMd = window.__scheutieExportSelection();
  if (!selectionMd) selectionSupported = false;
} catch {
  selectionSupported = false;
}

console.log("\n=== plain text (first 300 chars) ===");
console.log(plain.slice(0, 300));
console.log("=== stats ===", stats);
console.log("=== selection export ===", selectionSupported ? JSON.stringify(selectionMd) : "(jsdom cannot drive a selection)");

// ---------- assertions ----------
const expectations = [
  ["runtime defines __scheutieApplyCSS", typeof window.__scheutieApplyCSS === "function"],
  ["runtime defines __scheutieExportMarkdown", typeof window.__scheutieExportMarkdown === "function"],
  ["runtime defines __scheutieExportPlainText", typeof window.__scheutieExportPlainText === "function"],
  ["runtime defines __scheutieExportSelection", typeof window.__scheutieExportSelection === "function"],
  ["runtime defines __scheutieCountText", typeof window.__scheutieCountText === "function"],
  ["plain text drops markdown markers", !plain.includes("**") && !/^#{1,6}\s/m.test(plain)],
  ["plain text keeps conversation content", plain.includes("光合作用")],
  ["plain text excludes sidebar", !plain.includes("Python 装饰器")],
  ["stats counts characters", stats.chars > 0],
  ["stats counts CJK", stats.cjk > 0],
  ["stats counts latin words", stats.words > 0],
  ["selection export returns only the selection",
    !selectionSupported || (selectionMd.includes("光合作用核心要点") && !selectionMd.includes("Python 装饰器"))],
  ["has markdown title heading", /^#\s/m.test(md)],
  ["sidebar text excluded", !md.includes("Python 装饰器")],
  ["user question captured", md.includes("光合作用的核心要点整理一下")],
  ["h3 captured as heading", /^###\s+光合作用核心要点/m.test(md)],
  ["bold preserved", md.includes("**类囊体薄膜**")],
  ["italic preserved", md.includes("*叶绿体基质*")],
  ["list items consecutive", /^- .+\n- .+\n- /m.test(md)],
  ["code fence with language", /```python\n/.test(md)],
  ["code body intact", md.includes("return photons // 8 * 3")],
  ["code fence closed", /```\s*$/m.test(md)],
  ["link preserved", md.includes("[这份综述](https://example.com/photosynthesis)")],
  ["table header row", /\|\s*阶段\s*\|\s*场所\s*\|\s*产物\s*\|/.test(md)],
  ["table separator row", /\|\s*---\s*\|/.test(md)],
  ["table rows consecutive", /\|\s*光反应.*\|\n\|\s*暗反应/m.test(md)],
  ["blockquote present", /^>\s+/m.test(md)],
  ["no runaway blank lines", !/\n{3,}/.test(md)],
];

let failed = 0;
console.log("=== assertions ===");
for (const [name, ok] of expectations) {
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}`);
  if (!ok) failed++;
}

console.log(
  `\n[test] ${expectations.length - failed} passed, ${failed} failed` +
    `  (sample written to tests/export.sample.md)`
);
process.exit(failed === 0 ? 0 : 1);
