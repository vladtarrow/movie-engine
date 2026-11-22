# Kdenlive 26.08.3 operations and how the AI performs them

Source of the list: every menu action in Kdenlive's `src/kdenliveui.rc` (tag v26.08.3). The machine-readable map is `engine/tools/data/kdenlive-actions.csv`:

- `op`: the same operation, run end to end;
- `equiv`: reached another way, or only partly;
- `ui`: changes only the view, playback, selection or settings;
- `na`: not possible here.

What is proven and what is not: `docs/kdenlive-proof.md`.

## Equivalents, not the same operation

| Kdenlive action | What differs |
|---|---|
| Multicam | no live angle switching: cuts with `split`, `remove`, `track-set -Hide` |
| Send to library | a sequence in this project, not Kdenlive's shared library |
| Save selection / Save to bin | a sequence instead of a playlist file or clip |
| Save as / Save copy | `archive` or a file copy; the open document keeps its name |
| Open backup | `backups` lists them; restoring is a file copy |
| OpenTimelineIO import / export | clips and gaps only |
| Manage subtitles | one subtitle track per sequence |
| Speed clip job | renders a new H.264 file instead of an .mlt clip |

## File

| Kdenlive action | kdp.ps1 |
|---|---|
| New | `new -Profile <mlt profile> -VideoTracks n -AudioTracks n` |
| Open / Open recent | `kdenlive-bg.ps1 <project>` (user: `kdenlive.cmd`) |
| Revert | `kd-reload.ps1` (automatic with `kd-watch.ps1`) |
| Save | `kd-pull.ps1` (every editing command does it first) |
| Save as / Save copy | copy the `.kdenlive` file; `archive` for a self-contained copy |
| Archive project | `archive -Out <folder>` (project + all media, relative paths) |
| Render | `render` (Kdenlive renderer), `render -Preset <name>`, `preview`, `frame` |
| Import / Export OpenTimelineIO | `otio-import -File f.otio`, `otio-export -Out f.otio` (clips and gaps) |
| Open backup | `backups` lists Kdenlive's backups; `undo` / `redo` for the AI's own edits |
| Project settings | `profile-set -Profile name` (fps change rescales frame counts), `profile-from-clip -Bin id`, `proxy -Enable/-Disable`, `zone` |

## Edit

| Kdenlive action | kdp.ps1 |
|---|---|
| Undo / Redo | `undo`, `redo` (snapshot before every edit, `.kdp-history`, 100 kept) |
| Clear undo history | `clear-history` |
| Cut / Copy / Paste clips | `copy`, `move`, `remove` |
| Paste effects / Delete effects | `effect-copy [-Force]`, `effect-clear` |
| Find | UI only |

## View, Monitor, Settings, Help

All **UI only** (layouts, full screen, playback, seek, monitor zoom/overlays/scaling, MLT preview settings, themes, cache management, config wizard, debug info).

## Project (bin)

| Kdenlive action | kdp.ps1 |
|---|---|
| Add clip or folder | `bin-add -File f` (video, audio, image, Lottie/rawr animation), `folder`, `bin-folder` |
| Add colour clip | `bin-color` |
| Add image sequence | `slideshow` |
| Add title clip | `title`, `title-text` |
| Add template title | `title-save` (make a template), `title-template -File t.kdenlivetitle -Text ...` |
| Add animation | `bin-add -File anim.json` |
| Add playlist / project as clip | `playlist-clip -File x.kdenlive|x.mlt` |
| Generators (counter, noise, colour bars) | `generator -Id count|noise|frei0r.test_pat_B` |
| Create folder | `folder` |
| Extract audio | `extract-audio -Bin id` |
| Transcode / friendly transcode | `transcode -Bin id ["-FfArgs:..."] [-Replace]` |
| Locate clip (relink) | `relink -Folder dir`, `bin-replace-file` |
| Reload clip | `bin-reload` |
| Insert at timecode | `add -At` |
| Replace clip | `bin-replace-file -Bin id -File f` |
| Replace in timeline | `replace-in-timeline -Bin A -With B` |
| Duplicate clip | `bin-duplicate` |
| Proxy clip | `proxy -Enable` (project-wide; Kdenlive builds proxies) |
| Clip properties / edit clip | `bin-info`, `bin-set -Params "force_fps=..||force_aspect_ratio=..||audio_index=..||kdenlive:description=.."` |
| Rename / Delete clip | `bin-rename`, `bin-remove` |
| Adjust profile to clip | `profile-from-clip -Bin id` |
| Clean project (unused clips) | `clean` |
| Clip effects (bin) | `bin-effect -Bin id -Id effect` |
| Clip markers add / edit / delete / delete all | `marker`, `marker-set`, `marker-remove [-At]`, `marker-list` |

## Sequence (timeline)

| Kdenlive action | kdp.ps1 |
|---|---|
| New sequence, open/next/previous sequence | `sequence-add`, `-Sequence <name>` on any command (switching tabs is UI only) |
| Selection actions | UI only (clips are addressed by `-Track` + `-At`) |
| Edit duration, resize start/end | `trim [-KeepEnd]`, `ripple-trim` |
| Delete selected | `remove` |
| Cut clip | `split` |
| Mix clips (crossfade) | `mix`, `unmix` |
| Change speed / reverse | `speed` (timewarp), `remap` (time remap with keyframes) |
| Switch clip / disable clip | `disable`, `enable` |
| Extract clip / lift | `remove -Ripple` / `remove` |
| Save to bin, send to library, save selection | `copy-to-sequence` (selection into a sequence), `playlist-clip` |
| Send to sequence / copy to sequence | `copy-to-sequence -From -ToTime -Target -To` |
| Expand clip (nested sequence -> its clips) | `expand` |
| Replace timeline clip | `replace-in-timeline` |
| Group / Ungroup | `group`, `ungroup` (linked audio+video: `add-av`) |
| Insert / overwrite at in point | `add -Insert` / `add -Overwrite` |
| Remove extract / lift | `remove -Ripple` / `remove` |
| Insert space / remove space / remove space in all tracks | `space-insert -At -Dur [-Tracks]`, `space-remove -At [-Dur] [-Tracks]` |
| Delete all spaces / delete all clips (track) | `spaces-remove-all`, `track-clear` |
| Master effects | `effect-add -Master` |
| Insert / delete track | `track-add [-Audio]`, `track-remove` |
| Disable / lock track (one or all) | `track-set -Hide/-Show`, `-Lock/-Unlock` |
| Target / active track switches | UI only |
| Subtitles: add, disable, lock, manage, import, export | `sub-add`, `sub-state -Disable/-Lock`, `sub-import -File x.srt`, `sub-export -Out x.srt` |
| Speech recognition (subtitles from audio) | **not available**: needs Kdenlive's Whisper/Vosk Python packages, which are not installed (would be a download; ask the user) |
| Timeline preview (prerender zones) | UI only (performance cache) |
| Disable timeline effects | `effects-all -Disable/-Enable` |
| Set / clear zone | `zone -From -ToTime` |

## Tool

| Kdenlive action | kdp.ps1 |
|---|---|
| Normal / overwrite / insert mode | `add` (default place), `-Overwrite`, `-Insert` |
| Selection, razor | `split` |
| Spacer | `space-insert`, `space-remove` |
| Slip | `slip -By s` |
| Ripple | `ripple-trim` |
| Multicam | angles on separate tracks (`add`/`add-av` at the same time) + `split`/`remove`/`track-set -Hide`: the same result as the multicam tool, which is a live-playback UI |

## Markers (guides)

| Kdenlive action | kdp.ps1 |
|---|---|
| Add guide (with category) | `guide-add [-CategoryIndex] [-Dur]` |
| Edit / delete / delete all | `guide-set`, `guide-remove`, `guide-clear` |
| Categories | `guide-category -CategoryIndex n -Name -Color` |
| Export guides (chapters) | `guide-export -Out f.txt [-Format "{timecode} {comment}"]` |
| Lock / search guides | UI only |

## Effects and compositions panels

Effects of the 433 in Kdenlive's catalog that this Windows build can load (see `docs/proof/assets.txt`; the others are refused) (`effects`, `effect-info`, `effect-add/-set/-remove/-list`, on clip, track, master or bin clip; keyframes as MLT animation strings) and compositions (`compositions`, `comp-info`, `comp-add/-set/-remove/-list`).

## Not possible for an AI on its own

- Recording audio from a microphone (Kdenlive's audio record button): the user records, the AI imports the file.
- Speech recognition: see above (needs an install).
