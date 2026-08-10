# 038 - Container Image And GHCR Publish

## Goal

Build and publish backend container images from GitHub.

## Previous Behavior

- There is no backend image.
- `mPi5` K3s has no `foodtracker` sync deployment.

## New Behavior

- GitHub builds a backend container image.
- Image is published to GHCR or the chosen registry.
- Image tags are deterministic and deployable to `mPi5`.

## Invariants

- Image must support the `mPi5` runtime architecture.
- Secrets must not be baked into the image.
- Build and publish must happen only after tests pass.

## Explicit Assumptions

- `mPi5` is ARM64.
- GHCR private image access may require an image pull secret in K3s.

## Atomic Work

- Add Dockerfile.
- Add `.dockerignore`.
- Add local image build check.
- Add GitHub Actions image build workflow.
- Add GHCR publish on main branch or release tag.
- Add image tag convention.
- Add image pull secret documentation.

## Edge Cases

- ARM64 image build fails on GitHub.
- Image starts but health check fails.
- Private registry credentials expire.
- Image tag deployed before database migration exists.

## Done Criteria

- Backend image builds locally or in CI.
- GHCR contains a deployable image.
- Image architecture matches `mPi5` K3s.

## Verification

- Run container locally where possible and hit `/health`.
- Confirm GitHub Actions publishes image.
- Confirm image metadata includes expected architecture.
