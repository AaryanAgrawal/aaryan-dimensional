# How robots join the tailnet

Researched 2026-08-09 against tailscale.com docs and the tailscale 1.102.2 client (source and binary).
Verification method is stated per claim. Anything unrun is marked.

## Recommendation

Create one **OAuth client**, owned by the tailnet, with scope `auth_keys` and tag `tag:robot`; OAuth
clients are owned by the tailnet rather than a person and their secrets do not expire, so this is the
only credential that survives someone leaving. At bring-up the operator's laptop uses that secret to
mint a **single-use, pre-approved, non-ephemeral, `tag:robot` auth key** with a ten minute expiry, and
hands only that key to the robot; the robot never holds the minting secret. Tagging is what actually
solves the ownership problem: a tagged node's identity is the tag, not the human who authenticated it,
and its node key expiry is disabled by default, so it neither dies with an offboarded account nor drops
off the tailnet after 180 days.

Aaryan creates the OAuth client once and adds nine lines to the policy file. Everything else is tooling.

---

## Evidence

### 1. Auth keys

Auth keys are one-off or reusable, and independently ephemeral, pre-approved, or tagged. Expiry is the
binding constraint: "You can choose the number of days, between 1 and 90 inclusive, for the key expiry.
If you don't specify an expiry time, the auth key will expire after the maximum of 90 days." There is no
non-expiring auth key. Tailscale says so directly on the OAuth page: "You cannot generate long-lived auth
keys, because they expire after 90 days, or, for one-off keys, as soon as you use them."

Generating or revoking a key requires Owner, Admin, IT admin, or Network admin. Applying a tag to a key
requires owning that tag, except that Owner, Admin and Network admin can apply any tag.

An expired auth key does not disconnect the robots it authenticated: "If an auth key expires, any device
authorized by it remains authorized until its node key expires." The key is a door, not a lease.

- https://tailscale.com/kb/1085/auth-keys
- https://tailscale.com/docs/features/oauth-clients

### 2. Tags — confirmed

The claim holds. "Applying a tag to a device removes any user-based authentication," and tags "serve the
same role as a user account, except they're intended for service-based devices." The offboarding
consequence is stated outright: "Removing a user won't affect the device if you use tags to manage the
device instead." A tagged device and a user-owned device cannot coexist on the same machine, in either
direction: authenticating a tagged device as a user strips its tags.

To be usable a tag must exist in `tagOwners` before anything can apply it. An empty owner list is legal
and means only Owner, Admin and Network admin can apply it: "All tags are implicitly owned by Owners,
Admins, and Network admins of a tailnet."

One consequence that matters for CI later: "devices with a tag-based identity cannot use SSH to connect
to a device with a user-based identity." Laptop to robot is user to tag and works. Robot to laptop does
not, which is what we want anyway.

The CLI flag is `--advertise-tags=tag:robot` (verified by running `tailscale up --help` on 1.102.2).

- https://tailscale.com/kb/1068/tags

### 3. OAuth clients vs auth keys

OAuth is the recommendation for anything long-lived, for two reasons that both apply to us.

The first is expiry. Access tokens last one hour and are minted on demand; the client secret itself has no
documented expiry, and nothing in the docs mentions rotating it. So the credential the tooling stores never
needs a calendar reminder.

The second is ownership, and it is the stronger one: "OAuth clients must be owned by the tailnet, and not
by an individual user." An auth key is generated *by* a person and inherits their identity unless tagged.
An OAuth client has no person behind it at all.

The cost is that OAuth clients can only produce tagged nodes: "Devices registered with OAuth client
credentials are tag-owned," and the client source refuses outright — `errors.New("oauth authkeys require
--advertise-tags")`. For a robot fleet that is the desired behaviour, not a cost.

- https://tailscale.com/docs/features/oauth-clients
- https://github.com/tailscale/tailscale/blob/main/feature/oauthkey/oauthkey.go

### 4. Node key expiry — solved by the same decision

Node keys, not auth keys, are what kills a robot in a warehouse. "By default, node keys automatically
expire every 180 days," and "if reauthentication does not occur, keys expire and connections to/from the
given endpoint will stop working."

Tagging fixes it without any extra step: "When you apply a tag to a device for the first time and
authenticate it, the tagged device's key expiry is disabled by default." Changing tags later does not
change the setting unless the device re-authenticates, at which point expiry is disabled again.

The failure mode that remains is a human re-running `tailscale up` on a robot without `--advertise-tags`
and clicking through a browser login. That converts the robot to a user-owned node, restores the 180-day
expiry, and re-attaches it to whoever clicked. The tooling should never emit a login URL.

- https://tailscale.com/kb/1028/key-expiry

### 5. Unattended install on Linux

"On Linux, Tailscale runs as the system, and is available even when no users are logged in." There is no
`--unattended` flag on Linux; that flag is Windows only (verified against `tailscale up --help`, 1.102.2,
which does not list it). Headless is the normal case.

Install and join, all as root:

```sh
curl -fsSL https://tailscale.com/install.sh | sh
tailscale up \
  --auth-key=file:/run/ts-key \
  --advertise-tags=tag:robot \
  --hostname=g1-a1b2c3 \
  --ssh \
  --accept-risk=lose-ssh \
  --timeout=90s
```

Root is needed for the install and for `tailscale up`; the daemon owns `/var/lib/tailscale` at mode 0700.
`--auth-key` accepts a `file:` prefix, which keeps the key out of the robot's process list — verified in
the flag help: `node authorization key; if it begins with "file:", then it's a path to a file containing
the authkey`. Write it 0600 and delete it after; it is single use anyway.

**The verify command is `tailscale up` itself.** Reading the source, `up` returns nil only once the backend
reaches `Running`; a backend error such as an invalid or expired key hits `fatalf("backend error: %v")`, and
`--timeout` expiring returns `timeout waiting for Tailscale service to enter a Running state`. So exit 0
from that invocation means joined. Confirm the address separately with `tailscale ip -4`, which errors with
`no current Tailscale IPs; state: %v` when there is none.

Two flags exist for a reason. `--accept-risk=lose-ssh` is only consulted when the current shell is itself an
SSH session over Tailscale, which bring-up is not, but re-runs later will be, and the prompt blocks on stdin.
`--timeout=90s` matters because the default is `0s`, meaning block forever — and a robot waiting on device
approval will hang the script with no output.

One trap worth knowing: "If flags are specified, the flags must be the complete set of desired settings. An
error is returned if any setting would be changed as a result of an unspecified flag's default value, unless
the `--reset` flag is also used." Re-running bring-up with a different flag set fails rather than converging.
Keep the invocation byte-identical, or pass `--reset`.

- https://tailscale.com/kb/1088/run-unattended
- https://tailscale.com/kb/1031/install-linux
- https://github.com/tailscale/tailscale/blob/main/cmd/tailscale/cli/up.go

### 6. Least-privilege policy

Defining an `acls` section replaces the default allow-all, and Tailscale then denies by default. Tagged
devices are not members of the tailnet, so `autogroup:member` and named users never match a robot as a
source. Giving robots no source rule at all is therefore the whole of the restriction — robots cannot reach
each other, cannot reach laptops, and cannot reach anything else on the tailnet.

```hujson
{
  "groups": {
    "group:fleet": ["aaryan@servicerobotco.com"],
  },
  "tagOwners": {
    "tag:robot": ["group:fleet"],
  },
  "acls": [
    {"action": "accept", "src": ["group:fleet"], "dst": ["tag:robot:22"]},
  ],
  "ssh": [
    {"action": "accept", "src": ["group:fleet"], "dst": ["tag:robot"], "users": ["unitree", "root"]},
  ],
}
```

Both sections are required. The `acls` entry carries the packets and the `ssh` entry authorises the session;
Tailscale SSH needs both. Adding a dimos port later is one edit to `dst`, `tag:robot:22,8080`.

`"action": "check"` in the `ssh` block would force the operator through the identity provider every 12 hours
(`checkPeriod`, default `12h`). Start with `accept`, because a browser prompt in the middle of a scripted
bring-up is exactly the interactive step we are removing.

Tailscale SSH does not touch `sshd_config` or `authorized_keys`; it claims port 22 on the Tailscale address
only, so the factory `unitree`/`123` login on the wired link keeps working for recovery.

- https://tailscale.com/kb/1337/policy-syntax
- https://tailscale.com/kb/1193/tailscale-ssh

### 7. ARM64 and Ubuntu 20.04

Supported, and I checked the actual repository rather than the docs. `pkgs.tailscale.com/stable/ubuntu`
publishes a `focal` suite with a `binary-arm64` component carrying 147 versions, current at 1.102.2. I
downloaded `tailscale_1.102.2_arm64.deb` (35.7 MB) and listed it: `/usr/bin/tailscale`, `/usr/sbin/tailscaled`,
`/lib/systemd/system/tailscaled.service`, `/etc/default/tailscaled`. Its only dependency is `iptables`. The
postinst runs `deb-systemd-helper enable` and `deb-systemd-invoke restart`, and the unit is
`WantedBy=multi-user.target` with `Restart=on-failure` and state at `/var/lib/tailscale/tailscaled.state`,
so it comes back on its own after a reboot with no extra step.

The install script covers focal. Doing it by hand is:

```sh
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/focal.noarmor.gpg \
  | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/focal.tailscale-keyring.list \
  | tee /etc/apt/sources.list.d/tailscale.list
apt-get update && apt-get install -y tailscale
```

Tailscale SSH needs the client at 1.24 or later, so 1.102.2 is comfortable. If `tun` is missing on the
Jetson kernel, `modprobe tun` plus a line in `/etc/modules-load.d/tun.conf`; I did not check a G1 for this.

- verified by running against https://pkgs.tailscale.com/stable/ubuntu/dists/focal/main/binary-arm64/Packages

---

## Once, by Aaryan, in the admin console

1. Add the policy file block from section 6 (Access controls page). `tag:robot` must exist before any key
   can carry it.
2. Create an OAuth client (Settings, OAuth clients) with scope `auth_keys` and tag `tag:robot`. It must be
   `auth_keys`, not `auth_keys:read` — only the former reaches `POST /api/v2/tailnet/:tailnet/keys`.
   The tag on the client and the tag on the key must match exactly — Tailscale's exact-match check does not
   consult `tagOwners`, so a subset or a differently-named tag is rejected unless ownership is spelled out.
3. Copy the client secret once. It is shown once. Store it wherever the team already keeps shared secrets,
   not in the repo.
4. Nothing thereafter. No 90-day rotation, no key to re-issue, no per-robot console step.

## Every time, by the tooling

On the operator's laptop, before it touches the robot:

1. `POST https://api.tailscale.com/api/v2/oauth/token` with the client id and secret, giving a one-hour
   access token.
2. `POST https://api.tailscale.com/api/v2/tailnet/-/keys` with that token and this body. Field names and
   the response shape are from Tailscale's own client, `client/tailscale/keys.go`; the secret comes back in
   the `key` field.

```json
{
  "capabilities": {
    "devices": { "create": {
      "reusable": false, "ephemeral": false, "preauthorized": true, "tags": ["tag:robot"]
    } }
  },
  "expirySeconds": 600
}
```

3. Copy the key to the robot at 0600, run the `tailscale up` from section 5, delete the file.
4. Record the tailnet address from `tailscale ip -4` into the device record next to the wifi address.

If no credential resolves, fail with the next step printed. Do not fall back to printing a login URL. A robot
with no tailnet is a robot you drive to; a robot on someone's personal account is a robot you lose when they
leave, and the second is worse.

## Decisions where the plan was silent

**Tailscale is infect's job, not helm's.** The boundary test — does the compat engine need this to pick a
wheel? No. It is a pre-helm step in the recipe, and it runs from the laptop against the robot, which is the
shape infect already has.

**One tag, `tag:robot`, not per-model tags.** Tags do not intersect in ACLs, so `tag:g1` plus `tag:prod` can
never express "both"; Tailscale's own guidance is composite names like `tag:prod-g1`. We have one access
pattern today. Split when a second one exists.

**The one-liner alternative was rejected.** `tailscale up --auth-key='tskey-client-...?ephemeral=false&preauthorized=true'
--advertise-tags=tag:robot` is documented and works — the client detects the `tskey-client-` prefix and does
the OAuth exchange itself. It is rejected because it puts a credential that can mint `tag:robot` keys for the
whole tailnet onto every robot we ship, and because of its default: reading `feature/oauthkey/oauthkey.go`,
`ephemeral` defaults to **true** and `preauthorized` to **false** on that path. Forgetting `?ephemeral=false`
means the robot is deleted from the tailnet the first time it powers down. Minting on the laptop has neither
property. Keep the one-liner as a documented manual fallback, never as the default path.

**Drop `--accept-routes`.** The current script passes it. With no subnet routers in the tailnet it does
nothing, and it is not part of the minimal flag set that `tailscale up` demands stay stable across re-runs.

## Not verified

- **Which tailnet.** Everything above assumes a `servicerobotco.com` tailnet where Aaryan is Owner or Admin.
  If the current robots are on a personal tailnet, they are already the failure mode this doc describes and
  need re-authenticating into the org tailnet, which changes their node keys but not their addresses.
- **Whether device approval is on.** `preauthorized: true` is harmless if it is off and necessary if it is on,
  so the tooling sets it either way. I could not read the tailnet's setting.
- **`description` on a created key.** The admin console has the field; it is absent from Tailscale's Go client
  struct, so I did not confirm the API accepts it. Worth sending `"description": "g1-bringup <hostname>"` and
  checking the Keys page — a per-robot label is worth having.
- **Exit codes end to end.** I read `up.go` and `ip.go` and ran `tailscale --help`, `tailscale status` and
  `tailscale ip -4` from the 1.102.2 binary with no daemon (both exit 1). I did not run a real join: no
  tailscaled here, and no root. The claim that exit 0 from `tailscale up --timeout=90s` means joined is read
  from source, not executed.
- **`tun` on the G1's kernel.** Untested on hardware.
- **How long focal packages last.** Ubuntu 20.04 is past standard support. Tailscale still publishes focal
  arm64 today, current with every other suite. There is no announced end date, and no fallback if it stops
  other than the static arm64 tarball, which ships its own systemd unit.
