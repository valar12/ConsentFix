# Entra ID Auth Code Fix (ConsentFix Mitigation)

This repository contains **PowerShell scripts** designed to mitigate the *ConsentFix / OAuth authorization-code phishing* technique targeting Microsoft Entra ID tenants.

The scripts implement Microsoft-recommended hardening by:

* Requiring **explicit assignment** to selected Microsoft first-party service principals
* Assigning access via a **security group**
* Preventing unassigned users from authenticating to vulnerable OAuth public-client apps (e.g. Azure CLI)

This approach significantly reduces tenant-wide exposure while preserving access for approved users.

---

## Background

ConsentFix is an identity phishing technique that abuses legitimate Microsoft OAuth flows for **pre-consented first-party applications** (such as Azure CLI and PowerShell). Users can be socially engineered into completing an OAuth sign-in and unknowingly providing an authorization code, which attackers can redeem for access tokens.

This is **not a traditional CVE**; it is an abuse of expected OAuth behavior combined with social engineering. Mitigation focuses on **restricting which users are allowed to authenticate to these applications**.

---

## Scripts in this Repository

### 1. `Identify-EntraAppRole-AuthCodeFix.ps1`

**Purpose:**

* Identifies whether target Microsoft first-party service principals exist in the tenant
* Reports whether `AppRoleAssignmentRequired` is enabled
* Helps assess current exposure

**Use when:**

* You want a read-only assessment before making changes

---

### 2. `CreateRestrict-EntraAppRole-AuthCodeFix.ps1`

**Purpose:**

* Creates a **security group** (if it does not already exist)
* Ensures service principals exist for specified Microsoft app IDs
* Sets `AppRoleAssignmentRequired = true`
* Assigns the security group to each service principal

**This is the primary mitigation script.**

**Key behaviors:**

* Reuses an existing group if the display name already exists
* Fails safely if multiple groups share the same name
* Validates the group is **security-enabled**
* Avoids duplicate app role assignments

---

### 3. `List-EntraAppRole-RequiredGroups-AuthCodeFix.ps1`

**Purpose:**

* Lists which **groups are assigned** to each protected service principal
* Useful for validation, audits, and documentation

---

## Prerequisites

* PowerShell 7.x recommended
* Microsoft Graph PowerShell SDK installed

```powershell
Install-Module Microsoft.Graph -Scope CurrentUser
```

* Account with one of the following roles:

  * Global Administrator
  * Privileged Role Administrator

---

## Required Microsoft Graph Permissions

The scripts request the following delegated permissions:

* `Application.ReadWrite.All`
* `AppRoleAssignment.ReadWrite.All`
* `Group.ReadWrite.All`

These permissions are required to:

* Modify service principals
* Assign app roles
* Create or read security groups

---

## Recommended Usage Order

1. **Assess current state**

   ```powershell
   .\Identify-EntraAppRole-AuthCodeFix.ps1
   ```

2. **Apply mitigation (create/reuse group and restrict apps)**

   ```powershell
   .\CreateRestrict-EntraAppRole-AuthCodeFix.ps1 -GroupDisplayName "Restricted-Microsoft-CLI-Access"
   ```

3. **Validate assignments**

   ```powershell
   .\List-EntraAppRole-RequiredGroups-AuthCodeFix.ps1
   ```

---

## Default Microsoft Apps Covered

The mitigation targets commonly abused Microsoft first-party public-client apps, including:

* Microsoft Azure CLI
* Microsoft Azure PowerShell
* Visual Studio
* Visual Studio Code
* Microsoft Teams PowerShell Cmdlets

You can customize the app list by modifying the `$Apps` parameter in the scripts.

---

## Operational Guidance

* **Do not assign this group broadly.** Only users who genuinely need CLI/dev tooling should be members.
* Consider managing group membership via **Privileged Identity Management (PIM)**.
* Restricting these apps may impact developers or administrators — test in a pilot tenant if possible.
* This mitigation **does not remediate already-compromised accounts**. Use standard incident response actions if compromise is suspected.

---

## Security Notes

* The scripts are designed to be **safe to re-run** (idempotent where possible).
* Group lookup is performed by **display name** — ensure uniqueness.
* All Graph sessions are explicitly disconnected after execution.

---

## Disclaimer

These scripts are provided as-is. Review and test in your environment before production use. Ensure changes align with your organization’s security and access governance policies.

---

## References

* Push Security – ConsentFix research
* Microsoft Entra ID documentation
* MSEndpointMgr ConsentFix Quick Fix

---

**Maintainers:** Security / Identity Engineering
