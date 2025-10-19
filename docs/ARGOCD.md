# Argo CD - GitOps Continuous Delivery

This document provides a comprehensive guide to the Argo CD deployment in the management AKS cluster, including architecture, multi-tenancy setup, team onboarding, and best practices.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Multi-Tenancy Model](#multi-tenancy-model)
- [Getting Started](#getting-started)
- [Team Onboarding Guide](#team-onboarding-guide)
- [Application Deployment Patterns](#application-deployment-patterns)
- [RBAC and Security](#rbac-and-security)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)
- [Cost Optimization](#cost-optimization)

---

## Overview

**Argo CD** is a declarative, GitOps continuous delivery tool for Kubernetes. It enables teams to manage their Kubernetes applications using Git as the single source of truth.

### Key Features

- **GitOps Workflow**: Declarative configuration stored in Git
- **Multi-Tenancy**: Namespace isolation via AppProjects
- **Azure AD SSO**: Single Sign-On with corporate credentials
- **RBAC**: Fine-grained role-based access control
- **UI & CLI**: Rich web interface and command-line tool
- **Auto-Sync**: Automatic deployment on Git commit
- **Health Monitoring**: Real-time application health status
- **Rollback**: Easy rollback to previous Git commits
- **Observability**: Integrated with Prometheus metrics

### Deployment Details

- **Namespace**: `argocd`
- **Version**: 7.7.0 (Helm chart)
- **High Availability**: 2 replicas for server and repo-server
- **Authentication**: Azure AD via Dex (OAuth2)
- **Storage**: Kubernetes secrets for state management
- **Monitoring**: Prometheus ServiceMonitors enabled

---

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────────┐
│                         Argo CD (argocd namespace)              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌─────────────────┐  │
│  │  Argo CD     │    │  Repo        │    │  Application    │  │
│  │  Server      │───▶│  Server      │◀───│  Controller     │  │
│  │  (2 replicas)│    │  (2 replicas)│    │  (1 replica)    │  │
│  └──────┬───────┘    └──────────────┘    └────────┬────────┘  │
│         │                                           │           │
│         │            ┌──────────────┐              │           │
│         │            │  Dex         │              │           │
│         └───────────▶│  (Azure AD   │              │           │
│                      │   OAuth2)    │              │           │
│                      └──────────────┘              │           │
│                                                     │           │
│         ┌───────────────────────────────────────────┘           │
│         │                                                       │
│  ┌──────▼──────────────────────────────────────────────────┐  │
│  │                    AppProjects                           │  │
│  │  ┌────────────┐  ┌────────────┐  ┌─────────────────┐   │  │
│  │  │ platform   │  │ team-alpha │  │  team-beta      │   │  │
│  │  │ (full)     │  │ (limited)  │  │  (limited)      │   │  │
│  │  └────────────┘  └────────────┘  └─────────────────┘   │  │
│  └──────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
         ┌────────────────────────────────────────────┐
         │       Kubernetes Cluster Resources          │
         ├────────────────────────────────────────────┤
         │  ┌──────────────┐    ┌──────────────┐     │
         │  │ ns-alpha-*   │    │ ns-beta-*    │     │
         │  │ (Team Alpha) │    │ (Team Beta)  │     │
         │  └──────────────┘    └──────────────┘     │
         └────────────────────────────────────────────┘
```

### Data Flow

1. **Developer commits** manifest changes to Git repository
2. **Argo CD Repo Server** polls Git repository for changes
3. **Application Controller** detects drift between Git and cluster state
4. **Controller syncs** resources to Kubernetes cluster (if auto-sync enabled)
5. **Health Assessment** monitors application health
6. **Metrics exported** to Prometheus for observability

---

## Multi-Tenancy Model

Argo CD uses **AppProjects** to implement namespace isolation and RBAC boundaries for teams.

### AppProject Concept

An AppProject defines:
- **Source Repositories**: Which Git repos can be synced
- **Destinations**: Which namespaces/clusters can be deployed to
- **Resource Whitelists/Blacklists**: What Kubernetes resources are allowed
- **Roles**: RBAC policies for team members
- **Sync Windows**: When deployments are allowed

### Tenancy Hierarchy

```
┌─────────────────────────────────────────────────────────┐
│ AppProject: platform (Platform Team)                    │
│ ├─ Source Repos: * (all)                                │
│ ├─ Destinations: * (all namespaces)                     │
│ └─ Roles: AKS-Platform-Team = admin                     │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ AppProject: team-alpha (Team Alpha)                     │
│ ├─ Source Repos: github.com/org/team-alpha-*            │
│ ├─ Destinations: ns-alpha-* namespaces only             │
│ └─ Roles: AKS-Team-Alpha = admin                        │
│           AKS-Team-Alpha-Developers = read-only         │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│ AppProject: team-beta (Team Beta)                       │
│ ├─ Source Repos: github.com/org/team-beta-*             │
│ ├─ Destinations: ns-beta-* namespaces only              │
│ └─ Roles: AKS-Team-Beta = admin                         │
│           AKS-Team-Beta-Developers = read-only          │
└─────────────────────────────────────────────────────────┘
```

### Security Guarantees

- ✅ Teams **cannot** deploy to other teams' namespaces
- ✅ Teams **cannot** sync from other teams' repositories
- ✅ Teams **cannot** create cluster-scoped resources (unless explicitly allowed)
- ✅ Teams **cannot** see or modify other teams' applications
- ✅ RBAC enforced via Azure AD group membership

---

## Getting Started

### Prerequisites

1. **Azure AD Access**: Member of `AKS-Platform-Team` group
2. **Azure CLI**: Authenticated (`az login`)
3. **kubectl**: Configured for the management cluster
4. **argocd CLI**: Install from https://argo-cd.readthedocs.io/en/stable/cli_installation/

### Initial Setup

#### 1. Create Azure AD App Registration

Run the PowerShell script to create the Azure AD application for SSO:

```powershell
cd scripts
.\create-argocd-app-registration.ps1
```

This will:
- Create an Azure AD app registration named "ArgoCD-Management-Cluster"
- Configure redirect URIs for OAuth2 callback
- Generate a client secret (valid for 2 years)
- Update `infrastructure/.env` with credentials

#### 2. Deploy Argo CD

```bash
# Source environment variables
cd infrastructure
source .env

# Plan and apply Terraform
terraform plan
terraform apply
```

#### 3. Access Argo CD UI

**Option A: Public HTTPS Access (Recommended)**

ArgoCD is publicly accessible via HTTPS with Azure AD authentication:
- URL: `https://argocd.<INGRESS_IP>.nip.io`
- Authentication: Azure AD SSO via Dex
- Get the URL: `terraform output argocd_url`
- See [INGRESS.md](INGRESS.md) for detailed access instructions

**Option B: Port Forward (Development/Troubleshooting)**

```bash
kubectl port-forward -n argocd svc/argocd-server 8080:443
# Then open: https://localhost:8080
```

#### 4. Get Admin Password

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

**Login options:**
- **Admin**: `admin` / (password from above)
- **Azure AD SSO**: Click "LOG IN VIA AZURE AD" button

#### 5. Install Argo CD CLI

```bash
# macOS
brew install argocd

# Linux
curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x /usr/local/bin/argocd

# Windows
choco install argocd-cli
```

**Login via CLI:**

```bash
argocd login localhost:8080 --username admin --password <password>
# Or via SSO
argocd login localhost:8080 --sso
```

---

## Team Onboarding Guide

### Step 1: Create Azure AD Group

Create an Azure AD group for the team (if not exists):

```bash
az ad group create \
  --display-name "AKS-Team-Example" \
  --mail-nickname "AKS-Team-Example"
```

Add team members to the group.

### Step 2: Create Namespaces

Create Kubernetes namespaces for the team:

```yaml
# ns-team-example-dev.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ns-team-example-dev
  labels:
    team: example
    environment: dev
    pod-security.kubernetes.io/enforce: baseline
---
# ns-team-example-prod.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: ns-team-example-prod
  labels:
    team: example
    environment: prod
    pod-security.kubernetes.io/enforce: restricted
```

Apply via kubectl:

```bash
kubectl apply -f ns-team-example-dev.yaml
kubectl apply -f ns-team-example-prod.yaml
```

### Step 3: Create AppProject

Use the template from `examples/argocd-appproject-example.yaml`:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-example
  namespace: argocd
spec:
  description: "AppProject for Team Example"

  sourceRepos:
    - "https://github.com/your-org/team-example-*"

  destinations:
    - namespace: "ns-team-example-*"
      server: "https://kubernetes.default.svc"

  namespaceResourceWhitelist:
    - group: "*"
      kind: "*"

  roles:
    - name: admin
      policies:
        - "p, proj:team-example:admin, applications, *, team-example/*, allow"
      groups:
        - "AKS-Team-Example"
```

Apply via kubectl or Argo CD:

```bash
kubectl apply -f appproject-team-example.yaml
```

### Step 4: Grant Team Access

Team members in the Azure AD group can now:
1. Log in to Argo CD UI via Azure AD SSO
2. See only their AppProject and Applications
3. Create Applications scoped to their namespaces

---

## Application Deployment Patterns

### Pattern 1: Single Application

**Use Case**: Deploy one microservice to one namespace

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: team-example-api
  namespace: argocd
spec:
  project: team-example

  source:
    repoURL: "https://github.com/your-org/team-example-api"
    targetRevision: "main"
    path: "k8s"

  destination:
    server: "https://kubernetes.default.svc"
    namespace: "ns-team-example-dev"

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Pattern 2: Helm Chart

**Use Case**: Deploy application using Helm chart

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: team-example-web
  namespace: argocd
spec:
  project: team-example

  source:
    repoURL: "https://github.com/your-org/team-example-web"
    targetRevision: "v1.2.3"
    path: "charts/web"
    helm:
      releaseName: web
      values: |
        image:
          tag: "1.2.3"
        ingress:
          enabled: true

  destination:
    server: "https://kubernetes.default.svc"
    namespace: "ns-team-example-prod"

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Pattern 3: Kustomize

**Use Case**: Deploy with environment-specific overlays

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: team-example-worker
  namespace: argocd
spec:
  project: team-example

  source:
    repoURL: "https://github.com/your-org/team-example-worker"
    targetRevision: "main"
    path: "k8s/overlays/dev"

  destination:
    server: "https://kubernetes.default.svc"
    namespace: "ns-team-example-dev"

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Pattern 4: App of Apps

**Use Case**: Manage multiple related applications

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: team-example-platform
  namespace: argocd
spec:
  project: team-example

  source:
    repoURL: "https://github.com/your-org/team-example-platform"
    targetRevision: "main"
    path: "argocd-apps"

  destination:
    server: "https://kubernetes.default.svc"
    namespace: "argocd"

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

## RBAC and Security

### Azure AD Integration

Argo CD uses **Dex** as an OAuth2 proxy to Azure AD.

**Authentication Flow:**
1. User clicks "LOG IN VIA AZURE AD" in Argo CD UI
2. Redirected to `login.microsoftonline.com`
3. Authenticate with Azure AD credentials
4. Azure AD returns user profile + group memberships
5. Dex maps groups to Argo CD roles
6. User granted permissions based on RBAC policy

### RBAC Policy

RBAC is configured in `infrastructure/argocd-helm.tf`:

```csv
# Platform Team - Full access
g, AKS-Platform-Team, role:admin

# Team-specific access
p, role:team-alpha-admin, applications, *, team-alpha/*, allow
g, AKS-Team-Alpha, role:team-alpha-admin

# Viewer role
p, role:viewer, applications, get, */*, allow
g, AKS-Developers, role:viewer
```

**Policy Syntax:**
- `g, <group>, <role>`: Grant role to Azure AD group
- `p, <role>, <resource>, <action>, <object>, <effect>`: Permission rule

### AppProject Roles

Each AppProject can define custom roles:

```yaml
roles:
  - name: admin
    policies:
      - "p, proj:team-example:admin, applications, *, team-example/*, allow"
    groups:
      - "AKS-Team-Example"
```

### Best Practices

1. **Principle of Least Privilege**: Grant minimum necessary permissions
2. **Use Azure AD Groups**: Never hardcode usernames
3. **AppProject per Team**: Isolate teams with separate projects
4. **Namespace Prefix Convention**: Use `ns-{team}-{env}` pattern
5. **Disable Admin User**: After SSO is working, disable local admin
6. **Audit Logs**: Enable audit logging for compliance

---

## Troubleshooting

### Issue: Cannot Login with Azure AD

**Symptoms**: "Failed to query provider" error

**Solutions:**
1. Check Azure AD app registration redirect URIs match Argo CD URL
2. Verify client secret is not expired
3. Check Dex logs: `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-dex-server`
4. Ensure API permissions granted (User.Read, GroupMember.Read.All)

### Issue: Application Stuck in "Progressing"

**Symptoms**: Application never reaches "Healthy" status

**Solutions:**
1. Check application events: `argocd app get <app-name>`
2. View sync status: `argocd app sync <app-name> --dry-run`
3. Check resource health: `kubectl get events -n <namespace>`
4. Review Argo CD logs: `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller`

### Issue: "Permission Denied" When Creating Application

**Symptoms**: User cannot create Application in UI

**Solutions:**
1. Verify user is member of correct Azure AD group
2. Check AppProject destinations allow target namespace
3. Verify sourceRepos whitelist includes Git repository
4. Review RBAC policy: `argocd proj get <project-name>`

### Issue: Git Repository Not Syncing

**Symptoms**: Application not updating from Git changes

**Solutions:**
1. Check repository credentials (if private repo)
2. Verify webhook configured in Git provider (for push-based sync)
3. Check repo-server logs: `kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server`
4. Manually trigger sync: `argocd app sync <app-name>`

### Issue: High Memory Usage

**Symptoms**: Repo-server or controller OOMKilled

**Solutions:**
1. Increase resource limits in `infrastructure/argocd-helm.tf`
2. Reduce number of tracked Applications
3. Disable auto-sync for large applications
4. Split monorepo into multiple smaller repos

---

## Best Practices

### Repository Structure

**Option 1: Monorepo**
```
team-example-manifests/
├── apps/
│   ├── api/
│   ├── web/
│   └── worker/
├── base/
│   └── common-resources.yaml
└── overlays/
    ├── dev/
    ├── staging/
    └── prod/
```

**Option 2: Repo per App**
```
team-example-api/
├── src/
├── k8s/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
└── Dockerfile
```

### Git Branching Strategy

**Recommended**: GitFlow with environment branches

- `main` → Production (`ns-team-example-prod`)
- `staging` → Staging (`ns-team-example-staging`)
- `develop` → Development (`ns-team-example-dev`)

Configure Application per environment:

```yaml
# app-dev.yaml
spec:
  source:
    targetRevision: "develop"
  destination:
    namespace: "ns-team-example-dev"

# app-prod.yaml
spec:
  source:
    targetRevision: "main"
  destination:
    namespace: "ns-team-example-prod"
```

### Sync Policies

**Development Environment**: Aggressive auto-sync

```yaml
syncPolicy:
  automated:
    prune: true       # Delete resources not in Git
    selfHeal: true    # Auto-correct manual changes
```

**Production Environment**: Manual approval

```yaml
syncPolicy:
  automated: null     # Require manual sync
```

### Health Checks

Define custom health checks for CRDs:

```yaml
# In argocd-cm ConfigMap
resource.customizations: |
  example.com/MyCustomResource:
    health.lua: |
      hs = {}
      if obj.status ~= nil and obj.status.ready then
        hs.status = "Healthy"
      else
        hs.status = "Progressing"
      end
      return hs
```

### Secrets Management

**Option 1**: Sealed Secrets (recommended)

```bash
# Encrypt secret
kubeseal --format yaml < secret.yaml > sealed-secret.yaml
# Commit sealed-secret.yaml to Git
```

**Option 2**: Azure Key Vault with CSI Driver

```yaml
# Reference secret from Key Vault
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: azure-keyvault
spec:
  provider: azure
  parameters:
    keyvaultName: "kv-management-northeurope-prod"
    objects: |
      array:
        - objectName: "api-secret"
          objectType: "secret"
```

**Option 3**: External Secrets Operator

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: api-secret
spec:
  secretStoreRef:
    name: azure-keyvault
  target:
    name: api-secret
  data:
    - secretKey: password
      remoteRef:
        key: api-password
```

---

## Cost Optimization

### Current Resource Usage

| Component              | CPU Request | Memory Request | Replicas | Monthly Cost |
|------------------------|-------------|----------------|----------|--------------|
| Argo CD Server         | 100m        | 128Mi          | 2        | ~$5          |
| Application Controller | 250m        | 512Mi          | 1        | ~$8          |
| Repo Server            | 100m        | 256Mi          | 2        | ~$6          |
| Dex                    | 50m         | 64Mi           | 1        | ~$2          |
| Redis                  | 100m        | 128Mi          | 1        | ~$3          |
| **Total**              | **700m**    | **1216Mi**     | **7**    | **~$24**     |

### Optimization Strategies

1. **Reduce Replicas for Dev**:
   - Single replica for server and repo-server (saves ~$5/month)
   - Only recommended for non-production clusters

2. **Adjust Resource Limits**:
   - Monitor actual usage via Prometheus
   - Reduce limits if consistently under-utilized

3. **Disable Unused Features**:
   - Disable notifications controller if not using alerts
   - Disable applicationSet if not using app-of-apps pattern

4. **Stop Cluster Overnight** (Dev clusters only):
   - `az aks stop` saves compute costs
   - Argo CD state preserved in Kubernetes secrets

---

## Monitoring and Observability

### Prometheus Metrics

Argo CD exports metrics to Prometheus:

- **Application Health**: `argocd_app_health_status`
- **Sync Status**: `argocd_app_sync_status`
- **Sync Duration**: `argocd_app_sync_total`
- **API Requests**: `argocd_api_request_total`

### Grafana Dashboards

Import official Argo CD dashboard:

1. Open Grafana UI
2. Navigate to Dashboards → Import
3. Enter dashboard ID: **14584**
4. Select Prometheus datasource

### Example Queries

**Applications Out of Sync:**
```promql
count(argocd_app_sync_status{sync_status="OutOfSync"})
```

**Failed Sync Operations:**
```promql
sum(rate(argocd_app_sync_total{phase="Failed"}[5m]))
```

**Application Health:**
```promql
count by (health_status) (argocd_app_health_status)
```

---

## References

- **Official Documentation**: https://argo-cd.readthedocs.io/
- **Helm Chart**: https://github.com/argoproj/argo-helm
- **Best Practices**: https://argo-cd.readthedocs.io/en/stable/user-guide/best_practices/
- **RBAC Documentation**: https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/

---

**Last Updated**: 2025-01-18
**Maintained By**: Platform Team
