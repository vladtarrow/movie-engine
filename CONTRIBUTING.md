# Contributing to movie-engine

Thank you for helping. This project lets AI agents edit Kdenlive projects while a person keeps working in the same editor, so it has a few rules that protect that person. Please read them before you change code.

## Ground rules

1. **Never disturb the desktop.** No focus stealing, keystrokes, mouse input or full-desktop screenshots. Drive Kdenlive only through UI Automation patterns (Invoke, ExpandCollapse, Window.Close) and capture only its own window.
2. **Test editors run hidden.** Start a test Kdenlive only through `engine/tools/kd-hidden.ps1` (invisible desktop, own profile, own TEMP), never on the visible desktop.
3. **Portable.** No installs outside the folder, no reliance on the Windows user profile, relative media paths in projects.
4. **Prove results, not calls.** A test must check the *result* (the project XML, a rendered frame, the editor state), through the command line, not by calling an internal function.
5. **No silent downgrades.** If Kdenlive cannot do something, build it with a generator and place it as a clip. Do not ship a weaker effect.

## Development setup

Follow the installation steps in [README.md](README.md#installation). You need Windows 10/11, the portable Kdenlive 26.08.3 in `engine/Kdenlive/`, Node.js (the Windows x64 `.zip`) unpacked into `engine/node/`, and `engine\node\npm.cmd install --prefix engine\voice`.

PowerShell scripts target **Windows PowerShell 5.1**:

- Save scripts that contain non-ASCII text as UTF-8 **with BOM**.
- Check exit codes of native tools; set `$ErrorActionPreference = 'Stop'` where a method exception must stop the script.
- Type both arguments of `[math]::Min` / `Max` (`[math]::Min([double]1, $v)`), or the int overload rounds your value.
- Never `FindFirst(TreeScope.Descendants)` from the main window of a loaded project; use the narrow finders in `engine/tools/kd-ui.ps1`.

## Adding or changing a `kdp.ps1` operation

1. Implement it in `engine/tools/kdp-ops.ps1` / `kdp-ops2.ps1` and wire it in `engine/kdp.ps1` (also document it in the header comment).
2. Update the action map `engine/tools/data/kdenlive-actions.csv` (`op`, `equiv`, `ui`, `na`).
3. Add a result check to `engine/tools/kdp-clitest.ps1` and run:

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File engine\tools\kdp-clitest.ps1 -Report docs\proof\clitest.txt
   powershell -NoProfile -ExecutionPolicy Bypass -File engine\tools\kdp-coverage-check.ps1
   ```

   The coverage check fails while a proof file is older than the code it covers.
4. If the change touches live sync (`kd-ui.ps1`, `kd-state.ps1`, `kd-watch.ps1`, `kd-reload.ps1`, `kd-pull.ps1`), also run `engine\tools\kd-livetest.ps1 -Report docs\proof\live-en.txt`.
5. Update `docs/kdenlive-proof.md` if what is proven changed.

## Interface languages

UI Automation finds Kdenlive items by name. To support another interface language, add its names to `$KdNames`, `$KdInfoTitle` and `$KdRevertTitle` in `engine/tools/kd-ui.ps1`. Then run `kd-langcheck.ps1` and `kd-livetest.ps1` with `MOVIE_ENGINE_UI_LANG` set to that language, and add the reports to `docs/proof/`.

## Generators

New generators go to `engine/tools/`. They render outside Kdenlive and write their output to `materials/aigenerated/<project>/<job>/`, never overwriting. Keep them deterministic, so the same inputs give the same frames, and add a small demo under `examples/` when it helps.

## Documentation

- `README.md` is the source; the translations live in `docs/readme/`. When you change the README, update the translations or mark them as outdated at the top.
- Verified quirks go to `AGENTS.md` or the matching skill in `.claude/skills/`, so the next agent does not have to rediscover them.
- Documents are Markdown.

## Pull requests

- One topic per pull request, with the commands you ran and their results (the `docs/proof/` diff is the best evidence).
- Say plainly what you could not verify.
