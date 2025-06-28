#!/usr/bin/env bash
# =============================================================================
# k8s-utils.sh: List or compare container images across Kubernetes namespaces
# Usage:
#   ./k8s-utils.sh list    [-c CONTEXT] -n NAMESPACE [--html FILE]
#   ./k8s-utils.sh compare [-c1 CTX1] -n1 NS1 [-c2 CTX2] -n2 NS2 [--html FILE]
# Requires: kubectl, jq
# =============================================================================
set -euo pipefail

# ---- Helpers ----
usage() {
  cat <<EOF >&2
Usage:
  $0 list    [-c CONTEXT] -n NAMESPACE [--html FILE]
  $0 compare [-c1 CTX1] -n1 NS1 [-c2 CTX2] -n2 NS2 [--html FILE]
EOF
  exit 1
}
require_cmd() { command -v "$1" &>/dev/null || {
  echo "❌ '$1' not found" >&2
  exit 1
}; }
resolve_ctx() { [[ -n "$1" ]] && echo "$1" || kubectl config current-context; }
check_ctx() { kubectl config get-contexts -o name | grep -qxF "$1" || {
  echo "❌ context '$1' not found" >&2
  exit 1
}; }
check_ns() { kubectl --context "$1" get namespace "$2" &>/dev/null || {
  echo "❌ namespace '$2' not in context '$1'" >&2
  exit 1
}; }

# Draw table border given column widths
print_border() {
  local widths=($@) line="+"
  for w in "${widths[@]}"; do
    line+=$(printf '%*s' $((w + 2)) '' | tr ' ' '-')+
  done
  echo "$line"
}

# Escape &, <, > in input
html_escape() {
  local s="$1"
  printf '%s' "$s" |
    sed -e 's/&/\&amp;/g' \
      -e 's/</\&lt;/g' \
      -e 's/>/\&gt;/g'
}

# Default resource kinds in desired order
DEFAULT_KINDS=(Deployment StatefulSet DaemonSet Job CronJob Service)

# Fetch resources: kind|name|images|versions
get_resources() {
  local ctx=$1 ns=$2
  for kind in "${DEFAULT_KINDS[@]}"; do
    if [[ "$kind" == "Service" ]]; then
      # Services: no containers
      mapfile -t items < <(
        kubectl --context "$ctx" -n "$ns" get svc -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null | sort
      )
      for name in "${items[@]}"; do
        echo "Service|$name||"
      done
    else
      # Workloads: list containers
      kubectl --context "$ctx" -n "$ns" get "$(echo $kind | tr '[:upper:]' '[:lower:]')s" -o json 2>/dev/null | jq -r \
        " .items[] |
          \"$kind\" as \$kt |
          .metadata.name as \$nm |
          (if .spec.template? then .spec.template.spec.containers
           elif .spec.jobTemplate? then .spec.jobTemplate.spec.template.spec.containers
           else [] end) as \$ctrs |
          (\$ctrs | map((.image | split(\"/\")[-1] | split(\":\") | .[0])) | join(\",\")) as \$imgs |
          (\$ctrs | map((.image | split(\":\") | if length>1 then .[1] else \"\" end)) | join(\",\")) as \$vers |
          \"\(\$kt)|\(\$nm)|\(\$imgs)|\(\$vers)\""
    fi
  done
}

# ---- LIST MODE ----
list_mode() {
  local ctx="" ns=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -c | --context)
      ctx="$2"
      shift 2
      ;;
    -n | --namespace)
      ns="$2"
      shift 2
      ;;
    --html)
      html="$2"
      shift 2
      ;;
    -h | --help) usage ;;
    *)
      echo "❌ Unknown $1" >&2
      usage
      ;;
    esac
  done
  [[ -z "$ns" ]] && echo "❌ namespace required" >&2 && usage

  require_cmd kubectl
  require_cmd jq

  ctx=$(resolve_ctx "$ctx")

  check_ctx "$ctx"
  check_ns "$ctx" "$ns"

  mapfile -t rows < <(get_resources "$ctx" "$ns")

  # Compute widths
  local h1=TYPE h2=NAME h3=IMAGES h4=VERSIONS
  local w1=${#h1} w2=${#h2} w3=${#h3} w4=${#h4}
  for r in "${rows[@]}"; do
    IFS='|' read -r t n i v <<<"$r"
    ((${#t} > w1)) && w1=${#t}
    ((${#n} > w2)) && w2=${#n}
    ((${#i} > w3)) && w3=${#i}
    ((${#v} > w4)) && w4=${#v}
  done

  print_border $w1 $w2 $w3 $w4
  printf "| %-${w1}s | %-${w2}s | %-${w3}s | %-${w4}s |\n" "$h1" "$h2" "$h3" "$h4"
  print_border $w1 $w2 $w3 $w4
  for r in "${rows[@]}"; do
    IFS='|' read -r t n i v <<<"$r"
    printf "| %-${w1}s | %-${w2}s | %-${w3}s | %-${w4}s |\n" "$t" "$n" "$i" "$v"
  done
  print_border $w1 $w2 $w3 $w4

  if [[ -n "$html" ]]; then
    {
      echo '<!DOCTYPE html><html><head><meta charset="utf-8">'
      echo '<style>'
      echo 'table.compare-tbl { border-collapse:collapse; margin-bottom:1rem; }'
      echo 'table.compare-tbl th, table.compare-tbl td { border:1px solid #444; padding:8px; text-align:left; }'
      echo 'table.compare-tbl thead th { background:#f0f0f0; }'
      echo 'table.compare-tbl tbody tr:nth-child(even) { background:#fafafa; }'
      echo 'h1 { font-family:sans-serif; margin-bottom:1rem; }'
      echo 'pre.context { background:#1e1e1e; color:#d4d4d4; font-family:monospace; padding:0.5rem 1rem; border-radius:4px; display:inline-block; margin-bottom:2rem; }'
      echo '</style></head><body>'
      echo "<h1>Resources in:</h1>"
      echo "<pre class='context'>Context: $(html_escape "$ctx")</pre>"
      echo "<pre class='context'>Namespace: $(html_escape "$ns")</pre>"
      echo '<table class="compare-tbl">'
      echo "<thead><tr><th>Type</th><th>Name</th><th>Images</th><th>Versions</th></tr></thead><tbody>"
      for r in "${rows[@]}"; do
        IFS='|' read -r t n i v <<<"$r"
        printf "<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td></tr>\n" \
          "$(html_escape "$t")" \
          "$(html_escape "$n")" \
          "$(html_escape "$i")" \
          "$(html_escape "$v")"
      done
      echo "</tbody></table>"
      echo "</body></html>"
    } >"$html"

    echo -e "\nHTML file generated: $html\n"
  fi
}

# ---- COMPARE MODE ----
compare_mode() {
  local ctx1="" ns1="" ctx2="" ns2="" html=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -c1 | --context1)
      ctx1="$2"
      shift 2
      ;;
    -n1 | --namespace1)
      ns1="$2"
      shift 2
      ;;
    -c2 | --context2)
      ctx2="$2"
      shift 2
      ;;
    -n2 | --namespace2)
      ns2="$2"
      shift 2
      ;;
    --html)
      html="$2"
      shift 2
      ;;
    -h | --help) usage ;;
    *)
      echo "❌ Unknown $1" >&2
      usage
      ;;
    esac
  done
  [[ -z "$ns1" || -z "$ns2" ]] && echo "❌ both namespaces required" >&2 && usage

  require_cmd kubectl
  require_cmd jq

  ctx1=$(resolve_ctx "$ctx1")
  ctx2=$(resolve_ctx "$ctx2")

  check_ctx "$ctx1"
  check_ctx "$ctx2"
  check_ns "$ctx1" "$ns1"
  check_ns "$ctx2" "$ns2"

  mapfile -t d1 < <(get_resources "$ctx1" "$ns1")
  mapfile -t d2 < <(get_resources "$ctx2" "$ns2")

  declare -A V1 V2 I1 I2 P1 P2
  for e in "${d1[@]}"; do
    IFS='|' read -r k n i v <<<"$e"
    key="$k|$n"
    V1["$key"]="$v"
    I1["$key"]="$i"
    P1["$key"]=1
  done
  for e in "${d2[@]}"; do
    IFS='|' read -r k n i v <<<"$e"
    key="$k|$n"
    V2["$key"]="$v"
    I2["$key"]="$i"
    P2["$key"]=1
  done

  mapfile -t ALL_KEYS < <(
    printf '%s\n' "${!P1[@]}" "${!P2[@]}" | sort -u
  )

  DIFFS=()
  MATCHES=()

  for key in "${ALL_KEYS[@]}"; do
    IFS='|' read -r k n <<<"$key"
    if [[ "$k" == "Service" ]]; then
      if [[ -v P1[$key] ]]; then v1='<present>'; else v1='<missing>'; fi
      if [[ -v P2[$key] ]]; then v2='<present>'; else v2='<missing>'; fi
      r="$k|$n||$v1|$v2"
    else
      v1=${V1[$key]:-<missing>}
      v2=${V2[$key]:-<missing>}
      imgs=${I1[$key]:-${I2[$key]:-}}
      r="$k|$n|$imgs|$v1|$v2"
    fi
    [[ "$v1" == "$v2" ]] && MATCHES+=("$r") || DIFFS+=("$r")
  done

  mapfile -t DIFFS < <(printf "%s\n" "${DIFFS[@]}" | sort -t '|' -k1,1 -k2,2)
  mapfile -t MATCHES < <(printf "%s\n" "${MATCHES[@]}" | sort -t '|' -k1,1 -k2,2)

  # Render function
  render_table() {
    local title="$1"
    shift
    local rows=("$@")
    local h1=TYPE h2=NAME h3=IMAGES h4=$ns1 h5=$ns2
    local w1=${#h1} w2=${#h2} w3=${#h3} w4=${#h4} w5=${#h5}
    for r in "${rows[@]}"; do
      IFS='|' read -r t n i v1 v2 <<<"$r"
      ((${#t} > w1)) && w1=${#t}
      ((${#n} > w2)) && w2=${#n}
      ((${#i} > w3)) && w3=${#i}
      ((${#v1} > w4)) && w4=${#v1}
      ((${#v2} > w5)) && w5=${#v2}
    done
    echo -e "\n$title"
    print_border $w1 $w2 $w3 $w4 $w5
    printf "| %-${w1}s | %-${w2}s | %-${w3}s | %-${w4}s | %-${w5}s |\n" "$h1" "$h2" "$h3" "$h4" "$h5"
    print_border $w1 $w2 $w3 $w4 $w5
    for r in "${rows[@]}"; do
      IFS='|' read -r t n i v1 v2 <<<"$r"
      printf "| %-${w1}s | %-${w2}s | %-${w3}s | %-${w4}s | %-${w5}s |\n" "$t" "$n" "$i" "$v1" "$v2"
    done
    print_border $w1 $w2 $w3 $w4 $w5
  }

  # Show differences then equals
  [[ ${#DIFFS[@]} -gt 0 ]] && render_table "🔍 Differences" "${DIFFS[@]}"
  [[ ${#MATCHES[@]} -gt 0 ]] && render_table "✅ Matches" "${MATCHES[@]}"

  if [[ -n "$html" ]]; then
    {
      echo '<!DOCTYPE html><html><head><meta charset="utf-8">'
      echo '<style>'
      echo 'table.compare-tbl { border-collapse:collapse; margin-bottom:1rem; }'
      echo 'table.compare-tbl th, table.compare-tbl td { border:1px solid #444; padding:8px; text-align:left; }'
      echo 'table.compare-tbl thead th { background:#f0f0f0; }'
      echo 'table.compare-tbl tbody tr:nth-child(even) { background:#fafafa; }'
      echo 'h1 { font-family:sans-serif; margin-bottom:1rem; }'
      echo 'pre.context { background:#1e1e1e; color:#d4d4d4; font-family:monospace; padding:0.5rem 1rem; border-radius:4px; display:inline-block; margin-bottom:2rem; }'
      echo '</style></head><body>'
      echo "<h1>Resources in:</h1>"
      echo "<pre class='context'>Context 1: $(html_escape "$ctx1")</pre>"
      echo "<pre class='context'>Namespace 1: $(html_escape "$ns1")</pre>"
      echo "<pre class='context'>Context 2: $(html_escape "$ctx2")</pre>"
      echo "<pre class='context'>Namespace 2: $(html_escape "$ns2")</pre>"
      echo "<h1>Differences</h1>"
      echo "<table class='compare-tbl'><tr><th>Type</th><th>Name</th><th>Images</th><th>$ns1</th><th>$ns2</th></tr>"
      for r in "${DIFFS[@]}"; do
        IFS='|' read -r t n i v1 v2 <<<"$r"
        v1=$(html_escape "$v1")
        v2=$(html_escape "$v2")
        echo "<tr><td>$t</td><td>$n</td><td>$i</td><td>$v1</td><td>$v2</td></tr>"
      done
      echo "</table>"

      echo "<h1>Matches</h1>"
      echo "<table class='compare-tbl'><tr><th>Type</th><th>Name</th><th>Images</th><th>$ns1</th><th>$ns2</th></tr>"
      for r in "${MATCHES[@]}"; do
        IFS='|' read -r t n i v1 v2 <<<"$r"
        v1=$(html_escape "$v1")
        v2=$(html_escape "$v2")
        echo "<tr><td>$t</td><td>$n</td><td>$i</td><td>$v1</td><td>$v2</td></tr>"
      done
      echo "</table>"

      echo "</body></html>"
    } >"$html"

    echo -e "\nHTML file generated: $html\n"
  fi
}

# ---- Main ----

[[ $# -lt 1 ]] && usage
case "$1" in
list)
  shift
  list_mode "$@"
  ;;
compare)
  shift
  compare_mode "$@"
  ;;
*) usage ;;
esac
