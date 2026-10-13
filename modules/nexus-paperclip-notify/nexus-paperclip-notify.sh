state_dir=${STATE_DIRECTORY:-/var/lib/nexus-paperclip-notify}
state=$state_dir/notified.json
failing=$state_dir/failing-since

if [ "${1:-}" != poll ]; then
  if "$0" poll; then
    rm -f "$failing" "$failing.reported"
    exit 0
  fi
  now=$(date +%s)
  [ -f "$failing" ] || echo "$now" >"$failing"
  since=$(cat "$failing")
  if [ $((now - since)) -ge "$FAIL_GRACE_SECONDS" ] && [ ! -e "$failing.reported" ]; then
    touch "$failing.reported"
    echo "nexus-paperclip-notify: failing since $(date -u -d "@$since" +%FT%TZ)" >&2
    exit 1
  fi
  exit 0
fi

items='[]'
cursor=
while :; do
  query=limit=100
  [ -z "$cursor" ] || query="$query&cursor=$(jq -rn --arg c "$cursor" '$c | @uri')"
  page=$(curl -fsS --max-time 20 "$PAPERCLIP_API/api/companies/$PAPERCLIP_COMPANY/attention?$query")
  items=$(jq -c --argjson acc "$items" '$acc + .items' <<<"$page")
  cursor=$(jq -r '.nextCursor // empty' <<<"$page")
  [ -n "$cursor" ] || break
done

waiting=$(jq -c '
  def kind_name:
    if .sourceKind == "issue_thread_interaction" then
      {ask_user_questions: "Question", request_confirmation: "Confirm", request_checkbox_confirmation: "Confirm",
       request_item_verdicts: "Verdicts", suggest_tasks: "Tasks", connection_intent: "Connection"}[.subject.metadata.kind // ""] // "Interaction"
    else {approval: "Approval", decision: "Decision", blocker_attention: "Blocked"}[.sourceKind] end;
  def cut($n): if length > $n then .[:$n - 1] + "…" else . end;
  map(select(.sourceKind == ("issue_thread_interaction", "approval", "decision", "blocker_attention")))
  | map({
      key: (if .sourceKind == "blocker_attention" then "blocker:" + (.relatedIssue.id // .subject.id) else .id end),
      title: ([kind_name, (.relatedIssue.identifier // .subject.identifier // empty)] | join(" ")),
      message: ((.relatedIssue.title // .subject.title // "") as $t | (.detail.firstQuestionText // (if .sourceKind == "blocker_attention" then .whyNow else null end) // .subject.title // .whyNow // "") as $s
                | [$t, (if $s == $t then empty else $s end)] | map(select(. != "")) | join("\n") | cut(400)),
      href: (.subject.href // .relatedIssue.href // ""),
      priority: (if .sourceKind == "blocker_attention" then 3 else 4 end)
    })
  | unique_by(.key)' <<<"$items")

write_state() {
  printf '%s\n' "$1" >"$state.tmp"
  mv "$state.tmp" "$state"
}

if [ ! -f "$state" ]; then
  seeded=$(jq -c --arg now "$(date -u +%FT%TZ)" 'map({key, value: $now}) | from_entries' <<<"$waiting")
  write_state "$seeded"
  echo "nexus-paperclip-notify: seeded $(jq length <<<"$seeded") existing waiting items without notifying"
  exit 0
fi

notified=$(cat "$state")
fresh=$(jq -c --argjson seen "$notified" 'map(select($seen[.key] == null))' <<<"$waiting")
token=$(cat "$NTFY_TOKEN_FILE")
count=$(jq length <<<"$fresh")
for i in $(seq 0 $((count - 1))); do
  entry=$(jq -c ".[$i]" <<<"$fresh")
  body=$(jq -c --arg topic "$NTFY_TOPIC" --arg base "$PAPERCLIP_LINK_BASE" \
    '{topic: $topic, title: .title, message: .message, priority: .priority, tags: ["paperclip"]}
     + (if .href == "" then {} else {click: ($base + .href)} end)' <<<"$entry")
  id=$(curl -fsS --max-time 20 -H @<(printf 'Authorization: Bearer %s\nContent-Type: application/json\n' "$token") \
    --data-binary "$body" "$NTFY_URL" | jq -r .id)
  key=$(jq -r .key <<<"$entry")
  notified=$(jq -c --arg key "$key" --arg now "$(date -u +%FT%TZ)" '.[$key] = $now' <<<"$notified")
  write_state "$notified"
  echo "nexus-paperclip-notify: notified $key as ntfy $id"
done

pruned=$(jq -c --argjson waiting "$waiting" '($waiting | map({key, value: true}) | from_entries) as $live | with_entries(select($live[.key]))' <<<"$notified")
[ "$pruned" = "$notified" ] || write_state "$pruned"
