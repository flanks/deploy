#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────────────────────
# configure-spam-filter.sh
# Tunes Stalwart spam filter for relay traffic (Mailgun → Stalwart pipeline).
#
# Problem: Inbound mail relayed from Mailgun triggers relay-inherent spam rules
# (SPF/DMARC/HELO checks fail because the webhook relay isn't the original MTA).
# These scores push legitimate mail to Junk.
#
# Solution: Zero out scores for relay-inherent rules and raise the spam
# threshold so relayed mail lands in INBOX.
#
# Usage:
#   docker exec eurion-stalwart sh -c "$(cat configure-spam-filter.sh)"
#   # OR run each command individually:
#   docker exec eurion-stalwart stalwart-cli -u https://127.0.0.1:443 -c admin:PASSWORD server add-config KEY VALUE
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

STALWART_URL="${STALWART_URL:-https://127.0.0.1:443}"
STALWART_CREDS="${STALWART_CREDS:-admin:nRcbdrbws9}"

cli() {
  stalwart-cli -u "$STALWART_URL" -c "$STALWART_CREDS" "$@"
}

echo "=== Configuring Stalwart spam filter for relay traffic ==="

# Raise spam/discard thresholds so relayed mail isn't misclassified
cli server add-config spam-filter.score.spam 999.0
cli server add-config spam-filter.score.discard 9999.0

# Zero out scores for rules that always trigger on relayed mail
cli server add-config spam-filter.list.scores.VIOLATED_DIRECT_SPF 0.0
cli server add-config spam-filter.list.scores.HELO_IPREV_MISMATCH 0.0
cli server add-config spam-filter.list.scores.DMARC_NA 0.0
cli server add-config spam-filter.list.scores.RCVD_COUNT_ZERO 0.0
cli server add-config spam-filter.list.scores.RCVD_NO_TLS_LAST 0.0

# Disable spam filter on SMTP and internal SMTP sessions
# (belt and suspenders — the score overrides above handle it too)
cli server add-config session.smtp.data.spam-filter.enable false
cli server add-config session.smtp-internal.data.spam-filter.enable false

echo "=== Spam filter configured for relay traffic ==="
echo ""
echo "Explanation of zeroed rules:"
echo "  VIOLATED_DIRECT_SPF (was 3.50)  — SPF fails because relay IP isn't in sender's SPF record"
echo "  HELO_IPREV_MISMATCH (was 1.00)  — Docker container HELO doesn't match PTR"
echo "  DMARC_NA (was 1.00)             — DMARC can't validate relay-injected mail"
echo "  RCVD_COUNT_ZERO (was 0.50)      — Reconstructed MIME has no Received headers"
echo "  RCVD_NO_TLS_LAST (was 0.25)     — Internal Docker SMTP hop isn't TLS"
