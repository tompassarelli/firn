---
description: Capture the supplied text as one new North thread, verbatim
argument-hint: <title text>
---

# /capture — thin North adapter

Capture is zero-ceremony: the entire supplied text becomes ONE literal title
argument to `north capture`. Never split it into words, never let the shell
expand quotes, backticks, or `$vars` inside it, never rephrase, trim, or
"clean up" the wording, and never add extra facts or dispatch. One thread in,
one thread out.

If `$ARGUMENTS` is empty or only whitespace, do not capture — ask the user for
a title instead.

Otherwise run exactly this form, which survives embedded double quotes,
backticks, and `$vars` because the heredoc body is bounded by a quoted
delimiter (`'EOF'`), so nothing inside it is shell-expanded, and the whole
heredoc collapses to a single `$(...)` argument:

```sh
north capture "$(cat <<'EOF'
$ARGUMENTS
EOF
)"
```

Report back the `@id` that `north capture` prints for the new thread.

Request: $ARGUMENTS
