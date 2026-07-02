# 044 - Network Exposure And TLS Policy

## Goal

Decide how iPhones reach the `foodtracker` sync backend on `mPi5` when they are
not on the home LAN.

## Previous Behavior

- `foodtracker` has no backend endpoint.
- `mPi5` runs K3s with Traefik and cert-manager, but Argo CD is intentionally
  accessed by port-forward and no public exposure policy is defined.

## New Behavior

- The sync backend has an explicit connectivity mode:
  - LAN-only
  - VPN/private network
  - public HTTPS ingress
  - tunnel provider
- TLS, DNS, firewall, and certificate ownership are documented before clients
  depend on the endpoint.

## Invariants

- Auth tokens must not be sent over plaintext HTTP outside local development.
- Argo CD exposure remains separate from backend API exposure.
- Backend exposure must not assume MetalLB or external-secrets because
  `mPi5.md` says they are not installed.
- If the backend is LAN-only, the app must communicate that sync is unavailable
  outside the reachable network.

## Explicit Assumptions

- The phrase "when there is internet" requires a reachable backend endpoint,
  not merely local network availability.
- Phase one may choose LAN/VPN-only if public exposure is not worth the risk
  yet.
- cert-manager is available on `mPi5`, but issuer type and domain ownership must
  still be selected.

## Atomic Work

- Compare exposure options:
  - LAN-only with manual testing
  - Tailscale/WireGuard-style private network
  - router port forward plus DNS and Traefik HTTPS ingress
  - Cloudflare Tunnel or similar tunnel
- Select the phase-one option.
- Document DNS and certificate requirements.
- Add K8s ingress/tunnel manifests only after the option is chosen.
- Add iOS server URL validation for the selected URL shape.
- Add operational checks for endpoint reachability from LAN and cellular.

## Edge Cases

- Phone is on cellular and cannot reach LAN-only service.
- Home IP changes.
- TLS certificate expires.
- Router blocks inbound traffic.
- Tunnel provider is down.
- Backend URL changes while devices have pending outbox entries.

## Done Criteria

- Connectivity mode is explicitly chosen and documented.
- iOS sync settings know whether LAN-only or public/VPN endpoint is expected.
- Backend API is reachable through the selected path before two-device sync is
  considered complete.

## Verification

- Test backend `/health` from the same LAN.
- Test backend `/health` from outside LAN if the selected mode claims external
  reachability.
- Confirm TLS certificate and hostname match for non-local HTTP traffic.
