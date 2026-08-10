# 039 - K8s Manifests For mPi5

## Goal

Add Kubernetes manifests for deploying the sync backend and PostgreSQL on
`mPi5`.

## Previous Behavior

- `mPi5` has K3s, Traefik, ServiceLB, cert-manager, and Argo CD.
- There is no `foodtracker` namespace, database PVC, or backend deployment.

## New Behavior

- The repo contains K8s manifests for:
  - namespace
  - PostgreSQL PVC/deployment/service
  - backend deployment/service
  - config
  - secret template
  - ingress route if exposure is chosen
- Manifests are compatible with the current `mPi5` add-ons.

## Invariants

- Secrets are templates only unless committed values are intentionally harmless.
- PVC names must be stable.
- Manifests must not assume external-secrets, MetalLB, Longhorn, or monitoring
  because `mPi5.md` says those are not installed.
- Database data must live on persistent storage.

## Explicit Assumptions

- K3s local-path storage is acceptable for phase one on a single-node Pi.
- Public ingress/TLS policy must be chosen before exposing sync outside LAN.

## Atomic Work

- Add `k8s/` directory for `foodtracker` sync backend.
- Add namespace manifest.
- Add PostgreSQL PVC/deployment/service.
- Add backend deployment/service.
- Add ConfigMap for non-secret config.
- Add Secret example for database password and device pairing/admin token.
- Add optional Traefik ingress manifest only after exposure decision.
- Add local `kubectl apply --dry-run=server` verification.

## Edge Cases

- Pod reschedules and PostgreSQL must keep data.
- Image pull secret missing.
- Backend starts before database readiness.
- Pi restarts.
- LAN-only endpoint used while phone is on cellular.

## Done Criteria

- K8s manifests are present and match `mPi5` capabilities.
- No real secrets are committed.
- Backend and PostgreSQL can be applied to the cluster.

## Verification

- Run server-side dry-run with `KUBECONFIG=/Users/mark1ns0n/.kube/mpi5-k3s.yaml`.
- Apply to a test namespace or real namespace when ready.
- Confirm pods, services, PVCs, and logs.
