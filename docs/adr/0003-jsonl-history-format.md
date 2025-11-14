# 0003. JSONL Format for Build History

**Status**: Accepted
**Date**: 2025-11-13
**Decision Maker(s)**: Project Maintainer

## Context

### Background

System needs to track complete build history for each image to enable:
- Version history queries ("what versions have been built?")
- Rewind functionality ("rebuild from version X")
- Performance metrics ("how long do builds take?")
- Audit trail ("when was version Y built?")

### Problem Statement

Build history requires:
1. Simple, Git-friendly format (text, diffable, no binary)
2. Queryable without database (jq parsing)
3. Append-only for audit trail
4. Support for complex records (architectures, registries, performance data)

## Decision

Use JSONL format (JSON Lines - one JSON object per line) for `{image}/history.jsonl`.

### Implementation Details

**File Format**:
```json
{"version":"1.0.0","timestamp":"2025-11-13T10:30:00Z","commit":"abc123","branch":"master","architectures":{"amd64":{"status":"success","digest":"sha256:...","duration_seconds":245,"cache_hit_rate":88,"image_size_bytes":149221376},"arm64":{"status":"success","digest":"sha256:...","duration_seconds":238,"cache_hit_rate":85,"image_size_bytes":152445892}}}
{"version":"1.0.1","timestamp":"2025-11-13T11:15:00Z","commit":"def456","branch":"master","architectures":{"amd64":{"status":"success","digest":"sha256:...","duration_seconds":242},"arm64":{"status":"success","digest":"sha256:...","duration_seconds":240}}}
```

**Record Structure**:
- `version`: Detected/built version string
- `timestamp`: Build completion time (ISO 8601)
- `commit`: Git commit SHA of the build
- `branch`: Git branch name
- `architectures`: Per-architecture build results
  - `status`: success, partial (one arch failed), failed
  - `digest`: Pushed image digest (SHA256)
  - `duration_seconds`: Build time
  - `cache_hit_rate`: BuildKit cache effectiveness (%)
  - `image_size_bytes`: Final image size

**Queries**:
```bash
# List all versions
jq -r '.version' history.jsonl

# Get last 5 versions with timestamps
jq -r '.version + " (" + .timestamp + ")"' history.jsonl | tail -5

# Find builds after specific date
jq 'select(.timestamp > "2025-11-01")' history.jsonl

# Get performance metrics
jq '.architectures | to_entries | map(.key + ": " + (.value.duration_seconds | tostring) + "s")' history.jsonl | tail -1
```

### Key Principles Applied

- **Principle 3**: Version History is Immutable Truth - Append-only format prevents modification
- **Principle 10**: Scale Through Configuration - Text-based history scales to thousands of versions

## Consequences

### Positive

- **Simple, Git-friendly** - Text format diffs cleanly in Git
- **Queryable with standard tools** - jq handles all common queries
- **Append-only audit trail** - Can't modify past records
- **Human-readable** - Line-by-line format easy to inspect
- **No external dependencies** - No database required
- **Scalable** - Works efficiently for 1000+ records per image

### Negative

- **Manual parsing** - Scripts must use jq (vs. database API)
- **No built-in indexing** - Large history files require linear scan
- **Concurrent access** - Need file locking for append safety
- **Limited querying** - Complex queries harder than SQL

### Neutral

- **File size grows** - With 1000+ versions, history files can be 10-50KB per image

## Alternatives Considered

### Alternative 1: SQL Database (SQLite or PostgreSQL)

**Description**: Store history in database, query with SQL.

**Rejected Because**:
- Requires database setup/maintenance
- Not Git-friendly (binary or complex initialization)
- Overkill for this use case (simple append-only log)
- Adds deployment complexity
- History not easily diffable in Git

### Alternative 2: JSON Array

**Description**: Store all records in single JSON array: `[{...}, {...}, {...}]`

**Rejected Because**:
- Requires parsing entire file to append
- Slow for large history
- Git diffs show entire file as changed (even for one append)
- Not streaming-friendly

### Alternative 3: CSV Format

**Description**: Simple CSV format, queryable with standard tools.

**Rejected Because**:
- Can't represent nested data (architectures object)
- Complex escaping rules
- Harder to extend with new fields
- Less structured than JSON

## Implementation Details

**Append Operation**:
```bash
# Safely append to history.jsonl
{
  jq -n --arg v "1.2.3" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '{version: $v, timestamp: $ts, architectures: {}}'
} >> {image}/history.jsonl
```

**File Lock Handling**:
- Use `flock` for concurrent append safety
- Atomic write operations

**Immutability**:
- Never modify existing lines
- Only append new lines
- Delete only as part of explicit archive/prune operation

## Version Query Examples

```bash
# Latest version
tail -1 hello-world/history.jsonl | jq '.version'

# All versions (newest first)
tac hello-world/history.jsonl | jq '.version'

# Count total builds
wc -l hello-world/history.jsonl

# Builds in last 7 days
jq "select(.timestamp > \"$(date -u -d '7 days ago' +%Y-%m-%d)\")" hello-world/history.jsonl
```

## References

- JSONL Specification: [JSON Lines](https://jsonlines.org/)
- jq Manual: [jq documentation](https://stedolan.github.io/jq/)
- Related documentation: [performance.md](../performance.md)
