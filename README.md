# ![Azure RBAC Orphaned Assignment Cleanup](./assets/azure-rbac-banner-1280x640.jpg)

This repository provides an **Azure DevOps pipeline and PowerShell automation** to detect and safely remediate **orphaned Azure RBAC role assignments** across subscriptions and management groups.

An *orphaned* RBAC assignment occurs when a role assignment still exists in Azure Resource Manager (ARM), but the associated **Microsoft Entra ID object** (user, group, service principal, managed identity, etc.) no longer exists.

The solution is designed to align with the **Microsoft Cloud Adoption Framework (CAF)** and **Well-Architected Framework** security guidance, and supports principles outlined in the **Australian Cyber Security Centre (ACSC) Essential Eight**, with a strong emphasis on governance, least privilege, and operational safety.

---

## Key Capabilities

- Detects orphaned RBAC assignments across:
  - Azure subscriptions
  - Azure management groups
- Produces a **reviewable JSON artifact** prior to any remediation
- Requires **manual approval** before removal actions occur
- Applies **dual validation safeguards** before deleting any role assignment
- Avoids deletion attempts where Azure enforces guardrails on the **last Owner** or **User Access Administrator** at subscription scope
- Designed for scheduled, repeatable execution in Azure DevOps
- Tested on a **vanilla Ubuntu Microsoft-hosted Azure DevOps agent**

### Future Enhancements

Planned or potential enhancements include:

- Optional scanning of **resource group–scoped RBAC assignments**, following the same staged and safeguarded approach used for subscriptions and management groups.

Any expansion of scope will continue to prioritise:
- explicit validation
- least privilege
- manual approval prior to remediation

---

## Cloud Adoption Framework & Well-Architected Alignment

This project aligns with Microsoft’s **Cloud Adoption Framework (CAF)** Secure methodology and the **Well-Architected Framework – Security pillar**.

### Zero Trust & Least Privilege

- Identity existence is **explicitly verified** prior to RBAC changes, aligning with CAF’s *Verify explicitly* principle.
- A minimal custom RBAC role is used for cleanup operations, enforcing *least privilege* access.

Reference:

- CAF Security considerations: <https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/strategy/inform/security>
- CAF Secure methodology: <https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/secure/overview>
- Cloud Adoption Framework overview: <https://learn.microsoft.com/en-us/azure/cloud-adoption-framework/overview>

### Governance & Operational Safety

- Manual approval gates ensure RBAC changes are intentional and reviewed.
- Guardrails prevent removal of critical administrative access.
- The process is auditable via structured logs and artifacts.

---

## ACSC Essential Eight Alignment

While focused on cloud identity and access management, this solution supports several **ACSC Essential Eight** principles, particularly:

- **Restrict Administrative Privileges**
  - Automated identification and cleanup of stale RBAC assignments reduces unnecessary administrative access.
- **Least Privilege Access**
  - Service connections operate with narrowly scoped permissions.

Reference:

- ACSC Essential Eight overview: <https://learn.microsoft.com/en-us/compliance/anz/e8-overview>

---

## Pipeline Architecture

The Azure DevOps pipeline executes in **two controlled stages**.

### Stage 1 – Scan for Unknown RBAC Assignments

- Enumerates RBAC role assignments across scoped subscriptions and management groups.
- Validates the existence of principals in Microsoft Entra ID using Microsoft Graph.
- Outputs a JSON artifact (`UnknownAssignments.json`) listing orphaned assignments.
- Produces annotated logs for traceability.

### Stage 2 – Review and Remove Unknown Assignments

- Requires **manual approval** before execution.
- Re-validates each assignment before removal.
- Deletes only assignments that still meet strict safety conditions.

---

## Removal Safeguards

A role assignment is removed **only when all of the following conditions are met**:

1. The Microsof Entra ID object **does not exist**.
2. The RBAC role assignment **still exists in Azure**.
3. The assignment is **not** the last:
   - Owner, or
   - User Access Administrator  
   at the **subscription scope**.

These safeguards ensure that:

- No blind deletions occur.
- Race conditions are avoided.
- Subscriptions cannot be orphaned from administrative access.

---

## Permissions Required

### Microsoft Graph

Used solely for identity validation.

- Application permission: `Directory.Read.All`

### Azure RBAC (ARM)

The service connection requires permissions to read and delete role assignments.

A custom role similar to the following is recommended:

```json
{
  "actions": [
    "Microsoft.Authorization/roleAssignments/read",
    "Microsoft.Authorization/roleAssignments/delete"
  ],
  "notActions": [],
  "dataActions": [],
  "notDataActions": []
}
```

Additional notes:

- The service connection also has **Reader** access in Azure.
- The custom role can be assigned at subscription or management group scope depending on desired coverage.
- Management group enumeration **requires** a subscription context with the `Microsoft.Management` resource provider registered (e.g., `az provider register --namespace Microsoft.Management`).

---

## Local Development Environment (Dev Container)

For local development using VS Code Dev Containers, see [devcontainer.md](./devcontainer.md).

---

## Azure DevOps Agent Considerations

- The pipeline is configured and tested for a **standard Ubuntu Microsoft-hosted Azure DevOps agent**.
- Depending on individual agent configurations:
  - Some tooling and module installation steps may be unnecessary.
  - These steps can be removed or optimised safely.
- PowerShell 7.2+ is required.

---

## Artifacts

The scan stage produces a build artifact containing:

- `Logs/` – Detailed execution logs.
- `UnknownAssignments.json` – The authoritative list of proposed RBAC removals.

This JSON file is the **sole input** to the removal stage and must be reviewed prior to approval.

---

## Known Platform Behaviours

- Azure enforces guardrails preventing deletion of the **last Owner** or **User Access Administrator** at subscription scope.
- Such assignments are skipped and clearly reported for manual remediation if required.

---

## Intended Use

This repository is provided as a **reference implementation** for improving RBAC hygiene in Azure environments.

Consumers should:

- Review and adapt the solution to their governance model.
- Validate permissions and safeguards in non-production environments first.

---
