# Product and Technical Proposal Template

Use two maintained, cross-linked documents for a feature proposal.

## 1. Product requirements

Write `<feature>-prd.md` for what users need:

- product promise and problem;
- user experience and workflows;
- user stories and requirements;
- success criteria;
- non-goals.

Do not create or maintain implementation issues in the PRD. Once the PRD is accepted, attach its
Linear milestone and create delivery issues in Linear.

Keep internal components, data structures, providers, APIs, storage, and cloud stack out of the
PRD. At the bottom, link to the technical proposal:

```markdown
---

**Technical implementation:** [Technical Architecture](<feature>-architecture.md)
```

## 2. Technical proposal

Write `<feature>-architecture.md` for how the product could be built:

- link back to the PRD at the top;
- show the base flow;
- compare the meaningful architecture alternatives and their tradeoffs;
- state the recommended approach and staged rollout;
- define ownership, versioning, interfaces, local state, and optional cloud boundaries;
- include a small code skeleton when it makes boundaries easier to review;
- list only the decisions the team needs to approve.

Do not publish a private technical proposal in a public issue. Keep it in a private repository or
paste it into a private Linear issue.

## Maintenance rule

Update both documents in the same change whenever product behavior changes an architectural
assumption. Do not duplicate content: the PRD states the behavior and links here; the technical
proposal explains its implementation.

The Markdown files are the editable source of truth. Use VS Code's Markdown preview while writing,
then generate HTML copies for review. Never hand-edit generated HTML because the next render will
replace those changes.
