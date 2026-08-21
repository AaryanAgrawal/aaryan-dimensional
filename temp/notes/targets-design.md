# The dios target registry

**Deliverables:** this document, and a compiling, tested skeleton at
`/home/dimos/aaryan-dimensional/workspace/targets-skeleton/` (24 tests, clippy clean, rustfmt
clean). Nothing was written into `dimos-bios`.

Aaryan's instruction, verbatim:

> the storage for 'targets' should have name mac and ip and whatever else and can be in the config
> file locally where dios is installed.

> we will also have recipes like go2 which will have dimos run on the laptop, in that case infect
> should just scan for local dimos correctly and get the doc's IP and MAC and store properly.

---

## 1. What a target is

A target is a robot dios knows about. Not a robot dios installed onto — that is a narrower thing,
and conflating the two is the first mistake available here (§4).

**Identity is the MAC.** An IP is a DHCP lease. On the G1 the lease is 8 hours and it moved during
this project; a registry keyed on address loses the robot every time the router feels like it. A
MAC is burned into an interface and survives a reboot, a reflash and a network change.

The codebase already agrees. `src/infect/journal.rs` keys the per-robot journal by MAC and
says why in its own header — *"DHCP moves a robot's address between runs, and a journal that cannot
find its robot rebuilds CycloneDDS for fifteen minutes to learn it was already built."* The
registry uses the same normalisation (lowercase, colon-separated, `-` accepted on input) so that
`targets.<mac>` and `~/.dimos/infect/journal/<mac>.json` name the same robot. If those two ever
disagree about what a MAC looks like, a resume silently starts over.

### Fields

| field | type | why it is here |
|---|---|---|
| `name` | string | the only thing an operator types. Unique. Never derived from the hostname (§6c) |
| `mac` | MAC, optional | the identity, and the config key. Optional only for §6f |
| `links[]` | list | every way we have reached it: `via`, `ip`, `mac`, `iface`, `last_seen` |
| `recipe` | string | which recipe matched |
| `lane` | string | `webrtc` / `zenoh` — the lane decides where dimos runs |
| `transport` | string | the **dimos** transport: `lcm`, `zenoh`, `webrtc`. A recipe's `[config] transport` |
| `blueprint` | string | what `dimos run` should run with no arguments |
| `dimos_on` | `robot` \| `laptop` | mirrors a recipe's `[recipe] target` |
| `installed[]` | list | what dios put on the robot: `dios`, `dimos`, `go2web`. **Empty means untouched** |
| `env_file` | path | laptop-side `.env` carrying this robot's address (§3) |
| `model` | string | the vendor model the matcher captured, `g1plus_pc4` |
| `board` | string | `Orin NX`, from `robot.rs::BoardRecord` |
| `serial` | string | when a vendor exposes one. Nothing reads one today |
| `hostname` | string | recorded because it is useful in a log line. Never an identity |
| `tailscale` | string | the tailnet name, when the robot joined one |
| `ssh_user` | string | `unitree`. Saves a flag on every subsequent command |
| `notes` | string | the operator's. A scan never touches it |
| `first_seen` / `last_seen` / `last_infect` | timestamps | `last_infect` distinguishes "we have seen it" from "we provisioned it" |

`ip` is not a stored field — it is `links[0].ip`, the address on the link we most recently reached
it on. This is the one place I did not take Aaryan's field list literally, and §6d is the reason:
a G1 is on `192.168.123.164` over the cable and `10.0.0.190` over wifi **at the same time**, and a
single `ip` field means the two runs overwrite each other forever. `dios target list` still prints
a column called IP, because that is what a person wants to see; it is computed, so it cannot drift
from the links list. Storing both a top-level `ip` and a links list would create exactly the kind
of invariant that a registry rots along.

Three fields are deliberately absent:

- **`role` (host/peer)** — derived from `installed.is_empty()`. A field that restates another field
  is a field that goes stale.
- **`reachable` / `online`** — the registry records what was true when we last looked. A liveness
  bit in a config file is a lie within minutes; liveness is what `dios infect scan` is for.
- **`password`** — infect reads the robot password from `INFECT_ROBOT_PASSWORD` and never from a
  flag. The registry is a group-readable JSON file under `$HOME`; it must not become the place a
  factory password gets persisted. (`~/.dimos/config.json` on this laptop is mode 664.)

### A naming collision worth fixing before it spreads

The word **transport** already means two things in this codebase: `identify::Transport` is
wired/wifi, and `RunConfig.transport` is lcm/zenoh. The registry keeps `transport` for the dimos
sense (matching recipes) and calls the link sense `via`. Separately, **target** now means three
things: a robot in this registry, a recipe's `[recipe] target` (which machine runs the stack), and
`--target` on the CLI. The registry calls the recipe sense `dimos_on`; the recipe key itself should
eventually be renamed `runs_on`, which is a one-line change in `manifest.rs` while there are two
recipes.

---

## 2. Where it lives — the existing config, not a new file

**Decision: `~/.dimos/config.json`, under a `targets` section.** This is what Aaryan asked for, and
it is also the right call. The argument both ways:

**For the config file.** `config.rs`'s own header says *"This is the single source of truth for
persistent user configuration — don't add a second config store elsewhere."* Taking it at its word
gets, for free: `dios config list` shows the fleet; `dios config get targets.8c:1f:64:00:11:22.name`
reads one field with no new code; `dios config set` is the escape hatch when the registry is wrong
at 2am and the CLI has no verb for it; `dios uninstall` already removes `~/.dimos` and so removes
the registry; and there is one file to back up, sync or copy to a second laptop.

**Against.** Three real costs, none fatal.

1. *Concurrent writes.* `config::save` is read-modify-write with no lock and no temp file. Two
   `dios infect` runs against two robots can lose one another's target. Note that infect's own
   `journal.rs` already writes through `.tmp` + `rename` precisely because of this. **Fix in
   `config::save`, not in a separate targets store** — every `dios config set` has the same bug
   today, and a targets-only workaround leaves it. Write to `config.json.tmp` and `rename`; that is
   atomic on the same filesystem and is four lines.
2. *Size.* A hundred robots is roughly 40 KB of JSON re-parsed on every `dios config get`. Fine.
   A thousand is not, and at that point targets move to `~/.dimos/targets.json` behind the same
   API — which is why every function in the skeleton takes a `&Value` root rather than reading the
   file itself. The migration is one function.
3. *Blast radius.* A malformed target makes the whole config unreadable, including `desktop.port`.
   Mitigated by `list()` reporting *which key* failed rather than skipping it silently, and by the
   registry never holding anything a person could not retype.

**Shape.** Flat, keyed by the id:

```json
"targets": {
  "8c:1f:64:00:11:22": { "name": "atlas", "...": "..." },
  "38:1b:9e:61:c9:a4": { "name": "scout", "...": "..." },
  "default": "8c:1f:64:00:11:22"
}
```

`targets.default` shares a namespace with the robots. That is safe **by construction**, not by
convention: an id is either a MAC or `name:<slug>`, and neither can ever render as the string
`default` — the test `a_reserved_key_can_never_be_a_target_id` asserts it from all three
directions. The alternative, `targets.robots.<id>` plus `targets.default`, costs a segment on every
dotted read for the same guarantee, so I chose the flat one. If a reviewer dislikes it, the change
is one constant.

Real output from `cargo run --example demo` (a G1 infected over the cable, later seen on wifi, then
renamed; a Go2 provisioned in the webrtc lane; `atlas` set default):

```json
{
  "desktop": { "on_boot": true },
  "targets": {
    "38:1b:9e:61:c9:a4": {
      "blueprint": "unitree-go2",
      "dimos_on": "laptop",
      "env_file": "/home/dimos/dimos/.env",
      "first_seen": "2026-08-10T07:40:03.232304113Z",
      "lane": "webrtc",
      "last_infect": "2026-08-10T07:40:03.232304828Z",
      "last_seen": "2026-08-10T07:40:03.232240604Z",
      "links": [
        { "ip": "10.0.0.104", "last_seen": "…", "mac": "38:1b:9e:61:c9:a4", "via": "wifi" }
      ],
      "mac": "38:1b:9e:61:c9:a4",
      "name": "scout",
      "recipe": "unitree-go2"
    },
    "8c:1f:64:00:11:22": {
      "blueprint": "unitree-g1",
      "dimos_on": "robot",
      "hostname": "ubuntu",
      "installed": ["dimos", "dios"],
      "links": [
        { "iface": "wlan0", "ip": "10.0.0.190",      "mac": "8c:1f:64:00:11:23", "via": "wifi"  },
        { "iface": "eth0",  "ip": "192.168.123.164", "mac": "8c:1f:64:00:11:22", "via": "wired" }
      ],
      "mac": "8c:1f:64:00:11:22",
      "model": "g1plus_pc4",
      "name": "atlas",
      "recipe": "unitree-g1",
      "ssh_user": "unitree",
      "transport": "lcm"
    },
    "default": "8c:1f:64:00:11:22"
  }
}
```

Every optional field is `skip_serializing_if`, so nothing writes a null. A robot that only a scan
has seen is five keys — `name`, `mac`, `links`, `first_seen`, `last_seen` — asserted by
`a_target_is_readable_through_the_ordinary_config_path`.

---

## 3. The laptop-runs-dimos case

The Go2 webrtc lane: `[lane.webrtc] target = "laptop"`, and the recipe comment says *"laptop runs
everything; robot is a peripheral"*. Nothing is installed on the robot. The registry still records
it, for three reasons that are each concrete:

1. The laptop's dimos needs `ROBOT_IP` in its `.env` — `verb/config.rs` writes it, and the recipe
   sets `env = { ROBOT_IP = "{robot_ip}" }`. When the Go2's lease moves, *something* has to know
   which file to rewrite. That is `env_file`.
2. The operator needs to say *which* Go2. Two Go2s on one office wifi are two addresses and no
   names without this.
3. `dios infect` re-run against the same robot should resume, and resume is keyed by MAC.

**The distinction is `installed`, and it is a list, not a boolean.** Empty means dios never wrote
to that machine — `role()` returns `Peer`. Non-empty names what we put there. This handles the case
that a boolean cannot: the Go2 **zenoh** lane installs `go2web` on the robot but still runs dimos
on the laptop. That is `installed: ["go2web"]`, `dimos_on: laptop` — a host and a laptop-run stack
at once. A single "did we install on it" flag collapses zenoh and webrtc into the same record and
loses the fact that one of them has our binary and a systemd unit on it.

So there are two orthogonal facts, and the registry stores both:

|  | `installed` empty | `installed` non-empty |
|---|---|---|
| **`dimos_on: laptop`** | Go2 webrtc — pure peer, robot untouched | Go2 zenoh — our bridge onboard, our planner on the laptop |
| **`dimos_on: robot`** | (a robot we only scanned) | G1 — the full install |

Tested by `the_laptop_lane_records_a_peer_we_never_wrote_to`, which asserts `role() == Peer`,
`installed` empty, `last_infect` set — a peer can still be a *finished* install — and `env_file`
pointing at the laptop's `.env`.

**On "scan for local dimos correctly".** Aaryan's second sentence has two halves. The registry half
is done above. The other half — infect finding the dimos install on the operator's own laptop
rather than assuming a path — is a `pkg`-side question, and dios already has the answer:
`dimos.dir` and `dimos.dirs` in the config — and on this laptop that store is already wrong:
`dimos.dir` is `/proc/cannot-write-here` and the first of the two `dimos.dirs` entries,
`/home/dimos/dimensional-trial/dimos`, no longer exists (the repo was renamed). The
webrtc lane should resolve its `dir` argument from `dimos.dir` instead of hardcoding, and record
the result as `env_file`. That is a `verb/config.rs` change, not a registry change, and I have
flagged it rather than designed it.

---

## 4. Commands

```
dios target list [--json]              name, mac, ip, recipe, lane, role, last seen
dios target show [<name>]              one robot, all links, journal state
dios target add <name> [--ip --mac --via --recipe --lane]
dios target rm <name>
dios target rename <old> <new>
dios target set-default <name>         copied from `wendy device set-default`
dios target unset-default
dios target reset <name>               reflashed: keep the name, drop the install (§6b)
```

and one global flag, alongside the `--dry-run` / `--verbose` / `--non-interactive` that dios
already makes global:

```
--target <name>        accepted by every infect command; also takes a bare MAC
```

Eight verbs is the whole surface. `wendy` has ~20 under `device` plus a `fleet` noun; that is a
cloud product with groups and tags, and dios does not need it — group operations can wait until
someone has more than three robots.

**Resolution order**, which is the actual feature (`resolve()` in the skeleton):

1. `--target <name>` — or a bare MAC, because a script with an address book has MACs, not names
2. `$DIOS_TARGET` — set once per shell, for CI
3. `targets.default`
4. the only target there is, if there is exactly one
5. otherwise an error **listing the names that exist** — `several targets, so say which: --target
   <name>; known: g1-001122, go2`

Step 4 matters more than it looks: an operator with one robot never encounters the concept at all.
Step 5 follows the house pattern from `manifest.rs`, whose unknown-lane error names the lanes that
exist. `resolution_order_is_flag_env_default_then_the_only_one` pins all five.

Deliberately not in the surface: `dios target set <name> <field> <value>`. That is
`dios config set targets.<mac>.<field>`, which already exists and already works. Only `rename` gets
its own verb, because it has a uniqueness check and, for a `name:`-keyed target, moves the key.

---

## 5. How it gets populated

Automatically, and by exactly two writers:

- **the end of a successful `dios infect`** — the full record: recipe, lane, blueprint, transport,
  what was installed, `last_infect`
- **`dios infect scan`** — an address and a MAC, and nothing it did not measure

`dios target add` exists for the robot neither can reach yet. It is the escape hatch, not the path.

Both writers go through **one function**, `upsert(root, &Observation)`, and this is the single most
important decision in the design:

> **An `Observation` has every field optional, and absence never overwrites presence.**

Without it, the cheap writer destroys the expensive one: a `scan` that runs after an install and
writes a whole `Target` blanks `recipe`, `blueprint` and `installed` because scanning does not know
them. That is the classic registry rot, it is silent, and you find out when `dimos run` needs
arguments again. `a_scan_never_erases_what_an_infect_recorded` is the test; it is the one to keep
if the rest are ever cut.

`installed` merges as a **union**, so the zenoh lane adding `go2web` does not remove `dios`.
`notes` is never written by an observation at all — it is the operator's.

A third writer is worth considering later and is not in this design: recording a target when
`dios setup` runs *on the robot itself*, so a robot that provisioned itself appears in its own
registry. It needs a story for which machine's config that is, and I did not invent one.

---

## 6. Identity edge cases

Each one has a named test in `src/targets.rs`.

**(a) Same robot, new IP.** Match by MAC, update the link's `ip` and `last_seen`, return
`Updated { moved: Some((old, new)) }` so the caller can print *"atlas moved 192.168.123.164 →
192.168.123.201"*. The link is replaced in place, not appended — two links for one interface is how
you end up with a record full of dead addresses.
→ `a_new_lease_moves_the_address_and_not_the_identity`

**(b) Reflashed robot.** Same MAC, and everything the old install said is now false: the venv is
gone, `dios` is not installed, the blueprint was never written. `reset()` keeps what the *operator*
owns — `name`, `notes`, `first_seen` — and drops everything the *machine* told us: `recipe`, `lane`,
`blueprint`, `transport`, `installed`, `last_infect`. Links are kept, because a reflash does not
move a cable. A fresh `dios infect` then repopulates it, which is precisely what a reflash is.
Detecting the reflash automatically is a separate problem (a machine-id or install-marker probe);
`dios target reset` is the manual answer, and it is honest about being manual.
→ `a_reflash_keeps_the_operators_name_and_drops_the_install`

**(c) Two robots called `ubuntu`.** Guaranteed: every fresh G1 ships with that hostname. Three
defences, all structural rather than advisory:

- the hostname is **never** the key — the MAC is
- the hostname is **never** the proposed name. A new target is named `<recipe tail>-<last 3 MAC
  octets>`: `unitree-g1` + `8c:1f:64:00:11:22` → `g1-001122`. Two robots collide only if they share
  three MAC octets
- if a name still collides, `unique()` suffixes `-2`, `-3`. It never merges

The test puts two G1s in the registry with the **same hostname and the same IP** (both freshly
plugged into the same static address, which is what actually happens on a bench) and asserts they
remain two targets with two names.
→ `two_robots_that_both_call_themselves_ubuntu_stay_two_targets`, `a_name_collision_suffixes_rather_than_merging`

**(d) Reachable over two transports at once.** The G1 after step 3 of the bring-up is on
`192.168.123.164` over the cable *and* `10.0.0.190` over wifi. Those are two different MACs —
`eth0` and `wlan0` are different interfaces — so the naive "match on MAC" files it twice.

The registry stores one identity MAC plus a `links` list, each link carrying **its own MAC**, and
`find_by_mac` searches the identity MAC *and every link's MAC*. Either interface finds the same
record. `ip()` returns the most recently reached link, so after wifi comes up, commands use the
wifi address. `identify.rs` already distinguishes `wired` from `wifi` for exactly this reason —
`a_wired_probe_ignores_a_wifi_reply` — so `via` is the same vocabulary.

The test also pins the honest limitation: a wifi link observed with **no** identity MAC is a new
target until something ties the two MACs together. Nothing on the network can do that — only the
robot can, by reporting both of its interfaces. So `dios infect` should read `ip -o link` on the
robot once it has ssh and record every MAC. Until it does, joining the two is an operator action
(re-run infect over the wifi link with the wired MAC in hand).
→ `one_robot_on_two_transports_is_one_target_with_two_links`

**(e) A renamed target.** The key does not move, because the key is the MAC. The journal keeps
resolving, `targets.default` keeps pointing at the same robot (it stores an *id*, not a name), and
the old name stops resolving. This is the whole payoff of not keying on the name.
→ `a_renamed_target_is_still_found_by_mac`

**(f) A robot with no MAC.** Not in Aaryan's list, and unavoidable. ARP only answers on the same L2
segment. Verified on this laptop: `ip neigh` has MACs for all 49 hosts on `10.0.0.0/24`, and
`ip neigh get 8.8.8.8 dev wlp129s0` returns `Neighbour entry not found` — off-link, ARP resolves
the *gateway*, so a routed robot presents no MAC of its own. A Go2 on a different VLAN, or reached
over Tailscale, is exactly this case.

Such a target is filed under `name:<slug>` and `is_stable()` is false. `upsert` **promotes** it to
a MAC key the moment one is learned, carrying name, notes and recipe across the re-key and leaving
no duplicate. Promotion is the only place a name is allowed to decide identity, and it is
restricted to MAC-less records — a MAC-keyed record is never matched by name, because two robots
really can share a name before anyone renames one.
→ `a_target_with_no_mac_is_stored_and_promoted_later`

*(This was one of two bugs the tests caught: my first cut matched by name only when the observation
had no MAC, which made promotion impossible — the promoting observation is precisely the one that
has both. The other was `rename` updating `targets.default` after deleting the old key, so the
default briefly pointed at nothing and the update failed.)*

**(g) A MAC that is not stable.** Measured on this laptop's LAN just now: **18 of 49** neighbours
carry the locally-administered bit, i.e. a randomised MAC. Randomisation is per-network, so such an
address is not an identity. `Mac::is_locally_administered()` recognises it and
`Target::identity_is_soft()` reports it, so `dios target list` can flag the row rather than
pretending. The mitigation in infect is a preference, not a check: **when both a wired and a wifi
MAC are known, key on the wired one** — vendor-burned NICs on a Jetson do not randomise, and wifi
is where randomisation lives. Ubuntu 20.04's NetworkManager leaves `wifi.cloned-mac-address` at
`preserve` by default, so a stock G1 is fine; a customer who hardens their fleet may not be.
→ `a_randomised_mac_is_recognisable`

**(h) A corrupt entry.** `list()` errors naming the key — `` `targets.the-lab-robot` is not a
target id `` — rather than skipping it. A registry that quietly drops a robot is worse than one
that refuses to load, and it matches `journal.rs`, whose corrupt-journal error tells you which file
to delete.
→ `an_unreadable_entry_names_its_key`

**(i) Duplicate add.** `add` refuses a name that exists and a MAC that exists, naming the target
that already holds it.
→ `adding_a_duplicate_is_refused_by_name_and_by_mac`

**(j) Removing the default.** Clears `targets.default` rather than leaving it dangling. `resolve`
also refuses loudly if the default points at a missing robot, because that is a config bug worth a
sentence rather than a silent fallthrough.
→ `removing_the_default_clears_it`

---

## 7. The skeleton

```
targets-skeleton/
  Cargo.toml            versions identical to dimos-bios/Cargo.lock — no new dependency
  rustfmt.toml          copied from dimos-infect
  src/lib.rs
  src/config.rs         excerpt of dios's src/config.rs, function for function. DELETED on graft
  src/targets.rs        767 lines of code, 453 of tests, 21 tests
  src/cli.rs            the `dios target` surface + global --target, 3 tests
  examples/demo.rs      prints the JSON quoted in §2
```

Verified, not asserted:

```
$ cargo test --offline
test result: ok. 24 passed; 0 failed
$ cargo clippy --offline --all-targets     # 0 warnings
$ cargo fmt --check                        # clean
```

(Toolchain: `/nix/store/5snjz7c8x0vdhsxk858m46jibzklk8sp-rust-default-1.97.0/bin`. `cargo` is not
on `PATH` in this shell; the nix store copy is. Nothing was installed.)

**How it fits dios rather than replacing anything.** `targets.rs` calls only
`config::{get_value, set_value, unset_value, load, save}` — functions that exist today, unchanged.
It adds no field to `defaults()`, because an empty registry is the absence of a key, not a default
value.

The merge landed while this was being written: `dimos-bios` now builds a binary called `dios`, the
config module is `src/pkg/config.rs` re-exported flat as `crate::config`, and infect lives at
`src/infect/` with `journal.rs` beside it. **The registry belongs in `src/infect/targets.rs`** — it
is knowledge about robots, and `lib.rs` states the rule as *"`pkg` knows PLATFORMS … it never
learns that robots exist"*. infect calling into pkg is the allowed direction, so
`use crate::config` compiles unchanged. (`lib.rs` says `tests/boundary.rs` enforces this; that file
is not in the tree yet — only `tests/recipes.rs` is.)

Grafting is then:

1. `cp targets-skeleton/src/targets.rs dimos-bios/src/infect/targets.rs`, delete the skeleton's
   `config.rs` — `use crate::config` resolves to the real one
2. `pub mod targets;` in `src/infect/mod.rs`
3. two variants into `src/cli.rs`: `Command::Target { action }` and the global `--target` on `Cli`
4. a printer — every store function returns data, none of them print
5. call `targets::upsert` at the end of infect's runner and in `infect scan`
6. make `journal.rs::RobotId` and `targets.rs::Mac` one type. They are the same normalisation
   written twice today; the registry was written to match, but two copies of an identity rule is
   exactly the drift this design exists to prevent

Every store function takes `&Value` / `&mut Value` rather than reading the file, so the tests need
no filesystem and no `HOME`, and moving the registry to its own file later is one function.

---

## 8. What I had to guess

1. **Which "transport" Aaryan meant** in "name, mac, ip, recipe, lane, transport". I stored the
   dimos one (`lcm`/`zenoh`) as `transport` because it matches the recipes, and the link one as
   `via`. If he meant wired/wifi, the fields exist and only the names swap.
2. **That `ip` may be computed rather than stored.** He said "ip". I store `links[]` and derive it,
   for §6d. `dios target list` still shows an IP column. This is the one place I did not follow the
   letter.
3. **`targets.default` living inside the `targets` section.** Safe by construction and tested, but
   it is a taste call; `targets.robots.<id>` is the conservative alternative.
4. **That `name`, not MAC, is what CLI verbs take.** `rename`, `rm`, `set-default` take names;
   `--target` accepts either.
5. **What `dios infect scan` can actually learn.** I assumed IP + MAC from ARP on the same L2 and
   nothing off-link. Verified for ARP on this laptop; the scanner itself does not exist yet (it is
   in `todo.md`, blocked on the transport trait), so its output shape is my assumption.
6. **The "scan for local dimos" half of Aaryan's sentence.** I read it as: the webrtc lane must
   find the laptop's own dimos install rather than assume a path, and `dimos.dir` / `dimos.dirs`
   in the config is where that lives. Recorded as `env_file`. If he meant something else —
   discovering a *running* dimos process, say — this part is wrong.
7. **Reflash detection is manual.** `dios target reset` is a command someone runs. Detecting it
   (machine-id, an install marker) is designable but I had no robot to measure against.
8. **`dios` vs `dim`.** I wrote `dios` everywhere per the plan; `dimos-bios` still builds a binary
   called `dim` and another workflow is mid-rename.
9. **Nothing was tested against a robot.** The G1 has been offline since 2026-08-07. Every MAC in
   the tests is a fixture; the ARP, randomisation and off-link numbers are from this laptop.
10. **`config::save` is not atomic.** I assert this is a real bug (read-modify-write, no lock, no
    temp file) and that the fix belongs in `config.rs`. I did not fix it — that file is in the repo
    another workflow is editing.
