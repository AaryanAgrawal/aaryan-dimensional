type Source = {
  name: string;
  issues: string;
  note?: string;
};

type Destination = {
  initiative: string;
  rationale: string;
  projects: string[];
};

type Migration = {
  sources: Source[];
  destination: Destination;
};

const migrations: Migration[] = [
  {
    sources: [
      { name: "Navigation Framework", issues: "15 total · 9 active" },
      { name: "Nav — VSLAM V1", issues: "8 total · 1 active" },
      { name: "No Project — navigation", issues: "39 active", note: "classified from issue titles" },
    ],
    destination: {
      initiative: "Navigation",
      rationale: "A durable product capability with distinct 2D, visual-odometry, and 3D outcomes.",
      projects: ["[tentative] Unattended 2D Navigation", "[tentative] Stereo Visual Odometry Module", "[tentative] Quadruped 3D Navigation"],
    },
  },
  {
    sources: [
      { name: "Manipulation Framework", issues: "212 total · 59 active" },
      { name: "No Project — manipulation", issues: "13 active", note: "classified from issue titles" },
    ],
    destination: {
      initiative: "Manipulation",
      rationale: "The largest source area; its work separates cleanly by shippable behavior and data loop.",
      projects: ["[tentative] Reliable Pick-and-Place", "[tentative] Mobile Manipulation", "[tentative] Manipulation Teleoperation & Dataset Capture", "[tentative] ACT Manipulation Policy Deployment"],
    },
  },
  {
    sources: [
      { name: "Control Framework", issues: "58 total · 22 active" },
      { name: "No Project — control", issues: "13 active", note: "classified from issue titles" },
    ],
    destination: {
      initiative: "Control",
      rationale: "Shared robot-control capability with two different end states: dependable control and learned policies.",
      projects: ["[tentative] Whole-Body Control Runtime", "[tentative] RL Locomotion Policy Integration"],
    },
  },
  {
    sources: [
      { name: "Perception Framework", issues: "17 total · 11 active" },
      { name: "No Project — perception", issues: "3 active", note: "classified from issue titles" },
    ],
    destination: {
      initiative: "Perception",
      rationale: "Reusable world-understanding outputs consumed by Navigation, Manipulation, and Agents.",
      projects: ["[tentative] 3D Scene Reconstruction & Object Registration", "[tentative] Multi-Camera Calibration"],
    },
  },
  {
    sources: [
      { name: "Agent Framework", issues: "37 total · 19 active" },
      { name: "Memory Framework", issues: "11 total · 10 active" },
      { name: "Agent", issues: "0 attached", note: "braindump, not another workstream" },
      { name: "No Project — agents + memory", issues: "6 active", note: "classified from issue titles" },
    ],
    destination: {
      initiative: "Agents & Memory",
      rationale: "Memory is part of the agent product loop, not an independently shipped product area.",
      projects: ["[tentative] Long-Horizon Agent Runtime", "[tentative] Long-Horizon Agent Evaluation Suite", "[tentative] Robot Spatial Memory"],
    },
  },
  {
    sources: [
      { name: "Hardware Integration", issues: "22 total · 14 active" },
      { name: "Hardware Initiatives", issues: "1 total · 1 active" },
      { name: "No Project — hardware", issues: "20 active", note: "classified from issue titles" },
    ],
    destination: {
      initiative: "Hardware",
      rationale: "One home for platform readiness. Products become separate Projects only after an accepted PRD.",
      projects: ["[tentative] M20 Pro Integration", "[tentative] Unitree Go2 Platform Integration", "[tentative] Galaxea A1Z Platform Integration"],
    },
  },
  {
    sources: [
      { name: "Infrastructure", issues: "22 total · 6 active" },
      { name: "OEM System", issues: "0 attached", note: "its system-management scope becomes DIOS" },
      { name: "No Project — infrastructure", issues: "43 active", note: "classified from issue titles" },
      { name: "No Project — OEM / deployment", issues: "10 active", note: "classified from issue titles" },
      { name: "No Project — simulation", issues: "20 active", note: "classified from issue titles" },
    ],
    destination: {
      initiative: "Infrastructure",
      rationale: "Cross-cutting delivery systems: installation, runtime, release, and shared physical-agent CI.",
      projects: ["[tentative] DIOS Robot Software Installer", "[tentative] RelayBridge Hosted Robot Transport", "[tentative] Robot Software OTA", "[tentative] PimSim Robot Skill Regression"],
    },
  },
  {
    sources: [
      { name: "Web Framework", issues: "18 total · 14 active" },
      { name: "No Project — web", issues: "8 active", note: "classified from issue titles" },
    ],
    destination: {
      initiative: "Web",
      rationale: "A real product surface with a user-facing dashboard and a reusable web platform.",
      projects: ["[tentative] Robot Operations Dashboard", "[tentative] Robot Web Application SDK"],
    },
  },
];

const removals = [
  {
    name: "OEM Enablement",
    verdict: "REMOVE",
    evidence: "The old OEM System Project has 0 attached issues. “OEM” describes a customer/channel context, not one engineering outcome.",
    route: "The DIOS installer and Robot Software OTA → Infrastructure. Robot setup → Hardware. Customer-specific work → the product Project it enables.",
  },
  {
    name: "Simulation",
    verdict: "REMOVE",
    evidence: "There is one shared platform outcome and 20 active unprojected simulation issues—not a portfolio of independent Projects.",
    route: "PimSim Robot Skill Regression → Infrastructure. Skill-specific simulation work stays in Navigation, Manipulation, or Control.",
  },
  {
    name: "Memory",
    verdict: "MERGE",
    evidence: "Memory Framework has 11 issues, 10 active; its milestones and APIs directly support agent behavior and evaluation.",
    route: "Merge into Agents & Memory; preserve the work as Robot Spatial Memory and Long-Horizon Agent Evaluation Suite.",
  },
  {
    name: "Launches",
    verdict: "DISSOLVE",
    evidence: "The old Project contains 21 issues, 11 active, but a launch is a state of product work rather than a durable product area.",
    route: "Move each issue to the Project being launched. Track launches with a label, view, or milestone.",
  },
  {
    name: "Hardware Products",
    verdict: "DO NOT CREATE YET",
    evidence: "6D force/torque, the Go2 accessory pack, and Alfred are three possible products, not one coherent outcome.",
    route: "Keep them as candidates. Create one Project per accepted product PRD; until then, they do not occupy the hierarchy.",
  },
];

const nonProjects = [
  ["Learning Framework", "Empty container; create work only when a concrete outcome has an owner and PRD."],
  ["Weekly All-Hands", "Meeting notes belong in a document, not the product hierarchy."],
  ["Hiring Test", "Hiring operations sit outside Engineering product planning."],
  ["Agent", "Keep its useful context in the Agents & Memory brief; do not create a duplicate Initiative or Project."],
  ["No Project — other", "32 active issues need manual triage; do not manufacture a catch-all Project for them."],
];

const orphanGroups = [
  ["Infrastructure", 43], ["Navigation", 39], ["Needs review", 32], ["Simulation", 20],
  ["Hardware", 20], ["Manipulation", 13], ["Control", 13], ["OEM / deployment", 10],
  ["Web", 8], ["Agents", 3], ["Memory", 3], ["Perception", 3],
] as const;

const projectCount = migrations.reduce((total, migration) => total + migration.destination.projects.length, 0);

export default function Home() {
  return (
    <main className="page">
      <header className="hero">
        <div className="eyebrow"><span>DIMENSIONAL · ENGINEERING V2</span><span>READ-ONLY PROPOSAL · 14 AUG 2026</span></div>
        <div className="heroGrid">
          <div>
            <p className="kicker">THE SIMPLIFICATION</p>
            <h1>From containers<br />to outcomes.</h1>
          </div>
          <div className="heroSummary">
            <p>Engineering v1 accumulated broad Framework Projects, activity buckets, and 259 issues with no Project. The clean v2 structure has only durable product areas at the Initiative level.</p>
            <div className="heroNumbers">
              <div><strong>18</strong><span>source Projects</span></div>
              <b>→</b>
              <div><strong>{migrations.length}</strong><span>Initiatives</span></div>
              <b>→</b>
              <div><strong>{projectCount}</strong><span>outcome Projects</span></div>
            </div>
          </div>
        </div>
      </header>

      <section className="ruleStrip" aria-label="Proposed Linear hierarchy">
        <div><span>01</span><strong>Initiative + Brief</strong><small>Ongoing direction; the Brief evolves</small></div>
        <i>→</i>
        <div><span>02</span><strong>Project + PRD</strong><small>User story; done when it works or is cancelled</small></div>
        <i>→</i>
        <div><span>03</span><strong>Milestone</strong><small>Dated checkpoint; objective definition of done</small></div>
        <i>→</i>
        <div><span>04</span><strong>Issue</strong><small>Assignable execution task</small></div>
      </section>

      <section className="contract" aria-label="Document and deadline rules">
        <div className="contractIntro">
          <p>THE OPERATING CONTRACT</p>
          <h2>Briefs orient. PRDs commit. Milestones schedule.</h2>
        </div>
        <div className="contractGrid">
          <article>
            <span>INITIATIVE · NEVER “DONE”</span>
            <h3>Navigation</h3>
            <strong>Attached document: Navigation Brief</strong>
            <p>Maintains the direction, product context, boundaries, and current portfolio. Update it as the direction evolves.</p>
          </article>
          <article>
            <span>PROJECT · OUTCOME, NOT DEADLINE</span>
            <h3>[tentative] Stereo Visual Odometry Module</h3>
            <strong>Attached document: Project PRD</strong>
            <p>States the user story and qualitative acceptance bar. It ends when the user outcome works—or the Project is cancelled.</p>
          </article>
          <article>
            <span>MILESTONE · HAS TARGET DATE</span>
            <h3>cuVSLAM module</h3>
            <strong>Acceptance: objective and testable</strong>
            <p>Defines a dated proof point inside the Project: an artifact, metric, integration, or validation that can be called complete.</p>
          </article>
        </div>
        <p className="teleopRule"><strong>Teleop classification:</strong> make Teleop an Initiative only when it has multiple ongoing Project-sized outcomes. The current Teleoperation &amp; Data Collection work is one bounded Manipulation Project, so it stays there for now.</p>
      </section>

      <section className="section decisionSection">
        <div className="sectionHead">
          <div><p>DECISION 01</p><h2>What should not be an Initiative</h2></div>
          <p>An Initiative survives only when it will continuously contain multiple independently shippable Projects. Names for activities, customers, meetings, or a single Project fail that test.</p>
        </div>
        <div className="removalList">
          {removals.map((item) => (
            <article className="removalRow" key={item.name}>
              <div><span>{item.verdict}</span><h3>{item.name}</h3></div>
              <p><strong>Why:</strong> {item.evidence}</p>
              <p><strong>Where the work goes:</strong> {item.route}</p>
            </article>
          ))}
        </div>
      </section>

      <section className="section migrationSection">
        <div className="sectionHead">
          <div><p>DECISION 02</p><h2>Engineering v1 → Engineering v2</h2></div>
          <p>Issue counts are a current snapshot of the original Engineering team. “No Project” counts are active issues classified from their titles; they are evidence for routing, not proposed containers.</p>
        </div>
        <div className="comparisonLabels" aria-hidden="true">
          <span>ENGINEERING V1 · SOURCE</span><span>ROUTE</span><span>ENGINEERING V2 · PROPOSED</span>
        </div>
        <div className="comparison">
          {migrations.map((migration, index) => (
            <article className="migrationRow" key={migration.destination.initiative}>
              <div className="sourceColumn">
                {migration.sources.map((source) => (
                  <div className="sourceProject" key={source.name}>
                    <div><span>PROJECT / ISSUE POOL</span><strong>{source.name}</strong></div>
                    <em>{source.issues}</em>
                    {source.note && <small>{source.note}</small>}
                  </div>
                ))}
              </div>
              <div className="routeColumn"><span>{String(index + 1).padStart(2, "0")}</span><i>→</i></div>
              <div className="destinationColumn">
                <div className="initiativeTitle"><span>INITIATIVE</span><h3>{migration.destination.initiative}</h3><p>{migration.destination.rationale}</p></div>
                <div className="projectList">
                  {migration.destination.projects.map((project) => (
                    <div key={project}><span>PROJECT + PRD</span><strong>{project}</strong></div>
                  ))}
                </div>
              </div>
            </article>
          ))}
        </div>
      </section>

      <section className="section orphanSection">
        <div className="sectionHead compact">
          <div><p>SOURCE AUDIT</p><h2>The 207 active orphan issues</h2></div>
          <p>Engineering v1 has 259 issues with no Project, 207 still active. This is the cleanup queue—not a reason to create a “Miscellaneous” Project.</p>
        </div>
        <div className="orphanChart">
          {orphanGroups.map(([name, count]) => (
            <div className="orphanBar" key={name}>
              <span>{name}</span>
              <div><i style={{ width: `${Math.max((count / 43) * 100, 7)}%` }} /></div>
              <strong>{count}</strong>
            </div>
          ))}
        </div>
      </section>

      <section className="section finalSection">
        <div className="sectionHead compact">
          <div><p>FINAL ANSWER</p><h2>Eight Initiatives, no catch-alls</h2></div>
          <p>Each Initiative gets an evolving Brief. Each listed Project gets one attached PRD. The Project is outcome-bound, while its Milestones carry dates and objective acceptance criteria.</p>
        </div>
        <div className="finalGrid">
          {migrations.map((migration, index) => (
            <article key={migration.destination.initiative}>
              <span>{String(index + 1).padStart(2, "0")} · INITIATIVE</span>
              <h3>{migration.destination.initiative}</h3>
              <ol>{migration.destination.projects.map((project) => <li key={project}>{project}</li>)}</ol>
            </article>
          ))}
        </div>
      </section>

      <section className="section namingSection">
        <div className="sectionHead compact">
          <div><p>PROJECT NAMING GATE</p><h2>The name must reveal the boundary</h2></div>
          <p>If a reader still has to ask “which runtime?”, “which transport?”, or “release of what?”, the proposed object is a category—not a Project. Do not create it until the outcome can be named.</p>
        </div>
        <div className="namingGrid">
          <div className="namingColumn rejectedNames">
            <span>REJECT · CAPABILITY CATEGORIES</span>
            <strong>Runtime &amp; Transport</strong>
            <strong>Software OTA &amp; Release</strong>
            <strong>Control Platform</strong>
            <strong>Web Platform</strong>
          </div>
          <div className="namingArrow" aria-hidden="true">→</div>
          <div className="namingColumn acceptedNames">
            <span>USE · BOUNDED OUTCOMES</span>
            <strong>[tentative] RelayBridge Hosted Robot Transport</strong>
            <strong>[tentative] Robot Software OTA</strong>
            <strong>[tentative] Whole-Body Control Runtime</strong>
            <strong>[tentative] Robot Web Application SDK</strong>
          </div>
        </div>
        <p className="namingRule"><strong>Rule:</strong> use one concrete noun plus the system or user boundary. Release work, runtime cleanup, and shared refactors stay as Issues inside the Project whose outcome they unlock; they do not receive permanent catch-all Projects.</p>
      </section>

      <section className="section versionSection">
        <div className="sectionHead compact">
          <div><p>PROJECT VERSIONING RULE</p><h2>Name the next outcome, not “v2”</h2></div>
          <p>A version number is useful only when the version itself is a compatibility or customer promise. Most continued product development should expose what becomes newly possible.</p>
        </div>
        <div className="versionGrid">
          <article>
            <span>SAME USER OUTCOME</span>
            <h3>Keep the Project</h3>
            <p>Use dated Milestones such as Internal Alpha, Beta, Robot Validation, and GA. Remaining Issues continue against the same PRD.</p>
          </article>
          <article>
            <span>NEW USER OUTCOME</span>
            <h3>Create a new Project</h3>
            <p>After Unattended 2D Navigation, name the next outcome Multi-Floor Navigation or Dynamic Obstacle Recovery—not “2D Navigation v2.”</p>
          </article>
          <article>
            <span>SHIPPING BATCH</span>
            <h3>Use a Linear Release</h3>
            <p>A deployment version groups shipped Issues. It does not need another Project unless the release creates a separately managed product outcome.</p>
          </article>
          <article>
            <span>VERSION IS THE CONTRACT</span>
            <h3>Then use “v1”</h3>
            <p>Use it for an installer format, API, hardware revision, or customer commitment where v1 and v2 must remain distinguishable.</p>
          </article>
        </div>
        <div className="versionExample">
          <div><span>AVOID</span><strong>[tentative] 2D Navigation v2</strong></div>
          <i>→</i>
          <div><span>PREFER</span><strong>[tentative] Multi-Floor Navigation</strong></div>
        </div>
      </section>

      <section className="section exclusionsSection">
        <div className="sectionHead compact">
          <div><p>OUTSIDE THE MAP</p><h2>Do not preserve old clutter</h2></div>
          <p>Historical issues stay searchable in Engineering v1. Only active work moves, after its destination Project exists and has an owner.</p>
        </div>
        <div className="exclusionList">
          {nonProjects.map(([name, reason]) => <div key={name}><strong>{name}</strong><span>{reason}</span></div>)}
        </div>
      </section>

      <footer>
        <span>Evidence: Engineering v1 Projects, milestones, descriptions, and all active unprojected issue titles</span>
        <strong>NO LINEAR CHANGES MADE</strong>
      </footer>
    </main>
  );
}
