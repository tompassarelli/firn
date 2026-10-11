# Secrets

firn is public and carries no personal secrets. Hosts get theirs from a
private overlay flake that builds the host from firn (`firn.lib.mkSystem` with
`extraModules`), keeps its own encrypted `secrets/*.yaml` and `.sops.yaml`, and
points each consumer at them. Secrets go through
[sops-nix](https://github.com/Mic92/sops-nix): the private age key stays
machine-local at `/var/lib/sops-nix/key.txt`, never in a repository.

Secret-backed modules have no default file, so a host that enables one without
an overlay value fails evaluation instead of reading a path in firn:

- `myConfig.modules.awscli.sopsFile` (keys `aws-access-key-id`, `aws-secret-access-key`);
- `myConfig.modules.cloudflare-auth.sopsFile` (key `cloudflare-global-api-key`);
- `sops.secrets.<name>.sopsFile` for secrets a host declares without a file,
  such as the `wg-nexus` client's `wireguard-nexus-laptop` and `nexus-endpoint`.

**Bring your own:**

```bash
age-keygen -o ~/.config/sops/age/keys.txt           # prints your public key
# in your overlay: put that public key in .sops.yaml as the `admin` recipient
sops secrets/aws.yaml                                # create and encrypt
sudo install -Dm600 ~/.config/sops/age/keys.txt /var/lib/sops-nix/key.txt
```

```nix
# overlay hosts/<host>.nix
{ ... }: {
  myConfig.modules.awscli.sopsFile = toString ../secrets/aws.yaml;
}
```

Or simplest: leave the secret-backed modules disabled.

## Tom's machines

Tom's overlay is the private `south` repository. Its encrypted files live at
`${SOUTH_SECRETS:-$HOME/code/south/main/secrets}` (aws, bnet, cloudflare,
digitalocean, gmail, vastai, wireguard). Decrypt only into a command's
environment, never to the terminal, for example:

`DIGITALOCEAN_ACCESS_TOKEN=$(sudo SOPS_AGE_KEY_FILE=/var/lib/sops-nix/key.txt sops -d --extract '["token"]' "${SOUTH_SECRETS:-$HOME/code/south/main/secrets}/digitalocean.yaml") doctl ...`

Cloudflare credentials reach commands through `with-cloudflare <profile> --
<command>`; the vast.ai key and bnet credentials are projected to
`/run/secrets/vastai-api-key` and `/run/secrets/bnet`.
