# 040 - ArgoCD GitOps Deploy

## Goal

Deploy the sync backend to `mPi5` through Argo CD instead of manual kubectl
drift.

## Previous Behavior

- `mPi5` has Argo CD installed.
- `foodtracker` has no Argo application.

## New Behavior

- An Argo CD Application points at the repository's K8s manifests.
- Merged GitHub changes can reconcile to `mPi5`.
- Manual cluster changes are minimized.

## Invariants

- Argo CD credentials and admin password stay out of the repo.
- GitOps config must reference stable paths and image tags.
- Failed sync must be observable and reversible.

## Explicit Assumptions

- Argo CD is accessed by port-forward unless a separate auth/TLS exposure
  decision is made.
- Image updates can be manual tag edits first; automated image updater is later.

## Atomic Work

- Add Argo CD Application manifest or install instructions.
- Decide namespace and repo path.
- Configure sync policy.
- Add image tag update workflow or documented manual release step.
- Add rollback instructions.
- Verify Argo sees manifests and reconciles them.

## Edge Cases

- Argo cannot access private GitHub repo.
- GHCR image pull secret missing in target namespace.
- Manifest applies but pods fail readiness.
- Sync accidentally prunes PVC.
- User changes manifests manually on cluster.

## Done Criteria

- Argo CD can deploy `foodtracker` sync backend from Git.
- Deployment state is inspectable from Argo and kubectl.
- Rollback path is documented.

## Verification

- Port-forward Argo CD on `mPi5`.
- Confirm Application health/sync status.
- Confirm backend `/health` through service or ingress.
