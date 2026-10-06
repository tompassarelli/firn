# SSH and account access

## Authority boundaries

Distinguish account control from access to an existing server. SSH does not
prove DigitalOcean API access, account identity, or permission to change billing.

## Known SSH route; verify before mutation

The verified server is `greywrought-dev`, at `137.184.38.104`. From Tom's local
machine, use the existing SSH identity without reading its contents:

```sh
ssh -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes \
  -o ConnectTimeout=10 -i /home/tom/.ssh/greywrought-wiki-admin \
  tom@137.184.38.104 'hostname; id'
```

Direct SSH as `tom` is verified. Use `root` with the same identity only for a
required administrative boundary. The local SSH alias `greywrought-dev` is not
currently configured. `play.greywrought.com` is Cloudflare-proxied and must not
be used as an SSH destination. The historical `165.232.138.122` route is not
the current verified server; do not cycle through historical addresses.

Host keys must match the existing known-hosts record. A mismatch stops access;
do not disable host checking or replace the key based only on an unauthenticated
scan. If the verified address becomes unreachable, consult authenticated
account inventory or the newest successful access record through `convo`.
Verify hostname and the requested service before a write.

## Account control

The account console is https://cloud.digitalocean.com/. Use an existing
authenticated browser session or an already configured `doctl` context. This
machine currently has no verified `doctl` executable or configured context;
do not claim API access from working SSH.

When a request requires account inventory or API actions, inspect command
availability and credential-file existence only. If an established context is
available, `doctl account get` and a narrowly selected Droplet listing can
verify its identity without printing credentials. If access is missing, use
the authorized credential mechanism under the global credential-use boundary;
ask for interaction only when it is actually required. Do not create a personal
access token, copy browser cookies, or scrape password stores as a workaround.

Creating, resizing, destroying, changing firewalls/DNS, adding billable
resources, or changing production requires authorization for that specific
outcome. A request to run development on the account ordinarily means reuse
the existing server, not provision a new one.

## Rationale

SSH, account API access, DNS reachability, and deployment authority are four
separate claims. Test the one the task needs. Cached host facts locate the first
safe probe; they are not timeless inventory. An authenticated inventory change
can supersede an address, but a host-key mismatch cannot be waved away.
