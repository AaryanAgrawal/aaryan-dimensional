import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

async function render() {
  const workerUrl = new URL("../dist/server/index.js", import.meta.url);
  workerUrl.searchParams.set("test", `${process.pid}-${Date.now()}`);
  const { default: worker } = await import(workerUrl.href);

  return worker.fetch(
    new Request("https://structure.example/", {
      headers: { accept: "text/html", host: "structure.example" },
    }),
    { ASSETS: { fetch: async () => new Response("Not found", { status: 404 }) } },
    { waitUntil() {}, passThroughOnException() {} },
  );
}

test("server-renders the detailed v1 to v2 migration map", async () => {
  const response = await render();
  assert.equal(response.status, 200);
  assert.match(response.headers.get("content-type") ?? "", /^text\/html\b/i);

  const html = await response.text();
  assert.match(html, /<title>Dimensional Engineering v1 → v2 · Simplified Structure<\/title>/i);
  assert.match(html, /From containers/);
  assert.match(html, /8<\/strong><span>Initiatives/);
  assert.match(html, /23<\/strong><span>outcome Projects/);
  assert.match(html, /Engineering v1 → Engineering v2/);
  assert.match(html, /259 issues with no Project/);
  assert.match(html, /207 active orphan issues/);
  assert.match(html, /Briefs orient\. PRDs commit\. Milestones schedule\./);
  assert.match(html, /Navigation Brief/);
  assert.match(html, /cuVSLAM module/);
  assert.match(html, /PROJECT · OUTCOME, NOT DEADLINE/);
  assert.match(html, /MILESTONE · HAS TARGET DATE/);
  assert.match(html, /make Teleop an Initiative only when it has multiple ongoing Project-sized outcomes/);
  assert.match(html, /OEM Enablement/);
  assert.match(html, /The old OEM System Project has 0 attached issues/);
  assert.match(html, /Agents &amp; Memory/);
  assert.match(html, /PimSim Robot Skill Regression/);
  assert.match(html, /RelayBridge Hosted Robot Transport/);
  assert.match(html, /Robot Software OTA/);
  assert.match(html, /The name must reveal the boundary/);
  assert.match(html, /Name the next outcome, not “v2”/);
  assert.match(html, /Use a Linear Release/);
  assert.match(html, /\[tentative\] Multi-Floor Navigation/);
  assert.match(html, /NO LINEAR CHANGES MADE/);
  assert.doesNotMatch(html, /<button|aria-pressed|Filter initiatives/i);
  assert.doesNotMatch(html, /codex-preview|Your site is taking shape|SkeletonPreview/);
});

test("keeps removed containers out of the proposed initiative set", async () => {
  const page = await readFile(new URL("../app/page.tsx", import.meta.url), "utf8");
  const destinations = [...page.matchAll(/initiative: "([^"]+)"/g)].map((match) => match[1]);
  assert.deepEqual(destinations, [
    "Navigation", "Manipulation", "Control", "Perception",
    "Agents & Memory", "Hardware", "Infrastructure", "Web",
  ]);
  assert.doesNotMatch(page, /initiative: "(?:OEM Enablement|Simulation|Memory|Launches)"/);
  assert.match(page, /DIOS Robot Software Installer/);
  assert.match(page, /RelayBridge Hosted Robot Transport/);
  assert.match(page, /Robot Software OTA/);
  assert.doesNotMatch(page, /projects: \[[^\]]*"Runtime & Transport"/);
  assert.doesNotMatch(page, /projects: \[[^\]]*"Software OTA & Release"/);
  const proposedProjectNames = [...page.matchAll(/projects: \[([^\n]+)\]/g)]
    .flatMap((match) => [...match[1].matchAll(/"([^"]+)"/g)].map((name) => name[1]));
  assert.equal(proposedProjectNames.length, 23);
  assert.equal(proposedProjectNames.filter((name) => name.startsWith("[tentative] ")).length, 23);
  assert.match(page, /one attached PRD/i);
  assert.match(page, /Milestone/);
  assert.match(page, /Issue/);
});

test("retains static and accessible presentation safeguards", async () => {
  const [page, layout, css] = await Promise.all([
    readFile(new URL("../app/page.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/layout.tsx", import.meta.url), "utf8"),
    readFile(new URL("../app/globals.css", import.meta.url), "utf8"),
  ]);

  assert.doesNotMatch(page, /"use client"|useState|onClick|<button/);
  assert.match(layout, /export const metadata/);
  assert.match(css, /prefers-reduced-motion:\s*reduce/);
  assert.match(css, /focus-visible/);
});
