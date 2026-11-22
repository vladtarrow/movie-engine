# What is proven about the Kdenlive engine

State of 2026-11-23. **This is not a claim that every Kdenlive operation is supported.** The document of 2026-11-21 claimed that and was wrong: its tests called internal functions and compared no results.

Raw results are in `docs/proof/`. A check counts only if it ran through `engine/kdp.ps1` or in a real Kdenlive and compared the result.

## Results

| Check | Evidence | Result |
|---|---|---|
| Every kdp command, with a check of its result | `clitest.txt` | 134 of 134 (2026-11-23, English interface). New check "frame shows titles": titles were missing from `frame`/`preview` until the melt copy kept XML whitespace |
| Projects built by that test open in real Kdenlive | `load.txt` | 11 of 11 at 18:15, before the last changes to kd-ui, kd-state and kd-testenv |
| Live update on a small project | `live.txt` | 13 of 13, also at 20:26 after the last changes |
| Live update with the English interface (default since 2026-11-23) | `live-en.txt` | 13 of 13 |
| Interface language of the launchers | `language.txt`, `language-ru.txt` | English by default, Russian with `MOVIE_ENGINE_UI_LANG=ru`; the File menu is found by name in both |
| Live update on the big project | `live.txt` | **Failed**: the loading window was taken for a blocking dialog. Fixed, not rerun |
| Copy to another path, start with the copy's launcher | none | **Not proven**: the launcher blocked its caller until Kdenlive closed. Fixed, not rerun |
| Fast open through `kd-open.ps1` | not saved in docs/proof: run by a second session | Small project: 21 of 21, window minimized. Big project on the real desktop: loaded (139 s reported by that session). **The editor held the focus for 3.2 s**, so a start without taking focus is not achieved |
| Effects | `assets.txt` | 433 tried: 271 change the output, 87 render but change nothing at default values, 75 unavailable in this build |
| Compositions | `assets.txt` | 56 tried: 54 change the output, 1 neutral, 1 unavailable |

"Renders but changes nothing" is not proof that the effect works with other values. `brightness`, `gain`, `gamma` and `audiobalance` moved into that group when their defaults were corrected to neutral values.

`kdp-coverage-check.ps1` currently reports gaps for the unproven rows above, and it should.

## Coverage of Kdenlive's menu

222 menu actions plus 13 jobs and panels, 235 rows in `engine/tools/data/kdenlive-actions.csv`:

- 120 are the same operation.
- 11 are reached another way or only partly. Each has its difference in `coverage-check.txt`.
- 103 concern only viewing, playback, selection or settings.
- 1 is not possible without an install: speech recognition (Whisper or Vosk).

## Limits

- This Windows build has no sox, ladspa or movit modules and lacks some frei0r and avfilter effects. `kdp.ps1` refuses them.
- Interchange export and import carry clips and gaps only.
- Multicam has no live angle switching.
- A start from an agent takes the focus for about 3 s (measured on the real desktop 2026-11-22) and then hands it back. Agents ask before starting the editor while the user works.

## Repeat

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File engine\tools\kdp-clitest.ps1 -Report docs\proof\clitest.txt
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File engine\tools\kdp-assetsweep.ps1 -Report docs\proof\assets.txt
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File engine\tools\kdp-portabletest.ps1 -Report docs\proof\portable.txt
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File engine\tools\kd-livetest.ps1 -Report docs\proof\live-en.txt
```

Add `-Big <a large project>` to also reload a copy of a large project (about 1000 clips).

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File engine\tools\kd-langcheck.ps1 -Report docs\proof\language.txt
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File engine\tools\kdp-coverage-check.ps1
```
