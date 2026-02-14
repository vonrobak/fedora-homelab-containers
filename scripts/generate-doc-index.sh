#!/bin/bash
# Documentation Index Generator
# Creates comprehensive index of all documentation files
# Quick Search section dynamically discovers guide files for each service

set -euo pipefail

OUTPUT_FILE="${HOME}/containers/docs/AUTO-DOCUMENTATION-INDEX.md"
DOCS_DIR="${HOME}/containers/docs"
GUIDES_DIR="${HOME}/containers/docs/10-services/guides"
QUADLET_DIR="${HOME}/containers/quadlets"

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

# Find all documentation related to a service
find_service_docs() {
    local service=$1

    # Direct guide match
    if [[ -f "${GUIDES_DIR}/${service}.md" ]]; then
        echo "guide:10-services/guides/${service}.md"
    fi

    # Try base name for multi-part services (immich-server → immich)
    local base_name="${service%%-*}"
    if [[ "$base_name" != "$service" && -f "${GUIDES_DIR}/${base_name}.md" ]]; then
        echo "guide:10-services/guides/${base_name}.md"
    fi

    # Related guides (e.g., immich-ml-troubleshooting.md for immich)
    local search_prefix="$service"
    [[ "$base_name" != "$service" ]] && search_prefix="$base_name"
    for f in "${GUIDES_DIR}/${search_prefix}-"*.md; do
        [[ -f "$f" ]] || continue
        local base
        base=$(basename "$f")
        echo "related:10-services/guides/${base}"
    done

    # ADR references (grep for service name in decision files)
    for dir in "$DOCS_DIR"/*/decisions; do
        [[ -d "$dir" ]] || continue
        for f in "$dir"/*"${service}"*.md; do
            [[ -f "$f" ]] || continue
            local relpath
            relpath=$(realpath --relative-to="$DOCS_DIR" "$f")
            local adr_num
            adr_num=$(basename "$f" .md | grep -oP 'ADR-\d+' || echo "")
            echo "adr:${relpath}:${adr_num}"
        done
    done

    # Config directory
    if [[ -d "${HOME}/containers/config/${service}" ]]; then
        echo "config:~/containers/config/${service}/"
    fi

    # Quadlet file
    if [[ -f "${QUADLET_DIR}/${service}.container" ]]; then
        echo "quadlet:~/.config/containers/systemd/${service}.container"
    fi
}

# Generate index
generate_index() {
    local timestamp
    timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    local total_docs
    total_docs=$(find "$DOCS_DIR" -name "*.md" -type f | wc -l)

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

    # Foundation guides
    find "$DOCS_DIR/00-foundation/guides" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename
        basename=$(basename "$file")
        local relpath
        relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
        echo "- [$basename]($relpath)" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

**Decisions (ADRs):**
EOF

    find "$DOCS_DIR/00-foundation/decisions" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename
        basename=$(basename "$file" .md)
        local relpath
        relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
        local adr_num
        adr_num=$(echo "$basename" | grep -oP 'ADR-\d+' || echo "")
        echo "- $adr_num: [$basename]($relpath)" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

---

### 10-services/ ($(count_files "$DOCS_DIR/10-services") documents)

**Service-specific documentation and deployment guides**

**Service Guides:**
EOF

    find "$DOCS_DIR/10-services/guides" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename
        basename=$(basename "$file")
        local relpath
        relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
        echo "- [$basename]($relpath)" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

**Service Decisions (ADRs):**
EOF

    find "$DOCS_DIR/10-services/decisions" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename
        basename=$(basename "$file" .md)
        local relpath
        relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
        local adr_num
        adr_num=$(echo "$basename" | grep -oP 'ADR-\d+' || echo "")
        echo "- $adr_num: [$basename]($relpath)" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

---

### 20-operations/ ($(count_files "$DOCS_DIR/20-operations") documents)

**Operational procedures, runbooks, and architecture**

**Guides:**
EOF

    find "$DOCS_DIR/20-operations/guides" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename
        basename=$(basename "$file")
        local relpath
        relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
        echo "- [$basename]($relpath)" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

**Runbooks:**
EOF

    find "$DOCS_DIR/20-operations/runbooks" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename
        basename=$(basename "$file" .md)
        local relpath
        relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
        echo "- [$basename]($relpath)" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

---

### 30-security/ ($(count_files "$DOCS_DIR/30-security") documents)

**Security architecture, configurations, and incident response**

**Guides:**
EOF

    find "$DOCS_DIR/30-security/guides" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename
        basename=$(basename "$file")
        local relpath
        relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
        echo "- [$basename]($relpath)" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

**Security ADRs:**
EOF

    find "$DOCS_DIR/30-security/decisions" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename
        basename=$(basename "$file" .md)
        local relpath
        relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
        local adr_num
        adr_num=$(echo "$basename" | grep -oP 'ADR-\d+' || echo "")
        echo "- $adr_num: [$basename]($relpath)" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

**Runbooks:**
EOF

    find "$DOCS_DIR/30-security/runbooks" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename
        basename=$(basename "$file" .md)
        local relpath
        relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
        echo "- [$basename]($relpath)" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

---

### 40-monitoring-and-documentation/ ($(count_files "$DOCS_DIR/40-monitoring-and-documentation") documents)

**Monitoring stack, SLOs, and documentation practices**

**Guides:**
EOF

    find "$DOCS_DIR/40-monitoring-and-documentation/guides" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename
        basename=$(basename "$file")
        local relpath
        relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
        echo "- [$basename]($relpath)" >> "$OUTPUT_FILE"
    done

    cat >> "$OUTPUT_FILE" <<EOF

---

### 97-plans/ ($(count_files "$DOCS_DIR/97-plans") documents)

**Strategic plans and forward-looking projects**
EOF

    find "$DOCS_DIR/97-plans" -name "*.md" -type f 2>/dev/null | sort | while read -r file; do
        local basename
        basename=$(basename "$file")
        local relpath
        relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
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

    local recent_files
    recent_files=$(get_recent_files | head -20)
    if [[ -n "$recent_files" ]]; then
        echo "$recent_files" | while read -r file; do
            local basename
            basename=$(basename "$file")
            local relpath
            relpath=$(realpath --relative-to="$DOCS_DIR" "$file")
            local mod_date
            mod_date=$(stat -c %y "$file" | cut -d' ' -f1)
            echo "- $mod_date: [$basename]($relpath)" >> "$OUTPUT_FILE"
        done
    else
        echo "*No files modified in last 7 days*" >> "$OUTPUT_FILE"
    fi

    # Dynamic Quick Search section
    cat >> "$OUTPUT_FILE" <<'EOF'

---

## Quick Search by Service

EOF

    # Get all running services and generate documentation links
    local services
    services=$(podman ps --format '{{.Names}}' 2>/dev/null | sort || true)

    # Group services for display (primary services only, skip backing stores)
    local primary_services="traefik authelia crowdsec jellyfin immich-server nextcloud vaultwarden home-assistant homepage gathio prometheus grafana loki alertmanager"

    for service in $primary_services; do
        # Skip if not running
        echo "$services" | grep -qx "$service" || continue

        local display_name="$service"
        # Capitalize first letter for display
        display_name="$(echo "$service" | sed 's/\b./\U&/; s/-/ /g' | sed 's/\b./\U&/g')"

        echo "**${display_name}:**" >> "$OUTPUT_FILE"

        local found_docs=false
        while IFS=':' read -r type path extra; do
            case "$type" in
                guide)
                    echo "- Guide: [$(basename "$path")](${path})" >> "$OUTPUT_FILE"
                    found_docs=true
                    ;;
                related)
                    echo "- Related: [$(basename "$path")](${path})" >> "$OUTPUT_FILE"
                    found_docs=true
                    ;;
                adr)
                    echo "- ADR: [${extra}](${path})" >> "$OUTPUT_FILE"
                    found_docs=true
                    ;;
                config)
                    echo "- Config: \`${path}\`" >> "$OUTPUT_FILE"
                    found_docs=true
                    ;;
                quadlet)
                    echo "- Quadlet: \`${path}\`" >> "$OUTPUT_FILE"
                    found_docs=true
                    ;;
            esac
        done < <(find_service_docs "$service")

        # Monitoring services share a guide
        case "$service" in
            prometheus|grafana|loki|alertmanager)
                echo "- Stack Guide: [monitoring-stack.md](40-monitoring-and-documentation/guides/monitoring-stack.md)" >> "$OUTPUT_FILE"
                echo "- SLO Framework: [slo-framework.md](40-monitoring-and-documentation/guides/slo-framework.md)" >> "$OUTPUT_FILE"
                found_docs=true
                ;;
        esac

        if [[ "$found_docs" == "false" ]]; then
            echo "- *(no dedicated documentation)*" >> "$OUTPUT_FILE"
        fi

        echo "" >> "$OUTPUT_FILE"
    done

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

*Auto-generated by `scripts/generate-doc-index.sh`*
*Updates daily to reflect documentation changes*
EOF

    log "✓ Documentation index generated: $OUTPUT_FILE"
    log "  Total documents: $total_docs"
}

main() {
    log "Starting documentation index generation..."

    generate_index

    log "✓ Complete!"
}

main "$@"
