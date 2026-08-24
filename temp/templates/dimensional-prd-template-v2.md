# [Feature name] PRD

| | |
|---|---|
| **Owner** | Who is accountable? |
| **Project** | Which broad Linear project contains this work? |
| **Labels** | Which Linear labels apply? |
| **Status** | Draft / Review / Accepted / Shipped |
| **Milestone** | Leave blank until accepted |
| **Last updated** | YYYY-MM-DD |

> **Five-minute rule:** A new reviewer should understand the problem, proposed experience, and
> approval criteria in five minutes. Link evidence and technical detail instead of pasting it here.

## 1. Problem

### What problem are we solving?

*In a short paragraph, explain who experiences the problem, what happens today, and why it matters. Include evidence naturally where it strengthens the explanation.*

[Describe the problem in clear prose.]

### Why now?

*What changed in customer need, technology, strategy, or risk?*

-

### Existing alternatives

*What do users do today, and why is it insufficient?*

| Alternative | What works | Remaining gap |
|---|---|---|
| | | |

## 2. Solution

### Customer messaging

*Explain the value in one sentence. Add a second only when it directly completes the first.*

**[What changes, for whom, and why it matters.]**

### What we are building

*What is the smallest complete product experience that solves the problem?*

Describe the user flow in 3–6 short paragraphs or bullets. Include commands only when they clarify
the experience, and mark syntax as subject to change. Use one diagram only when it materially helps.

### Non-goals and rejected options

*What are we deliberately not doing, and why?*

- **Not building:** [scope] — [reason]
- **Rejected:** [option] — [reason]

## 3. Usage scenarios

*Which two or three real situations must the product handle?*

### Scenario 1 — [person + outcome]

- **Context:**
- **Trigger:**
- **Expected path:**
- **Hard case:**

### Scenario 2 — [person + outcome]

- **Context:**
- **Trigger:**
- **Expected path:**
- **Hard case:**

## 4. Product requirements

*What must be true for the product direction to be accepted?*

Keep requirements user-visible and testable. Put architecture, APIs, storage, package formats,
implementation tasks, and detailed test procedures in the linked technical proposal or Linear.

| ID | Requirement | Priority | Proof |
|---|---|---|---|
| R1 | The product must… | Must | Demonstrated by… |
| R2 | The product should… | Should | Measured by… |

## 5. Success metrics

*What observable results tell us this worked?*

Use 3–5 metrics. Each needs a target and measurement method.

| Outcome | Target | How measured |
|---|---:|---|
| | | |

### Launch guardrails

*What must not regress while we pursue those outcomes?*

- **Safety:**
- **Reliability:**
- **Compatibility / operations:**

---

## Optional appendices

Add only what reviewers need:

- **Dependencies and risks** — what could prevent the product outcome
- **Open product questions** — question, decider, and decision date
- **Decision log** — what changed and why
- **Technical proposal** — a separate, linked architecture document

## After acceptance

Review the PRD and technical proposal together before updating Linear. Once accepted, attach one
Linear milestone. Keep the work breakdown outside the PRD.
