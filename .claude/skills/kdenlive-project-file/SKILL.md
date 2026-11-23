---
name: kdenlive-project-file
description: Create and edit Kdenlive .kdenlive project files (MLT XML) for this project and check them headlessly with melt. Use when building or changing a video project, adding clips or titles, setting a vertical/horizontal profile, or rendering a check frame without opening the GUI.
---

# Kdenlive project files

Paths below are relative to a Movie Engine folder (a clone of https://github.com/vladtarrow/movie-engine). If the current project has no `engine\kdp.ps1`, it is not one: use the `movie-engine-setup` skill first instead of guessing paths.

A `.kdenlive` file is MLT XML with Kdenlive properties. Kdenlive 26.08.3 opens older documents (`kdenlive:docproperties.version` 1.04, `producer="main_bin"`) and upgrades them in memory on load (verified). Once Kdenlive itself saves, the file is in the newer format (version 1.1, with sequences and uuids) — read such a file before editing it and preserve everything you do not understand.

## Use the tool, not hand edits

`engine\kdp.ps1` is the command line; `engine\tools\kdp-core.ps1` (timeline/bin model) and `engine\tools\kdp-ops.ps1` (everything else) are the functions behind it. The full command list is in the header of `engine\kdp.ps1`. Every editing command: pulls the user's edits from the open Kdenlive, edits, runs `Test-KdpProject` (refuses to save if Kdenlive would complain), saves; `kd-watch.ps1` then shows the change in the open editor.

```powershell
$k = 'engine\kdp.ps1'; $p = 'projects\<name>\<name>.kdenlive'
powershell -NoProfile -ExecutionPolicy Bypass -File $k new -Project $p -Profile vertical_hd_30 -VideoTracks 3 -AudioTracks 2
powershell -NoProfile -ExecutionPolicy Bypass -File $k bin-add -Project $p -File materials\download\clip.mp4
powershell -NoProfile -ExecutionPolicy Bypass -File $k add-av -Project $p -Bin 3 -Track V1 -AudioTrack A1 -At 0 -In 2 -Dur 5
powershell -NoProfile -ExecutionPolicy Bypass -File $k effect-add -Project $p -Id fade_from_black -Track V1 -At 1 -Fade 0.5
powershell -NoProfile -ExecutionPolicy Bypass -File $k effect-add -Project $p -Id qtblend -Track V2 -At 1 -Params "rect=00:00:00.000=0 300 1080 1920 1;00:00:02.000=0 0 1080 1920 1"
powershell -NoProfile -ExecutionPolicy Bypass -File $k info -Project $p
```

Effects and compositions are generic: effects and compositions defined in `engine\Kdenlive\kdenlive-26.08.3_standalone\bin\data\kdenlive\{effects,transitions}\*.xml` can be added; parameters you do not pass get the definition's defaults (`%width`, `%height`, `%fade` resolved). Those defaults are already raw MLT values; `factor` only scales Kdenlive's panel, never divide by it. About 80 of the assets have no MLT module in this Windows build (`docs/proof/assets.txt`) and are refused. Find them with `effects -Search`, `effect-info -Id`, `compositions`, `comp-info -Id`. Parameter values are raw MLT values (keyframes as `time=value;time=value`, rects `x y w h opacity`, colours `0xRRGGBBAA`); separate several params with `||`.

### Tested how (2026-11-22)

`engine\tools\kdp-clitest.ps1` runs every command as a separate process and checks the result with its own reader, ffprobe or pixels; the projects it builds are then opened in a real Kdenlive (`docs/proof/clitest.txt`, `load.txt`). The older self-tests only call the functions: they are a quick smoke test, not proof.

| Area | Operations |
|---|---|
| Project | new (any MLT profile, N video + M audio tracks), info, validate, profiles, fonts |
| Bin | media (video+audio, video, audio, image), colour, title (font/size/colour/outline/place/align, multi-line), title text change, rename, remove, folders, move to folder, clip markers |
| Timeline | add (place / overwrite / ripple insert), add linked audio+video (AVSplit group), move (also across tracks), trim in/out (optionally keep end), split, remove (optionally ripple), speed (timewarp, negative = reverse, keep pitch), disable/enable, user groups, same-track crossfade mix / unmix |
| Effects | add any effect to a clip, a whole track, or the master; fades place themselves at clip start/end; list, set params, disable/enable, remove; type check (audio effects only on audio) |
| Compositions | add any composition between tracks (default: the next lower video track, or `-Below`), list, set params, remove |
| Tracks | add video/audio, remove (empty or `-Force`), rename, lock/unlock, hide/show (mute for audio) |
| Guides / subtitles | guides with categories and ranges; subtitles (.ass sidecar + burn-in) |
| Output | `frame` (one PNG via melt), `preview` (fast melt mp4, optional range), `render` (Kdenlive renderer; melt when the project has subtitles), `render -Preset <name>` with any Kdenlive/MLT preset (`presets` lists them) |
| Sequences | `sequence-add` (own tracks; placed before all sequences so any of them can use it), `-Sequence <name>` on any command to edit inside it, `add -Bin <sequence>` to nest it (refuses self-nesting and cycles) |
| Special clips | slideshow from a folder or `img_%04d.png` pattern (per-image time, fade, loop, crop, Pan/Zoom animation), Lottie/Glaxnimate (`.json/.rawr/.lottie` via `bin-add`, length read from MLT), time remap (constant `-Speed` or keyframed `-Map "out=src;..."`, blend, pitch), proxies on/off |
| Linked clips | move, trim, split, remove, slip, ripple-trim, speed and remap change both halves (`-Alone` for one); groups follow moved clips |
| Crossfades | several per track; `unmix -At` removes one; moving/trimming/speed/remap/split/remove of a clip inside a crossfade is refused with a hint to unmix first |

Gotcha found: bin clips can share a name (e.g. a sequence and a renamed clip); `Get-KdpBinClip` now refuses an ambiguous name, so address such clips by bin id.

### Done differently on purpose

- **Stabilize:** vid.stab through melt (two passes), as Kdenlive does. Never ffmpeg `deshake`: much weaker.
- **Multicam:** Kdenlive's multicam tool is a live-playback UI mode; its result is ordinary cuts. Put each angle on its own track (synced with `add`/`add-av` at the same time) and cut with `split`/`remove`/`track-set -Hide`.
- **Audio recording:** needs a person at a microphone. A voice-over goes in as a file (recorded by the user, or generated) via `bin-add` + `add`.
- **Keyframes:** passed as MLT animation strings in `-Params` (syntax in `reference.md` 5.3).
- **Render presets with `%dv_standard`/`%dar`** (VOB DVD) are refused: their placeholders are not documented.

## Rules Kdenlive enforces on load (verified in source and live, 2026-11-21)

- Every timeline clip's producer must carry the bin clip's `kdenlive:control_uuid`. Kdenlive maps timeline clips to bin clips by it (`meltBuilder.cpp` `constructTrackFromMelt`). Without it the clip is dropped, a modal "Problems found in your project file" dialog appears (steals focus) and the reason is appended to the project notes: "Timeline clip (chainN) without bin reference found and removed."
- Audio/video files: the bin clip is a `<chain>` (`avformat-novalidate`); each timeline use is a copy of it with its own id, the same `kdenlive:id` and `kdenlive:control_uuid`, plus `set.test_audio=1, set.test_image=0` on video tracks or `set.test_audio=0, set.test_image=1` on audio tracks. Images and colour clips may reference the bin producer directly.
- `kdenlive:file_hash` = MD5 of the whole file, or of the first and last 1,000,000 bytes if the file is larger than 2,000,000 bytes (`Get-KdpFileHash`).
- `kdenlive:clip_type` in the XML is the audio/video state, not the type enum: `0` audio+video, `1` audio only, `2` video only (images, colour, titles too). The sequence's type is `kdenlive:producer_type=17`.
- Full source-backed reference of the format: `reference.md` in this skill (sections: skeleton, bin clip kinds, timeline instances, effects with all ids, compositions, mixes, guides, subtitles, rendering, what Kdenlive rejects).
- melt stops an image/colour/title producer at its `length` property, although Kdenlive lets such clips be stretched on the timeline. An entry longer than `length` makes melt show the next clip early, so the picture drifts ahead of subtitles/audio (verified 2026-11-21 on a 334-slide cut: 5 s images used for up to 8.8 s were 11 slides ahead at 10 min). `Add-KdpClipToTimeline` and `Set-KdpClipTrim` now raise `length` as needed (`Expand-KdpEndlessLength`).
- A `kdenlivetitle` producer draws nothing when its `resource` property holds whitespace (it tries to load that as a file). An `XmlDocument` loaded without `PreserveWhitespace` and saved again indents empty `<property name="resource"></property>` into exactly that. `New-KdpMeltCopy` keeps whitespace (fixed 2026-11-23).
- Big projects (verified 2026-11-21, 333 slides + 224 VO + ~250 SFX): `Get-KdpBinClip` lists the whole bin on every call, so each `Add-KdpClipToTimeline` costs ~1 s at 400 bin clips (a build took 66 min). In bulk scripts cache bin clips by id and override `Get-KdpBinClip` (0.08 s per add). `Add-KdpEffect` also searches the timeline each call: in bulk, append `New-KdpAssetNode` filters to the entry `Add-KdpClipToTimeline` returns.
- Keyframe type `~=` (smooth) is Catmull-Rom and overshoots: with large keys at the clip ends (a whip enlarges the frame) the transform dips below full frame mid-clip and a black border shows (verified 2026-11-21). Use linear `=` for transform rects unless every neighbouring key has the same scale.
- Smooth playback: render images at the profile size (2400x1350 slides were rescaled every frame), and give heavy filters (dblur, gblur) `in`/`out` on the entry covering only the frames that need them; keyframes are then relative to the filter's `in`. Kdenlive 26.08.3 loads such clip-effect zones without marking the project modified (kd-check clean).
- Google Slides / Docs shared by link can be read without signing in: `.../document/d/<id>/export?format=md&tab=<tab>` (Markdown), `.../presentation/d/<id>/export/pptx` (speaker notes = VO lines) and `.../export/pdf`. Windows' own `Windows.Data.Pdf` renders PDF pages to PNG at any size from PowerShell 5.1 (no install); `export/png?pageid=` gives only 960x540.
- `kdenlive --render` quits after a few seconds without output when the project has subtitles (verified); render such projects with melt.
- A sequence tractor is identified by its `kdenlive:uuid` property; its element id is normally the same uuid, but `projects/proba-kdenlive` has id `tractor3` and loads fine. Find sequences by `kdenlive:uuid`/`producer_type=17`, never by id alone.
- Windows PowerShell 5.1 JSON trap: `ConvertFrom-Json` returns a JSON array as one object and `ConvertTo-Json` then writes `{"value":[...],"Count":n}`. Guides, markers and groups are written with the tool's own JSON writer (`ConvertTo-KdpJson`); never use `ConvertTo-Json` for them.
- Kdenlive writes load problems into the project notes (`kdenlive:documentnotes` in `main_bin`). After any reload that showed a dialog, run `kd-pull.ps1` and read the notes.
- `kdenlive.exe --render <project> <out.mp4>` renders headlessly through Kdenlive's own loader (hidden window, no focus change, about 2–3 min for 20 s of 1080x1920). The bundled build has no `--verify-file` option.

## Current format 1.1 (what Kdenlive 26.08.3 saves) — use this for edits

Learned from `projects/proba-kdenlive/proba.kdenlive` after Kdenlive saved it (2026-11-21):
- `<mlt ... version="7.43.0">`, `kdenlive:docproperties.version=1.1`, `kdenliveversion=26.08.3`, `uuid` and `activetimeline` = `{<uuid>}`.
- Times are timecode strings: `in="00:00:00.000" out="00:00:02.967"` (out inclusive), blanks `<blank length="00:00:05.267"/>`.
- Track content is unchanged in shape: track tractor → two playlists; clips are `<entry producer=... in out>` with `<property name="kdenlive:id">`.
- The timeline itself is a sequence tractor with `id="{<uuid>}"`, `kdenlive:producer_type=17`, `kdenlive:uuid`, `kdenlive:clipname=Sequence 1`, `kdenlive:sequenceproperties.*`; its tracks are the black producer and the track tractors. A final tractor wraps the sequence.
- Appending an `<entry>` to a track playlist and letting Kdenlive reload works (verified); tractor `out` values are recomputed by Kdenlive.
- Edit by inserting/changing `<entry>`/`<blank>` nodes; leave uuids, sequence properties and unknown properties untouched.

## Older format 1.04 (bootstrap only)

Kdenlive opens it but shows a one-time modal "upgraded, backup created" notice on the first save, which steals focus. Use it only to bootstrap a brand-new project, then let Kdenlive save once.

## Minimal working template (version 1.04, verified to load and render)

See `projects/proba-kdenlive/proba.kdenlive`. Structure, top to bottom:

1. `<mlt LC_NUMERIC="C" producer="main_bin" version="7.9.0" root="<project folder, forward slashes>">`
2. `<profile ...>` matching an MLT profile from `engine/Kdenlive/kdenlive-26.08.3_standalone/share/mlt/profiles/` (vertical 1080x1920 30 fps is `vertical_hd_30`: `frame_rate_num=30 width=1080 height=1920 display_aspect_num=9 display_aspect_den=16 colorspace=709 progressive=1`).
3. One `<producer>` per bin clip. Image clip: `mlt_service=qimage`, `resource` (relative to `root`), `length`, `ttl`, `kdenlive:clip_type=5`, `kdenlive:id=<unique int ≥2>`, `kdenlive:clipname`, `kdenlive:folderid=-1`.
4. `<playlist id="main_bin">` with `kdenlive:docproperties.*` (set `profile`, `version=1.04`) and one `<entry>` per bin producer.
5. `black_track` color producer.
6. For each track: two playlists and a `<tractor>` holding them. Audio tracks have `kdenlive:audio_track=1` and `hide="video"`; video tracks use `hide="audio"`. Clips go into the first playlist as `<entry producer=... in=... out=...>` with `<property name="kdenlive:id">` equal to the bin clip's id; gaps are `<blank length="N"/>`.
7. Main `<tractor>`: `black_track` first, then the track tractors bottom to top (audio first), plus internal transitions: `mix` for each audio track, `frei0r.cairoblend` for each video track, all with `internal_added=237`, `always_active=1`.

Times can be frame counts; `out` is inclusive (3 s at 30 fps is `in="0" out="89"`).

## Paths

`root` is absolute, so a copied project would use the old folder's media while that folder exists. `kdp.ps1`, the launchers (`tools\kd-rebase.ps1`) and every melt render replace it with the project's own folder.

Keep media paths relative to the project folder via the `root` attribute, e.g. `../../materials/aigenerated/<set>/card-1.png`, so the project survives copying the folder to another computer.

## Check headlessly with melt (no window)

```powershell
$melt = "engine\Kdenlive\kdenlive-26.08.3_standalone\bin\melt.exe"
Push-Location projects\<name>
& $melt "<name>.kdenlive" in=100 out=100 -consumer avformat:"..\..\.shots\frame-%05d.png" vcodec=png
Pop-Location
```

Then look at the PNG. Run melt from the project folder so relative paths resolve.

## Sample files

Kdenlive's own test projects (older formats) are at `https://invent.kde.org/multimedia/kdenlive/-/raw/v26.08.3/tests/dataset/<name>.kdenlive` (`test-mix`, `clip-ids`, `av`, `test-nesting`, ...). `clip-ids.kdenlive` is format 1.1 with sequences.

## After editing

If Kdenlive is running, make it show the change with the `kdenlive-live` skill (`engine\kd-reload.ps1`). Never overwrite the file while the user has unsaved changes in Kdenlive.
