# Plan: remote omp host on WSL2 with tmux

**Status:** proposed 2026-09-12 — no Windows or WSL setup has been applied.
**Outcome:** a Windows desktop can host long-lived omp sessions entirely inside
WSL2, survive terminal and SSH disconnects through tmux, and expose each active
session to a phone or laptop through omp's encrypted `/collab` browser/TUI
client. A private Tailscale + Windows OpenSSH path remains available to start,
reattach, or recover the Linux session when no collab link is active.

---

## 1. Decisions

- **Run omp and all development tools inside Ubuntu on WSL2.** PowerShell is
  used only for one-time Windows administration and as the SSH gateway into
  WSL. Agent processes, repositories, credentials, compilers, LSP servers, and
  tmux sessions live in Linux.
- **Use tmux for disconnect persistence, not reboot persistence.** Closing a
  local terminal, losing phone connectivity, or ending an SSH client must not
  kill omp. A Windows reboot, `wsl --shutdown`, or WSL failure still kills Linux
  processes; omp's persisted transcript is then recovered with `omp -c` and a
  new collab link.
- **Use omp `/collab` as the primary phone/laptop interface.** It provides the
  native session transcript, streaming tool cards, prompts, interrupts, and
  Agent Hub without terminal mirroring. The host opens an outbound encrypted
  WebSocket; no router port or WSL listener is needed.
- **Use Tailscale on Windows, not inside WSL.** Tailscale's WSL2 documentation
  recommends the Windows-host client when Windows also runs Tailscale because
  nested Tailscale packets can fail. The tailnet is the private transport for
  the recovery SSH path.
- **Use regular Windows OpenSSH over Tailscale.** Tailscale SSH's server is not
  available on Windows. Windows OpenSSH authenticates the client, then
  `wsl.exe` enters the Ubuntu distro and attaches tmux.
- **Keep repositories under `~/src` in the WSL filesystem.** Microsoft
  recommends storing files on the same operating system as the tools using
  them. `/mnt/c/...` is deliberately avoided for Linux Git, build, file-watch,
  permissions, and I/O behavior.
- **Do not automatically start omp at boot.** The correct project, model,
  approval mode, and recovery choice are deliberate operator decisions. An
  optional scheduled task may start an empty tmux session; the operator starts
  `omp` or `omp -c` inside it.
- **Do not expose SSH, RDP, a browser terminal, or the WSL VM to the public
  internet.** No router port forwarding. Windows Firewall limits SSH to
  Tailscale IPv4 peers, and SSH password authentication is disabled only after
  public-key login is proven.

## 2. Resulting architecture

```mermaid
flowchart LR
    Phone[Phone browser] -->|E2E encrypted collab| Relay[my.omp.sh relay]
    Laptop[Laptop browser or omp join] -->|E2E encrypted collab| Relay
    Relay -->|outbound WebSocket| OMP[omp host]
    OMP --> TMUX[tmux session in Ubuntu WSL2]
    TMUX --> Repo[repo under /home/user/src]

    PhoneSSH[Phone SSH client] -. recovery .-> Tailnet[Tailscale tailnet]
    LaptopSSH[Laptop SSH client] -. recovery .-> Tailnet
    Tailnet -. port 22 .-> WinSSH[Windows OpenSSH]
    WinSSH -. wsl.exe -d Ubuntu .-> TMUX
```

The two paths have separate purposes:

1. **Data plane:** `/collab` for normal prompting and observation. All tools run
   against the WSL repository; the guest never accesses the host filesystem
   directly.
2. **Control/recovery plane:** Tailscale + SSH for starting WSL, selecting a
   project, attaching tmux, authenticating providers, updating packages, or
   recovering after reboot. It remains useful if the hosted collab relay is
   unavailable.

## 3. Variables to settle before implementation

Record these values in the implementation session; do not bake placeholders
into scripts or SSH configuration:

| Variable | Example | Rule |
|---|---|---|
| Windows account | `dhruv` | Same account that owns the WSL distro |
| Windows/Tailscale hostname | `plex-desktop` | Unique, stable MagicDNS name |
| WSL distro | `Ubuntu` | Exact value from `wsl.exe -l -v` |
| Linux account | `dhruv` | Non-root default WSL user |
| Linux repository root | `/home/dhruv/src` | Never `/mnt/c/...` |
| tmux session | `omp-project` | One stable, shell-safe name per repository |
| project path | `/home/dhruv/src/project` | Absolute Linux path |

Also decide which laptop and phone SSH clients will hold keys. Each device gets
its own key so one lost device can be revoked without rotating the others.

## 4. Phase A — establish the Windows and WSL baseline

### A1. Inventory without changing state

Run in an elevated PowerShell window:

```powershell
winver.exe
wsl.exe --status
wsl.exe --list --verbose
```

Required state:

- Windows 10 2004/build 19041 or newer, or Windows 11.
- The selected distro's `VERSION` column is `2`.
- Windows is configured not to sleep while plugged in. Display sleep is fine;
  system sleep is not.
- Plex is healthy before networking changes; record one known-good remote or
  LAN playback check for the final regression test.

If WSL or Ubuntu is absent:

```powershell
wsl.exe --install -d Ubuntu
```

Reboot if requested, complete the first-launch Linux username/password prompt,
then update WSL and confirm version 2:

```powershell
wsl.exe --update
wsl.exe --list --verbose
```

If Ubuntu exists as WSL1, convert it before continuing:

```powershell
wsl.exe --set-version Ubuntu 2
```

Do not unregister or reinstall an existing distro without first inspecting its
data. `wsl --unregister` is destructive and is not part of this plan.

### A2. Install the Linux baseline

Inside Ubuntu as the normal Linux user:

```bash
sudo apt update
sudo apt upgrade
sudo apt install tmux git curl ca-certificates build-essential openssh-client
```

Verify:

```bash
uname -a
tmux -V
git --version
curl --version
```

Start with stock tmux configuration. Add terminal overrides only if the actual
phone/laptop clients demonstrate a color, key, or mouse defect; speculative
`TERM` customization creates harder-to-debug nested-terminal behavior.

### A3. Create Linux-native repository storage

```bash
mkdir -p "$HOME/src"
cd "$HOME/src"
git clone <repository-url>
cd <repository>
git status
```

The resulting path must begin `/home/<linux-user>/src/`. Confirm that Git does
not report unsafe ownership, executable-bit churn, or line-ending changes.
Windows can still browse the files through
`\\wsl$\Ubuntu\home\<linux-user>\src`, but Windows tools must not become the
primary writers.

## 5. Phase B — make WSL a complete omp development host

### B1. Configure Git and repository authentication in Linux

Treat WSL as a separate development machine:

1. Configure the intended Git name and email inside WSL.
2. Generate a dedicated Ed25519 SSH key in WSL, or authenticate `gh` inside
   WSL if that is the chosen GitHub flow.
3. Add only the public key to the Git provider.
4. Verify clone/fetch/push authorization against a disposable branch or a
   repository where a no-op fetch is sufficient.
5. Do not copy a Windows private key into the repository or containerize it
   later by accident.

Example key generation:

```bash
ssh-keygen -t ed25519 -C "<wsl-host-identity>"
ssh -T git@github.com
```

The Git identity must match the target repository's own rules. Repository-local
Git configuration overrides WSL-global defaults where required.

### B2. Install and authenticate omp inside WSL

Use upstream's Linux installer:

```bash
curl -fsSL https://omp.sh/install | sh
exec "$SHELL" -l
omp --version
```

Then launch omp once from the repository and complete provider login through
`/login`. Configuration and credentials belong under the Linux user's
`~/.omp`; there is no dependency on a Windows omp installation.

Smoke test with a read-only prompt:

```bash
cd "$HOME/src/<repository>"
omp
```

Prompt the agent to report the working directory and repository status without
changing files. Verify the paths are Linux paths and that the expected model can
complete one turn.

### B3. Install project-specific tools

Install every runtime, compiler, LSP server, debugger adapter, formatter, and
package manager that the project expects. Omp can only call binaries visible in
its WSL `PATH`; Windows installations do not count.

For each active language:

1. Install the runtime/toolchain in WSL.
2. Open the project in omp.
3. Ask omp to inspect LSP status or perform a harmless symbol lookup.
4. Run the project's normal build or executable smoke command.

Do not solve missing-tool errors by pointing WSL at Windows executables unless a
specific tool officially supports that mixed environment.

## 6. Phase C — establish the tmux lifecycle

### C1. One tmux session per repository

Create or attach the project session:

```bash
tmux new-session -A -s omp-<repository> -c "$HOME/src/<repository>"
```

Inside tmux, launch a new conversation:

```bash
omp
```

After a reboot or other process loss, resume the stored conversation instead:

```bash
omp -c
```

Operational keys and commands:

| Operation | Command |
|---|---|
| Detach without stopping omp | `Ctrl-b`, then `d` |
| List sessions | `tmux list-sessions` |
| Reattach | `tmux attach-session -t omp-<repository>` |
| Create or attach idempotently | `tmux new-session -A -s omp-<repository> -c <path>` |
| End deliberately | exit omp, then exit the tmux shell |
| Kill a wedged session | `tmux kill-session -t omp-<repository>` after inspecting it |

Do not use `kill-server` for routine cleanup; it terminates every project's
session.

### C2. Prove disconnect persistence

While omp is idle inside tmux:

1. Detach with `Ctrl-b d`.
2. Close the originating Windows/WSL terminal completely.
3. Reopen Ubuntu.
4. Confirm `tmux list-sessions` still lists the project.
5. Reattach and verify the same omp process, transcript, cwd, and model remain.
6. Start a harmless agent turn, detach while it runs, wait, and reattach.
7. Verify the completed response is present and no duplicate turn was created.

This proves the target behavior. Merely confirming that the tmux session name
exists is insufficient.

### C3. Record the reboot boundary

Run only after the live session is safe to interrupt:

```powershell
wsl.exe --terminate Ubuntu
```

Expected result: the target distro's tmux and omp processes are gone. Start
Ubuntu, recreate the same tmux session name, run `omp -c`, and verify the prior
persisted transcript can be resumed. This is recovery, not transparent process
persistence. Use `wsl.exe --shutdown` only when deliberately stopping every
running WSL distro.

## 7. Phase D — enable phone and laptop access with omp Collab

Inside the host omp session:

```text
/collab
```

The command prints a full-control browser URL, QR code, and native join command.

### D1. Phone workflow

1. Scan the QR code or transfer the full URL through a private channel.
2. Open it in the phone browser; no omp installation is required.
3. Verify the historical transcript and current footer load.
4. Submit a harmless prompt asking for the WSL working directory.
5. Confirm the host shows the guest-attributed prompt and the answer reports
   `/home/<linux-user>/src/<repository>`.
6. Interrupt one deliberately long, harmless response and verify the host stops.
7. Close and reopen the browser using the same link while the host remains
   active; verify it reconnects.

### D2. Laptop workflow

Either use the same browser link or install omp locally and run:

```bash
omp join "<collab-link>"
```

The guest's local cwd is irrelevant. The Windows desktop's WSL process remains
the authoritative host for files, tools, model usage, and session state.

### D3. Permission and revocation checks

- Run `/collab view` in a separate test session and confirm its link can observe
  but cannot prompt, interrupt, or control subagents.
- Treat a full link as a bearer credential: possession grants transcript access
  and session steering.
- Run `/collab status` to inspect participants.
- Run `/collab stop` and confirm every guest disconnects.
- Start sharing again and confirm the old link no longer grants access.

A collab link is valid only for that active hosted share. It is not a permanent
bookmark across `/collab stop`, omp exit, WSL shutdown, or Windows reboot. The
recovery path in Phase E exists to obtain a new link.

No inbound port, reverse proxy, Cloudflare Tunnel, Tailscale Funnel, or router
change is needed for Collab. The current production relay is hosted by omp and
is not distributed for self-hosting.

## 8. Phase E — build the private recovery/control path

This phase makes the system reachable when no collab session exists. It is not
required for a prestarted `/collab` session, but it is required for dependable
24/7 administration.

### E1. Install Tailscale on Windows and client devices

Install Tailscale on:

- the Windows desktop,
- the laptop,
- the phone.

Authenticate all three to the same tailnet. Keep MagicDNS enabled and give the
desktop a stable name such as `plex-desktop`. Run `tailscale ping
plex-desktop` from the laptop; on the phone, confirm the desktop is reachable
in the Tailscale app. Phase E5 proves the real phone/laptop SSH path rather
than treating a control-plane status indicator as sufficient.

Do **not** install or enable Tailscale inside WSL while Windows is already the
Tailscale node. Do not configure the desktop as an exit node or subnet router;
neither is needed and both would expand the networking scope around the Plex
host.

### E2. Install Windows OpenSSH Server

Run in elevated PowerShell:

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -Name sshd -StartupType Automatic
Get-Service sshd
Get-NetFirewallRule -Name OpenSSH-Server-In-TCP
```

Do not create a router port-forward for TCP 22.

### E3. Establish public-key authentication before hardening

Generate a separate SSH key on the laptop and in the phone SSH application.
Install only their public keys for the Windows account that owns the WSL distro.

Windows OpenSSH uses different key files based on account membership:

- Non-administrator account:
  `%USERPROFILE%\.ssh\authorized_keys`
- Administrator account:
  `C:\ProgramData\ssh\administrators_authorized_keys`

For the administrator file, apply Microsoft's required ACL from elevated
PowerShell:

```powershell
icacls.exe "C:\ProgramData\ssh\administrators_authorized_keys" `
  /inheritance:r /grant "Administrators:F" /grant "SYSTEM:F"
```

Test both laptop and phone key login while password login still works. Keep the
existing administrative session open during SSH configuration changes.

### E4. Restrict SSH after keys work

1. Resolve the exact Windows login name with `whoami`.
2. In `C:\ProgramData\ssh\sshd_config`, enable public-key authentication and
   disable password authentication. Optionally restrict `AllowUsers` to the
   exact WSL-owning Windows account after validating Windows OpenSSH's account
   spelling.
3. Validate configuration before restart:

   ```powershell
   sshd.exe -t
   ```

4. Restart the service only if validation succeeds:

   ```powershell
   Restart-Service sshd
   ```

5. Scope the generated firewall rule to Tailscale IPv4 sources:

   ```powershell
   Set-NetFirewallRule -Name OpenSSH-Server-In-TCP `
     -RemoteAddress 100.64.0.0/10
   ```

6. Connect using the desktop's Tailscale `100.x.y.z` address or MagicDNS name
   and confirm key-only login from both clients.
7. Confirm an ordinary LAN source outside the tailnet no longer reaches port
   22. If MagicDNS chooses an IPv6 address, explicitly use the Tailscale IPv4
   address rather than broadening the firewall until that need is verified.

The intended `sshd_config` policy is:

```text
PubkeyAuthentication yes
PasswordAuthentication no
```

Do not disable password authentication until every recovery client has a
proven key and at least one spare key is stored securely.

### E5. Attach WSL and tmux through the gateway

From the remote SSH shell on Windows:

```powershell
wsl.exe -d Ubuntu
```

Then, inside WSL:

```bash
tmux new-session -A -s omp-<repository> -c "$HOME/src/<repository>"
```

Normal cases:

- Existing live session: tmux attaches to the running omp host.
- No live session, no reboot: tmux opens the existing project shell; run `omp`.
- After reboot/WSL shutdown: tmux creates a fresh shell; run `omp -c`, then
  `/collab` to create a new guest link.
- Hosted relay unavailable: continue operating omp directly through the tmux
  terminal over Tailscale SSH.

Keep the Windows SSH shell as a thin gateway. Do not install a second copy of
omp in PowerShell and do not clone the project onto `C:`.

## 9. Phase F — optional tmux warm start

This is convenience only. Remote SSH can start WSL and tmux on demand, so defer
it until Phases A–E pass.

Create `~/.local/bin/ensure-omp-tmux` inside WSL:

```bash
#!/usr/bin/env bash
set -euo pipefail

session=omp-host
if ! /usr/bin/tmux has-session -t "$session" 2>/dev/null; then
  /usr/bin/tmux new-session -d -s "$session" -c "$HOME"
fi
```

Make it executable and run it twice; the second invocation must be a no-op:

```bash
chmod 0755 "$HOME/.local/bin/ensure-omp-tmux"
"$HOME/.local/bin/ensure-omp-tmux"
"$HOME/.local/bin/ensure-omp-tmux"
tmux list-sessions
```

Create a Windows Task Scheduler task under the same Windows account that owns
Ubuntu:

| Field | Value |
|---|---|
| Trigger | At log on |
| Program | `C:\Windows\System32\wsl.exe` |
| Arguments | `-d Ubuntu -- /home/<linux-user>/.local/bin/ensure-omp-tmux` |
| Multiple instances | Do not start a new instance |

Use an **At log on** trigger first because WSL distros are installed per Windows
user. If operation before interactive logon is required, test a separate
"whether user is logged on or not" task under that same account; do not assume
an `At startup` SYSTEM task can see the user's distro.

The task intentionally starts only an empty `omp-host` shell. Per-project tmux
sessions and omp remain operator-started. After a reboot there is still no live
collab link until omp is resumed and `/collab` is run again.

## 10. End-to-end acceptance checklist

Implementation is complete only when every applicable check passes:

### Host placement

- [ ] `wsl.exe -l -v` shows the selected distro at version 2.
- [ ] `which omp`, `which tmux`, `which git`, and language tools resolve inside
      WSL.
- [ ] The active repository path is `/home/<user>/src/...`, not `/mnt/c/...`.
- [ ] No omp process is running in Windows PowerShell or as a Windows binary.
- [ ] Omp can complete a read-only prompt and invoke required WSL tools.

### Persistence

- [ ] Closing the local terminal leaves tmux and omp running.
- [ ] Reattaching shows the same transcript, cwd, and active process.
- [ ] An agent turn completes while every terminal client is detached.
- [ ] `wsl --terminate Ubuntu` is observed to end that distro's tmux/omp
      processes without stopping unrelated distros.
- [ ] `omp -c` recovers the prior stored conversation after process loss.

### Remote Collab

- [ ] Phone joins through a browser over cellular, not only home Wi-Fi.
- [ ] Laptop joins through browser or `omp join`.
- [ ] A guest prompt executes against the WSL project path.
- [ ] Full-control interruption works.
- [ ] View-only sharing rejects mutation/control.
- [ ] `/collab stop` revokes the active links.
- [ ] No inbound or router port was opened for Collab.

### Recovery plane

- [ ] Tailscale reaches the Windows desktop from laptop and phone.
- [ ] Tailscale is installed on Windows, not duplicated inside WSL.
- [ ] Windows OpenSSH starts automatically.
- [ ] Each client uses a distinct public key.
- [ ] Password SSH is disabled only after key login passes.
- [ ] The SSH firewall rule accepts only `100.64.0.0/10` sources.
- [ ] Remote SSH can run `wsl.exe -d Ubuntu` and attach tmux.
- [ ] After a Windows reboot, remote SSH can start WSL, run `omp -c`, and issue
      a fresh `/collab` link.

### Plex regression

- [ ] Plex LAN playback still works.
- [ ] Existing Plex remote access still works.
- [ ] No Tailscale exit-node, subnet-router, router NAT, or Plex port setting was
      changed as part of this work.
- [ ] CPU and memory at idle are acceptable with WSL + tmux running but omp
      idle.

## 11. Operations runbook

### Normal start

```powershell
wsl.exe -d Ubuntu
```

```bash
tmux new-session -A -s omp-<repository> -c "$HOME/src/<repository>"
omp
```

Then `/collab` and open the generated link.

### Resume after disconnect

```bash
tmux attach-session -t omp-<repository>
```

The existing collab link remains valid while that hosted share is still alive.

### Resume after reboot

```bash
tmux new-session -A -s omp-<repository> -c "$HOME/src/<repository>"
omp -c
```

Then run `/collab` and distribute the new link privately.

### Suspected leaked collab link

```text
/collab stop
/collab
```

Confirm the old guest disconnects and discard the old URL.

### Lost SSH client

1. Remove that device from the tailnet.
2. Remove only that device's public key from the Windows authorized-keys file.
3. Restart `sshd` after validating configuration.
4. Test a surviving recovery key before ending the administrative session.

### WSL maintenance and backup

Stop active work deliberately before export:

```powershell
wsl.exe --terminate Ubuntu
wsl.exe --export Ubuntu "<backup-path>\Ubuntu-omp.tar"
```

The export contains repositories, `~/.omp`, tmux configuration, and Linux
credentials; protect it as sensitive data. A backup does not preserve running
tmux processes.

## 12. Risks and retreat positions

| Risk | Detection | Response |
|---|---|---|
| Windows reboot or `wsl --shutdown` kills omp | tmux session absent | Start tmux, run `omp -c`, issue a new collab link |
| Collab link leaks | Unknown participant or accidental sharing | `/collab stop`, restart sharing, rotate the link |
| Hosted relay unavailable | Browser/native guests cannot connect | Attach through Tailscale + SSH and use tmux directly |
| Phone browser drops connection | Guest disappears from `/collab status` | Reopen the same active link; host continues in tmux |
| SSH key misconfiguration | Public-key login fails | Keep password enabled and an admin session open until fixed |
| SSH exposed beyond tailnet | Firewall rule accepts broad sources | Scope it to `100.64.0.0/10`; verify no router forward |
| WSL/Windows dual Tailscale conflict | Broken or low-MTU tailnet traffic | Remove the WSL client; keep Tailscale only on Windows |
| `/mnt/c` performance or permission defects | Slow Git/build, watcher failures, mode churn | Move the clone to `~/src`; do not tune around cross-filesystem use |
| Linux tool missing | omp tool call reports executable absent | Install and verify it inside WSL, not Windows |
| tmux display/key defect | Wrong colors, broken chords, stale redraw | Reproduce with stock config, identify client `$TERM`, then add the smallest verified tmux fix |
| WSL resource pressure affects Plex | Playback regression or sustained idle load | Stop unused omp sessions; tune WSL limits only from measured pressure |

## 13. Scope and repository obligations

This plan initially produces machine-local Windows/WSL configuration. It does
not yet add a stow package, Windows provisioning script, secrets, SSH keys, omp
`config.yml`, or Tailscale policy to this repository.

If the setup is later automated in this dotfiles repo:

- add only idempotent scripts with placeholders or environment inputs, never
  machine credentials;
- document the new WSL/tmux/Tailscale setup in root `README.md` in the same
  change, because it adds tools and setup steps;
- preserve machine-local `~/.omp/agent/config.yml` rather than stowing it;
- include checks that refuse destructive WSL operations such as unregistering
  a distro or overwriting an existing SSH configuration;
- keep Plex configuration and networking outside the automation.

Explicitly out of scope:

- running omp as a Windows process;
- Dockerizing omp;
- publicly exposing SSH or a browser terminal;
- self-hosting omp's production collab relay, whose release artifacts are not
  currently published;
- preserving live processes across Windows reboot;
- automatically choosing a repository and starting an agent at boot;
- changing Plex remote access, ports, storage, or service identity.

## 14. Primary sources

- [OMP Collab: Live Session Sharing](https://github.com/can1357/oh-my-pi/blob/main/docs/collab.md)
  — join flow, permission model, end-to-end encryption, browser client,
  settings, and hosted-relay limitations.
- [oh-my-pi README](https://github.com/can1357/oh-my-pi)
  — current Linux and Windows installation support.
- [Microsoft: Install WSL](https://learn.microsoft.com/en-us/windows/wsl/install)
  — supported Windows versions, `wsl --install`, updates, distro listing, and
  WSL2 conversion.
- [Microsoft: Set up a WSL development environment](https://learn.microsoft.com/en-us/windows/wsl/setup/environment)
  — Linux-user setup and the recommendation to keep Linux-tool projects in the
  WSL filesystem.
- [Tailscale: Install on Windows with WSL2](https://tailscale.com/docs/install/windows/wsl2)
  — documented warning against running Tailscale simultaneously on Windows and
  inside WSL2.
- [Tailscale quickstart](https://tailscale.com/docs/how-to/quickstart)
  — tailnet enrollment and MagicDNS.
- [Microsoft: OpenSSH Server for Windows](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse)
  — installation, service startup, and firewall rule.
- [Microsoft: OpenSSH Server configuration for Windows](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh-server-configuration)
  — authentication methods, authorized-key locations, and administrator-file
  ACL requirements.
