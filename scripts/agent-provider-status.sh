#!/usr/bin/env bash
# Aggregate one provider from the versioned `north providers --json` document
# without collapsing installation, authentication, and headroom into one flag.
set -euo pipefail

provider="${1:?usage: agent-provider-status.sh <anthropic|openai>}"
jq -er --arg provider "$provider" '
  def valid_headroom:
    . == "plenty" or . == "normal" or . == "low" or
    . == "exhausted" or . == "unknown";
  def headroom_rank:
    if . == "unknown" then 0
    elif . == "exhausted" then 1
    elif . == "low" then 2
    elif . == "normal" then 3
    elif . == "plenty" then 4
    else -1 end;

  if .schemaVersion != 2 or (.providers | type) != "array" then
    error("unsupported north providers schema")
  else
    [.providers[] | select(.provider == $provider)] as $groups
    | if ($groups | length) != 1 or ($groups[0].targets | type) != "array" or
         ($groups[0].targets | length) == 0 then
        error("provider missing or malformed")
      else
        $groups[0].targets as $targets
        | if any($targets[];
            (.installed | type) != "boolean" or
            (.authenticated | type) != "boolean" or
            (.routing != "eligible" and .routing != "unavailable" and .routing != "disabled") or
            (.headroom | valid_headroom | not)) then
            error("provider target malformed")
          else
            [$targets[] | select(.routing == "eligible") | .headroom] as $eligible_headroom
            | [
                (if any($targets[]; .installed) then "yes" else "no" end),
                (if any($targets[]; .authenticated) then "yes" else "no" end),
                (if ($eligible_headroom | length) == 0 then "unknown"
                 else ($eligible_headroom | sort_by(headroom_rank) | last) end)
              ]
            | join("|")
          end
      end
  end
'
