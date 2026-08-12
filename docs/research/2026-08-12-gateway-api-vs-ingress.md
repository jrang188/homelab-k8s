# Gateway API vs Ingress for this cluster (Traefik on k3s)

Date: 2026-08-12 · Research only — no decision made. All claims verified against primary sources (official docs, spec, source, first-party APIs) on the date above.

## Recommendation

Adopt Gateway API **alongside** Ingress (not instead of it) for new HTTPS routing through Traefik: Gateway API v1 is GA, Traefik 3.7 (already pinned in this repo as chart 41.2.0) is a conformant v1.6.1 implementation, cert-manager integrates natively, and this repo currently has **zero** existing Ingress resources to migrate. Keep the `kubernetesIngress` provider enabled (default) so Ingress keeps working with zero cost; there is no official deprecation of Ingress and it must not be treated as such.

---

## Evidence

### 1. Gateway API GA status

1.1 **Gateway API v1.4.0 is a GA (Standard channel) release, announced by SIG-Network.** Kubernetes blog "Gateway API v1.4.0" (2025-11-06): "The Kubernetes SIG Network community presented the General Availability (GA) release of Gateway API (v1.4.0)!" and "Gateway API v1.4.0 brings three new features to the *Standard channel* (Gateway API's GA release channel): BackendTLSPolicy… supportedFeatures… and Named rules for Routes"; Mesh, Default gateways, and `externalAuth` remain experimental.
   https://kubernetes.io/blog/2025/11/06/gateway-api-v1-4/

1.2 **As of today (2026-08-11) the latest release is v1.6.1** (tagged 2026-07-16), preceded by v1.6.0 (2026-06-29). v1.6.0 graduated **TCPRoute and UDPRoute to GA (v1)** and deprecated their v1alpha2 versions — L4 routing is now GA too.
   https://github.com/kubernetes-sigs/gateway-api/releases/tag/v1.6.1 , https://github.com/kubernetes-sigs/gateway-api/releases/tag/v1.6.0

1.3 **Gateway API is the official SIG-Network project, positioned as the next generation of Ingress.** gateway-api.sigs.k8s.io: "Gateway API is an official Kubernetes project focused on L4 and L7 routing in Kubernetes. This project represents the **next generation of Kubernetes Ingress**, Load Balancing, and Service Mesh APIs."
   https://gateway-api.sigs.k8s.io/docs/

1.4 **Relationship between the SIG-Network standard and Traefik's implementation: Traefik is an implementation of the standard.** Traefik docs (primary): "The Kubernetes Gateway provider is a Traefik implementation of the Gateway API specification from the Kubernetes Special Interest Groups (SIGs). This provider supports Standard version **v1.6.1** of the Gateway API specification."
   https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-gateway/

1.5 **Channels are the stability mechanism.** The Standard channel (GA/stable) contains Beta-or-GA-versioned resources and Standard-graduated fields; the Experimental channel adds Alpha-versioned resources/fields "and makes no backwards compatibility guarantees." Gateway, GatewayClass and HTTPRoute have been in the Standard channel "since v0.5.0 and are considered stable APIs."
   https://gateway-api.sigs.k8s.io/docs/concepts/versioning/ , https://gateway-api.sigs.k8s.io/docs/

### 2. Traefik's Gateway API support and the pinned chart

2.1 **Traefik 3.7 fully supports HTTPRoute core and many extended features from the Standard channel, plus TCPRoute from the Experimental channel.** "It fully supports all `HTTPRoute` core and some extended features, like `BackendTLSPolicy`, `GRPCRoute`, and `TLSRoute` resources from the Standard channel, as well as `TCPRoute` from the Experimental channel." `TCPRoute` requires the `experimentalChannel` option **and** the Experimental-channel CRDs (enabling it without those CRDs prevents the provider from starting).
   https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-gateway/

2.2 **Traefik's conformance report for exactly the version in this repo (v3.7.10) against Gateway API v1.6.1 exists and is published in the Gateway API repo** (`conformance/reports/v1.6/traefik-traefik/`, experimental channel, 2026-07-30). GATEWAY-HTTP: core 36 passed / 0 failed / 1 skipped (`HTTPRouteMultipleGateways`); extended 26 passed with supported features including `HTTPRoutePathRewrite`, `HTTPRouteHostRewrite`, `HTTPRouteBackendRequestHeaderModification`, `HTTPRouteMethodMatching`, `HTTPRouteQueryParamMatching`, `HTTPRoute303/307/308RedirectStatusCode`, `BackendTLSPolicy`, weighted-route-relevant core tests. Unsupported (extended only): `HTTPRouteCORS`, request mirroring/timeouts/retry, `ListenerSet`, client-cert validation, `GatewayStaticAddresses`.
   https://github.com/kubernetes-sigs/gateway-api/tree/main/conformance/reports/v1.6/traefik-traefik

2.3 **The pinned upstream chart (traefik-41.2.0) installs Traefik v3.7.10** (chart `appVersion: v3.7.10`), and requires Kubernetes ≥ 1.25.
   https://raw.githubusercontent.com/traefik/traefik-helm-chart/v41.2.0/traefik/Chart.yaml

2.4 **Gateway API is an opt-in flag in chart 41.2.0 — NOT deployed by default.** Chart `values.yaml` at tag v41.2.0: `providers.kubernetesGateway.enabled: false` (default). The chart's `gateway.enabled: true` and `gatewayClass.enabled: true` defaults are inert until that provider flag is set — both `templates/gateway.yaml` and `templates/gatewayclass.yaml` are wrapped in `{{- if and (.Values.gateway).enabled (.Values.providers.kubernetesGateway).enabled }}`, and the Gateway-API RBAC block in `templates/rbac/clusterrole.yaml` is likewise gated on `(.Values.providers.kubernetesGateway).enabled`. (Verified directly in the vendored tarball `infra/traefik/charts/traefik-41.2.0.tgz`.) **The premise "Gateway API resources are deployed by default in this chart version" is FALSE.**
   https://raw.githubusercontent.com/traefik/traefik-helm-chart/v41.2.0/traefik/values.yaml

2.5 **The chart does not ship Gateway API CRDs.** `crds/` in the tarball contains only `traefik.io_*` and `hub.traefik.io_*` CRDs. Traefik's install docs require installing the CRD bundle separately (`kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.1/standard-install.yaml`).
   https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-gateway/

2.6 **k3s ships Traefik v3 with optional Gateway API support.** k3s docs (networking services): "K3s comes with Traefik v3, which includes optional support for the Gateway API. In order to enable Gateway API support, deploy a HelmChartConfig that sets `providers.kubernetesGateway.enabled` to true." (This repo replaces the k3s/kube-hetzner Traefik with its own ArgoCD-managed install, so the repo must set that flag itself.)
   https://docs.k3s.io/networking/networking-services

### 3. Feature comparison relevant to this cluster

3.1 **TLS termination (cert-manager): supported natively by both, but Gateway API's model is role-oriented.** cert-manager docs (primary): "cert-manager can generate TLS certificates for Gateway resources… configured by adding annotations to a Gateway" — `cert-manager.io/issuer` / `cert-manager.io/cluster-issuer` — with the Gateway listener's `tls.certificateRefs` pointing at the resulting Secret (`mode: Terminate`; Passthrough unsupported). Gateway API support in cert-manager is **beta since 1.15** ("no longer gated behind a feature flag"), enabled via `config.gatewayAPI.enabled: true`, and "cert-manager 1.14+ is tested with v1 Kubernetes Gateway API."
   https://cert-manager.io/docs/usage/gateway/ , https://cert-manager.io/docs/configuration/acme/http01/

3.2 **Multi-tenancy / namespace boundaries: Gateway API is strictly more capable.** The official intro lists "**Shared Gateways and cross-Namespace support** — They allow the sharing of load balancers and VIPs by permitting independent Route resources to attach to the same Gateway… even across Namespaces — safely without direct coordination," plus explicit personas (infrastructure provider / cluster operator / application developer). Cross-namespace references are granted explicitly via `ReferenceGrant`.
   https://gateway-api.sigs.k8s.io/docs/ , https://gateway-api.sigs.k8s.io/docs/concepts/api-overview/

3.3 **HTTP-route-level features: Gateway API makes them first-class instead of annotation-based.** "**Expressive** — Gateway API resources support core functionality for things like header-based matching, traffic weighting, and other capabilities that were only possible in Ingress through custom annotations." Weighted `backendRef`s (canary-style splitting), header/query/method matching, URL rewrite (`HTTPRoutePathRewrite`/`HostRewrite`), redirects, timeouts and retries are all part of the spec; Traefik passes core conformance and supports the extended rewrite/header features (see 2.2).
   https://gateway-api.sigs.k8s.io/docs/

3.4 **The Ingress "frozen" claim is NOT supported by primary sources.** The official Gateway API FAQ says: "Will Gateway API replace the Ingress API? **No.** The Ingress API is GA since Kubernetes 1.19. There are no plans to deprecate this API and we expect most Ingress controllers to support it indefinitely." k3s docs similarly: "the traditional Ingress API is still supported (and not planned to be deprecated)." What primary sources *do* say is that Gateway API is the **next generation** ("the next generation of Kubernetes Ingress") and the migration guide calls it "the successor to the Ingress API" — i.e. new feature velocity is in Gateway API, but Ingress is maintained, not frozen/deprecated.
   https://gateway-api.sigs.k8s.io/docs/faq/ , https://docs.k3s.io/networking/networking-services , https://gateway-api.sigs.k8s.io/guides/getting-started/migrating-from-ingress/

3.5 **What Gateway API gives up vs Ingress:** an explicit `Gateway` resource and listeners must exist (no implicit default HTTP/HTTPS entrypoints); there is no direct equivalent of the Ingress "default backend"; route selection is via `parentRef` instead of `ingressClassName`; conflicting rules "must be handled as prescribed in [the] API Design Guide"; Traefik specifically skips `HTTPRouteMultipleGateways` in conformance (one Gateway per HTTPRoute is the safe target).
   https://gateway-api.sigs.k8s.io/guides/getting-started/migrating-from-ingress/

### 4. Migration cost

4.1 **The official migration guide is provided by the Gateway API project** (not Traefik — Traefik's own migration guide, `migrate/v2-to-v3`, is only about Traefik v2→v3 version syntax and never mentions Ingress→Gateway API). The guide's worked example converts one Ingress into: (1) a `Gateway` with HTTP:80 and HTTPS:443 listeners (TLS `mode: Terminate`, `certificateRefs` to the existing Secret), (2) one `HTTPRoute` per host attached via `parentRefs` + `sectionName`, (3) a redirect `HTTPRoute`/filter replacing the annotation-based HTTP→HTTPS redirect. An `ingress2gateway` conversion tool exists but "The conversion results should always be tested and verified."
   https://gateway-api.sigs.k8s.io/guides/getting-started/migrating-from-ingress/

4.2 **Ingress and Gateway API run side-by-side with no conflict.** The FAQ confirms Ingress is not replaced; on the Traefik side the `kubernetesIngress` and `kubernetesGateway` providers are independent (both default-on/off-able in chart values) and reconcile different resource types against the same entrypoints. In practice: enable `providers.kubernetesGateway.enabled: true`, install the Gateway API CRDs, and leave existing Ingress resources untouched.
   https://gateway-api.sigs.k8s.io/docs/faq/ , https://raw.githubusercontent.com/traefik/traefik-helm-chart/v41.2.0/traefik/values.yaml

4.3 **Exact changes required (per primary sources):**
   - Install Gateway API CRDs (Standard channel v1.6.1): `kubectl apply -f …/v1.6.1/standard-install.yaml` — the Traefik chart does not install them (2.5).
   - Chart values: `providers.kubernetesGateway.enabled: true` (2.4). RBAC for the provider is "automatically managed for you" when using the Helm chart (Traefik install docs).
   - Gateway listeners' ports must match Traefik entrypoints: "`Gateway` listener ports must match the configured EntryPoint ports of the Traefik deployment" (chart defaults: web=8000, websecure=8443).
   - TLS: annotate the Gateway with `cert-manager.io/cluster-issuer` and reference the resulting Secret in `tls.certificateRefs`; enable cert-manager Gateway support (`config.gatewayAPI.enabled: true`; needs cert-manager ≥ 1.15 for beta support).
   - TCP/UDP routing (if ever wanted): set `experimentalChannel: true` AND install `experimental-install.yaml` (v1.6.1); without the Experimental CRDs the Gateway provider refuses to start.
   - Traefik middlewares remain Traefik-specific CRDs; they are referenced from HTTPRoutes via `ExtensionRef` filters (requires the `kubernetesCRD` provider, which is enabled by default) — Gateway API does not replace Traefik CRDs.
   https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-gateway/ , https://cert-manager.io/docs/usage/gateway/

### 5. Specific to this repo (verified in-repo)

5.1 `infra/traefik/Chart.yaml` pins dependency `traefik ^41.2.0` (Chart.lock resolves 41.2.0) — chart 41.2.0 → Traefik v3.7.10, the exact version with a published Gateway API v1.6.1 conformance report (2.2).

5.2 `infra/traefik/values.yaml` has `deployment.replicas: 3`, `log.level: DEBUG`, `service.spec.type: LoadBalancer`, `ingressClass.enabled: true` + `isDefaultClass: true`. It does **not** set `providers.kubernetesGateway`, so the Gateway API provider is currently OFF (default `false`).

5.3 `helm show values` / tarball inspection of `traefik-41.2.0.tgz` shows the Gateway/GatewayClass/RBAC resources are all conditional on `providers.kubernetesGateway.enabled` (default `false`). **The claim that Gateway API resources are deployed by default in this chart version is FALSE** (2.4).

5.4 `CONTEXT.md` ("Ingress path") confirms Traefik is the cluster's only ingress controller, owned via `infra/traefik`, behind Klipper + Floating IP — consistent with Gateway API being layered on the same Traefik, no new controller needed.

5.5 `docs/adr/0004-own-traefik-remove-metallb.md` "Traefik CRDs/config this repo can't currently reach" refers to Traefik's **own** CRDs in the `traefik.io` API group (`IngressRoute`, `IngressRouteTCP/UDP`, `Middleware`, `TLSOption`, `TLSStore`, `ServersTransport`, `TraefikService`) owned by kube-hetzner's Traefik install. Gateway API does **not** replace those — they live in the separate `gateway.networking.k8s.io` group and are still required for middlewares/TLSOptions (referenced via `ExtensionRef`/policy from HTTPRoutes). Gateway API adoption is complementary, not a substitute, to owning the `traefik.io` CRDs.

5.6 **The repo currently contains no Ingress resources and no HTTPRoutes** (repo-wide grep for `kind: Ingress` / `networking.k8s.io/v1` / `gateway.networking`/`HTTPRoute` returns nothing; `apps/*` directories contain only a vendored chart tarball with no templates). Migration cost is therefore ~zero — there is nothing to convert today, and the decision is purely about the routing API future apps (whoami/hello-world/example apps) should use.

5.7 `infra/cert-manager/` currently vendors **cert-manager chart v1.14.3**, which predates the beta Gateway API support in cert-manager 1.15 ("Since cert-manager 1.15, the Gateway API support is no longer gated behind a feature flag"). Enabling Gateway-style TLS termination would require bumping to ≥ 1.15.0 (and setting `config.gatewayAPI.enabled: true`).
   https://cert-manager.io/docs/configuration/acme/http01/

---

## Notes for this repo (if adopted)

Concrete, minimal path to Gateway API **alongside** Ingress (keeps existing behavior, zero migration):

1. **Install Gateway API CRDs (Standard channel, v1.6.1)** once, cluster-scoped. Options: `kubectl apply` the `standard-install.yaml` bundle, or add a plain-manifest ArgoCD component (`infra/gateway-api` — plain manifests are already the repo's accepted pattern per `docs/adr/0001`; note CRDs are cluster-scoped so the ApplicationSet's `CreateNamespace=true` is harmless). Traefik's chart will NOT install them.
2. **Enable the provider in `infra/traefik/values.yaml`:**
   ```yaml
   providers:
     kubernetesGateway:
       enabled: true
   ```
   Leave `kubernetesIngress.enabled: true` (default) — Ingress resources keep working untouched. No `helm dependency update` needed (chart version unchanged).
3. **Decide on the default Gateway.** The chart renders `Gateway`/`GatewayClass` (controllerName `traefik.io/gateway-controller`) as soon as the provider is enabled (`gateway.enabled`/`gatewayClass.enabled` default `true`). The default `web` listener is port 8000 (matches entrypoint); the `websecure` (8443) listener is commented out because HTTPS requires `certificateRefs` — either enable it with `cert-manager.io/cluster-issuer` annotation + certificateRefs, or define your own Gateway in the app namespaces. Listener ports must match Traefik entrypoint ports.
4. **TLS with cert-manager:** bump the vendored cert-manager chart from 1.14.3 to ≥ 1.15.0, set `config.gatewayAPI.enabled: true`, then annotate the Gateway with `cert-manager.io/cluster-issuer` (ClusterIssuers are namespace-agnostic; `cert-manager.io/issuer` must be same-namespace as the Gateway). Reference the provisioned Secret in the listener's `tls.certificateRefs`.
5. **Write new routes as `HTTPRoute`s** (attached via `parentRefs` to the Traefik Gateway, `sectionName` per listener) rather than Ingress for new apps. Features that matter here and were previously annotation-only: header/query/method matching, weighted `backendRefs` (canary), path/host rewrite, redirects — all Standard-channel core/extended and conformance-passed by Traefik 3.7.10.
6. **Cross-namespace routes** (Gateway in one namespace, route/backends elsewhere) need an explicit `ReferenceGrant` — the Gateway's `allowedRoutes.namespaces` policy is namespace-restrictive by default.
7. **Do NOT enable `experimentalChannel`** unless TCP/TLSRoute is actually needed — it requires the Experimental CRDs, and enabling the option without them breaks the Gateway provider.
8. **Watch two Traefik gaps** (from the conformance report): one HTTPRoute should reference a single Gateway (`HTTPRouteMultipleGateways` skipped), and extended-only features (CORS, request mirroring, timeouts, retries, ListenerSet) are unsupported — they'd stay Traefik-CRD/annotation territory.

## Primary sources consulted

- https://kubernetes.io/blog/2025/11/06/gateway-api-v1-4/ (SIG-Network GA announcement, v1.4.0)
- https://github.com/kubernetes-sigs/gateway-api/releases/tag/v1.6.1 and /tag/v1.6.0 (latest releases; TCP/UDPRoute GA)
- https://gateway-api.sigs.k8s.io/docs/ (intro: "next generation of Kubernetes Ingress"; design goals)
- https://gateway-api.sigs.k8s.io/docs/concepts/versioning/ (Standard vs Experimental channels)
- https://gateway-api.sigs.k8s.io/docs/faq/ (Ingress not deprecated; Gateway API not a replacement)
- https://gateway-api.sigs.k8s.io/guides/getting-started/migrating-from-ingress/ (official migration guide)
- https://doc.traefik.io/traefik/reference/install-configuration/providers/kubernetes/kubernetes-gateway/ (Traefik Gateway provider, v1.6.1 support, enablement, experimentalChannel, CRD install)
- https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/gateway-api/ (supported resources; entrypoint port matching; ExtensionRef)
- https://raw.githubusercontent.com/traefik/traefik-helm-chart/v41.2.0/traefik/values.yaml (chart 41.2.0 defaults: kubernetesGateway disabled by default)
- https://github.com/traefik/traefik-helm-chart/tree/v41.2.0 (chart source) and local `infra/traefik/charts/traefik-41.2.0.tgz` (templates gated on `providers.kubernetesGateway.enabled`)
- https://github.com/kubernetes-sigs/gateway-api/tree/main/conformance/reports/v1.6/traefik-traefik (Traefik v3.7.10 conformance report for Gateway API v1.6.1)
- https://cert-manager.io/docs/usage/gateway/ and https://cert-manager.io/docs/configuration/acme/http01/ (cert-manager Gateway API support, beta ≥1.15)
- https://docs.k3s.io/networking/networking-services (k3s Traefik + optional Gateway API; Ingress not planned for deprecation)
- Local repo: `infra/traefik/Chart.yaml`, `infra/traefik/values.yaml`, `infra/traefik/Chart.lock`, `infra/traefik/charts/traefik-41.2.0.tgz`, `CONTEXT.md`, `docs/adr/0004-own-traefik-remove-metallb.md`, `argocd-resources/applicationset-infra.yaml`
