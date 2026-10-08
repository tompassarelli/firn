# Accounts and login

Accounts: encrypted pairs live in nixos-config:secrets/bnet.yaml (a, b, c, d).
Account a is Tom's personal account and install
(~/.local/share/Steam/steamapps/compatdata/3516115571); the login helper
refuses it, and it needs Tom's explicit per-session authorization. Never sign
in, log out or switch accounts on the owner's launcher, and never pass
`--owner-authorized` without that authorization. Standing case: on 6 Oct 2026
Tom authorized `wisp play` on a's install for Wisp#14/#73 checks only, with no
sign-in, logout or account changes. Test clients use b (client B)
and c (client A, ~/.local/share/wc3-melee/client-a); concurrent online clients
need distinct accounts and separate prefixes. Ordinary credential prompts on
A/B are yours: verify a real login form and the focused field, then run
nixos-config:dotfiles/bin/wc3-login-field (account a|b|c, username|password)
in a shell with jq, xdotool and sops, using the machine SOPS key through sudo.
Never print decrypted values or put them in arguments, clipboard, traces,
screenshots or files. Enable supported persistent login and verify launcher
online state and W3 SSO before Play. Authenticator, CAPTCHA or account lock
is a blocker: notify by email only through an available authenticated route
and say so honestly when there is none.
