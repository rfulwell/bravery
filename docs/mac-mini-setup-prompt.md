Set up this Mac Mini (64 GB RAM) as the build machine for my Bravery project, from the command line.

## Context

Bravery is my personal Android browser: Brave plus a few patches. The repo is
https://github.com/rfulwell/bravery; its README is the source of truth, so read
`README.md` (especially "Building on a Mac with Docker Desktop") and
`docker/compose.yaml`, `docker/entrypoint.sh` and
`config/bravery.conf.example` before you start.

Builds run in a linux/amd64 Docker container under Docker Desktop. The container
is also a GitHub Actions self-hosted runner with the label `bravery`. A workflow
on GitHub's free runners watches for new Brave releases and queues the build job
on this machine. I want everything installed and registered, but **no build
started** unless I say so.

## Rules

- Anything that needs my password, a secret, or a GUI click is mine to do. Stop
  and tell me exactly what to run or click, then wait. This covers sudo,
  `gh auth login`, the keystore password, Docker Desktop's first-launch license
  screen, and macOS permission prompts. Never ask me to paste a secret into this
  chat, and never write the keystore password into any file yourself.
- Check before you change. Report what's already installed or configured, and
  don't redo it.
- Don't delete Docker volumes, images or data you didn't create. If anything
  looks like it would destroy existing data, ask first.
- At the end, give me a short summary: what you did, what I still need to do,
  and anything that looked wrong.

## Steps

1. **Survey the machine.** Report `uname -m` (arm64 = Apple Silicon, x86_64 =
   Intel), `sw_vers`, `sysctl -n hw.ncpu hw.memsize`, and free disk space
   (`df -h /`). The build needs about 400 GB free. If the internal disk has less,
   stop and ask me about using an external SSD for Docker's disk image.

2. **Prerequisites.** Make sure Homebrew, git and the GitHub CLI (`gh`) are
   installed (`brew install git gh`). On Apple Silicon, make sure Rosetta 2 is
   installed (`softwareupdate --install-rosetta --agree-to-license`; it may need
   my password).

3. **Docker Desktop.** Install it if missing (`brew install --cask docker`), then
   `open -a Docker`. If the license or first-run screen appears, ask me to
   complete it, and wait until `docker info` works.

4. **Docker Desktop settings.** Quit Docker Desktop, then edit its settings file.
   Recent versions use
   `~/Library/Group Containers/group.com.docker/settings-store.json`, older ones
   `settings.json` in the same folder. Inspect the file first and use the key
   names it actually contains; back it up before editing. Target values:
   - memory: 52 GB (`MemoryMiB` 53248)
   - CPUs: all cores
   - swap: 4 GB
   - disk size limit: at least 400 GB (`DiskSizeMiB`)
   - Apple Silicon only: virtualization framework on, and Rosetta for amd64
     emulation on (`UseVirtualizationFramework`, `UseVirtualizationFrameworkRosetta`)
   - start Docker Desktop at login (`AutoStart`)

   If a setting can't be set from the file, tell me exactly where to click in
   the Docker Desktop UI instead. Restart Docker Desktop and verify:
   - `docker info` shows the CPU count and ~52 GB of memory
   - `docker run --rm --platform linux/amd64 alpine uname -m` prints `x86_64`

5. **Keep the Mac awake.** Builds take hours and stop if the Mac sleeps. Give me
   the command to run myself (`sudo pmset -a sleep 0 disksleep 0`; the display
   may still sleep). Also remind me that Docker Desktop only runs while I'm
   logged in, so automatic login or staying logged in is needed after a reboot.

6. **GitHub access.** Ask me to run `gh auth login` (HTTPS, with the default
   scopes plus `workflow`). Confirm with `gh auth status` and
   `gh repo view rfulwell/bravery`.

7. **Repo and image.**
   ```bash
   git clone https://github.com/rfulwell/bravery ~/bravery   # or git pull if it exists
   mkdir -p ~/.bravery
   cd ~/bravery/docker && docker compose build
   ```
   The image build takes about 10 minutes. If it fails, show me the failing step
   and its error, propose a fix, and wait for me before changing files in the repo.

8. **Config and signing key.** Ask me to run this in a terminal:
   `cd ~/bravery/docker && docker compose run --rm bravery setup`
   It prompts for the new keystore password, so I type it myself. After it
   finishes, set these in `~/.bravery/bravery.conf` yourself:
   `BRAVERY_OFFICIAL_BUILD=0` and `BRAVERY_CONCURRENT_LINKS=1`. Then ask me to
   fill in `BRAVERY_KEYSTORE_PASSWORD` and `BRAVERY_KEY_PASSWORD` (the same
   password). Remind me to back up `~/.bravery`, because losing the key means
   Bravery can never be updated in place.

9. **Register the runner.** Get a registration token with
   `gh api -X POST repos/rfulwell/bravery/actions/runners/registration-token --jq .token`
   and pass it straight into the register command without printing it:
   ```bash
   cd ~/bravery/docker
   docker compose run --rm bravery register "$(gh api -X POST repos/rfulwell/bravery/actions/runners/registration-token --jq .token)"
   docker compose up -d
   ```
   Verify the runner shows up as online with the label `bravery`:
   `gh api repos/rfulwell/bravery/actions/runners --jq '.runners[] | {name, status, labels: [.labels[].name]}'`
   Check that the container stays up (`docker compose ps`,
   `docker compose logs --tail 50`).

10. **Cleanup.** Delete a leftover test branch:
    `git -C ~/bravery push origin --delete docker-wip`. It's fine if it's
    already gone.

11. **Stop there.** Don't trigger a build. Tell me that the first build starts
    from GitHub with
    `gh workflow run watch-brave.yml --repo rfulwell/bravery`, and that the
    first one downloads ~100 GB and takes many hours. Offer to run that command
    when I'm ready, and if I say yes, show me how to follow it with
    `gh run watch` and `docker compose logs -f`.
