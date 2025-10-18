# Observability Stack

This document describes the observability infrastructure deployed in the management cluster, including metrics, logs, and traces collection, storage, and visualization.

## Overview

The observability stack follows the **Grafana LGTM** (Loki, Grafana, Tempo, Mimir/Prometheus) pattern with OpenTelemetry for standardized telemetry collection. All components are deployed in the `observability` namespace.

### Components

| Component | Purpose | Storage | Retention |
|-----------|---------|---------|-----------|
| **Prometheus** | Metrics storage and querying | 50 GB Azure Disk | 30 days |
| **Loki** | Log aggregation and storage | 50 GB Azure Disk | 31 days |
| **Tempo** | Distributed tracing backend | 50 GB Azure Disk | 30 days |
| **Grafana** | Unified visualization and dashboards | 10 GB Azure Disk | N/A |
| **Alertmanager** | Alert routing and management | 10 GB Azure Disk | N/A |
| **OpenTelemetry Collector** | Centralized telemetry gateway | In-memory | N/A |
| **Promtail** | Log collection agent (DaemonSet) | N/A | N/A |

**Total Storage**: 170 GB across 4 Azure managed disks

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Applications                             │
│  (instrumented with OpenTelemetry SDKs or exporters)            │
└────────────┬────────────────────────────────────────────────────┘
             │ OTLP (gRPC/HTTP)
             ▼
┌─────────────────────────────────────────────────────────────────┐
│              OpenTelemetry Collector (3 replicas)                │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │   Receivers  │  │  Processors  │  │   Exporters  │          │
│  │  - OTLP gRPC │─▶│ - K8s attrs  │─▶│ - Prometheus │          │
│  │  - OTLP HTTP │  │ - Batch      │  │ - Tempo      │          │
│  │  - Prometheus│  │ - Memory lim │  │ - Loki       │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
└───┬─────────────────────┬─────────────────────┬─────────────────┘
    │                     │                     │
    ▼                     ▼                     ▼
┌─────────┐          ┌─────────┐          ┌─────────┐
│Prometheus│         │  Tempo  │          │  Loki   │
│  (2/2)  │         │  (1/1)  │          │  (1/1)  │
│ 50GB disk│         │ 50GB disk│         │ 50GB disk│
└────┬────┘          └────┬────┘          └────┬────┘
     │                    │                     │
     └────────────────────┴─────────────────────┘
                          │
                          ▼
                  ┌──────────────┐
                  │   Grafana    │
                  │    (3/3)     │
                  │  10GB disk   │
                  └──────────────┘
                          │
                          ▼
                  ┌──────────────┐
                  │  Azure AD    │
                  │  OAuth2 SSO  │
                  └──────────────┘
```

## Deployment Details

### Namespace Isolation

All observability components run in the `observability` namespace with the `privileged` pod security enforcement level (required for Promtail to read host logs).

### Storage Configuration

All persistent volumes use Azure managed disks with customer-managed encryption:
- **Disk Encryption Set**: `des-management-northeurope-prod`
- **Key Vault**: `kv-accd-northeurope-prod`
- **Storage Class**: `default` (StandardSSD_LRS)

**Key Permissions Required**:
- AKS cluster system-assigned identity has `Key Vault Crypto Service Encryption User` role on the Key Vault
- AKS cluster system-assigned identity has `Reader` role on the Disk Encryption Set

### High Availability

- **Prometheus**: 2 replicas with pod anti-affinity (spread across nodes)
- **Alertmanager**: 2 replicas with pod anti-affinity
- **OpenTelemetry Collector**: 3 replicas (deployment mode)
- **Grafana**: 1 replica (stateful dashboard storage)
- **Tempo**: 1 replica (single-binary mode)
- **Loki**: 1 replica (single-binary mode)
- **Promtail**: DaemonSet (runs on all nodes)

## Authentication & Authorization

### Grafana SSO with Azure AD

Grafana is configured with Azure AD OAuth2 authentication:

- **Azure AD Application**: Created via `scripts/create-grafana-app-registration.ps1`
- **Redirect URI**: `http://grafana.observability.svc.cluster.local/login/generic_oauth` (update for production ingress)
- **Role Mapping**:
  - Members of `AKS-Platform-Team` Azure AD group → Grafana Admin
  - All other authenticated users → Grafana Viewer

**Local Admin Access** (for testing/emergency):
- Username: `admin`
- Password: `changeme` (TODO: Move to Azure Key Vault secret)

### Namespace Isolation (Future Enhancement)

The current setup uses Grafana RBAC for namespace-level data isolation. Teams can only see logs/metrics/traces from their own namespaces through Grafana dashboard variables and query filters.

**Implementation approach**:
1. Grafana dashboard variables filter by `namespace` label
2. User permissions map to specific namespaces via Azure AD groups
3. Grafana Enterprise (or alternative RBAC plugin) enforces query-level filtering

## Data Collection

### Metrics Collection

**Sources**:
1. **Kubernetes cluster metrics**: Collected by kube-state-metrics and node-exporter
2. **Application metrics**: Applications send OTLP metrics to OpenTelemetry Collector
3. **Collector metrics**: OpenTelemetry Collector exports its own metrics via Prometheus remote write

**Flow**:
```
Application → OTLP → OTEL Collector → Prometheus Remote Write → Prometheus
```

### Logs Collection

**Sources**:
1. **Pod logs**: Promtail DaemonSet reads `/var/log/pods/*` on each node
2. **Application logs**: Applications send OTLP logs to OpenTelemetry Collector

**Flow**:
```
Pod logs → Promtail → Loki Push API → Loki
Application → OTLP → OTEL Collector → OTLP HTTP → Loki
```

### Traces Collection

**Sources**:
1. **Application traces**: Applications instrumented with OpenTelemetry SDKs

**Flow**:
```
Application → OTLP → OTEL Collector → OTLP gRPC → Tempo
```

## Application Instrumentation

### OpenTelemetry Collector Endpoints

Applications should send telemetry to:
- **gRPC**: `opentelemetry-collector.observability.svc.cluster.local:4317`
- **HTTP**: `http://opentelemetry-collector.observability.svc.cluster.local:4318`

### Environment Variables for Applications

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://opentelemetry-collector.observability.svc.cluster.local:4318"
  - name: OTEL_EXPORTER_OTLP_PROTOCOL
    value: "http/protobuf"
  - name: OTEL_SERVICE_NAME
    value: "your-service-name"
  - name: OTEL_RESOURCE_ATTRIBUTES
    value: "service.namespace=$(POD_NAMESPACE),service.instance.id=$(POD_NAME)"
  - name: POD_NAMESPACE
    valueFrom:
      fieldRef:
        fieldPath: metadata.namespace
  - name: POD_NAME
    valueFrom:
      fieldRef:
        fieldPath: metadata.name
```

### Supported Languages

OpenTelemetry has automatic instrumentation for:
- **Java**: OpenTelemetry Java agent
- **.NET**: OpenTelemetry .NET automatic instrumentation
- **Node.js**: `@opentelemetry/auto-instrumentations-node`
- **Python**: `opentelemetry-instrumentation`
- **Go**: Manual instrumentation with OpenTelemetry Go SDK

See [OpenTelemetry documentation](https://opentelemetry.io/docs/languages/) for instrumentation guides.

## Accessing Grafana

### Local Development (Port Forward)

```bash
kubectl port-forward -n observability svc/kube-prometheus-stack-grafana 3000:80
```

Then access at `http://localhost:3000`

**Note**: Azure AD SSO won't work with port-forward due to redirect URI mismatch. Use local admin credentials:
- Username: `admin`
- Password: `changeme`

### Production Access (Future)

Once an ingress controller is deployed:
1. Configure ingress with TLS certificate (cert-manager + Let's Encrypt)
2. Update Azure AD redirect URI to match public domain
3. Update Grafana `root_url` in Helm values to match public URL

## Pre-configured Dashboards

Grafana includes the following dashboards:

1. **Kubernetes Cluster Monitoring** (GrafanaLabs Dashboard 7249)
   - Cluster resource usage
   - Pod and container metrics
   - Node status and performance

2. **Node Exporter Full** (GrafanaLabs Dashboard 1860)
   - Detailed node-level metrics
   - CPU, memory, disk, network statistics
   - System-level performance indicators

## Querying Data

### Prometheus (Metrics)

Example queries:
```promql
# Pod CPU usage
rate(container_cpu_usage_seconds_total{namespace="your-namespace"}[5m])

# Pod memory usage
container_memory_usage_bytes{namespace="your-namespace"}

# HTTP request rate
rate(http_requests_total[5m])

# Error rate
rate(http_requests_total{status=~"5.."}[5m]) / rate(http_requests_total[5m])
```

### Loki (Logs)

Example queries:
```logql
# All logs from a namespace
{namespace="your-namespace"}

# Logs from specific pod
{namespace="your-namespace", pod="my-pod-123"}

# Error logs only
{namespace="your-namespace"} |= "error" or "ERROR"

# Count errors per minute
sum(count_over_time({namespace="your-namespace"} |= "error" [1m])) by (pod)
```

### Tempo (Traces)

- Use **Service Graph** to visualize service dependencies
- Search traces by:
  - Service name
  - Operation name
  - Duration
  - Tags (namespace, pod, etc.)
- Click on any span to see detailed timing and logs correlation

## Troubleshooting

### Grafana Not Loading

```bash
# Check Grafana pod status
kubectl get pods -n observability -l app.kubernetes.io/name=grafana

# Check Grafana logs
kubectl logs -n observability -l app.kubernetes.io/name=grafana -c grafana

# Restart Grafana
kubectl rollout restart deployment/kube-prometheus-stack-grafana -n observability
```

### No Metrics Appearing

```bash
# Check Prometheus targets
kubectl port-forward -n observability svc/kube-prometheus-stack-prometheus 9090:9090
# Visit http://localhost:9090/targets

# Check Prometheus logs
kubectl logs -n observability prometheus-kube-prometheus-stack-prometheus-0 -c prometheus
```

### No Logs Appearing

```bash
# Check Promtail is running on all nodes
kubectl get pods -n observability -l app.kubernetes.io/name=promtail

# Check Promtail logs
kubectl logs -n observability -l app.kubernetes.io/name=promtail

# Check Loki logs
kubectl logs -n observability -l app.kubernetes.io/name=loki
```

### No Traces Appearing

```bash
# Check OpenTelemetry Collector
kubectl get pods -n observability -l app.kubernetes.io/name=opentelemetry-collector

# Check OTEL Collector logs
kubectl logs -n observability -l app.kubernetes.io/name=opentelemetry-collector

# Verify application is sending traces to correct endpoint
kubectl exec -it <your-pod> -- env | grep OTEL
```

### Disk Space Issues

```bash
# Check PVC usage
kubectl get pvc -n observability

# Check actual disk usage inside pods
kubectl exec -n observability prometheus-kube-prometheus-stack-prometheus-0 -c prometheus -- df -h /prometheus
kubectl exec -n observability tempo-0 -- df -h /var/tempo
kubectl exec -n observability loki-0 -- df -h /var/loki
```

## Retention and Storage Management

### Current Retention Policies

- **Prometheus**: 30 days (`retention = "30d"`)
- **Loki**: 31 days (`retention_period = "744h"`)
- **Tempo**: 30 days (`retention = "720h"`)

### Extending Storage

If you need more storage space:

1. **Expand PVC** (Azure Disk supports online expansion):
   ```bash
   kubectl edit pvc <pvc-name> -n observability
   # Change spec.resources.requests.storage to new size
   ```

2. **Update Helm values** to match:
   ```hcl
   # In observability-kube-prometheus-stack.tf
   storageSpec = {
     volumeClaimTemplate = {
       spec = {
         resources = {
           requests = {
             storage = "100Gi"  # Changed from 50Gi
           }
         }
       }
     }
   }
   ```

## Cost Optimization

### Current Costs (Approximate)

- **Storage**: 170 GB × $0.0875/GB/month ≈ **$15/month**
- **Compute**: Included in node costs (no additional charge)

### Optimization Strategies

1. **Reduce retention periods** if 30 days is too long
2. **Use object storage** for long-term storage (Azure Blob):
   - Prometheus → Thanos for long-term metrics
   - Loki → Azure Blob backend
   - Tempo → Azure Blob backend
3. **Sample metrics** at lower resolution for older data
4. **Filter logs** to exclude verbose/debug logs in production

## Security Considerations

### Current Security Measures

✅ **Encryption at rest**: All disks encrypted with customer-managed keys (CMK)
✅ **Network isolation**: All components communicate within cluster network
✅ **RBAC**: Kubernetes RBAC controls access to observability namespace
✅ **SSO**: Azure AD OAuth2 for Grafana authentication
✅ **Secret management**: OAuth2 secrets stored as Kubernetes secrets

### Future Enhancements

- [ ] Move Grafana admin password to Azure Key Vault (via CSI driver)
- [ ] Enable TLS for inter-component communication
- [ ] Implement network policies to restrict traffic
- [ ] Add audit logging for Grafana access
- [ ] Implement namespace-level data isolation with Grafana Enterprise

## Maintenance

### Regular Tasks

- **Weekly**: Review Grafana dashboards and alerts
- **Monthly**: Check disk usage and retention policies
- **Quarterly**: Update Helm chart versions
- **Yearly**: Review and rotate OAuth2 client secrets

### Backup and Disaster Recovery

**What to backup**:
1. **Grafana dashboards**: Stored on PVC, should be backed up regularly
2. **Grafana datasources**: Defined in Terraform, backed up via Git
3. **Alertmanager configuration**: Stored in ConfigMaps, backed up via Git

**What NOT to backup** (ephemeral/reproducible):
- Prometheus metrics (time-series data)
- Loki logs (log data)
- Tempo traces (trace data)

**Recovery**:
```bash
# Redeploy entire observability stack from Terraform
cd infrastructure
terraform apply

# Grafana will recreate its database and dashboards from provisioning configs
```

## Related Documentation

- [Architecture Overview](ARCHITECTURE.md) - Overall cluster architecture
- [Network Configuration](NETWORKING.md) - Network policies and Cilium setup
- [Security Checklist](SECURITY_CHECKLIST.md) - Security best practices
- [Terraform Modules](../infrastructure/) - IaC definitions

## References

- [Grafana Documentation](https://grafana.com/docs/)
- [Prometheus Documentation](https://prometheus.io/docs/)
- [Loki Documentation](https://grafana.com/docs/loki/latest/)
- [Tempo Documentation](https://grafana.com/docs/tempo/latest/)
- [OpenTelemetry Documentation](https://opentelemetry.io/docs/)
- [kube-prometheus-stack Helm Chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)
