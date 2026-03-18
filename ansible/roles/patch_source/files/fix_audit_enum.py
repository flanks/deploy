#!/usr/bin/env python3
"""
Ensure shared/src/types/audit.ts AuditAction enum has all values
needed by the services. Idempotent — only adds missing values.
"""
import os
import re

SOURCE = os.environ.get("EURION_SOURCE", "/opt/eurion/source")
AUDIT_PATH = f"{SOURCE}/backend/shared/src/types/audit.ts"

REQUIRED_VALUES = {
    "SETTINGS_UPDATED": "settings.updated",
    "EXPORT_REQUESTED": "export.requested",
    "GDPR_ERASURE": "gdpr.erasure",
    "GDPR_EXPORT": "gdpr.export",
    "CREATE": "resource.created",
    "UPDATE": "resource.updated",
    "DELETE": "resource.deleted",
    "WORKFLOW_CREATED": "workflow.created",
    "WORKFLOW_APPROVED": "workflow.approved",
    "WORKFLOW_REJECTED": "workflow.rejected",
    "CALL_ENDED": "call.ended",
    "RECORDING_STARTED": "recording.started",
    "RECORDING_STOPPED": "recording.stopped",
}

with open(AUDIT_PATH) as f:
    content = f.read()

# Find the closing brace of the AuditAction enum specifically (not any interface).
# Locate the enum block and find its own closing brace.
enum_match = re.search(r'(export enum AuditAction \{[^}]+)\}', content, re.DOTALL)
if not enum_match:
    print("ERROR: Could not find AuditAction enum in audit.ts")
    exit(1)

enum_end = enum_match.end() - 1  # position of the closing } of the enum
added = []

for key, value in REQUIRED_VALUES.items():
    # Check only within the enum block to avoid false positives in interfaces
    if f"  {key} " not in enum_match.group(0):
        insert_line = f"  {key} = '{value}',"
        content = content[:enum_end] + f"\n{insert_line}" + content[enum_end:]
        # Re-match after insertion so subsequent inserts go to the right place
        enum_match = re.search(r'(export enum AuditAction \{[^}]+)\}', content, re.DOTALL)
        enum_end = enum_match.end() - 1
        added.append(key)

with open(AUDIT_PATH, "w") as f:
    f.write(content)

print(f"AuditAction: added {len(added)} missing values: {added}")
