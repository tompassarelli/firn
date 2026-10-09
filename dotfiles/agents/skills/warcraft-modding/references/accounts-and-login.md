# Accounts and login

- Never touch Tom's game install or account a.
- Use encrypted b/c/d pairs from nixos-config:secrets/bnet.yaml for test clients with distinct accounts/prefixes.
- Match client B to account b and client A to account c at ~/.local/share/wc3-melee/client-a.
- Verify the real login form and focused field before wc3-login-field with account b/c/d and username/password.
- Type through private-desktop.sh type with jq/xdotool/sops and the machine SOPS key; xdotool type drops Battle.net characters.
- Keep decrypted values out of arguments, clipboard, traces, screenshots, files and output.
- Enable persistent login and verify launcher online state and W3 SSO before Play.
- Bring Tom authenticator/CAPTCHA/account-lock blockers.
