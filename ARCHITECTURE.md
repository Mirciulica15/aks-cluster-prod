# Architecture Documentation

This document provides a technical overview of the AKS-based management cluster landing zone and its adjacent Azure resources.

## Table of Contents

- [Overview](#overview)
- [Architecture Diagram](#architecture-diagram)
- [Core Components](#core-components)
- [Network Architecture](#network-architecture)
- [Security Architecture](#security-architecture)
- [Observability Stack](#observability-stack)
- [Resource Naming Convention](#resource-naming-convention)
- [High Availability & Scalability](#high-availability--scalability)
- [Cost Optimization](#cost-optimization)

## Overview

This landing zone implements a **management AKS cluster** designed to host shared organizational resources and tooling for development teams. The architecture follows Azure best practices for security, observability, and cost optimization while maintaining production-grade reliability.

**Key Characteristics:**

- **Purpose**: Management cluster for shared development tools and services
- **Region**: North Europe (configurable via `variables.tf`)
- **Environment**: Production
- **Deployment Method**: Infrastructure as Code (Terraform)
- **State Management**: Azure Storage Account backend

## Architecture Diagram

```text
┌─────────────────────────────────────────────────────────────────────┐
│                    Azure Subscription                                │
│                                                                       │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │  Resource Group: rg-management-northeurope-prod             │   │
│  │                                                               │   │
│  │  ┌───────────────────────────────────────────────────┐      │   │
│  │  │  Virtual Network (10.0.0.0/16)                    │      │   │
│  │  │                                                     │      │   │
│  │  │  ┌──────────────────────────────────────┐         │      │   │
│  │  │  │  Node Subnet (10.0.0.0/22)           │         │      │   │
│  │  │  │  - ~1000 node IP capacity            │         │      │   │
│  │  │  │  - AKS node VMs                      │         │      │   │
│  │  │  └──────────────────────────────────────┘         │      │   │
│  │  │                                                     │      │   │
│  │  │  ┌──────────────────────────────────────┐         │      │   │
│  │  │  │  Pod Subnet (10.0.16.0/20)           │         │      │   │
│  │  │  │  - ~4000 pod IP capacity             │         │      │   │
│  │  │  │  - Delegated to AKS                  │         │      │   │
│  │  │  │  - Azure CNI Overlay                 │         │      │   │
│  │  │  └──────────────────────────────────────┘         │      │   │
│  │  │                                                     │      │   │
│  │  └───────────────────────────────────────────────────┘      │   │
│  │                                                               │   │
│  │  ┌───────────────────────────────────────────────────┐      │   │
│  │  │  AKS Cluster                                      │      │   │
│  │  │  - Cilium CNI (network plugin & dataplane)       │      │   │
│  │  │  - Azure RBAC enabled                            │      │   │
│  │  │  - API server IP whitelisting                    │      │   │
│  │  │  - Disk encryption at rest                       │      │   │
│  │  │  - Hubble observability                          │      │   │
│  │  └───────────────────────────────────────────────────┘      │   │
│  │                                                               │   │
│  │  ┌───────────────────────────────────────────────────┐      │   │
│  │  │  Key Vault (Premium SKU with HSM)                │      │   │
│  │  │  - Disk encryption keys                          │      │   │
│  │  │  - Network ACL: IP whitelist only               │      │   │
│  │  │  - RBAC authorization                            │      │   │
│  │  └───────────────────────────────────────────────────┘      │   │
│  │                                                               │   │
│  │  ┌───────────────────────────────────────────────────┐      │   │
│  │  │  Disk Encryption Set                             │      │   │
│  │  │  - Customer-managed keys                         │      │   │
│  │  │  - Auto-rotation enabled                         │      │   │
│  │  └───────────────────────────────────────────────────┘      │   │
│  │                                                               │   │
│  │  ┌───────────────────────────────────────────────────┐      │   │
│  │  │  Log Analytics Workspace                         │      │   │
│  │  │  - 30-day retention                              │      │   │
│  │  │  - Container Insights integration                │      │   │
│  │  └───────────────────────────────────────────────────┘      │   │
│  │                                                               │   │
│  └─────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘
```

## Core Components

### 1. AKS Cluster (`aks.tf`)

**Configuration:**

- **SKU**: Free tier (cost optimization)
- **Kubernetes Version**: Managed by Azure (automatic upgrades via stable channel)
- **Node Pool**: Single pool for system and user workloads
  - VM Size: `Standard_D2s_v3` (2 vCPU, 8 GB RAM)
  - Node Count: 1 (configurable)
  - OS Disk: Ephemeral (48 GB)
  - Max Pods per Node: 50
- **Identity**: System-assigned managed identity
- **Upgrade Strategy**: 33% max surge, 30-minute drain timeout

**Network Configuration:**

- **CNI Plugin**: Azure CNI (overlay mode)
- **Network Policy**: Cilium
- **Data Plane**: Cilium
- **Service CIDR**: 172.16.0.0/16
- **DNS Service IP**: 172.16.0.10

**Advanced Features:**

- Azure Policy enforcement
- Key Vault Secrets Provider (with secret rotation)
- Container Insights (OMS agent)
- Cilium observability and security features

### 2. Virtual Network (`vnet.tf`)

**Address Space**: 10.0.0.0/16

**Subnets:**

| Subnet     | CIDR         | Purpose           | Capacity   |
| ---------- | ------------ | ----------------- | ---------- |
| snet-nodes | 10.0.0.0/22  | AKS node VMs      | ~1,019 IPs |
| snet-pods  | 10.0.16.0/20 | Pod IP allocation | ~4,091 IPs |

**Design Rationale:**

- Separate subnets for nodes and pods enable Azure CNI overlay mode
- Pod subnet is delegated to `Microsoft.ContainerService/managedClusters`
- Supports ~80 nodes at 50 pods per node capacity

### 3. Key Vault (`key-vault.tf`)

**Configuration:**

- **SKU**: Premium (with HSM support)
- **Features**:
  - Disk encryption enabled
  - Purge protection enabled
  - RBAC authorization
  - Public network access with ACL restrictions

**Security:**

- Network ACLs: Default deny, whitelist IPs only
- Bypass: Azure Services allowed
- Role Assignments:
  - User Access Administrator (for deployment principal)
  - Key Vault Administrator (for key management)
  - Key Vault Crypto Service Encryption User (for Disk Encryption Set)

**Keys:**

- `key-disk-encryption`: RSA-HSM 2048-bit key for disk encryption
  - Auto-rotation: Managed via expiration date
  - Operations: decrypt, encrypt, sign, unwrapKey, verify, wrapKey

### 4. Disk Encryption Set (`disk-encryption-set.tf`)

**Purpose**: Customer-managed encryption keys for AKS node disks

**Configuration:**

- Linked to Key Vault key (`key-disk-encryption`)
- Auto key rotation enabled
- System-assigned identity with crypto user permissions

### 5. Log Analytics Workspace (`log-analytics-workspace.tf`)

**Configuration:**

- **SKU**: PerGB2018 (pay-as-you-go)
- **Retention**: 30 days
- **Integration**: Connected to AKS via OMS agent

**Collected Data:**

- Container logs
- Kubernetes events
- Node metrics
- Cilium flow logs (via Hubble metrics)

### 6. Cilium & Hubble (`aks.tf`, `hubble-ui.tf`)

**Cilium Configuration:**

- Managed by AKS (version controlled by Azure)
- Network plugin: Azure CNI integration
- Network policy enforcement
- Advanced networking features:
  - Observability enabled
  - Security features enabled
  - Flow metrics collection

**Hubble Observability:**

- **Hubble Relay**: AKS-managed (v1.15.0)
  - TLS-enabled gRPC endpoint
  - Aggregates flows from all Cilium agents
- **Hubble UI**: Self-deployed (v0.13.1)
  - Frontend: Nginx-based web interface
  - Backend: gRPC client to hubble-relay
  - mTLS authentication with certificate-based auth
  - RBAC: ClusterRole for namespace/pod/service visibility
  - Access: Via `kubectl port-forward`

**Flow Metrics:**

- Source/destination pod identification
- TCP/UDP connection tracking
- DNS query logging (with filtering)
- Service map visualization

## Network Architecture

### IP Address Planning

| Component    | CIDR/Range    | Purpose               |
| ------------ | ------------- | --------------------- |
| VNet         | 10.0.0.0/16   | Overall address space |
| Node Subnet  | 10.0.0.0/22   | Node VM NICs          |
| Pod Subnet   | 10.0.16.0/20  | Pod IPs (delegated)   |
| Service CIDR | 172.16.0.0/16 | ClusterIP services    |
| DNS Service  | 172.16.0.10   | Kubernetes DNS        |

### Traffic Flow

1. **Ingress Traffic:**

   - API Server: Whitelisted IPs → Azure Load Balancer → AKS API Server
   - Applications: User-defined (LoadBalancer/Ingress controller)

2. **East-West Traffic:**

   - Pod-to-Pod: Cilium overlay network
   - Network policies: Cilium enforces L3/L4/L7 rules
   - Observability: Hubble captures all flows

3. **Egress Traffic:**
   - Azure services: Direct via Azure backbone
   - Internet: Via Azure-managed NAT (no custom NAT gateway)

### API Server Access Control

- **IP Whitelisting**: Configured via `ip_range_whitelist` variable
- **Authentication**: Azure AD integration (local accounts disabled)
- **Authorization**: Azure RBAC for Kubernetes resources

## Security Architecture

### Identity & Access Management

**AKS Cluster Identity:**

- System-assigned managed identity
- Azure RBAC for Kubernetes authorization
- No local Kubernetes accounts

**User Authentication:**

- Azure AD integration via `kubelogin`
- Dynamic token acquisition using Azure CLI
- RBAC role assignment via `azurerm_role_assignment`

**Service Accounts:**

- Hubble UI: ClusterRole with read-only permissions
  - Namespaces, services, endpoints, pods (get, list, watch)
  - Network policies (get, list, watch)

### Data Encryption

**At Rest:**

- Node disks: Customer-managed keys (CMK) via Disk Encryption Set
- Key Vault: HSM-backed RSA-2048 keys
- Secrets: Azure Key Vault Secrets Provider

**In Transit:**

- API Server: TLS 1.2+
- Hubble Relay: mTLS with client certificates
- Cilium node-to-node: IPSec (if enabled)

### Network Security

**Perimeter Security:**

- API Server: IP whitelist enforcement
- Key Vault: Network ACL with IP restrictions

**Internal Security:**

- Network Policies: Cilium-based enforcement
- Pod Security: Azure Policy integration
- Admission Control: Gatekeeper policies (e.g., block default namespace)

### Compliance

**Azure Policy:**

- Enforces organizational standards
- Examples:
  - Prevent usage of default namespace
  - Require resource tags
  - Enforce naming conventions

**Checkov Scanning:**

- Pre-commit security checks
- Documented exemptions for cost optimization

## Observability Stack

### Logging

**Container Logs:**

- Collected by: OMS Agent (Container Insights)
- Destination: Log Analytics Workspace
- Retention: 30 days

**Kubernetes Events:**

- API server events
- Controller manager events
- Scheduler events

### Metrics

**Cluster Metrics:**

- Node CPU, memory, disk usage
- Pod resource utilization
- API server latency

**Cilium/Hubble Metrics:**

- Flow metrics (source/destination context)
- TCP connection metrics
- DNS query metrics
- Drop events

### Tracing & Visualization

**Hubble UI:**

- Service map visualization
- Real-time flow monitoring
- Namespace-level filtering
- Flow direction indicators

**Access Method:**

```bash
kubectl port-forward -n kube-system svc/hubble-ui 12000:80
# Open http://localhost:12000
```

### Alerting

**Future Enhancements:**

- Azure Monitor alerts on cluster health
- Log Analytics queries for anomaly detection
- Integration with notification channels

## Resource Naming Convention

All resources follow a consistent naming pattern:

```hcl
<resource-type>-<project>-<location>-<environment>
```

**Examples:**

- AKS Cluster: `aks-management-northeurope-prod`
- Virtual Network: `vnet-management-northeurope-prod`
- Key Vault: `kv-mgmt-northeurope-prod` (shortened due to 24-char limit)
- Resource Group: `rg-management-northeurope-prod`

**Variables:**

- `project`: "management" (default)
- `location`: "northeurope" (default)
- `environment`: "prod" (default)

## High Availability & Scalability

### Current Configuration (Cost-Optimized)

- **Node Count**: 1 (single node)
- **Availability Zones**: Not enabled
- **Node Pool**: Single pool for system and user workloads

### Production-Ready Scaling Path

To enhance availability:

1. **Increase Node Count:**

   ```hcl
   node_count = 3
   ```

2. **Enable Availability Zones:**

   ```hcl
   zones = ["1", "2", "3"]
   ```

3. **Separate System/User Node Pools:**

   - System pool: 1-3 nodes (taints + CriticalAddonsOnly)
   - User pool: Auto-scaling 1-10 nodes

4. **Enable Cluster Autoscaler:**

   ```hcl
   auto_scaling_enabled = true
   min_count           = 1
   max_count           = 10
   ```

### Scalability Limits

**Current Capacity:**

- Nodes: ~1,000 (limited by node subnet size)
- Pods: 50 per node × node count
- Services: 65,000+ (limited by service CIDR)

## Cost Optimization

### Implemented Strategies

1. **Free AKS SKU**: No management plane costs
2. **Single Node Pool**: Avoid dedicated system pool overhead
3. **Ephemeral OS Disks**: No disk storage costs, faster provisioning
4. **Standard_D2s_v3 VMs**: Right-sized for management workloads
5. **30-Day Log Retention**: Balance observability vs storage costs
6. **Public Cluster**: Avoid Bastion VM or VPN costs

### Cost Monitoring

**Pre-commit Check:**

- Infracost runs on every commit
- Fails if monthly cost > $100
- Provides cost forecast before apply

**Monthly Cost Estimate:**

- VM compute: ~$70-100/month
- Log Analytics: Pay-per-GB ingestion
- Key Vault: Premium SKU + operations
- Storage: Terraform state + ephemeral disks

### Exempted Security Checks

The following Checkov checks are intentionally skipped for cost reasons:

- `CKV_AZURE_170`: Free SKU (vs Standard/Premium)
- `CKV_AZURE_232`: Single node pool (vs dedicated system pool)
- `CKV_AZURE_115`: Public cluster (vs private cluster)

**Rationale**: This is a management cluster for development tooling, not production workloads. The security posture is adequate with IP whitelisting and Azure RBAC.

## Deployment & Operations

### Prerequisites

See [README.md](README.md) for detailed setup instructions.

### Deployment Process

1. Configure environment variables (`infrastructure/.env`)
2. Run pre-commit hooks (`./init-dev.sh`)
3. Initialize Terraform (`terraform init`)
4. Plan changes (`terraform plan`)
5. Apply configuration (`terraform apply`)

### State Management

- **Backend**: Azure Storage Account
- **Container**: `terraform`
- **State File**: `managementcluster.tfstate`
- **Configuration**: See `provider.tf`

### CI/CD Pipelines

Located in `pipelines/`:

- `azure-pipelines-terraform-apply.yml`: Infrastructure deployment
- `azure-pipelines-terraform-destroy.yml`: Infrastructure teardown

### Maintenance

**Regular Tasks:**

- Monitor Infracost reports for cost drift
- Review Log Analytics queries for anomalies
- Rotate Key Vault encryption keys (automatic via expiration)
- Update Terraform provider versions

**Kubernetes Upgrades:**

- AKS automatic upgrades enabled (stable channel)
- Node pool OS security patches: Automatic

## Future Enhancements

### Planned Improvements

1. **GitOps Integration:**

   - Flux or ArgoCD for declarative deployments
   - Git-based configuration management

2. **Enhanced Observability:**

   - OpenTelemetry setup

3. **Advanced Security:**

   - OPA for policy-as-code

## References

- [AKS Best Practices](https://learn.microsoft.com/en-us/azure/aks/best-practices)
- [Cilium Documentation](https://docs.cilium.io/)
- [Hubble Observability](https://docs.cilium.io/en/stable/gettingstarted/hubble/)
- [Azure CNI Overlay](https://learn.microsoft.com/en-us/azure/aks/configure-azure-cni-overlay)
- [CLAUDE.md](CLAUDE.md) - Development guide for Claude Code

---

**Last Updated**: 2025-10-17
**Maintained By**: Mircea Talu <talumircea13@gmail.com>
