# Secrets

Secrets go through [sops-nix](https://github.com/Mic92/sops-nix): the
encrypted `secrets/*.yaml` are committed (safe — they're encrypted), the
private age key stays machine-local at `/var/lib/sops-nix/key.txt` (never in
the repo), and `.sops.yaml` lists the public age recipients.

The `awscli` module is opt-in (off unless a host enables it) and exposes a
`sopsFile` option so a fork points it at its own encrypted file.

**Forking — bring your own:**

```bash
age-keygen -o ~/.config/sops/age/keys.txt           # prints your public key
# put that public key in .sops.yaml as the `admin` recipient
cp secrets/aws.yaml.example secrets/aws.yaml         # fill real values
sops --encrypt --in-place secrets/aws.yaml           # encrypt to your key
sudo install -Dm600 ~/.config/sops/age/keys.txt /var/lib/sops-nix/key.txt
```

Or simplest: **don't enable `awscli`** — nothing else needs secrets, and the
config builds clean without it. The `secrets/*.yaml.example` files document
the cleartext structure of each.
