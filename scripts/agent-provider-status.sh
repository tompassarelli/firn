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
  def valid_availability_tuple:
    if .availabilityReason == "ready" then
      .installed and .authenticated and .available
    elif .availabilityReason == "command_missing" then
      (.installed | not) and (.authenticated | not) and (.available | not)
    elif .availabilityReason == "authentication_missing" then
      .installed and (.authenticated | not) and (.available | not)
    elif .availabilityReason == "unknown" then
      (.authenticated | not) and (.available | not)
    elif .availabilityReason == "disabled" then
      (.available | not) and ((.authenticated | not) or .installed)
    else false end;
  def expected_routing:
    if .availabilityReason == "disabled" then "disabled"
    elif (.available | not) then "unavailable"
    elif .headroom == "exhausted" then "exhausted"
    else "eligible" end;
  def valid_v3_target($provider):
    type == "object" and
    (.id | type) == "string" and (.id | length) > 0 and
    .provider == $provider and
    (.installed | type) == "boolean" and
    (.authenticated | type) == "boolean" and
    (.available | type) == "boolean" and
    (.availabilityReason | valid_availability_reason) and
    (.headroom | valid_headroom) and
    ((.authenticated and .headroom == "unknown") | not) and
    valid_availability_tuple and
    .routing == expected_routing;
  def valid_v3_document:
    [.providers[].provider] as $provider_ids
    | [.providers[].targets[].id] as $target_ids
    | ($provider_ids | length) == ($provider_ids | unique | length) and
      ($target_ids | length) == ($target_ids | unique | length) and
      all(.providers[];
        type == "object" and
        (.provider == "anthropic" or .provider == "openai") and
        (.targets | type) == "array" and (.targets | length) > 0 and
        (. as $group | all(.targets[]; valid_v3_target($group.provider))));

  if ((.schemaVersion != 2 and .schemaVersion != 3) or
      (.providers | type) != "array" or
      (.schemaVersion == 3 and (valid_v3_document | not))) then
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
            else false end) then
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
