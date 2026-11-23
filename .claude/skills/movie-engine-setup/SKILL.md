---
name: movie-engine-setup
description: Get a working Movie Engine folder (AI video editing in Kdenlive on Windows) — clone https://github.com/vladtarrow/movie-engine and run its one-step setup (portable Node.js, Node packages, portable Kdenlive 26.08.3). Use when the user wants to edit video with Kdenlive through an agent and the current folder has no engine\kdp.ps1, or when setup.cmd has not been run yet.
---

# Setting up Movie Engine

Movie Engine is a folder, not a library: the tools (`engine\kdp.ps1`, live sync, generators) work only from inside a clone of the repository, and the user's video projects live in its `projects\` folder. Windows 10/11 x64 only.

## Is this already a Movie Engine folder?

Look for `engine\kdp.ps1` and `setup.cmd` in the current project.
- Both present: skip to "Run the setup".
- Missing: clone it. Ask the user where (a plain folder they own, for example `C:\video\movie-engine`; not Program Files, not inside OneDrive if they can avoid it), then:

```powershell
git clone https://github.com/vladtarrow/movie-engine.git <folder>
```

Then tell the user to open that folder in Claude Code (or Codex), because the project instructions (`AGENTS.md`, `CLAUDE.md`) and skills load from there.

## Run the setup

`setup.cmd` (which runs `engine\install.ps1`) installs everything inside the folder, with no admin rights, skipping parts that are already there:
1. Node.js, latest LTS Windows x64 `.zip` from nodejs.org, checked against its `SHASUMS256.txt`, into `engine\node\`.
2. `npm install` of `engine\voice` (pinned versions).
3. Kdenlive 26.08.3 portable from download.kde.org (about 250 MB), SHA-256 checked, unpacked into `engine\Kdenlive\`.

It downloads files, so first show the user what it will do and ask:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File engine\install.ps1 -DryRun
```

After a yes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File engine\install.ps1
```

Exit 0 means ready; 1 prints `FAILED:` with the reason (a hash mismatch deletes the bad download). Running it again resumes.

## After setup

- The user starts the editor with `engine\kdenlive.cmd` (or double-clicks `open-last-project.cmd`).
- From here follow `AGENTS.md` and the `kdenlive-project-file` and `kdenlive-live` skills.
