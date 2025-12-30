#!/bin/bash
# Documentation Index Generator
# Creates comprehensive index of all documentation files

set -euo pipefail

OUTPUT_FILE="${HOME}/containers/docs/AUTO-DOCUMENTATION-INDEX.md"
DOCS_DIR="${HOME}/containers/docs"

log() {
    echo "[$(date +'%H:%M:%S')] $*" >&2
}

# Get recently updated files (last 7 days)
get_recent_files() {
    find "$DOCS_DIR" -name "*.md" -mtime -7 -type f | sort
}

# Count files in directory
count_files() {
    local dir=$1
    find "$dir" -name "*.md" -type f 2>/dev/null | wc -l
}

# Generate index
generate_index() {
    local timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    local total_docs=$(find "$DOCS_DIR" -name "*.md" -type f | wc -l)

    log "Generating documentation index..."

    cat > "$OUTPUT_FILE" <<EOF
# Documentation Index (Auto-Generated)

**Generated:** $timestamp
**Total Documents:** $total_docs

---

## Quick Navigation

### Auto-Generated Documentation
- [Service Catalog](AUTO-SERVICE-CATALOG.md) - Current service inventory
- [Network Topology](AUTO-NETWORK-TOPOLOGY.md) - Network architecture diagrams
- [Dependency Graph](AUTO-DEPENDENCY-GRAPH.md) - Service dependencies and critical paths
- [This Index](AUTO-DOCUMENTATION-INDEX.md) - Complete documentation catalog

### Key Entry Points
- [CLAUDE.md](../CLAUDE.md) - Project instructions for Claude Code (START HERE)
- [Homelab Architecture](20-operations/guides/homelab-architecture.md) - Complete architecture overview
- [Autonomous Operations](20-operations/guides/autonomous-operations.md) - OODA loop automation

---

## Documentation by Category

### 00-foundation/ ($(count_files "$DOCS_DIR/00-foundation") documents)

**Fundamentals and core concepts**

**Guides:**
EOF

    # Add foundation guides
    find "$DOCS_DIR/00-foundation/guides" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename=$(basename "$file")
        local relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
        echo "- [$basename]($relpath)" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

**Decisions (ADRs):**
EOF

    # Add foundation ADRs
    find "$DOCS_DIR/00-foundation/decisions" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename=$(basename "$file" .md)
        local relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
        # Extract ADR number if present
        local adr_num=$(echo "$basename" | grep -oP 'ADR-\d+' || echo "")
        echo "- $adr_num: [$basename]($relpath)" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

---

### 10-services/ ($(count_files "$DOCS_DIR/10-services") documents)

**Service-specific documentation and deployment guides**

**Service Guides:**
EOF

    # Add service guides
    find "$DOCS_DIR/10-services/guides" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename=$(basename "$file")
        local relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
        echo "- [$basename]($relpath)" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

**Service Decisions (ADRs):**
EOF

    # Add service ADRs
    find "$DOCS_DIR/10-services/decisions" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename=$(basename "$file" .md)
        local relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
        local adr_num=$(echo "$basename" | grep -oP 'ADR-\d+' || echo "")
        echo "- $adr_num: [$basename]($relpath)" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

---

### 20-operations/ ($(count_files "$DOCS_DIR/20-operations") documents)

**Operational procedures, runbooks, and architecture**

**Guides:**
EOF

    # Add operations guides
    find "$DOCS_DIR/20-operations/guides" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename=$(basename "$file")
        local relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
        echo "- [$basename]($relpath)" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

**Runbooks:**
EOF

    # Add runbooks
    find "$DOCS_DIR/20-operations/runbooks" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename=$(basename "$file" .md)
        local relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
        echo "- [$basename]($relpath)" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

---

### 30-security/ ($(count_files "$DOCS_DIR/30-security") documents)

**Security architecture, configurations, and incident response**

**Guides:**
EOF

    # Add security guides
    find "$DOCS_DIR/30-security/guides" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename=$(basename "$file")
        local relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
        echo "- [$basename]($relpath)" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

**Security ADRs:**
EOF

    # Add security ADRs
    find "$DOCS_DIR/30-security/decisions" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename=$(basename "$file" .md)
        local relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
        local adr_num=$(echo "$basename" | grep -oP 'ADR-\d+' || echo "")
        echo "- $adr_num: [$basename]($relpath)" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

**Runbooks:**
EOF

    # Add security runbooks
    find "$DOCS_DIR/30-security/runbooks" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename=$(basename "$file" .md)
        local relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
        echo "- [$basename]($relpath)" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

---

### 40-monitoring-and-documentation/ ($(count_files "$DOCS_DIR/40-monitoring-and-documentation") documents)

**Monitoring stack, SLOs, and documentation practices**

**Guides:**
EOF

    # Add monitoring guides
    find "$DOCS_DIR/40-monitoring-and-documentation/guides" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename=$(basename "$file")
        local relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
        echo "- [$basename]($relpath)" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

---

### 97-plans/ ($(count_files "$DOCS_DIR/97-plans") documents)

**Strategic plans and forward-looking projects**
EOF

    find "$DOCS_DIR/97-plans" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename=$(basename "$file")
        local relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
        local status="📋"
        if grep -q "Status.*Complete" "$file" 2>/dev/null; then
            status="✅"
        elif grep -q "Status.*Draft" "$file" 2>/dev/null; then
            status="📝"
        fi
        echo "- $status [$basename]($relpath)" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

---

### 98-journals/ ($(count_files "$DOCS_DIR/98-journals") documents)

**Chronological project history (append-only log)**

Complete dated entries documenting the homelab journey. See directory for full chronological listing.

---

### 99-reports/ ($(count_files "$DOCS_DIR/99-reports") documents)

**Automated system reports and point-in-time snapshots**

Recent intelligence reports and resource forecasts. Updated automatically by autonomous operations.

---

## Recently Updated (Last 7 Days)

EOF

    # Add recently updated files
    local recent_files=$(get_recent_files | head -20)
    if [[ -n "$recent_files" ]]; then
        echo "$recent_files" | while read -r file; do
            local basename=$(basename "$file")
            local relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
            local mod_date=$(stat -c %y "$file" | cut -d' ' -f1)
            echo "- $mod_date: [$basename]($relpath)" >> "$OUTPUT_FILE"
        done
    else
        echo "*No files modified in last 7 days*" >> "$OUTPUT_FILE"
    fi

    cat >> "$OUTPUT_FILE" <<'EOF'

---

## Documentation Practices

### Directory Structure

- **guides/** - Living reference documentation (updated in place)
- **decisions/** - Architecture Decision Records (immutable, dated)
- **runbooks/** - Operational procedures (DR, incident response)
- **journal/** - Chronological entries (append-only, never edited)

### File Naming Conventions

- **Guides:** Descriptive names (e.g., `slo-framework.md`)
- **ADRs:** `YYYY-MM-DD-ADR-NNN-description.md`
- **Journals:** `YYYY-MM-DD-description.md`
- **Reports:** `TYPE-YYYYMMDD-HHMMSS.json` or `.md`

See [CONTRIBUTING.md](CONTRIBUTING.md) for full documentation guidelines.

---

## Quick Search by Service

**Traefik:**
- Guide: [traefik.md](10-services/guides/traefik.md)
- Config: `~/containers/config/traefik/`
- Quadlet: `~/.config/containers/systemd/traefik.container`

**Authelia:**
- Guide: [authelia.md](10-services/guides/authelia.md)
- ADR: [ADR-006](30-security/decisions/2025-11-11-ADR-006-authelia-sso-yubikey-deployment.md)
- Config: `~/containers/config/authelia/`

**Jellyfin:**
- Guide: [jellyfin.md](10-services/guides/jellyfin.md)
- Management: `~/containers/scripts/jellyfin-manage.sh`

**Immich:**
- Guide: [immich.md](10-services/guides/immich.md)
- ADR: [ADR-004](10-services/decisions/2025-11-08-ADR-004-immich-deployment-architecture.md)

**Prometheus/Grafana:**
- Guides: [prometheus.md](10-services/guides/prometheus.md), [grafana.md](10-services/guides/grafana.md)
- SLO Framework: [slo-framework.md](40-monitoring-and-documentation/guides/slo-framework.md)

---

*Auto-generated by `scripts/generate-doc-index.sh`*
*Updates daily to reflect documentation changes*
EOF

    log "✓ Documentation index generated: $OUTPUT_FILE"
    log "  Total documents: $total_docs"
}

# Main
main() {
    log "Starting documentation index generation..."

    generate_index

    log "✓ Complete!"
}

main "$@"
