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
  def valid_v2_target:
    type == "object" and
    (.installed | type) == "boolean" and
    (.authenticated | type) == "boolean" and
    (.routing == "eligible" or .routing == "unavailable" or .routing == "disabled") and
    (.headroom | valid_headroom);
  def valid_availability_reason:
    . == "ready" or . == "command_missing" or
    . == "authentication_missing" or . == "disabled" or . == "unknown";
  def valid_v3_target($provider):
    type == "object" and
    (.id | type) == "string" and (.id | length) > 0 and
    .provider == $provider and
    (.installed | type) == "boolean" and
    (.authenticated | type) == "boolean" and
    (.available | type) == "boolean" and
    (.availabilityReason | valid_availability_reason) and
    (.headroom | valid_headroom) and
    (if .routing == "eligible" then
       .available and .installed and .authenticated and
       .availabilityReason == "ready" and .headroom != "exhausted"
     elif .routing == "exhausted" then
       .available and .installed and .authenticated and
       .availabilityReason == "ready" and .headroom == "exhausted"
     elif .routing == "unavailable" then
       (.available | not) and .availabilityReason != "disabled"
     elif .routing == "disabled" then
       (.available | not) and .availabilityReason == "disabled"
     else false end);

  if ((.schemaVersion != 2 and .schemaVersion != 3) or
      (.providers | type) != "array") then
    error("unsupported north providers schema")
  else
    [.providers[] |
      select((type == "object") and (.provider == $provider))] as $groups
    | if ($groups | length) != 1 or
         ($groups[0].provider | type) != "string" or
         ($groups[0].targets | type) != "array" or
         ($groups[0].targets | length) == 0 then
        error("provider missing or malformed")
      else
        .schemaVersion as $schema
        | $groups[0].targets as $targets
        | if any($targets[];
            if $schema == 2 then (valid_v2_target | not)
            else (valid_v3_target($provider) | not) end) then
            error("provider target malformed")
          else
            [$targets[] | select(.routing == "eligible") | .headroom] as $eligible_headroom
            | (if ($eligible_headroom | length) > 0 then "eligible"
               elif any($targets[]; .routing == "exhausted") then "exhausted"
               elif any($targets[]; .routing == "unavailable") then "unavailable"
               else "disabled" end) as $routing
            | [
                (if any($targets[]; .installed) then "yes" else "no" end),
                (if any($targets[]; .authenticated) then "yes" else "no" end),
                (if $routing == "eligible" then
                   ($eligible_headroom | sort_by(headroom_rank) | last)
                 elif $routing == "exhausted" then "exhausted"
                 else "unknown" end),
                $routing
              ]
            | join("|")
          end
      end
  end
'
