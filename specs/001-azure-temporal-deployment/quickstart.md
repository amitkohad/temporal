# Planning review and future implementation entry point

## Current deliverables
Read features.md, spec.md, research.md, plan.md, contracts/platform.md, tasks.md and checklists/requirements.md in that order. Implementation and Azure execution have not begun.

## Safe planning verification
- Confirm current branch is codex/001-azure-temporal-deployment.
- Review git diff and untracked Markdown artifacts.
- Check task IDs, relative links and requirement mappings.
- No cloud login is required for reviewing these documents.

## Before implementation
Resolve the spec input register. The user confirmed the source-only boundary for OS/toolchain/platform agents; follow docs/deployment/source-build.md. Select an approved immutable source release and compatible supported toolchain/provider/chart/database versions.
Review phase-1-decisions.md: T001, T002, T004, T005 and T006 have decision evidence; resolve partial T003, T007 and T008 before declaring Phase 1 complete. Later tasks remain unchecked. Future infrastructure scripts are paths in the plan, not existing working commands.

## Future non-deploying checks
After implementation, run Terraform formatting, backend-disabled initialization, validation/mocked tests and Helm rendering in a build-only environment. Follow docs/development/testing.md for any Go tests, always with test_dep. Run make lint-code-fast after code changes.
Do not run Terraform apply/destroy, database schema Jobs, image pushes, namespace registration, or Helm rollout until separately authorized.

## Execution handoff
A later execution request must identify environment/subscription/region, approved commit/digests, reviewed plans, private runner access and recovery owner. Use staged bootstrap -> infrastructure -> image publication -> schema -> application rollout; record evidence at each boundary. See tasks.md for execution-only activities.
