# Kdenlive 26.08.3 project file (document version 1.1, patch 1, MLT 7.43) - source-backed reference

Purpose: let an agent create and edit `.kdenlive` files by hand, with no GUI, so that Kdenlive 26.08.3 opens them cleanly (no modal dialog) and `melt` renders them.

## 0. How to read this document

Evidence tags used on every fact:
- **V** = verified: read in Kdenlive source at tag v26.08.3, or in a real `.kdenlive` file, or reproduced by running melt 7.43 (the standalone melt.exe in this repo).
- **P** = partial: source shows the mechanism but no real file shows the exact bytes, or behaviour inferred from source.
- **U** = unverified.

Source references are `path:line` relative to the repo root of `https://invent.kde.org/multimedia/kdenlive` at tag `v26.08.3` (raw URL `https://invent.kde.org/multimedia/kdenlive/-/raw/v26.08.3/<path>`). Line numbers are for that tag.

Real files used:
- `T/<name>` = `tests/dataset/<name>.kdenlive` in the repo. Versions: `clip-ids`, `missing-proxy`, `test-keyframes`, `test-missing`, `test-nesting`, `test-nesting-effects` are doc version 1.1; `av` and `test-mix` are 1.04 (same track structure).
- `PROBA-K` = `projects/proba-kdenlive/proba.kdenlive` as saved by Kdenlive 26.08.3 (60145-byte snapshot read first; the file on disk was later overwritten by an AI-written 71265-byte version, see 9.8). Snapshot facts quoted below come from the Kdenlive-saved one.
- `BAK` = `engine/profile-kdenlive/AppData/Roaming/kdenlive/.backup/proba-1795214000000-2026-11-21-03-24.kdenlive` (AI-written file with AV chains).
- Not run: Kdenlive itself (forbidden by the task). Everything about "what Kdenlive does on load" is from source reading. Everything marked "melt-verified" was rendered by `melt.exe` 7.43 from a scratch copy.

---
## 1. Top gotchas (read first)

1. **Timeline producers must carry `kdenlive:control_uuid` equal to their bin producer's.** Loader maps timeline clip -> bin clip through `kdenlive:control_uuid` (`src/timeline2/model/builders/meltBuilder.cpp:775-830`, `binIdCorresp[uuid]` filled at `src/bin/projectitemmodel.cpp:1595`). A timeline producer without it is dropped silently: `DocumentChecker::ensureControlIdForItem` sets `kdenlive:remove=1` (`src/doc/documentchecker.cpp:850-920`, line 917) and the builder skips it (`meltBuilder.cpp:824`). The `T/*` test files have no control_uuid at all (older); then DocumentChecker generates UUIDs for bin producers and matches timeline producers by `kdenlive:id` + `resource` (documentchecker.cpp:285-330, 850-915) - but that marks the document modified (gotcha 3). Evidence in this repo: the AI-written `BAK` has audio/video chains without `control_uuid` on timeline producers, and the Kdenlive-saved `PROBA-K` snapshot of the same project contains no audio/video clips at all (they were dropped). (V for mechanism, P for the correlation.)
2. **`<property name="xml_retain">1</property>` on `main_bin` is mandatory.** Bin loading reads `documentTractor->get_data("xml_retain")` (`projectitemmodel.cpp:1416-1420`); without it the loader prints "INVALID BIN PLAYLIST" and loads no clips (projectitemmodel.cpp:1601). Present in every real 1.1 file. (V)
3. **Anything that makes Kdenlive consider the document "modified/upgraded" produces a modal info box on the first save** ("Your project file was modified by Kdenlive... a backup copy called ..._backup0.kdenlive was created", `src/doc/kdenlivedoc.cpp:745-770`; `projects/proba-kdenlive/proba_backup0.kdenlive` is the physical trace of that dialog). Triggers: doc version < 1.1 or (version 1.1 and patchversion < 1) (`documentvalidator.cpp:175-227`, sets `m_modified`), missing `control_uuid` on any bin clip/sequence, missing/empty `documentid` (documentchecker.cpp:208-216), `.srt` subtitle list (documentvalidator.cpp:1972), `modified` attribute on `<mlt>`. A clean file = version `1.1` + patchversion `1` + `control_uuid` everywhere + numeric documentid. (V)
4. **Modal dialogs at load** come from `DocumentChecker` (`src/doc/documentchecker.cpp`), shown through `resolveProblemsWithGUI()` (line 114: `DCResolveDialog::exec()`), unless every item is a silently-fixed asset file (line 120-129). Any of these opens a dialog (V): missing media file; `kdenlive:file_hash` present but different from the real file hash (status `Reload`, line 1148); title image missing; title font whose exact family name is not installed (line 833-843, status `Placeholder`); `http(s)://` resource (`Remote`); unknown effect id / unknown transition id / missing luma or LUT file; a timeline producer whose `kdenlive:id` has no `main_bin` entry (`MissingBinClip`, line 405); circular sequence reference; non-existent `storagefolder` (KUrlRequesterDialog, line 224). Other modals: bad proxy parameters (`kdenlivedoc.cpp:1895-1960`), non-standard fps (`kdenlivedoc.cpp:2000-2008`), `kdenlive:docproperties.version` newer than 1.1 (`documentvalidator.cpp:216-226`), unreadable version (line 122), stale auto-save file `<md5(filename)>` next to the project (`src/project/projectmanager.cpp:762`), mix/composition repairs at load (`meltBuilder.cpp:617-632`, shown via `checkProjectWarnings`).
5. **`kdenlive:file_hash`: omit it or compute it exactly.** Hash = MD5 hex of the whole file when size <= 2,000,000 bytes, else MD5 of (first 1,000,000 bytes + last 1,000,000 bytes) (`src/bin/projectclip.cpp:1692-1716`); `kdenlive:file_size` = byte size. Checked on load only for `avformat*`, `qimage`, `pixbuf`, `glaxnimate` and slideshows (documentchecker.cpp:1126-1160); if absent or empty no check happens. Verified against PROBA-K: `card-1.png` size 23750, md5 `65f5e90933ca031df1a1e6b10312be34` = file value (V, computed with md5sum). For Color/Text/QText the hash is MD5 of resource/xmldata/text (projectclip.cpp:1636-1690) but is not verified on load.
6. **Track tractors need `out`.** A track `<tractor>` without `out` (the PROBA-K empty tracks) has zero length for melt; a clip-bearing track tractor must have `in="00:00:00.000" out=<end of its longest playlist>`. Kdenlive recomputes it, melt does not (my first title test failed exactly because of this). Sequence tractor and project tractor `out` too. (V, melt run)
7. **`kdenlive:clip_type` in XML means audio/video presence, not the ProducerType enum:** `0` = audio+video, `1` = audio only, `2` = video only (`mltcontroller/clipcontroller.cpp:829-900`, `jobs/cliploadtask.cpp:681-725`). The repo's generator writes `5` for images and `3` for AV: Kdenlive then treats the clip as having audio+video (default branch, clipcontroller.cpp:855-866). Use `2` for image/color/title/animation, `0` for AV, `1` for audio. Sequence clip: `0`. (V)
8. **Internal transitions/filters (`internal_added=237`) are rebuilt by Kdenlive on load** (`TimelineItemModel::buildTrackCompositing(true)` after removing them, `timelineitemmodel.cpp:801-860`; composition loader skips transitions that have `internal_added` or `kdenlive:mixcut`, `meltBuilder.cpp:283`). They are optional for Kdenlive but REQUIRED for melt to composite/mix (without them melt shows only the lowest track). Always write them. (V)
9. **Effects are only imported if the filter has `kdenlive_id`** (`effectstackmodel.cpp:1520`: "don't consider internal MLT stuff"). `kdenlive_id` must exist in `data/effects` (else dialog, gotcha 4). Effect type must match the clip state: audio effects on a video-only clip and vice versa are not imported (effectstackmodel.cpp:1550-1565).
10. **Positions in a clip's own filters/keyframes are source-frame coordinates, i.e. they start at the entry's `in`.** Fade-in filter `in` must equal the entry `in`, fade-out filter `out` must equal the entry `out`, otherwise Kdenlive "repairs" them (`effectstackmodel.cpp:1575-1595`; `AssetParameterModel` default keyframe prefix `"%1=".arg(getItemIn)`, assetparametermodel.cpp:126-129). Track/master filters use timeline frames (tractor `in=0`). (V for fades, P for the general rule)

---
## 2. Project skeleton (doc version 1.1)

### 2.1 Element order and roles (all V; PROBA-K, T/test-nesting, T/clip-ids)

```
<mlt LC_NUMERIC="C" producer="main_bin" root="<abs project dir>" version="7.43.0">
  <profile .../>                                   one, MLT profile attributes
  <producer|chain ...> bin clips (one per bin item; also separate timeline copies)
  <producer id="producerN" ... kdenlive:playlistid=black_track>   black track
  per track:  <playlist/> x2 , <tractor> (track tractor, 2 playlists, optional filters/mix transitions)
  <tractor id="{SEQ-UUID}"> sequence tractor: black + track tractors + internal transitions/filters
  <playlist id="main_bin"> docproperties + folders + xml_retain + one <entry> per bin item
  <tractor id="tractorN"> project tractor (kdenlive:projectTractor=1), one <track producer="{SEQ-UUID}">
</mlt>
```
Order is by dependency (MLT needs a producer defined before use). Kdenlive writes `main_bin` and the project tractor last. (V)

`<mlt>` attributes: `LC_NUMERIC` ("C" in the repo test files, the user's locale in PROBA-K `en_US.UTF-8`; both parse because numbers are written with '.'; use "C"), `producer="main_bin"` (kept; melt ignores it and plays the last tractor: verified, `melt proba.kdenlive -consumer xml:` shows root = project tractor), `root` (absolute project folder; relative `resource` paths are resolved against it, `kdenlivedoc.cpp:1818-1830`; empty root is replaced by the project file's folder, `documentvalidator.cpp:58-60`), `version="7.43.0"` (MLT version; for MLT <= 7.15 the validator strips `mute_on_pause`, documentvalidator.cpp:131-153).

### 2.2 `<profile>` (V, PROBA-K)
```xml
<profile colorspace="709" description="Vertical HD 30 fps" display_aspect_den="16" display_aspect_num="9" frame_rate_den="1" frame_rate_num="30" height="1920" progressive="1" sample_aspect_den="1" sample_aspect_num="1" width="1080"/>
```
`kdenlive:docproperties.profile` (name of an MLT profile file, e.g. `vertical_hd_30`) is looked up first; if not found, Kdenlive matches or creates a custom profile from this element (`kdenlivedoc.cpp:1987-2013`). Non-standard fps (not in the profiles repo) -> modal error (line 2000). Keep both consistent.

### 2.3 Black track producer (V)
```xml
<producer id="producer3" in="00:00:00.000" out="00:05:17.267">
  <property name="length">2147483647</property>
  <property name="eof">continue</property>
  <property name="resource">black</property>
  <property name="aspect_ratio">1</property>
  <property name="mlt_service">color</property>
  <property name="kdenlive:playlistid">black_track</property>
  <property name="mlt_image_format">rgba</property>
  <property name="set.test_audio">0</property>
</producer>
```
Loader skips it by `kdenlive:playlistid` in {playlistmain, timeline_preview, timeline_overlay, black_track, overlay_track} (meltBuilder.cpp:142-146, 155-160). It must be `<track producer=...>` index 0 of the sequence tractor. `out` is only its length; any value >= sequence length works.

### 2.4 Track tractor (V; PROBA-K, T/test-nesting)

Audio track "A1":
```xml
<playlist id="playlist0">
  <property name="kdenlive:audio_track">1</property>
</playlist>
<playlist id="playlist1">
  <property name="kdenlive:audio_track">1</property>
</playlist>
<tractor id="tractor0" in="00:00:00.000">
  <property name="kdenlive:audio_track">1</property>
  <property name="kdenlive:trackheight">67</property>
  <property name="kdenlive:timeline_active">1</property>
  <property name="kdenlive:collapsed">0</property>
  <property name="kdenlive:thumbs_format"/>
  <property name="kdenlive:audio_rec"/>
  <track hide="video" producer="playlist0"/>
  <track hide="video" producer="playlist1"/>
  <filter id="filter0">
    <property name="window">75</property>
    <property name="max_gain">20dB</property>
    <property name="channel_mask">-1</property>
    <property name="mlt_service">volume</property>
    <property name="internal_added">237</property>
    <property name="disable">1</property>
  </filter>
  <filter id="filter1">
    <property name="channel">-1</property>
    <property name="mlt_service">panner</property>
    <property name="internal_added">237</property>
    <property name="start">0.5</property>
    <property name="disable">1</property>
  </filter>
  <filter id="filter2">
    <property name="iec_scale">0</property>
    <property name="prefix">meta.media.audio_level.</property>
    <property name="mlt_service">audiolevel</property>
    <property name="internal_added">237</property>
    <property name="dbpeak">1</property>
    <property name="disable">1</property>
  </filter>
</tractor>
```
Video track "V1" (same shape, no `kdenlive:audio_track`, `hide="audio"`, no filters):
```xml
<playlist id="playlist2"> ...entries... </playlist>
<playlist id="playlist3"/>
<tractor id="tractor1" in="00:00:00.000" out="00:00:17.233">
  <property name="kdenlive:trackheight">67</property>
  <property name="kdenlive:timeline_active">1</property>
  <property name="kdenlive:collapsed">0</property>
  <property name="kdenlive:thumbs_format"/>
  <property name="kdenlive:audio_rec"/>
  <track hide="audio" producer="playlist2"/>
  <track hide="audio" producer="playlist3"/>
</tractor>
```
Rules (V):
- A track is a tractor with exactly 2 playlists (`constructTrackFromMelt` fails if `track.count() != 2`, meltBuilder.cpp:637). Playlist 1 is only used for same-track mixes (section 6); normal clips go in playlist 0. A bare `<playlist>` directly as sequence track is also accepted (meltBuilder.cpp:232-260) but nobody writes it.
- Audio vs video: property `kdenlive:audio_track`=1 on the **track tractor** decides (`meltBuilder.cpp:217`; also on both playlists, written by Kdenlive, `trackmodel.cpp:41, 982-990`). Absent = video.
- `hide` is the MLT track attribute, bit mask: 1 = video hidden, 2 = audio muted, 3 = both ("both"); `TrackModel::isHidden()` = `hide & 1`, `isMute()` = `hide & 2` (trackmodel.cpp:1645-1650). Defaults: audio track `hide="video"` (value 1), video track `hide="audio"` (value 2). Mute an audio track: `hide="both"` on its `<track>` elements; hide a video track: `hide="both"`. Loader reads the value from the first sub-playlist (`playlist.get_int("hide")`, meltBuilder.cpp:682-688; audio tracks default to 1 at :677, video to 2 at :680). Write the same `hide` on both `<track>` lines.
- Track name: `<property name="kdenlive:track_name">Music</property>` on the track tractor (meltBuilder.cpp:670-674; set at trackmodel.cpp:38). Optional.
- Lock: `<property name="kdenlive:locked_track">1</property>` on the track tractor (meltBuilder.cpp:225, trackmodel.cpp:1613,1668). Absent = unlocked.
- `kdenlive:trackheight` (px; 0 -> 100), `kdenlive:collapsed`, `kdenlive:thumbs_format`, `kdenlive:audio_rec`, `kdenlive:timeline_active`: optional UI state (meltBuilder.cpp:238-241, 670-690). Keep as written by Kdenlive.
- The three audio filters (`volume`, `panner`, `audiolevel`, all `disable=1`, `internal_added=237`) are the mixer strip; Kdenlive recreates them (rebuildMixer). Optional; with `disable=1` they do nothing in melt either. The video track has none.
- Track order inside the sequence tractor: `black`, then audio tracks, then video tracks. MLT index = position+1. With 2 audio tracks the order is `black, A2, A1, V1, V2` (the tag arithmetic in meltBuilder.cpp:166-200,228 gives the first audio track the highest A number; "video tracks are after audio tracks", kdenlivedoc.cpp:392). UI shows V2,V1,A1,A2 top to bottom. `kdenlive:sequenceproperties.activeTrack`/`videoTarget`/`audioTarget` are track *positions* (0-based, black not counted).

### 2.5 Sequence tractor (V; PROBA-K)
```xml
<tractor id="{5ba008e9-e6aa-438e-b0fd-afea2ec7ca27}" in="00:00:00.000" out="00:00:17.233">
  <property name="kdenlive:uuid">{5ba008e9-e6aa-438e-b0fd-afea2ec7ca27}</property>
  <property name="kdenlive:clipname">Sequence 1</property>
  <property name="kdenlive:sequenceproperties.hasAudio">1</property>
  <property name="kdenlive:sequenceproperties.hasVideo">1</property>
  <property name="kdenlive:sequenceproperties.activeTrack">1</property>
  <property name="kdenlive:sequenceproperties.tracksCount">3</property>
  <property name="kdenlive:sequenceproperties.documentuuid">{5ba008e9-e6aa-438e-b0fd-afea2ec7ca27}</property>
  <property name="kdenlive:control_uuid">{5ba008e9-e6aa-438e-b0fd-afea2ec7ca27}</property>
  <property name="kdenlive:duration">00:00:17.267</property>
  <property name="kdenlive:maxduration">518</property>
  <property name="kdenlive:producer_type">17</property>
  <property name="kdenlive:id">6</property>
  <property name="kdenlive:clip_type">0</property>
  <property name="kdenlive:file_size">0</property>
  <property name="kdenlive:folderid">5</property>
  <property name="kdenlive:sequenceproperties.audioTarget">-1</property>
  <property name="kdenlive:sequenceproperties.disablepreview">0</property>
  <property name="kdenlive:sequenceproperties.position">0</property>
  <property name="kdenlive:sequenceproperties.scrollPos">0</property>
  <property name="kdenlive:sequenceproperties.videoTarget">2</property>
  <property name="kdenlive:sequenceproperties.zonein">0</property>
  <property name="kdenlive:sequenceproperties.zoneout">90</property>
  <property name="kdenlive:sequenceproperties.zoom">8</property>
  <property name="kdenlive:sequenceproperties.groups">[
]
</property>
  <property name="kdenlive:sequenceproperties.guides">[
]
</property>
  <track producer="producer3"/>          <!-- black -->
  <track producer="tractor0"/>           <!-- A1 -->
  <track producer="tractor1"/>           <!-- V1 -->
  <track producer="tractor2"/>           <!-- V2 -->
  <transition id="transition0"> ...mix, a_track 0, b_track 1... </transition>
  <transition id="transition1"> ...qtblend, a_track 0, b_track 2... </transition>
  <transition id="transition2"> ...qtblend, a_track 0, b_track 3... </transition>
  <filter id="filter3"> ...volume, internal_added 237, disable 1... </filter>
  <filter id="filter4"> ...panner, internal_added 237, start 0.5, disable 1... </filter>
</tractor>
```
Facts:
- `id` = the uuid in braces; `kdenlive:uuid` must be the same uuid (bin loader keys on the `kdenlive:uuid` property, projectitemmodel.cpp:1470-1500; `main_bin` entry and project-tractor `<track>` reference the tractor by id). In the 71265-byte AI file the id is `tractor3` while `kdenlive:uuid` is a uuid: not verified to load (U) - use the real form.
- Required for a clean load (P, from loader code): `kdenlive:uuid`, `kdenlive:producer_type`=17, `kdenlive:id` (bin id), `kdenlive:control_uuid` (DocumentChecker adds it if missing but marks the doc modified, documentchecker.cpp:350-365), `kdenlive:sequenceproperties.documentuuid` = project uuid (`kdenlive:docproperties.uuid`), `hasAudio`/`hasVideo`, `kdenlive:duration`. `kdenlive:folderid` is the Sequences folder id (5 in PROBA-K) or -1. `kdenlive:maxduration` = duration in frames (518 = 17.267 s at 30 fps). `kdenlive:clip_type` is recomputed from hasAudio/hasVideo (clipcontroller.cpp:870-893).
- All `kdenlive:sequenceproperties.*` are copied into the document's per-sequence property map on load (`KdenliveDoc::loadSequenceProperties`, kdenlivedoc.cpp:2998); keys seen in real files: activeTrack, audioTarget, videoTarget, disablepreview, documentuuid, groups, guides, hasAudio, hasVideo, position, scrollPos, tracksCount, zonein, zoneout, zoom, verticalzoom, tracks, previewchunks, dirtypreviewchunks, timelineHash, subtitlesList, activeSubtitleIndex, globalSubtitleStyles, compositing.
- `kdenlive:sequenceproperties.compositing` (default `1`): >0 -> a video composition transition (qtblend, `TransitionsRepository::getCompositingTransition`, transitionsrepository.cpp:219-245) is built for every video track; 0 -> none (timelineitemmodel.cpp:801-860). Document-level `kdenlive:docproperties.compositing` exists too.
- The internal transitions (V, PROBA-K):
```xml
<transition id="transition0">
  <property name="a_track">0</property>
  <property name="b_track">1</property>
  <property name="duck_threshold">0</property>
  <property name="duck_attenuation">-12</property>
  <property name="duck_level">0</property>
  <property name="duck_fade_in">1500</property>
  <property name="duck_fade_out">250</property>
  <property name="prefix"/>
  <property name="mlt_service">mix</property>
  <property name="kdenlive_id">mix</property>
  <property name="internal_added">237</property>
  <property name="always_active">1</property>
  <property name="accepts_blanks">1</property>
  <property name="sum">1</property>
</transition>
<transition id="transition1">
  <property name="a_track">0</property>
  <property name="b_track">2</property>
  <property name="compositing">0</property>
  <property name="distort">0</property>
  <property name="rotate_center">0</property>
  <property name="mlt_service">qtblend</property>
  <property name="kdenlive_id">qtblend</property>
  <property name="internal_added">237</property>
  <property name="always_active">1</property>
</transition>
```
One `mix` per audio track (`b_track` = MLT index of the audio track), one `qtblend` (or `frei0r.cairoblend` in older files, T/test-mix) per video track (`b_track` = its MLT index), all with `a_track=0`. The `duck_*`/`prefix` keys are newer additions of `mix`; T/test-nesting has the shorter form (a_track, b_track, mlt_service, kdenlive_id, internal_added, always_active, accepts_blanks, sum). (V)
- Sequence-level filters: `volume` + `panner` (disable=1, internal_added=237) as in PROBA-K are the master mixer, optional. User master effects (section 4.3) are filters on this tractor with `kdenlive_id` and **without** `internal_added`.

### 2.6 `main_bin` playlist and document properties (V, PROBA-K)
```xml
<playlist id="main_bin">
  <property name="kdenlive:folder.-1.5">Sequences</property>
  <property name="kdenlive:sequenceFolder">5</property>
  <property name="kdenlive:docproperties.audioChannels">2</property>
  <property name="kdenlive:docproperties.binsort">0</property>
  <property name="kdenlive:docproperties.browserurl">C:/.../Videos/</property>
  <property name="kdenlive:docproperties.compositing">1</property>
  <property name="kdenlive:docproperties.documentid">1795214000000</property>
  <property name="kdenlive:docproperties.enableTimelineZone">0</property>
  <property name="kdenlive:docproperties.enableexternalproxy">0</property>
  <property name="kdenlive:docproperties.enableproxy">0</property>
  <property name="kdenlive:docproperties.externalproxyparams"/>
  <property name="kdenlive:docproperties.generateimageproxy">0</property>
  <property name="kdenlive:docproperties.generateproxy">0</property>
  <property name="kdenlive:docproperties.guidesCategories">[ ...9 category objects... ]</property>
  <property name="kdenlive:docproperties.kdenliveversion">26.08.3</property>
  <property name="kdenlive:docproperties.patchversion">1</property>
  <property name="kdenlive:docproperties.previewextension"/>
  <property name="kdenlive:docproperties.previewparameters"/>
  <property name="kdenlive:docproperties.profile">vertical_hd_30</property>
  <property name="kdenlive:docproperties.proxyextension"/>
  <property name="kdenlive:docproperties.proxyimageminsize">2000</property>
  <property name="kdenlive:docproperties.proxyimagesize">800</property>
  <property name="kdenlive:docproperties.proxyminsize">1000</property>
  <property name="kdenlive:docproperties.proxyparams"/>
  <property name="kdenlive:docproperties.proxyresize">640</property>
  <property name="kdenlive:docproperties.seekOffset">30000</property>
  <property name="kdenlive:docproperties.sessionid">{1781177c-2dd7-44c8-bb58-b8354162ba70}</property>
  <property name="kdenlive:docproperties.uuid">{5ba008e9-e6aa-438e-b0fd-afea2ec7ca27}</property>
  <property name="kdenlive:docproperties.version">1.1</property>
  <property name="kdenlive:docproperties.verticalzoom">1</property>
  <property name="kdenlive:docproperties.zoom">7</property>
  <property name="kdenlive:expandedFolders"/>
  <property name="kdenlive:binZoom">4</property>
  <property name="kdenlive:extraBins">project_bin:-1:0</property>
  <property name="kdenlive:documentnotes"/>
  <property name="kdenlive:documentnotesversion">2</property>
  <property name="kdenlive:docproperties.opensequences">{5ba008e9-...}</property>
  <property name="kdenlive:docproperties.activetimeline">{5ba008e9-...}</property>
  <property name="kdenlive:docproperties.layout">{ ...large JSON, optional... }</property>
  <property name="xml_retain">1</property>
  <entry in="00:00:00.000" out="00:00:04.967" producer="producer0"/>
  ...
  <entry in="00:00:00.000" out="00:00:12.000" producer="{5ba008e9-e6aa-438e-b0fd-afea2ec7ca27}"/>
</playlist>
```
- Every property named `kdenlive:docproperties.X` is read generically into the document property map (`KdenliveDoc::loadDocumentProperties`, kdenlivedoc.cpp:1818-1870). So only the ones Kdenlive consumes matter. Needed: `version` (1.1), `patchversion` (1), `uuid`, `profile`, `documentid` (digits only; used as cache folder name, documentchecker.cpp:208-216 and kdenlivedoc.cpp:1935-1950), `opensequences`, `activetimeline` (`;`-separated uuids; if `activetimeline` is null the project uuid is used, projectmanager.cpp:1033-1037). Everything else has defaults. `layout` (KDDockWidgets JSON) is cosmetic: omit it. `guidesCategories`: if missing, the 9 defaults are used (kdenlivedoc.cpp:404-413, 2980-2991). Do not write `proxyparams`/`proxyextension` with unusual values (modal warning, kdenlivedoc.cpp:1895-1960). `storagefolder`: only write if the folder exists. `docmetadata.*` = project metadata (kdenlivedoc.cpp:1855-1860).
- `kdenlive:docproperties.uuid` = uuid of the main sequence. `kdenlive:sequenceFolder` = id of the folder holding sequence clips (a folder must exist for it, projectitemmodel.cpp:1427-1433).
- Entries: one per bin item that is a clip or sequence, `producer` = producer/chain/tractor id (the sequence is referenced by its tractor id, i.e. its uuid). Folders are NOT entries; they are `kdenlive:folder.<parentId>.<id>` properties (section 3.9). Entry `in/out` are informational (PROBA-K writes `out=00:00:12.000` for the sequence entry while T/test-nesting writes `out=00:00:00.000`; both load).
- Bin ids are the integer `kdenlive:id`; they are renumbered internally on load (`getFreeClipId`, projectitemmodel.cpp:1585-1595) and the timeline mapping uses `control_uuid`. Ids must be unique among bin clips (duplicate id = assert, lines 1518 and 1544) and sequence ids share the same space. Real files start at 2 (1 seems reserved for the root folder; P). Folder ids share the counter (PROBA-K: images 2,3,4, folder 5, sequence 6).

### 2.7 Project tractor (V)
```xml
<tractor id="tractor3" in="00:00:00.000" out="00:00:17.233">
  <property name="kdenlive:projectTractor">1</property>
  <track in="00:00:00.000" out="00:00:17.233" producer="{5ba008e9-e6aa-438e-b0fd-afea2ec7ca27}"/>
</tractor>
```
Last element of the file. This is what melt plays. `out` = sequence duration - 1 frame as clock time. DocumentChecker/circular-ref check skip tractors carrying `kdenlive:projectTractor` (documentchecker.cpp:369, 432, 449).

### 2.8 Times (V)
- Kdenlive saves with MLT `time_format=clock` (`projectitemmodel.cpp:1766`): `in="00:00:02.967"`, `<blank length="00:00:05.267"/>`, `out` inclusive, `blank length` = duration (exclusive). Frame N -> `hh:mm:ss.mmm` rounded to ms. At 30 fps frame 89 = `00:00:02.967`.
- MLT parses plain integers (frames) in the same attributes: `in="0" out="89"`, `length="30"` (the repo's skill states it works for 1.04; the melt run used clock only). P for 1.1 under Kdenlive. Frames are exact; clock strings lose sub-ms precision, which is harmless at <= 60 fps but can drift by a frame at awkward fps. Prefer clock strings when mimicking Kdenlive, frames when computing programmatically (write what you can re-read exactly).
- `kdenlive:duration` on bin producers is read by `time_to_frames`, so frames (`150`), clock (`00:00:05.000`) and old SMPTE (`00:00:05:00`, T/test-nesting) all work (`cliploadtask.cpp:639-645`).
- Property `length` on image/color/title producers: frames or clock (cliploadtask.cpp:636 writes clock).

### 2.9 Minimal complete project (melt-verified; Kdenlive load not run)
Built from the PROBA-K and T/test-nesting shapes above, rendered by melt 7.43 (frames 40/70/100/175 produced correct output: image card, title with qtblend keyframe move, fade_to_black, timewarp video). It contains: image bin clip, title bin clip, color bin clip (unused), timewarp clip, A1 (empty), V1 (image with fade + timewarp), V2 (title with qtblend). Generator source: `C:/Users/TRUSTR~1/AppData/Local/Temp/claude/afd2cc8d363793d2/f9cbafd1-8e2c-4a3f-81fe-9af38df66b50/scratchpad/mini.py` (not a project file). All pieces are shown individually in the sections below; assemble them in the order of 2.1.

---
## 3. Bin clips

Common bin-producer properties (V): `kdenlive:id` (int), `kdenlive:control_uuid` (`{uuid}`), `kdenlive:folderid` (`-1` root or a folder id), `kdenlive:clipname` (display name; empty -> file name), optional `kdenlive:description`, `kdenlive:tags`, `kdenlive:rating`, `kdenlive:markers` (JSON), `kdenlive:zone_in`/`zone_out`, `kdenlive:clipzones`, `kdenlive:file_hash`, `kdenlive:file_size`, `kdenlive:duration`, `kdenlive:clip_type`. Copied to timeline producers via `getPassPropertiesList` (clipcontroller.cpp:446-455): `kdenlive:control_uuid, kdenlive:proxy, kdenlive:originalurl, kdenlive:multistreams, rotate, force_aspect_ratio, force_fps, force_progressive, force_tff, threads, force_colorspace, set.force_full_luma, templatetext, file_hash, autorotate, disable_exif, xmldata, vstream, astream, set.test_image, set.test_audio, ttl, kdenlive:tags, kdenlive:markers, kdenlive:masks, kdenlive:rating, length`.

Resolution of `resource`: relative paths are prefixed with `root` + "/" (clipcontroller.cpp:267-271, except `color` service and `<producer>`/`<tractor>` placeholders). Absolute Windows paths with `C:/` work. (V)

Type detection from `mlt_service` (clipcontroller.cpp:237-365, V): `avformat`/`avformat-novalidate` -> Audio/Video/AV (by `audio_index`/`video_index`; `avformat` is rewritten to `avformat-novalidate`), `qimage`/`pixbuf` -> Image, or SlideShow if the path contains `/.all.` or a `%NNd` pattern in the base name; `color`/`colour` -> Color; `kdenlivetitle` -> Text (no resource) or TextTemplate (resource set); `xml`/`consumer` -> Playlist (or `kdenlive:producer_type`); `tractor`/`xml-string` -> Timeline; `webvfx` -> WebVfx; `qtext` -> QText (also the "missing source" placeholder); `qml`; `glaxnimate` -> Animation; anything else -> `kdenlive:producer_type` or Unknown. ProducerType enum (`src/definitions.h:174`): Unknown 0, Audio 1, Video 2, AV 3, Color 4, Image 5, Text 6, SlideShow 7, Virtual 8, Playlist 9, WebVfx 10, TextTemplate 11, QText 12, Composition 13, Track 14, Qml 15, Animation 16, Timeline 17. It appears in XML only as `kdenlive:producer_type` (sequences = 17).

### 3.1 Video+audio file (chain, V: BAK, T/clip-ids)
```xml
<chain id="chain0" in="00:00:00.000" out="00:00:05.967">
  <property name="audio_index">1</property>
  <property name="mlt_service">avformat-novalidate</property>
  <property name="kdenlive:file_size">5012466</property>
  <property name="video_index">0</property>
  <property name="resource">../../materials/aigenerated/test-kit/test-video-vertical.mp4</property>
  <property name="length">180</property>
  <property name="kdenlive:clip_type">0</property>
  <property name="seekable">1</property>
  <property name="eof">pause</property>
  <property name="kdenlive:clipname">test-video-vertical.mp4</property>
  <property name="kdenlive:file_hash">ecba7c2a057b39bb7bd5a2f2a0e4acad</property>
  <property name="mute_on_pause">0</property>
  <property name="kdenlive:folderid">-1</property>
  <property name="kdenlive:id">7</property>
  <property name="kdenlive:control_uuid">{f1197afe-fda8-478b-a4ed-a214d86aff3e}</property>
</chain>
```
(The BAK file wrote `kdenlive:clip_type` 3 here; use 0.) A `<producer>` instead of `<chain>` also loads: `ClipController::addMasterProducer` wraps avformat producers in an `Mlt::Chain` (clipcontroller.cpp:128-135), and `mlt_service` is still `avformat-novalidate`. Kdenlive-saved files add dozens of `meta.media.*` probe properties (T/clip-ids lines 14-70); they are cache only. Required by the loader for an AV clip (P): `mlt_service`, `resource`, `audio_index`, `video_index` (used for the audio/video state), `length`, `kdenlive:id`, `kdenlive:control_uuid`. Kdenlive re-probes with `producer->probe()` when it opens the clip (cliploadtask.cpp:676-700) only for newly added clips; for loaded projects the stored `meta.media.*` are used for stream info (audio channels via `meta.media.N.codec.channels`), so for an AV clip missing `meta.media.*` the audio thumbnails/stream selector may be empty (P).
Timeline copies of this clip are separate chains with `set.test_audio`/`set.test_image` (section 5.1).

### 3.2 Audio only (V: BAK)
Same as 3.1 with `video_index` = `-1`, `audio_index` 0, `kdenlive:clip_type` 1 (BAK `chain1`: wav, `length` 600).

### 3.3 Image (qimage, V: PROBA-K)
```xml
<producer id="producer0" in="00:00:00.000" out="00:00:04.967">
  <property name="length">150</property>
  <property name="eof">pause</property>
  <property name="resource">../../materials/aigenerated/test-kit/cards/card-1.png</property>
  <property name="ttl">25</property>
  <property name="aspect_ratio">1</property>
  <property name="meta.media.progressive">1</property>
  <property name="seekable">1</property>
  <property name="format">2</property>
  <property name="meta.media.width">1080</property>
  <property name="meta.media.height">1920</property>
  <property name="mlt_service">qimage</property>
  <property name="kdenlive:clipname">card-1.png</property>
  <property name="kdenlive:duration">150</property>
  <property name="kdenlive:folderid">-1</property>
  <property name="kdenlive:clip_type">5</property>
  <property name="kdenlive:id">2</property>
  <property name="kdenlive:control_uuid">{205d4a51-6b50-4be6-b20e-f8b74bf6b1ec}</property>
  <property name="kdenlive:file_size">23750</property>
  <property name="kdenlive:file_hash">65f5e90933ca031df1a1e6b10312be34</property>
</producer>
```
(`kdenlive:clip_type` was `5` in the file; recommended `2`, gotcha 7.) `length`/`out` define how long the still lasts when dropped on the timeline; the default image duration is a user setting (`image_duration`). `ttl`=25 is what the generator wrote; Kdenlive-created stills usually omit it (a still with `ttl` in MLT qimage means "hold N frames per image", used by slideshows). `pixbuf` is accepted for old files. In the timeline an image producer is used as master producer directly (projectclip.cpp:1301, `getTimelineProducer` :965-1020: "Color, image and text clips always use master producer in timeline").

### 3.4 Color clip (V: T/test-nesting)
```xml
<producer id="producer0" in="00:00:00.000" out="00:00:04.960">
  <property name="length">00:00:05.000</property>
  <property name="eof">pause</property>
  <property name="resource">0x80ff80ff</property>
  <property name="aspect_ratio">1</property>
  <property name="mlt_service">color</property>
  <property name="kdenlive:clipname">Color Clip</property>
  <property name="kdenlive:duration">00:00:05:00</property>
  <property name="seekable">1</property>
  <property name="kdenlive:folderid">-1</property>
  <property name="kdenlive:id">4</property>
  <property name="mlt_image_format">rgb</property>
  <property name="kdenlive:clip_type">2</property>
  <property name="kdenlive:file_hash">e41d2d5aa7fe00585e597a92e0ac1bbd</property>
</producer>
```
`resource` = `0xRRGGBBAA` (or a name MLT knows). `mlt_image_format=rgb` is forced by Kdenlive (clipcontroller.cpp:319-322). `xml was here` property in the dataset is an MLT artefact.

### 3.5 Title clip (kdenlivetitle, V for properties; XML melt-verified)
Producer (shape from `ClipCreator::createTitleClip` clipcreator.cpp:60-80 and `ClipLoadTask` cliploadtask.cpp:342-398):
```xml
<producer id="producer1" in="00:00:00.000" out="00:00:02.967">
  <property name="length">00:00:03.000</property>
  <property name="eof">pause</property>
  <property name="resource"/>
  <property name="xmldata">&lt;kdenlivetitle width="1080" height="1920" out="89"&gt; ...escaped title XML... &lt;/kdenlivetitle&gt;</property>
  <property name="mlt_service">kdenlivetitle</property>
  <property name="kdenlive:duration">00:00:03.000</property>
  <property name="kdenlive:clipname">Title</property>
  <property name="kdenlive:folderid">-1</property>
  <property name="kdenlive:clip_type">2</property>
  <property name="kdenlive:id">3</property>
  <property name="kdenlive:control_uuid">{11111111-2222-3333-4444-555555555555}</property>
</producer>
```
`xmldata` is the title document as XML-escaped text (or CDATA). The MLT `kdenlivetitle` producer reads `xmldata`, or a `.kdenlivetitle` file given in `resource` (then the clip is a TextTemplate, with optional `templatetext` replacing the `%s` placeholders, clipcreator.cpp:384-420). Title width/height should equal the profile size (title scene is rendered at that size and scaled otherwise).
Title document grammar (V, `src/titler/titledocument.cpp:125-345`; sample from `data/titles/simple.kdenlivetitle`; the example below rendered correctly in melt, "Hello title" at (140,800)):
```xml
<kdenlivetitle width="1080" height="1920" out="89">
 <item type="QGraphicsTextItem" z-index="0">
  <position x="140" y="800">
   <transform>1,0,0,0,1,0,0,0,1</transform>
  </position>
  <content font="Arial" font-pixel-size="120" font-color="255,255,255,255" font-weight="700"
           font-italic="0" font-underline="0" font-outline-color="0,0,0,255" font-outline="3"
           letter-spacing="0" line-spacing="0" alignment="1" shadow="0;#64000000;3;3;3"
           kdenlive-axis-x-inverted="0" kdenlive-axis-y-inverted="0" box-width="800" box-height="150">Hello title</content>
 </item>
 <startviewport rect="0,0,1080,1920"/>
 <endviewport rect="0,0,1080,1920"/>
 <background color="0,0,0,0"/>
</kdenlivetitle>
```
Item types and content attributes (from titledocument.cpp): `QGraphicsTextItem` (`font`, `font-weight` Qt6 scale 100-1000, `font-pixel-size`, `font-italic`, `font-underline`, `letter-spacing`, `font-color` "r,g,b,a", `font-outline`, `font-outline-color`, `box-width`, `box-height`, `line-spacing`, `tab-width`, `alignment` (Qt::Alignment integer: 1 left, 2 right, 4 centre, P), `shadow` "enabled;color;blur;x;y", `typewriter`, `gradient`, `kdenlive-axis-x-inverted`, `kdenlive-axis-y-inverted`), `QGraphicsRectItem`/`QGraphicsEllipseItem` (`rect`, `pencolor`, `penwidth`, `brushcolor`, `gradient`, `cornerRadius`), `QGraphicsPixmapItem`/`QGraphicsSvgItem` (`url` absolute path, or `base64`). `position` x,y in title pixels (top-left of the item), `transform` 3x3 matrix row-major (`zoom`/`rotation` attrs optional). `startviewport`/`endviewport` rect = scroll animation. `font-weight < 100` is treated as Qt5 scale and converted (titlewidget.cpp:712-745). Relative image `url` is prefixed with root.
Gotchas: the font's exact family name must be installed or a dialog opens (gotcha 4); image urls must exist; `LC_NUMERIC="C"` is written on the root by Kdenlive when saving (titledocument.cpp:136) and is only needed if you use decimal numbers.

### 3.6 Image sequence / slideshow (P: shape from source, no real file)
`qimage` producer whose `resource` is a printf pattern (`/path/img_%04d.png`) or `/path/.all.png`; Kdenlive then types it SlideShow (clipcontroller.cpp:305-317). Extra properties (clipcreationdialog.cpp:315-322, 519-526): `ttl` (frames per image), `loop` (0/1), `crop` (0/1), `fade` (0/1), `luma_duration`, `luma_file`, `softness` (0-100), `animation` (name from `data/slideanimations.rc`), `low-pass`. On load `processSlideShow` attaches hidden filters to the producer (`avgblur`/`boxblur`, `affine` with `transition.rect`/`transition.cycle`, `luma` with `cycle`/`duration`/`luma.resource`, cliploadtask.cpp:160-212), which get serialised as plain `<filter>` children of the producer (no `kdenlive_id`). `length` = `ttl` x image count. File hash for slideshows = MD5 of names+sizes+hash of first/middle image (`ProjectClip::getFolderHash`, projectclip.cpp:1617-1634).

### 3.7 Animation (glaxnimate/lottie, P)
`mlt_service=glaxnimate`, `resource` = `.rawr`/`.json`/`.lottie` path; created at clipcreationdialog.cpp:196-204 with only `mlt_service`, `resource`, `kdenlive:folderid`; type Animation (clipcontroller.cpp:353). Hash is checked on load for glaxnimate (documentchecker.cpp:1126). Needs the `glaxnimate` MLT producer (present in the bundled melt: it is listed by `melt -query producers`).

### 3.8 Another project / MLT playlist file as clip (P)
`mlt_service` `xml` (or `consumer`), `resource` = path to `.kdenlive`/`.mlt`, type Playlist (`kdenlive:producer_type` 9 if present). Loaded with `Mlt::Producer(profile, nullptr, resource)`; Kdenlive adjusts length by `seekOffset` when the file is a `.kdenlive` (cliploadtask.cpp:420-450). Timewarp of a playlist uses `consumer:` prefix (projectclip.cpp:1144-1148). No real saved example is available in the repo.

### 3.9 Sequence clip (V: PROBA-K, T/test-nesting)
The sequence tractor of 2.5 *is* the bin clip: it sits in the file before `main_bin` and is listed as an `<entry producer="{uuid}">`. Extra sequences are additional tractors of the same shape (own `kdenlive:uuid`, own `kdenlive:id`, `kdenlive:sequenceproperties.documentuuid` = the **document** uuid for all sequences, own track tractors). `kdenlive:docproperties.opensequences` lists those that are open in tabs. Using a sequence in a timeline: an `<entry producer="{seq-uuid}" ...>` with `kdenlive:id` of the sequence and `kdenlive:maxduration` (T/test-nesting lines ~425-434, 505-515). A sequence cannot contain itself (checked, documentchecker.cpp:430-470; builder drops it, meltBuilder.cpp:798-812).

### 3.10 Folders (V)
Properties of `main_bin`: `kdenlive:folder.<parentId>.<folderId>` = folder name; root parent id is `-1`; e.g. `kdenlive:folder.-1.5` = `Sequences` (projectitemmodel.cpp:1329-1390, binplaylist.cpp:33-37, 90). A clip is placed in a folder with `kdenlive:folderid=<folderId>` (only the part after the last `.` is used, projectitemmodel.cpp:1670-1678; unknown folder -> root). Folder ids must be integers != parent (`folderId < 0 || parentId == folderId` is ignored), and at least one folder with parent `-1` must exist if any folder is declared (`Q_ASSERT(downLinks.count(-1) > 0)`, line 1368). `kdenlive:expandedFolders` = `;`-separated folder ids to show expanded.

### 3.11 Clip markers, name, description
- Markers on a bin clip: property `kdenlive:markers` = JSON array `[{"pos":<frames from clip start>,"comment":"text","type":<category index 0..8>,"duration":<frames, 0 = point marker>}]` (writer `MarkerListModel::toJson`, markerlistmodel.cpp:1025-1046; reader :886-950). Same format as guides (section 7). Categories are those of `guidesCategories`. (V)
- `kdenlive:clipname` = name (empty is allowed, T/clip-ids), `kdenlive:description` = text, `kdenlive:tags`, `kdenlive:rating`.

---
## 4. Timeline clip instances

### 4.1 Playlist structure (V)
Clips are `<entry>` children of the **first playlist of a track tractor**; gaps are `<blank length=.../>`; positions are implicit (sum of previous entries). From PROBA-K:
```xml
<playlist id="playlist2">
  <entry in="00:00:00.000" out="00:00:02.967" producer="producer0">
    <property name="kdenlive:id">2</property>
  </entry>
  <entry in="00:00:00.000" out="00:00:02.967" producer="producer1">
    <property name="kdenlive:id">3</property>
  </entry>
  <blank length="00:00:05.267"/>
  <entry in="00:00:00.000" out="00:00:02.967" producer="producer0">
    <property name="kdenlive:id">2</property>
  </entry>
</playlist>
```
- `in`/`out` select the used part of the producer (trim); out inclusive; duration in frames = out-in+1. Trimming = change these. Two entries may reference the same producer id (PROBA-K does; Kdenlive also writes separate per-clip copies, section 5.1).
- Per entry the only property Kdenlive needs is `<property name="kdenlive:id">N</property>` = bin id (real files always have it; the loader derives the bin clip from the producer's `control_uuid`, `kdenlive:id` is overwritten from the mapping, meltBuilder.cpp:821-826). Optional extras: `kdenlive:activeeffect` (index of selected effect, T/test-nesting-effects), `kdenlive:maxduration` (sequence entries), `kdenlive:hide_keyframes`, `kdenlive:audio_index`.
- Entry children: `<filter>` elements = clip effects (section 5).
- Clip length limit: for stills/titles/colors (`kdenlive:duration` / `length`) the clip may be extended beyond the original length (`endless resize`); for media files `out` must be < `length`.

### 4.2 Audio/video split and grouping (V for loader, P for exact bytes)
A file clip with audio and video appears as TWO entries: video entry on a video track, audio entry on an audio track, same start position, same `in/out`, same `kdenlive:id`. Each uses its own producer copy (a second `<chain>` with the same bin properties plus the state flags):
- video-track copy: `set.test_audio=1`, `set.test_image=0` (PROBA-K `chain2`: `astream` 0 too)
- audio-track copy: `set.test_audio=0`, `set.test_image=1` (PROBA-K/BAK `chain3`)
State inference on load (`inferState`, meltBuilder.cpp:729-753): state = (video = `set.test_image==0`, audio = `set.test_audio==0`), then forced video-only on a video track and audio-only on an audio track; both flags = 1 means **Disabled** (see 4.4). Stills/titles/colors need no flags.
The two entries are linked by a group in `kdenlive:sequenceproperties.groups`:
```json
[
  {
    "children": [
      { "data": "2:0", "leaf": "clip", "type": "Leaf" },
      { "data": "1:0", "leaf": "clip", "type": "Leaf" }
    ],
    "type": "AVSplit"
  }
]
```
Format (`GroupsModel::toJson`, groupsmodel.cpp:763-790; `fromJson` :822-900): array of root groups; a group = `{"type": "Normal"|"AVSplit"|"Leaf", "children":[...]}`; a leaf = `{"type":"Leaf","leaf":"clip"|"composition"|"subtitle","data":"<trackPosition>:<startFrame>:<subLayer>"}` where `trackPosition` = 0-based index among the sequence's tracks **excluding the black track** (so `tractor0`=0, `tractor1`=1, ...), `startFrame` = the item's start frame on the timeline (integer frames, not clock), `subLayer` = `-1` (the current writer emits `2:0:-1`; the 2-part form from T/test-nesting is also read). `AVSplit` must have exactly 2 children, one on an audio and one on a video track (groupsmodel.cpp ~1115-1135); `Normal` = user group (any items). A leaf that cannot be resolved (no clip starts at that frame on that track) invalidates the whole group (`fromJson` returns -1). Groups are loaded after the timeline is built and the property is then cleared (kdenlivedoc.cpp:2507-2516).
Without a group the two entries just behave independently (no move/trim linking). Audio-only or video-only use of a file: single entry, no group.

### 4.3 Properties of the timeline instance vs bin
Per-instance state is only: track, position, in/out, effects, state flags, `kdenlive:id`. Name/markers/description come from the bin clip. Clip markers of the bin clip show on all instances.

### 4.4 Disabled clip
Producer copy with `set.test_audio=1` and `set.test_image=1` (`ProjectClip::createDisabledMasterProducer`, projectclip.cpp:867-873; `getTimelineProducer` Disabled branch). Kdenlive uses a fresh clone with those flags and the entry keeps `kdenlive:audio_index`. (V source; no real saved file.)

### 4.5 Speed change / reverse (timewarp; V source, melt-verified)
A speed-changed clip uses a **timewarp producer** (one per clip instance; `ProjectClip::getTimelineProducer`, projectclip.cpp:965-1200):
```xml
<producer id="producer3" in="00:00:00.000" out="00:00:03.967">
  <property name="length">00:00:08.000</property>
  <property name="eof">pause</property>
  <property name="resource">2:../../materials/aigenerated/test-kit/test-video-vertical.mp4</property>
  <property name="warp_speed">2</property>
  <property name="warp_resource">../../materials/aigenerated/test-kit/test-video-vertical.mp4</property>
  <property name="warp_pitch">0</property>
  <property name="mlt_service">timewarp</property>
  <property name="kdenlive:id">5</property>
  <property name="kdenlive:control_uuid">{33333333-2222-3333-4444-555555555555}</property>
  <property name="set.test_audio">1</property>
  <property name="set.test_image">0</property>
</producer>
```
Mechanics: URL `timewarp:<speed>:<resource>` (`speed` printed with 15 significant digits), `length = round(original_length / |speed|)`, `ttl` scaled for stills, `warp_pitch`=1 enables pitch compensation, `set.test_*` as in 4.2, `kdenlive:id` + `kdenlive:control_uuid` of the bin clip, `warp_resource`/`warp_speed` written by MLT. `in/out` of the entry are in **output** frames (melt run: speed 2, project frame 100 = entry frame 10 showed source frame 20). Negative `speed` (e.g. `-1`) = reverse (the code uses `std::abs(speed)` for length, projectclip.cpp:1153). Both the audio and the video entry of an AV clip need their own timewarp producer with the matching flags. DocumentChecker reads these services: `timewarp` with `resource` = `speed:path` (documentchecker.cpp:934, processProxyNodes kdenlivedoc.cpp:2870-2890). Alternatively time remapping uses `<chain>` with a `<link mlt_service="timeremap" time_map="..." pitch image_mode>` child (clipmodel.cpp:480-510, 1013-1020; P, no sample). The `speed` effect (id `speed`, tag `timewarp`, type `av`) in `data/effects/speed.xml` is only the UI; it is never saved as a `<filter>` (it is applied by swapping the producer, `ClipModel::useTimewarpProducer`).

### 4.6 Freeze frame
Effect `freeze` (tag `freeze`, params `frame`, `freeze_before`, `freeze_after`; data/effects/freeze.xml) as a clip filter: `<filter><property name="mlt_service">freeze</property><property name="kdenlive_id">freeze</property><property name="frame">45</property><property name="freeze_before">0</property><property name="freeze_after">1</property></filter>` (shape from the effect XML, P; `frame` is a source frame, default `%position`). A true "freeze frame clip" (extract frame as image) produces a normal image clip: UNVERIFIED (no source found in this tag).

### 4.7 Clip in/out trimming and other per-entry facts
- Trim start: raise `in` (and shift the entry start by inserting/removing `blank` before it); trim end: lower `out`.
- Missing `blank` between entries means clips butt against each other; overlap on one playlist is impossible (use a mix, section 8).
- Zero-length: `out` < `in` is invalid.

---
## 5. Effects (filters)

### 5.1 Where a filter lives (V)
| Scope | XML location | Owner type in code |
|---|---|---|
| Timeline clip | `<filter>` child of the `<entry>` | TimelineClip |
| Bin clip (all instances) | `<filter>` child of the bin `<producer>`/`<chain>` | BinClip |
| Track | `<filter>` child of the track `<tractor>` (T/test-keyframes `tractor2`: `<filter id="filter7" out="00:00:00.200">`) | TimelineTrack (`TrackModel::importEffects`, trackmodel.cpp:1653) |
| Whole sequence ("Master") | `<filter>` child of the sequence tractor, no `internal_added` | Master (`TimelineModel::importMasterEffects`, timelinemodel.cpp:6977) |
Real clip-filter example (T/test-nesting-effects):
```xml
<entry producer="chain3" in="00:00:00.000" out="00:00:00.160">
  <property name="kdenlive:id">4</property>
  <property name="kdenlive:activeeffect">0</property>
  <filter id="filter9">
    <property name="u">226</property>
    <property name="v">150</property>
    <property name="mlt_service">sepia</property>
    <property name="kdenlive_id">sepia</property>
    <property name="kdenlive:collapsed">0</property>
  </filter>
</entry>
```
Real keyframed clip filter (T/test-keyframes):
```xml
<filter id="filter6">
  <property name="start">1</property>
  <property name="level">00:00:00.000=1;00:00:00.040=2.17;00:00:00.080=1.48;00:00:00.160=0.86</property>
  <property name="mlt_service">brightness</property>
  <property name="kdenlive_id">brightness</property>
  <property name="kdenlive:collapsed">0</property>
</filter>
```
Track-level filter (T/test-keyframes): same body with `<filter id="filter7" out="00:00:00.200">` placed in the track tractor.

### 5.2 Attributes and properties (V)
- `mlt_service` = the effect's `tag` (MLT filter name); `kdenlive_id` = the effect `id` from `data/effects` (when the XML has no `id`, id = tag, effectsrepository.cpp:80-95 and effectitemmodel.cpp:60-63 fallback `kdenlive_id` -> `mlt_service`). Both are written. Loader requires `kdenlive_id` (gotcha 9).
- Parameter properties are named exactly as the `name` attribute of `<parameter>` in the effect XML (effectitemmodel.cpp:75-160 reads `effect->get(paramName)`); write all of them, missing ones show the XML default in the UI but the MLT filter runs with its own default.
- `disable=1` = effect disabled; whole-stack disable is represented by `kdenlive:bin-disabled` on bin clips (effectitemmodel.cpp:20, effectstackmodel.cpp ~1532). `kdenlive:collapsed`, `kdenlive:activeeffect`, `kdenlive:kfrhidden`, `kdenlive:force_in_out`, `kdenlive:builtin`: UI state.
- Filter attributes `in`/`out` (clock): the effect's active range in producer frames (clip filters) or timeline frames (track/master). With `kdenlive:force_in_out=1` and `out>0` Kdenlive keeps them as zone limits (effectstackmodel.cpp:1525, 1580); otherwise Kdenlive resets them (fades) or leaves them (full length).
- Order in XML = stack order (top to bottom).
- Unique effects (`unique="1"`: fadein, fadeout, fade_from_black, fade_to_black, speed, audiomap...) can appear once per clip (effectstackmodel.cpp ~1541).
- Effects on a clip whose type mismatches the clip state are skipped on load (gotcha 9).

### 5.3 Keyframes syntax (V)
MLT animation string: `time=value;time=value`, time as clock `00:00:01.000` (what Kdenlive writes, `time_format=clock`) or frames (`24`). Negative time = from the end (`-1` = last frame; used by fades: `0=0;-1=1`). Operator between time and `=` selects interpolation (`KeyframeModel` map, `assets/keyframes/model/keyframemodel.cpp:22-65`): none = linear, `|` or `!` = discrete (hold), `~` = smooth (catmull-rom, loose), `$` = smooth natural, `-` = smooth tight, `a`/`b`/`c` sinusoidal in/out/in-out, `d,e,f` quadratic, `g,h,i` cubic, `j,k,l` quartic, `m,n,o` quintic, `p,q,r` exponential, `s,t,u` circular, `v,w,x` back, `y,z,A` elastic, `B,C,D` bounce. Example: `00:00:00.000=0;00:00:01.000~=1;00:00:02.000|=0`. Rect values: `x y w h opacity` per keyframe, e.g. `00:00:00.000=0 0 1080 1920 1;00:00:02.967=0 -300 1080 1920 1` (melt-verified in qtblend). A value without any `=` is a constant (Kdenlive prefixes `<itemIn>=` when it shows it). Point values `x y`. Colors `0xRRGGBBAA`.

### 5.4 Worked effect examples (shapes from `data/effects/*.xml` parameter lists; those marked "melt" were rendered)
Fade in video (id `fade_from_black`, tag `brightness`, unique; XML params `out` position default `%fade`, `in` fixed 0, multiswitch `level`/`alpha` default `level=1`, `alpha=0=0;-1=1`; fade-from-black variant `level=0=0;-1=1`, `alpha=1`):
```xml
<filter id="filter0" in="00:00:00.000" out="00:00:00.500">
  <property name="start">1</property>
  <property name="level">1</property>
  <property name="alpha">0=0;-1=1</property>
  <property name="mlt_service">brightness</property>
  <property name="kdenlive_id">fade_from_black</property>
</filter>
```
Fade out video (`fade_to_black`, `in` = `-%fade` relative to clip end, `out` = clip `out`; params `level=1`, `alpha=0=1;-1=0`; melt-verified, entry `in 0 out 2.967`, filter `in=00:00:02.000 out=00:00:02.967`):
```xml
<filter id="filter1" in="00:00:02.000" out="00:00:02.967">
  <property name="start">1</property>
  <property name="level">1</property>
  <property name="alpha">0=1;-1=0</property>
  <property name="mlt_service">brightness</property>
  <property name="kdenlive_id">fade_to_black</property>
</filter>
```
Audio fade (`fadein`/`fadeout`, tag `volume`, type audio, unique; fixed params `gain`/`end`, `in`/`out` positions):
```xml
<filter id="filter2" in="00:00:00.000" out="00:00:00.500">
  <property name="gain">0</property>
  <property name="end">1</property>
  <property name="mlt_service">volume</property>
  <property name="kdenlive_id">fadein</property>
</filter>
<filter id="filter3" in="00:00:09.500" out="00:00:10.000">
  <property name="gain">1</property>
  <property name="end">0</property>
  <property name="mlt_service">volume</property>
  <property name="kdenlive_id">fadeout</property>
</filter>
```
Volume/gain: id `gain` (tag `volume`, param `gain` linear, default 1, max 1000), id `volume` (tag `volume`, param `level` in dB, animated, default 0, v0.2), id `mute` (volume, `gain`=0 fixed), id `audiobalance`/`audiopan` (tag `panner`, param `start`/`split`). Example:
```xml
<filter id="filter4"><property name="gain">0.5</property><property name="mlt_service">volume</property><property name="kdenlive_id">gain</property></filter>
```
Transform / position-scale (id `qtblend`, tag `qtblend`; params `rect` animated rect "x y w h opacity", `rotation` animated -360..360, `compositing` list 0 (alpha blend)..., `distort` bool, `rotate_anchor` "0.5 0.5 0 0" (v3) or `rotate_center` (v2)). Melt-verified shape:
```xml
<filter id="filter21">
  <property name="rotate_center">1</property>
  <property name="mlt_service">qtblend</property>
  <property name="kdenlive_id">qtblend</property>
  <property name="rect">00:00:00.000=0 0 1080 1920 1;00:00:02.967=0 -300 1080 1920 1</property>
  <property name="rotation">0</property>
  <property name="compositing">0</property>
  <property name="distort">0</property>
</filter>
```
Note the document patch-version upgrade (documentvalidator.cpp:175-200): for patchversion < 1 a `qtblend` filter without `rotate_center=1` and without `rotate_anchor` gets `rotate_anchor="0 0"` and the doc is flagged modified; write patchversion 1 and either `rotate_anchor` (`0.5 0.5 0 0` = centre) or `rotate_center` explicitly.
Blur: `avfilter.avgblur` (`av.sizeX` animated default 1 max 500, `av.sizeY` default 0, `av.planes` list 7), `avfilter.gblur` (`av.steps` list 1-6, `av.planes`, `av.sigma` animated default 10 max 600, `av.sigmaV`), `box_blur` v2 (`hradius`, `vradius` animated default 1 max 1000, `preserve_alpha`), `frei0r.squareblur`.
Colour correction: `lift_gamma_gain` (tag `lift_gamma_gain`; `lift_r/g/b` default 0, `gamma_r/g/b` default 1, `gain_r/g/b` default 1 - colourwheel params, max 500), `avfilter.eq` (`av.contrast` -3..3 default 1, `av.brightness` -1..1 default 0, `av.saturation` 0..5 default 1, `av.gamma` 0..3 default 1, `av.gamma_r/g/b`, `av.gamma_weight`), `lumaliftgaingamma` (`lift`, `gain`, `gamma` animated), `brightness` (`level` animated, default 1, 0-400 %).
Example:
```xml
<filter id="filter5"><property name="av.contrast">1.1</property><property name="av.brightness">0.05</property><property name="av.saturation">1.2</property><property name="av.gamma">1</property><property name="mlt_service">avfilter.eq</property><property name="kdenlive_id">avfilter.eq</property></filter>
```
Crop: `crop` (tag `crop`; `top`,`left`,`bottom`,`right` px default 0, `center` bool, `center_bias`, `use_profile` default 1), `qtcrop` (`rect`, `radius`, `circle`, `color`).
Rotate: `affine` id `affine` (rotation.xml: `transition.fix_rotate_z` keyframe, `transition.rect`, `producer.resource`...), `affinerotate` (simplekeyframe `transition.rotate_z`, `transition.ox/oy`, `transition.keyed` fixed 1), or `qtblend` `rotation`.
Speed: via timewarp producer (4.5), not a filter. Pan-zoom: `pan_zoom` (tag `affine`, `transition.rect`).
Subtitle burn-in filter `avfilter.subtitles` (hidden, sequence-level) is described in 9.

### 5.5 Complete list of effect ids (data/effects at v26.08.3)
Source: every `<effect>` element in the 441-id set extracted from the 442 XML files under `data/effects` (incl. subfolders `avfilter/`, `frei0r/`, `ladspa/`, `movit/`, `sox/`; the 3 `templates/*.xml` effect groups are excluded), category from `data/kdenliveeffectscategory.rc`; type attribute defaults to `video` when absent (effectsrepository.cpp:156). Effects with several `version`s (qtblend 1-3, box_blur 1-2, dynamictext 1,6) appear once. `-` = not listed in the category file (uncategorised/hidden/internal). A filter with an id that is not in this table (or not provided by an installed MLT service via the auto-detected list in `included_effects.txt`) triggers the missing-effect dialog.


**-** (24)

| id | mlt_service (tag) | type |
|---|---|---|
| audiolevel | audiolevel | hidden |
| avfilter.acompressor | avfilter.acompressor | audio |
| avfilter.aecho | avfilter.aecho | audio |
| avfilter.agate | avfilter.agate | audio |
| avfilter.backgroundkey | avfilter.backgroundkey | video |
| avfilter.curves | avfilter.curves | video |
| avfilter.framestep | avfilter.framestep | video |
| avfilter.graphmonitor | avfilter.graphmonitor | video |
| avfilter.loudnorm | avfilter.loudnorm | audio |
| avfilter.separatefields | avfilter.separatefields | video |
| avfilter.shuffleplanes | avfilter.shuffleplanes | video |
| avfilter.subtitles | avfilter.subtitles | hidden |
| frei0r.delay0r | frei0r.delay0r | video |
| frei0r.facebl0r | frei0r.facebl0r | video |
| frei0r.facedetect | frei0r.facedetect | video |
| frei0r.tehRoxx0r | frei0r.tehRoxx0r | video |
| luma | luma | hidden |
| mask_start | mask_start | hidden |
| movit.lift_gamma_gain2 | movit.lift_gamma_gain | video |
| sox | sox | hidden |
| sox_pitch | sox | hidden |
| sox_reverb | sox | hidden |
| speed | timewarp | av |
| vidstab | vidstab | hidden |

**Alpha, Mask, and Keying** (26)

| id | mlt_service (tag) | type |
|---|---|---|
| avfilter.despill | avfilter.despill | video |
| avfilter.hsvkey | avfilter.hsvkey | video |
| chroma | chroma | video |
| frei0r.alpha0ps_alpha0ps | frei0r.alpha0ps_alpha0ps | video |
| frei0r.alpha0ps_alphagrad | frei0r.alpha0ps_alphagrad | video |
| frei0r.alpha0ps_alphaspot | frei0r.alpha0ps_alphaspot | video |
| frei0r.bgsubtract0r | frei0r.bgsubtract0r | video |
| frei0r.bluescreen0r | frei0r.bluescreen0r | video |
| frei0r.keyspillm0pup | frei0r.keyspillm0pup | video |
| frei0r.mask0mate | frei0r.mask0mate | video |
| frei0r.premultiply | frei0r.premultiply | video |
| frei0r.select0r | frei0r.select0r | video |
| frei0r.spillsupress | frei0r.spillsupress | video |
| frei0r.transparency | frei0r.transparency | video |
| lumakey | lumakey | video |
| mask_apply | mask_apply | video |
| mask_start-frei0r.alphaspot | mask_start | video |
| mask_start-frei0r.select0r | mask_start | video |
| mask_start-rotoscoping | mask_start | video |
| mask_start-shape | mask_start | video |
| obscure | obscure | video |
| opencv.tracker | opencv.tracker | video |
| rotoscoping | rotoscoping | video |
| shape | shape | video |
| spot_remover | spot_remover | video |
| strobe | strobe | video |

**Audio Correction;Channels** (4)

| id | mlt_service (tag) | type |
|---|---|---|
| audiobalance | panner | audio |
| audiopan | panner | audio |
| channelcopy | channelcopy | audio |
| swapchannels | channelswap | audio |

**Blur and Sharpen** (11)

| id | mlt_service (tag) | type |
|---|---|---|
| avfilter.avgblur | avfilter.avgblur | video |
| avfilter.bilateral | avfilter.bilateral | video |
| avfilter.boxblur | avfilter.boxblur | video |
| avfilter.cas | avfilter.cas | video |
| avfilter.dblur | avfilter.dblur | video |
| avfilter.gblur | avfilter.gblur | video |
| avfilter.sab | avfilter.sab | video |
| avfilter.smartblur | avfilter.smartblur | video |
| avfilter.unsharp | avfilter.unsharp | video |
| box_blur | box_blur | video |
| frei0r.squareblur | frei0r.squareblur | video |

**Channels** (3)

| id | mlt_service (tag) | type |
|---|---|---|
| audiomap | audiomap | audio |
| channelswap | channelswap | audio |
| mono | mono | audio |

**Color and Image Correction** (60)

| id | mlt_service (tag) | type |
|---|---|---|
| avfilter.chromahold | avfilter.chromahold | video |
| avfilter.colorbalance | avfilter.colorbalance | video |
| avfilter.colorchannelmixer | avfilter.colorchannelmixer | video |
| avfilter.colorcontrast | avfilter.colorcontrast | video |
| avfilter.colorcorrect | avfilter.colorcorrect | video |
| avfilter.colorhold | avfilter.colorhold | video |
| avfilter.colorize | avfilter.colorize | video |
| avfilter.colorlevels | avfilter.colorlevels | video |
| avfilter.colortemperature | avfilter.colortemperature | video |
| avfilter.eq | avfilter.eq | video |
| avfilter.exposure | avfilter.exposure | video |
| avfilter.fftfilt | avfilter.fftfilt | video |
| avfilter.grayworld | avfilter.grayworld | video |
| avfilter.greyedge | avfilter.greyedge | video |
| avfilter.histeq | avfilter.histeq | video |
| avfilter.hsvhold | avfilter.hsvhold | video |
| avfilter.huesaturation | avfilter.huesaturation | video |
| avfilter.limiter | avfilter.limiter | video |
| avfilter.lut3d | avfilter.lut3d | video |
| avfilter.monochrome | avfilter.monochrome | video |
| avfilter.negate | avfilter.negate | video |
| avfilter.normalize | avfilter.normalize | video |
| avfilter.selectivecolor | avfilter.selectivecolor | video |
| avfilter.swapuv | avfilter.swapuv | video |
| avfilter.vibrance | avfilter.vibrance | video |
| brightness | brightness | video |
| chroma_hold | chroma_hold | video |
| frei0r.B | frei0r.B | video |
| frei0r.G | frei0r.G | video |
| frei0r.R | frei0r.R | video |
| frei0r.balanc0r | frei0r.balanc0r | video |
| frei0r.bezier_curves | frei0r.curves | video |
| frei0r.brightness | frei0r.brightness | video |
| frei0r.bw0r | frei0r.bw0r | video |
| frei0r.colgate | frei0r.colgate | video |
| frei0r.coloradj_RGB | frei0r.coloradj_RGB | video |
| frei0r.colorenhance | frei0r.colorenhance | video |
| frei0r.colorize | frei0r.colorize | video |
| frei0r.contrast0r | frei0r.contrast0r | video |
| frei0r.curves | frei0r.curves | video |
| frei0r.equaliz0r | frei0r.equaliz0r | video |
| frei0r.hueshift0r | frei0r.hueshift0r | video |
| frei0r.invert0r | frei0r.invert0r | video |
| frei0r.levels | frei0r.levels | video |
| frei0r.luminance | frei0r.luminance | video |
| frei0r.normaliz0r | frei0r.normaliz0r | video |
| frei0r.saturat0r | frei0r.saturat0r | video |
| frei0r.sopsat | frei0r.sopsat | video |
| frei0r.three_point_balance | frei0r.three_point_balance | video |
| frei0r.tint0r | frei0r.tint0r | video |
| gamma | gamma | video |
| gradientmap | gradientmap | video |
| greyscale | greyscale | video |
| hslprimaries | hslprimaries | video |
| hslrange | hslrange | video |
| invert | invert | video |
| lift_gamma_gain | lift_gamma_gain | video |
| lumaliftgaingamma | lumaliftgaingamma | video |
| sepia | sepia | video |
| tcolor | tcolor | video |

**Deprecated** (16)

| id | mlt_service (tag) | type |
|---|---|---|
| affineshear | affine | video |
| avfilter.dctdnoiz | avfilter.dctdnoiz | video |
| avfilter.delogo | avfilter.delogo | video |
| boxblur | boxblur | video |
| frei0r.IIRblur | frei0r.IIRblur | video |
| frei0r.alpha0ps | frei0r.alpha0ps | video |
| frei0r.alphagrad | frei0r.alphagrad | video |
| frei0r.alphaspot | frei0r.alphaspot | video |
| frei0r.cluster | frei0r.cluster | video |
| frei0r.hqdn3d | frei0r.hqdn3d | video |
| frei0r.medians | frei0r.medians | video |
| frei0r.pr0be | frei0r.pr0be | video |
| frei0r.pr0file | frei0r.pr0file | video |
| frei0r.rgbnoise | frei0r.rgbnoise | video |
| frei0r.sharpness | frei0r.sharpness | video |
| grain | grain | video |

**EQ and Filters** (11)

| id | mlt_service (tag) | type |
|---|---|---|
| avfilter.allpass | avfilter.allpass | audio |
| avfilter.bandpass | avfilter.bandpass | audio |
| avfilter.bandreject | avfilter.bandreject | audio |
| avfilter.bass | avfilter.bass | audio |
| avfilter.equalizer | avfilter.equalizer | audio |
| avfilter.highpass | avfilter.highpass | audio |
| avfilter.highshelf | avfilter.highshelf | audio |
| avfilter.lowpass | avfilter.lowpass | audio |
| avfilter.lowshelf | avfilter.lowshelf | audio |
| sox_band | sox | audio |
| sox_bass | sox | audio |

**GPU Effects** (13)

| id | mlt_service (tag) | type |
|---|---|---|
| movit.blur | movit.blur | video |
| movit.diffusion | movit.diffusion | video |
| movit.flip | movit.flip | video |
| movit.glow | movit.glow | video |
| movit.lift_gamma_gain | movit.lift_gamma_gain | video |
| movit.mirror | movit.mirror | video |
| movit.opacity | movit.opacity | video |
| movit.rect | movit.rect | video |
| movit.saturation | movit.saturation | video |
| movit.sharpen | movit.sharpen | video |
| movit.unsharp_mask | movit.unsharp_mask | video |
| movit.vignette | movit.vignette | video |
| movit.white_balance | movit.white_balance | video |

**Generate** (12)

| id | mlt_service (tag) | type |
|---|---|---|
| avfilter.drawbox | avfilter.drawbox | video |
| avfilter.drawgrid | avfilter.drawgrid | video |
| dropshadow | dropshadow | video |
| dynamictext | dynamictext | video |
| frei0r.cairogradient | frei0r.cairogradient | video |
| frei0r.cairoimagegrid | frei0r.cairoimagegrid | video |
| frei0r.scanline0r | frei0r.scanline0r | video |
| frei0r.vignette | frei0r.vignette | video |
| gpsgraphic | gpsgraphic | video |
| gpstext | gpstext | video |
| timer | timer | video |
| vignette | vignette | video |

**Grain and Noise** (12)

| id | mlt_service (tag) | type |
|---|---|---|
| avfilter.chromanr | avfilter.chromanr | video |
| avfilter.fftdnoiz | avfilter.fftdnoiz | video |
| avfilter.hqdn3d | avfilter.hqdn3d | video |
| avfilter.median | avfilter.median | video |
| avfilter.noise | avfilter.noise | video |
| avfilter.removegrain | avfilter.removegrain | video |
| avfilter.vaguedenoiser | avfilter.vaguedenoiser | video |
| dust | dust | video |
| frei0r.denoise_hqdn3d | frei0r.denoise_hqdn3d | video |
| frei0r.dither | frei0r.dither | video |
| frei0r.filmgrain | frei0r.filmgrain | video |
| lines | lines | video |

**Image Adjustment** (15)

| id | mlt_service (tag) | type |
|---|---|---|
| avfilter.colormatrix | avfilter.colormatrix | video |
| avfilter.colorspace | avfilter.colorspace | video |
| avfilter.deband | avfilter.deband | video |
| avfilter.dilation | avfilter.dilation | video |
| avfilter.epx | avfilter.epx | video |
| avfilter.erosion | avfilter.erosion | video |
| avfilter.fieldorder | avfilter.fieldorder | video |
| avfilter.gradfun | avfilter.gradfun | video |
| avfilter.hqx | avfilter.hqx | video |
| avfilter.il | avfilter.il | video |
| avfilter.kerndeint | avfilter.kerndeint | video |
| avfilter.mcdeint | avfilter.mcdeint | video |
| avfilter.phase | avfilter.phase | video |
| avfilter.setrange | avfilter.setrange | video |
| avfilter.xbr | avfilter.xbr | video |

**MLT LADSPA** (11)

| id | mlt_service (tag) | type |
|---|---|---|
| declipper | ladspa | audio |
| equalizer | ladspa | audio |
| equalizer_15 | ladspa | audio |
| limiter | ladspa | audio |
| phaser | ladspa | audio |
| pitch_scale | ladspa | audio |
| pitch_shift | ladspa | audio |
| rate_scale | ladspa | audio |
| reverb | ladspa | audio |
| room_reverb | ladspa | audio |
| vinyl | ladspa | audio |

**Modulators** (6)

| id | mlt_service (tag) | type |
|---|---|---|
| avfilter.aphaser | avfilter.aphaser | audio |
| avfilter.apulsator | avfilter.apulsator | audio |
| avfilter.flanger | avfilter.flanger | audio |
| avfilter.vibrato | avfilter.vibrato | audio |
| sox_flanger | sox | audio |
| sox_phaser | sox | audio |

**More Checks** (7)

| id | mlt_service (tag) | type |
|---|---|---|
| avfilter.deblock | avfilter.deblock | video |
| avfilter.deflate | avfilter.deflate | video |
| avfilter.derain | avfilter.derain | video |
| avfilter.fspp | avfilter.fspp | video |
| avfilter.inflate | avfilter.inflate | video |
| avfilter.sr | avfilter.sr | video |
| frei0r.delaygrab | frei0r.delaygrab | video |

**Motion** (11)

| id | mlt_service (tag) | type |
|---|---|---|
| avfilter.lagfun | avfilter.lagfun | video |
| avfilter.shufflepixels | avfilter.shufflepixels | video |
| fade_from_black | brightness | video |
| fade_to_black | brightness | video |
| freeze | freeze | video |
| frei0r.baltan | frei0r.baltan | video |
| frei0r.gateweave | frei0r.gateweave | video |
| frei0r.glitch0r | frei0r.glitch0r | video |
| frei0r.nervous | frei0r.nervous | video |
| frei0r.pixs0r | frei0r.pixs0r | video |
| frei0r.vertigo | frei0r.vertigo | video |

**Noise Reduction and Audio Restoration** (1)

| id | mlt_service (tag) | type |
|---|---|---|
| ladspa.9354877 | ladspa.9354877 | audio |

**On Master** (6)

| id | mlt_service (tag) | type |
|---|---|---|
| audiolevelgraph | audiolevelgraph | video |
| audiospectrum | audiospectrum | video |
| audiowave | audiowave | video |
| audiowaveform | audiowaveform | video |
| dance | dance | video |
| lightshow | lightshow | video |

**Pitch and Time** (3)

| id | mlt_service (tag) | type |
|---|---|---|
| rboctaveshift | rbpitch | audio |
| rbpitch | rbpitch | audio |
| sox_stretch | sox | audio |

**Reverb, Echo, and Delays** (2)

| id | mlt_service (tag) | type |
|---|---|---|
| avfilter.compensationdelay | avfilter.compensationdelay | audio |
| sox_echo | sox | audio |

**Stereo and Binaural Images** (7)

| id | mlt_service (tag) | type |
|---|---|---|
| avfilter.bs2b | avfilter.bs2b | audio |
| avfilter.crossfeed | avfilter.crossfeed | audio |
| avfilter.extrastereo | avfilter.extrastereo | audio |
| avfilter.haas | avfilter.haas | audio |
| avfilter.sofalizer | avfilter.sofalizer | audio |
| avfilter.stereotools | avfilter.stereotools | audio |
| avfilter.stereowiden | avfilter.stereowiden | audio |

**Steve Harris' SWH Plugins** (45)

| id | mlt_service (tag) | type |
|---|---|---|
| ladspa.1185 | ladspa.1185 | audio |
| ladspa.1190 | ladspa.1190 | audio |
| ladspa.1191 | ladspa.1191 | audio |
| ladspa.1192 | ladspa.1192 | audio |
| ladspa.1195 | ladspa.1195 | audio |
| ladspa.1196 | ladspa.1196 | audio |
| ladspa.1202 | ladspa.1202 | audio |
| ladspa.1203 | ladspa.1203 | audio |
| ladspa.1207 | ladspa.1207 | audio |
| ladspa.1213 | ladspa.1213 | audio |
| ladspa.1218 | ladspa.1218 | audio |
| ladspa.1219 | ladspa.1219 | audio |
| ladspa.1402 | ladspa.1402 | audio |
| ladspa.1403 | ladspa.1403 | audio |
| ladspa.1404 | ladspa.1404 | audio |
| ladspa.1407 | ladspa.1407 | audio |
| ladspa.1408 | ladspa.1408 | audio |
| ladspa.1410 | ladspa.1410 | audio |
| ladspa.1411 | ladspa.1411 | audio |
| ladspa.1415 | ladspa.1415 | audio |
| ladspa.1423 | ladspa.1423 | audio |
| ladspa.1430 | ladspa.1430 | audio |
| ladspa.1431 | ladspa.1431 | audio |
| ladspa.1432 | ladspa.1432 | audio |
| ladspa.1433 | ladspa.1433 | audio |
| ladspa.1438 | ladspa.1438 | audio |
| ladspa.1886 | ladspa.1886 | audio |
| ladspa.1887 | ladspa.1887 | audio |
| ladspa.1888 | ladspa.1888 | audio |
| ladspa.1889 | ladspa.1889 | audio |
| ladspa.1890 | ladspa.1890 | audio |
| ladspa.1891 | ladspa.1891 | audio |
| ladspa.1892 | ladspa.1892 | audio |
| ladspa.1893 | ladspa.1893 | audio |
| ladspa.1895 | ladspa.1895 | audio |
| ladspa.1896 | ladspa.1896 | audio |
| ladspa.1897 | ladspa.1897 | audio |
| ladspa.1900 | ladspa.1900 | audio |
| ladspa.1901 | ladspa.1901 | audio |
| ladspa.1902 | ladspa.1902 | audio |
| ladspa.1903 | ladspa.1903 | audio |
| ladspa.1904 | ladspa.1904 | audio |
| ladspa.1905 | ladspa.1905 | audio |
| ladspa.1907 | ladspa.1907 | audio |
| ladspa.1913 | ladspa.1913 | audio |

**Stylize** (39)

| id | mlt_service (tag) | type |
|---|---|---|
| BurningTV | BurningTV | video |
| avfilter.chromashift | avfilter.chromashift | video |
| avfilter.edgedetect | avfilter.edgedetect | video |
| avfilter.elbg | avfilter.elbg | video |
| avfilter.kirsch | avfilter.kirsch | video |
| avfilter.photosensitivity | avfilter.photosensitivity | video |
| avfilter.pixelize | avfilter.pixelize | video |
| avfilter.prewitt | avfilter.prewitt | video |
| avfilter.pseudocolor | avfilter.pseudocolor | video |
| avfilter.rgbashift | avfilter.rgbashift | video |
| avfilter.roberts | avfilter.roberts | video |
| avfilter.scharr | avfilter.scharr | video |
| avfilter.sobel | avfilter.sobel | video |
| charcoal | charcoal | video |
| frei0r.aech0r | frei0r.aech0r | video |
| frei0r.cartoon | frei0r.cartoon | video |
| frei0r.colordistance | frei0r.colordistance | video |
| frei0r.colortap | frei0r.colortap | video |
| frei0r.edgeglow | frei0r.edgeglow | video |
| frei0r.emboss | frei0r.emboss | video |
| frei0r.glow | frei0r.glow | video |
| frei0r.heatmap0r | frei0r.heatmap0r | video |
| frei0r.kaleid0sc0pe | frei0r.kaleid0sc0pe | video |
| frei0r.lightgraffiti | frei0r.lightgraffiti | video |
| frei0r.ndvi | frei0r.ndvi | video |
| frei0r.ntsc | frei0r.ntsc | video |
| frei0r.pixeliz0r | frei0r.pixeliz0r | video |
| frei0r.posterize | frei0r.posterize | video |
| frei0r.primaries | frei0r.primaries | video |
| frei0r.rgbsplit0r | frei0r.rgbsplit0r | video |
| frei0r.sigmoidaltransfer | frei0r.sigmoidaltransfer | video |
| frei0r.sobel | frei0r.sobel | video |
| frei0r.softglow | frei0r.softglow | video |
| frei0r.threelay0r | frei0r.threelay0r | video |
| frei0r.threshold0r | frei0r.threshold0r | video |
| frei0r.twolay0r | frei0r.twolay0r | video |
| oldfilm | oldfilm | video |
| threshold | threshold | video |
| typewriter | typewriter | text |

**TAP Plugins** (19)

| id | mlt_service (tag) | type |
|---|---|---|
| ladspa.2141 | ladspa.2141 | audio |
| ladspa.2142 | ladspa.2142 | audio |
| ladspa.2143 | ladspa.2143 | audio |
| ladspa.2144 | ladspa.2144 | audio |
| ladspa.2145 | ladspa.2145 | audio |
| ladspa.2146 | ladspa.2146 | audio |
| ladspa.2147 | ladspa.2147 | audio |
| ladspa.2148 | ladspa.2148 | audio |
| ladspa.2149 | ladspa.2149 | audio |
| ladspa.2150 | ladspa.2150 | audio |
| ladspa.2151 | ladspa.2151 | audio |
| ladspa.2152 | ladspa.2152 | audio |
| ladspa.2153 | ladspa.2153 | audio |
| ladspa.2154 | ladspa.2154 | audio |
| ladspa.2155 | ladspa.2155 | audio |
| ladspa.2156 | ladspa.2156 | audio |
| ladspa.2157 | ladspa.2157 | audio |
| ladspa.2158 | ladspa.2158 | audio |
| ladspa.2159 | ladspa.2159 | audio |

**To be completed** (9)

| id | mlt_service (tag) | type |
|---|---|---|
| avfilter.atadenoise | avfilter.atadenoise | video |
| avfilter.bwdif | avfilter.bwdif | video |
| avfilter.dedot | avfilter.dedot | video |
| avfilter.doubleweave | avfilter.doubleweave | video |
| avfilter.random | avfilter.random | video |
| avfilter.tmix | avfilter.tmix | video |
| avfilter.w3fdif | avfilter.w3fdif | video |
| avfilter.weave | avfilter.weave | video |
| avfilter.yadif | avfilter.yadif | video |

**Tools** (3)

| id | mlt_service (tag) | type |
|---|---|---|
| avfilter.acrusher | avfilter.acrusher | audio |
| avfilter.crystalizer | avfilter.crystalizer | audio |
| avfilter.dcshift | avfilter.dcshift | audio |

**Transform, Distort, and Perspective** (29)

| id | mlt_service (tag) | type |
|---|---|---|
| 3wayrotate | affine | video |
| affine | affine | video |
| affinerotate | affine | video |
| avfilter.fillborders | avfilter.fillborders | video |
| avfilter.hflip | avfilter.hflip | video |
| avfilter.lenscorrection | avfilter.lenscorrection | video |
| avfilter.scroll | avfilter.scroll | video |
| avfilter.shear | avfilter.shear | video |
| avfilter.transpose | avfilter.transpose | video |
| avfilter.vflip | avfilter.vflip | video |
| avfilter.zoompan | avfilter.zoompan | video |
| crop | crop | video |
| frei0r.3dflippo | frei0r.3dflippo | video |
| frei0r.c0rners | frei0r.c0rners | video |
| frei0r.defish0r | frei0r.defish0r | video |
| frei0r.distort0r | frei0r.distort0r | video |
| frei0r.elastic_scale | frei0r.elastic_scale | video |
| frei0r.flippo | frei0r.flippo | video |
| frei0r.lenscorrection | frei0r.lenscorrection | video |
| frei0r.letterb0xed | frei0r.letterb0xed | video |
| frei0r.mirr0r | frei0r.mirr0r | video |
| frei0r.nosync0r | frei0r.nosync0r | video |
| frei0r.scale0tilt | frei0r.scale0tilt | video |
| mirror | mirror | video |
| pan_zoom | affine | video |
| pillar_echo | pillar_echo | video |
| qtblend | qtblend | video |
| qtcrop | qtcrop | video |
| wave | wave | video |

**Utilities** (13)

| id | mlt_service (tag) | type |
|---|---|---|
| avfilter.ciescope | avfilter.ciescope | video |
| avfilter.datascope | avfilter.datascope | video |
| avfilter.field | avfilter.field | video |
| avfilter.histogram | avfilter.histogram | video |
| avfilter.oscilloscope | avfilter.oscilloscope | video |
| avfilter.vectorscope | avfilter.vectorscope | video |
| avfilter.waveform | avfilter.waveform | video |
| frei0r.d90stairsteppingfix | frei0r.d90stairsteppingfix | video |
| frei0r.measure_pr0be | frei0r.measure_pr0be | video |
| frei0r.measure_pr0file | frei0r.measure_pr0file | video |
| frei0r.rgbparade | frei0r.rgbparade | video |
| frei0r.timeout | frei0r.timeout | video |
| frei0r.vectorscope | frei0r.vectorscope | video |

**VR360 and 3D** (10)

| id | mlt_service (tag) | type |
|---|---|---|
| avfilter.stereo3d | avfilter.stereo3d | video |
| frei0r.bigsh0t_eq_cap | frei0r.bigsh0t_eq_cap | video |
| frei0r.bigsh0t_eq_mask | frei0r.bigsh0t_eq_mask | video |
| frei0r.bigsh0t_eq_to_rect | frei0r.bigsh0t_eq_to_rect | video |
| frei0r.bigsh0t_eq_to_stereo | frei0r.bigsh0t_eq_to_stereo | video |
| frei0r.bigsh0t_eq_wrap | frei0r.bigsh0t_eq_wrap | video |
| frei0r.bigsh0t_hemi_to_eq | frei0r.bigsh0t_hemi_to_eq | video |
| frei0r.bigsh0t_rect_to_eq | frei0r.bigsh0t_rect_to_eq | video |
| frei0r.bigsh0t_stabilize_360 | frei0r.bigsh0t_stabilize_360 | video |
| frei0r.bigsh0t_transform_360 | frei0r.bigsh0t_transform_360 | video |

**Volume and Dynamics** (13)

| id | mlt_service (tag) | type |
|---|---|---|
| avfilter.acontrast | avfilter.acontrast | audio |
| avfilter.alimiter | avfilter.alimiter | audio |
| avfilter.compand | avfilter.compand | audio |
| avfilter.deesser | avfilter.deesser | audio |
| dynamic_loudness | dynamic_loudness | audio |
| fadein | volume | audio |
| fadeout | volume | audio |
| gain | volume | audio |
| loudness | loudness | audio |
| mute | volume | audio |
| normalise | volume | audio |
| sox_gain | sox | audio |
| volume | volume | audio |


Notes: audio effect ids with `type=audio` apply only to audio tracks/audio clips; `type=hidden` ids are internal (audiolevel, luma, mask_start, sox, sox_pitch, sox_reverb, vidstab, avfilter.subtitles). `data/effects/templates/` holds three effect groups (`secondary_color_correction`, `secondary_color_correction_v2`, `shut_off`) stored as `<effectgroup>`; a group is saved as its member filters. `data/excluded_effects.txt` (309 lines) lists MLT services that Kdenlive hides; `data/preferred_effects.txt` lists UI favourites. Kdenlive also lists MLT filters that have no XML in `data/effects` (generic auto UI) except excluded ones; they use `kdenlive_id` = MLT service name.

---
## 6. Compositions (transitions between tracks)

### 6.1 Storage (V: meltBuilder.cpp:268-345, compositionmodel.cpp:24-62, transitionsrepository.cpp:189-198)
A composition is a `<transition>` child of the **sequence tractor** with `in`/`out` (clock, out inclusive) = the time span, `a_track` = MLT index of the lower track, `b_track` = MLT index of the upper track (0 = black, tracks numbered as in 2.4), `mlt_service` = the transition tag, `kdenlive_id` = the transition id, plus its parameters; **no `internal_added`** and no `kdenlive:mixcut`. `force_track`=1 makes a_track authoritative: without it Kdenlive treats the composition as automatic and requires `a_track` = the MLT index of the video track directly below `b_track` (or 0 for the lowest video track); otherwise it sets `force_track=1` and shows a repair dialog (meltBuilder.cpp:300-315). Always write `force_track` yourself (`1`) when a_track is not the immediate lower video track. Unknown `kdenlive_id` -> dialog + composition removed. If `kdenlive_id` is empty the loader copies `mlt_service` into it (meltBuilder.cpp:284-288).
```xml
<transition id="transition3" in="00:00:01.000" out="00:00:02.000">
  <property name="a_track">2</property>
  <property name="b_track">3</property>
  <property name="mlt_service">luma</property>
  <property name="kdenlive_id">dissolve</property>
  <property name="resource"/>
  <property name="softness">0</property>
  <property name="reverse">0</property>
  <property name="alpha_over">0</property>
  <property name="fix_background_alpha">1</property>
  <property name="force_track">1</property>
</transition>
```
(shape P: parameters from `data/transitions/dissolve.xml`; the same-track variant is real, section 8.)
Picture-in-picture with `composite`/`affine`/`qtblend`:
```xml
<transition id="transition4" in="00:00:00.000" out="00:00:04.000">
  <property name="a_track">2</property>
  <property name="b_track">3</property>
  <property name="mlt_service">qtblend</property>
  <property name="kdenlive_id">qtblend</property>
  <property name="rect">00:00:00.000=540 960 480 853 1</property>
  <property name="rotation">0</property>
  <property name="compositing">0</property>
  <property name="distort">0</property>
  <property name="rotate_center">1</property>
  <property name="force_track">1</property>
</transition>
```
For `composite`: `geometry` (animated rect with opacity 0-100, default `0 0 %width %height 100`), `distort`, `aligned`, `halign`, `valign`, `luma`, `softness`, `progressive`. For `affine`: `rect`, `rotate_x/y/z`, `distort`, `keyed`=1, `transition.repeat_off`, `transition.mirror_off`.
Compositions lie on the track of `b_track` and belong to it for editing; they are also valid group leaves (`"leaf":"composition"`, track position:start frame).

### 6.2 All composition ids in `data/transitions` (v26.08.3)
| id | mlt_service (tag) | xml type attr | parameters (name type default) |
|---|---|---|---|
| affine | affine | - | rect animatedrect `0 0 %width %height 1`; rotate_x/y/z keyframe 0; distort bool 0; keyed fixed 1; transition.repeat_off 1; transition.mirror_off 1 |
| composite | composite | - | geometry animatedrect `0 0 %width %height 100`; distort 0; crop_to_fill 0; aligned 1; halign list 1; valign list 1; luma urllist; softness double 0; progressive 1 |
| dissolve | luma | videotransition (same-track mix) | resource urllist; softness 0; reverse 0; alpha_over 0; fix_background_alpha 1 |
| luma | luma | - (single-track) | resource urllist (wipe image: `%lumaPaths`, `.pgm`/`.png`); softness 0; alpha_over 0; fix_background_alpha 1; invert 0; reverse 0 |
| matte | matte | - | none |
| mix | mix | audiotransition (hidden in UI) | reverse bool 0 |
| qtblend | qtblend | - | rect animatedrect `0 0 %width %height 1`; rotation keyframe 0; compositing list 0; distort 0; rotate_center 1 |
| region | region | - | resource url; composite.geometry animatedrect; composite.operator list `over`; composite.aligned 1; composite.fill 1; composite.distort 0; composite.luma; composite.softness 0; luma_invert 0; composite.progressive 1; composite.deinterlace 0 |
| slide | affine | videotransition | rect wipe `0=-100% 0% 100% 100% 100%;-1=0% 0% 100% 100% 100%` |
| vqm | vqm | - | render bool 0 |
| wipe | composite | short | luma urllist; softness 0; luma_invert 0; geometry switch `0=0% 0% 100% 100% 0%;-1=0% 0% 100% 100% 100%` |

Plus the MLT-native ids listed in `data/included_transitions.txt`: `frei0r.addition, frei0r.addition_alpha, frei0r.alphaatop, frei0r.alphain, frei0r.alphaout, frei0r.alphaover, frei0r.alphaxor, frei0r.burn, frei0r.cairoaffineblend, frei0r.cairoblend, frei0r.color_only, frei0r.darken, frei0r.difference, frei0r.divide, frei0r.dodge, frei0r.grain_extract, frei0r.grain_merge, frei0r.hardlight, frei0r.hue, frei0r.lighten, frei0r.multiply, frei0r.overlay, frei0r.saturation, frei0r.screen, frei0r.sleid0r_push-{down,left,right,up}, frei0r.sleid0r_slide-{down,left,right,up}, frei0r.sleid0r_wipe-{barn-door-h,barn-door-v,circle,down,left,rect,right,up}, frei0r.softlight, frei0r.subtract, frei0r.uvmap, frei0r.value` (id = MLT service name). Excluded (`excluded_transitions.txt`): frei0r.composition, frei0r.alphainjection, frei0r.blend, frei0r.xfade0r, webvfx. `luma` ids whose `resource` points to a file are checked (missing -> dialog) except MLT built-in luma names (documentchecker.cpp:480-530); an empty `resource` is fine (MLT 7 generates a linear luma).

---
## 7. Same-track mixes (crossfades between adjacent clips)

### 7.1 Arrangement (V: T/test-mix lines 169-252; trackmodel.cpp:1850-2150, 2662-2740)
Within one track tractor, the second clip of a mix sits on the **other playlist** (playlist 1, or playlist 0 when the first clip was moved there), overlapping the first clip in time, and a `<transition>` is placed in the **track tractor** (not the sequence) with `a_track`/`b_track` in {0,1} = playlist indices:
```xml
<playlist id="playlist4">
  <blank length="00:00:05.080"/>
  <entry producer="producer0" in="00:00:00.000" out="00:00:05.440"> <property name="kdenlive:id">2</property> </entry>
  <blank length="00:00:04.000"/>
  <entry producer="producer0" in="00:00:00.000" out="00:00:03.960"> <property name="kdenlive:id">2</property> </entry>
</playlist>
<playlist id="playlist5">
  <blank length="00:00:05.080"/>
  <entry producer="producer1" in="00:00:00.000" out="00:00:13.440"> <property name="kdenlive:id">3</property> </entry>
</playlist>
<tractor id="tractor2" in="00:00:00.000" out="00:00:18.520">
  ...
  <track hide="audio" producer="playlist4"/>
  <track hide="audio" producer="playlist5"/>
  <transition id="transition1" in="00:00:14.560" out="00:00:18.560">
    <property name="a_track">0</property>
    <property name="b_track">1</property>
    <property name="factory">loader</property>
    <property name="resource"/>
    <property name="mlt_service">luma</property>
    <property name="kdenlive_id">luma</property>
    <property name="kdenlive:mixcut">87</property>
    <property name="reverse">1</property>
    <property name="softness">0</property>
    <property name="alpha_over">1</property>
    <property name="invert">0</property>
  </transition>
  <transition id="transition0" in="00:00:05.080" out="00:00:10.560">
    <property name="a_track">0</property>
    <property name="b_track">1</property>
    <property name="factory">loader</property>
    <property name="resource"/>
    <property name="mlt_service">luma</property>
    <property name="kdenlive_id">luma</property>
    <property name="kdenlive:mixcut">12</property>
    <property name="softness">0</property>
    <property name="alpha_over">1</property>
    <property name="invert">0</property>
    <property name="reverse">0</property>
  </transition>
</tractor>
```
Rules (V from loadMix, trackmodel.cpp:2662-2740, plantMix timelinemodel.cpp:7824):
- Mix region: `in` = start frame of the later-starting clip (it must be the start of an entry, else the mix is deleted: `hasClipStart(in)` check), `out` = end of the earlier-ending clip (exclusive end; Kdenlive re-sets in/out from the clips if they disagree, trackmodel.cpp:2700-2706). Clips A (earlier) and B (later) must satisfy `startA <= startB` and `endA <= endB` else "impossible mix, removed".
- `reverse=1` means the earlier clip is on playlist 1 and the later on playlist 0 (a_track 0/b_track 1 are kept; direction is expressed by `reverse`, trackmodel.cpp:2666-2670). If both clips are on playlists and `reverse` does not match, Kdenlive retries the opposite and otherwise deletes the mix.
- Video mix: `mlt_service=luma`, `kdenlive_id=luma` (or `dissolve`), `kdenlive:mixcut`. Created fresh by Kdenlive with `set_tracks(0,1)`/(1,0) (trackmodel.cpp:2126-2140, 2395-2410). Audio mix: `mlt_service=mix`, `kdenlive_id=mix`, `start=-1`, `accepts_blanks=1`, `kdenlive:mixcut`, `reverse` when needed (trackmodel.cpp:2098-2112).
- `kdenlive:mixcut` = cut offset (frames) inside the mix used for the UI snap marker; clamped to the mix duration, `0` is safe (trackmodel.cpp:2737; `ClipModel::setMixDuration` only uses it when > 0). P for exact semantics.
- Clip on playlist 1 without a mix is "incorrect subtrack": Kdenlive moves/trims it and shows a repair dialog (meltBuilder.cpp:880-975). Do not leave clips on the second playlist without a transition.
- Mix parameters (softness, `resource` wipe, `alpha_over`...) are the `luma`/`dissolve` transition parameters (section 6.2).
- Track tractor `in/out` must cover everything (V, gotcha 6).

---
## 8. Guides and subtitles

### 8.1 Guides (timeline markers) (V)
Sequence property `kdenlive:sequenceproperties.guides` = JSON array identical to clip markers:
```xml
<property name="kdenlive:sequenceproperties.guides">[
    {
        "comment": "Intro",
        "duration": 0,
        "pos": 0,
        "type": 0
    },
    {
        "comment": "Chapter 2",
        "duration": 90,
        "pos": 300,
        "type": 2
    }
]
</property>
```
`pos` frames (timeline), `duration` frames (0 = point guide, >0 = range), `type` = category index. Writer `MarkerListModel::toJson` (markerlistmodel.cpp:1025-1046), reader `importFromJson` (:886-950; missing `pos` skips the entry; unknown `type` is mapped `type % 9` and a "Recovered N" category is created). Categories: `kdenlive:docproperties.guidesCategories` = JSON `[{"color":"#9b59b6","comment":"Category 1","index":0}, ... ]` (9 defaults: `#9b59b6 #3daee9 #1abc9c #1cdc9a #c9ce3b #fdbc4b #f39c1f #f47750 #da4453`, kdenlivedoc.cpp:2980-2991; exact text in PROBA-K). Guides are loaded once and the property removed from the in-memory map (kdenlivedoc.cpp:2490-2500). Guide positions are not rescaled when the fps differs.

### 8.2 Subtitles (V for mechanism; P for filter bytes)
- Storage on disk: an **.ass** file next to the project file. Name = `<project file name>.ass` for the main sequence index 0 (e.g. `proba.kdenlive.ass`); `<project file name><sequence uuid>.ass` for other sequences; extra subtitle tracks append `-<index>` (`KdenliveDoc::subTitlePath`, kdenlivedoc.cpp:2649-2670, `final=true`). While editing Kdenlive works on a temp copy `<tmp>/<documentid>-<sessionid>.ass` and copies it next to the project on save (`updateWorkFilesBeforeSave`, kdenlivedoc.cpp:1031-1056). On load it copies the sidecar to the work path (subtitlemodel.cpp:45-75).
- Index: sequence property `kdenlive:sequenceproperties.subtitlesList` = JSON `[{"file":"proba.kdenlive.ass","id":0,"name":"Subtitles"}]` (`subtitlesFilesToJson`, subtitlemodel.cpp:1975-1990; reader `KdenliveDoc::JSonToSubtitleList`, kdenlivedoc.cpp:2712-2740: entries need `name` and `file`; relative `file` is prefixed with root). `kdenlive:sequenceproperties.activeSubtitleIndex` = active id. `kdenlive:sequenceproperties.globalSubtitleStyles` = JSON `[{"style":"Style: Default,..."}]`.
- Burn-in filter on the **sequence tractor** (created when subtitles exist, `SubtitleModel` ctor subtitlemodel.cpp:32-36 and `jsontoSubtitle` :1241-1253): `mlt_service=avfilter.subtitles`, `av.filename` = path of the .ass, `av.alpha`=1, `internal_added`=237; also `disable`, `kdenlive:locked`, `av.force_style` optional. On load only `disable`, `kdenlive:locked`, `av.force_style` are read from it; the file is found through `subtitlesList` (effectstackmodel.cpp:1497-1514). In the saved file `av.filename` points to the final sidecar path. Example (P):
```xml
<filter id="filter9">
  <property name="av.filename">C:/.../proba.kdenlive.ass</property>
  <property name="mlt_service">avfilter.subtitles</property>
  <property name="internal_added">237</property>
  <property name="av.alpha">1</property>
  <property name="disable">0</property>
</filter>
```
- .ass content written by Kdenlive (documentvalidator.cpp:2200-2225, definitions.cpp:250-270, 406-440):
```
[Script Info]
; Script generated by Kdenlive 26.08.3
ScriptType: v4.00+
PlayResX: 1080
PlayResY: 1920
LayoutResX: 1080
LayoutResY: 1920
WrapStyle: 0
ScaledBorderAndShadow: yes
YCbCr Matrix: None

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,...

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:01.00,0:00:03.00,Default,,0,0,0,,Hello
```
- `.srt` sidecars are converted to `.ass` on open if `subtitlesList` points to `.srt` (documentvalidator.cpp:1972-2262) and may ask to overwrite an existing `.ass` (modal). Always provide `.ass`.
- Render: with "embed subtitles" Kdenlive disables the filter (`disable=1`) and muxes a temp `.srt` with ffmpeg afterwards (renderrequest.cpp:182-240, renderer/renderjob.cpp:334); otherwise the filter burns them in.

---
## 9. Rendering

### 9.1 What Kdenlive does (V)
1. `RenderRequest::process` (`src/render/renderrequest.cpp:129-250`) writes the project scene list (same XML as a save, `time_format=clock`, `store=kdenlive`, `projectitemmodel.cpp:1740-1830`) to a temp `kdenlive-XXXXXX.mlt`, sets `autoclose=1` on the playlists of the main sequence (kdenlivedoc.cpp:2828-2860), optionally swaps proxies for originals, disables the subtitle filter, makes the black track transparent for alpha formats, then inserts a `<consumer>` element after `<profile>` (`setDocGeneralParams`, renderrequest.cpp:393-420):
```xml
<consumer in="0" out="249" mlt_service="avformat" rescale="bilinear" deinterlacer="onefield" f="mp4" movflags="+faststart" vcodec="libx264" crf="23" g="15" preset="veryfast" acodec="aac" ab="160k" target="C:/out/final.mp4"/>
```
(`in`/`out` = zone/render range in frames; preset params are copied attribute by attribute; `rescale`/`deinterlacer` come from settings.) 2-pass adds `pass`, `passlogfile`, `fastfirstpass` (renderrequest.cpp:432-460).
2. It runs `kdenlive_render delivery <path-to-melt> <playlist.mlt> --pid <kdenlive-pid> [--subtitle <srt>]` (`argsByJob`, renderrequest.cpp:26-38). `kdenlive_render` reads the `<consumer>` element for in/out/target, sets `MLT_NO_VDPAU=1` and starts **`melt -loglevel error -progress2 <playlist.mlt>`** (`renderer/renderjob.cpp:42-53`, kdenlive_render.cpp:170-260). melt runs the in-file consumer because the document has a `<consumer>` element (melt-verified: a copy of PROBA-K with the consumer above rendered 30 frames h264 + aac).
3. Presets: `export/profiles.xml` (shipped in `<install>/bin/data/kdenlive/export/profiles.xml`, i.e. `AppDataLocation/export/profiles.xml`) and the user's `AppLocalDataLocation/export/customprofiles.xml`, plus MLT avformat presets under `share/mlt/presets/consumer/avformat/` (`renderpresetrepository.cpp:97-120, 270, 355, 455`). Preset `MP4-H264/AAC` (profiles.xml lines 9-13): `f=mp4 movflags=+faststart vcodec=libx264 crf=%quality g=15 acodec=aac ab=%audiobitrate+'k'`; defaults quality 23 (range 15-45), audio bitrate 160k, speed list `preset=veryslow;slower;slow;medium;fast;faster;veryfast;superfast;ultrafast` with default index 6 = `veryfast`. Placeholders are replaced in `RenderRequest::loadPresetParams` (renderrequest.cpp:56-80).

### 9.2 Exact melt command lines (V: run on this machine, melt 7.43.0)
Render the whole project at the project profile (profile comes from the file's `<profile>`):
```
melt.exe "<project>.kdenlive" -silent -consumer avformat:"<out>.mp4" f=mp4 movflags=+faststart vcodec=libx264 crf=23 g=15 preset=veryfast acodec=aac ab=160k
```
Render a zone (frames, inclusive, relative to the project start): put `in=<first> out=<last>` right after the project path:
```
melt.exe "<project>.kdenlive" in=30 out=59 -consumer avformat:"<out>.mp4" f=mp4 movflags=+faststart vcodec=libx264 crf=23 g=15 preset=ultrafast acodec=aac ab=160k
```
(ran: 30 frames, h264 1080x1920 30 fps + aac). Run from any directory (the file's `root` makes `resource` paths resolve); on Windows pass `C:/...` style paths. Kdenlive-style equivalent: insert the `<consumer ... in= out= target=>` element (9.1) and run `melt <file>`. Single still frame: `-consumer avformat:frame-%05d.png vcodec=png` with `in=N out=N` (the existing skill does this). The `libmltsox.dll` dlopen warning printed by this bundle is harmless. Use `-silent` to suppress the interactive key help, `-progress2` for percent lines on stderr.
The H.264 MP4 preset shipped with MLT (`share/mlt/presets/consumer/avformat/x264-medium`) is: `f=mp4 acodec=aac ab=256k vcodec=libx264 threads=0 preset=medium vprofile=high crf=18 movflags=+faststart` (use `-consumer avformat:out.mp4 properties=x264-medium` as an alternative).
Render only guides ranges: Kdenlive splits the range at guides of a chosen category (`getGuideSections`, renderrequest.cpp:470+) producing one consumer per section - emulate with several melt runs.

---
## 10. What Kdenlive recomputes on load, and what it rejects

Recomputed / repaired silently (V):
- Bin ids (renumbered), `kdenlive:folderid` for lost folders (-> root), sequence `kdenlive:clip_type`, audio info, thumbnails, `kdenlive:file_size`/`file_hash` if missing (`ProjectClip::getFileHash`), `meta.media.*` probes for new clips, effect fade ranges, internal transitions and mixer filters (2.4/2.5), track `thumbs_format`, tractor `out` values, group membership, guide snaps, `seekOffset`.
- `DocumentChecker` (documentchecker.cpp:192-520): adds `control_uuid` to bin producers/tractors lacking it, matches timeline producers by kdenlive:id+resource/hash, adds `main_bin` entries for timeline producers with unknown `kdenlive:id` (item MissingBinClip -> dialog), recovers an empty `documentid` (new timestamp, modified), renames old effect ids (`frei0r.alpha0ps` -> `frei0r.alpha0ps_alpha0ps`, etc., line 274-276), replaces unknown effects that share an MLT tag with a known effect id, replaces `http` resources (dialog), fixes moved projects (relocates paths under old `root` when `root` no longer exists, lines 60-95).
- `DocumentValidator` (documentvalidator.cpp:40-175): sets empty `root`, removes `mute_on_pause` for old MLT, runs the version upgrade chain (all changes flag the doc modified), converts subtitles.
Rejected / errors (V):
- Not an `<mlt>` document or no `main_bin` playlist -> "not a Kdenlive project file" / "not valid" (kdenlivedoc.cpp:226-246, loadDocumentProperties returns false when `main_bin` missing).
- `kdenlive:docproperties.version` > 1.1 -> modal "project unsupported" (documentvalidator.cpp:216-226). Versions 0.5/0.7 unsupported.
- Track tractor with count != 2 sub-tracks -> timeline load fails (meltBuilder.cpp:630-636).
- Sequence referencing itself -> dropped.
- Duplicate sequence uuid in bin -> assertion/"invalid sequence clip" dialog (projectitemmodel.cpp:1470-1480, meltBuilder.cpp:60-67).
- Project profile with non-standard fps -> modal error.
Avoid-modal checklist: (a) version 1.1 / patchversion 1; (b) `control_uuid` on every bin producer, chain, sequence tractor and every timeline producer copy (same value as the bin clip); (c) numeric `documentid`; (d) all media paths exist (relative to `root`) or are absolute; `file_hash` absent or exact; (e) title fonts installed; (f) every `kdenlive_id` in the effect and transition tables; (g) no clip on playlist 1 without a mix; compositions with correct a_track or `force_track=1`; (h) no `storagefolder`, no `proxyparams`; (i) no leftover `<md5>` autosave next to the project; (j) subtitles as `.ass`; (k) clean first-save: no `modified`/`upgraded` triggers, otherwise a one-time info box + `_backupN.kdenlive` appears at the first save.

---
## 11. Verification log (this session)

| Claim | How verified |
|---|---|
| melt plays the project tractor, ignores `producer="main_bin"` | `melt proba.kdenlive -consumer xml:` root = project tractor |
| In-file `<consumer>` renders with plain `melt file` | copy of PROBA-K + consumer, 30 frames h264/aac |
| `in= out=` zone render | `melt proba.kdenlive in=30 out=59 -consumer avformat:zone.mp4 ...`: ffprobe h264 1080x1920 30/1, aac |
| Title xmldata, fade_to_black, qtblend rect keyframes, timewarp x2 in a 1.1-shaped project | mini project rendered at frames 40/70/100/175; timewarp frame 100 -> source frame 20 |
| file hash algorithm | md5sum of card-1.png equals `kdenlive:file_hash` in PROBA-K; size 23750 equals `file_size` |
| track tractor needs `out` | first title test: tractor2 had no usable `out` -> title missing |
| Not verified | Kdenlive-side load of any hand-written file (Kdenlive not run); freeze-frame clip; time remap link bytes; slideshow/animation/playlist saved shapes; `mixcut` semantics beyond clamp |

---
## 12. Additional features (sequences, slideshow, animation, time remap, render presets)

Evidence tags as in section 0. `T/test-nesting` = tests/dataset/test-nesting.kdenlive. Everything marked "melt-verified" was rendered by the bundled melt 7.43.0 from scratch files. **Kdenlive itself was not run**: "Kdenlive accepts it without a dialog" below is a source-reading conclusion (P), never an observation. Sources were read at tag v26.08.3 (paths relative to the repo root; `timeremap.cpp` = `src/dialogs/timeremap.cpp`, `slideshowclip.cpp` = `src/project/dialogs/slideshowclip.cpp`).

### 12.1 Additional sequences (nested timelines)

**Model (V).** A sequence is a `<tractor id="{uuid}">` carrying `kdenlive:uuid`, `kdenlive:producer_type=17`, `kdenlive:id`, `kdenlive:control_uuid` and its own `kdenlive:sequenceproperties.*` (section 2.5). Every sequence has its own black producer (`kdenlive:playlistid=black_track`, track index 0), its own track tractors and its own internal `mix`/`qtblend` transitions (T/test-nesting lines 129-223, 325-432, 534-640: three sequences, each with its own black `producerN` and `transition*`). The loader skips the black track and internal transitions of every sequence and rebuilds them (gotcha 8), but melt needs them (they composite that sequence), so write them for B exactly as for A.

**Bin entry (V).** One `<entry producer="{uuid}" in= out=>` per sequence in `main_bin` (T/test-nesting 722-724 write `out="00:00:00.000"`, PROBA-K writes the real length; both load). All sequences carry the same `kdenlive:sequenceproperties.documentuuid` = the **project** uuid (`kdenlive:docproperties.uuid`) (T/test-nesting lines 136, 337, 546). The tractor is found by `kdenlive:uuid` (`projectitemmodel.cpp:1470-1500`); a duplicate uuid triggers an assertion / "invalid sequence clip" dialog (`projectitemmodel.cpp:1488-1491`, `meltBuilder.cpp:60-67`). Bin ids (`kdenlive:id`) of clips, sequences and folders share one counter and must be unique.

**Which sequence is main (V).** The project tractor's single `<track producer="{A-uuid}">` and `kdenlive:docproperties.uuid` name the main sequence. `kdenlive:docproperties.opensequences` (`;`-separated uuids = tabs opened) and `kdenlive:docproperties.activetimeline` (tab raised on load) are read at `projectmanager.cpp:1026-1066`; a null `activetimeline` falls back to the project uuid (1033-1036); a new project writes both = project uuid (`projectmanager.cpp:388-389`). T/test-nesting lists all three sequences in `opensequences` and activates the first. A sequence not listed in `opensequences` still loads (all sequence models are built from the bin, `projectmanager.cpp:1060+`).

**Folder (V).** `<property name="kdenlive:folder.-1.<id>">Sequences</property>` + `<property name="kdenlive:sequenceFolder"><id></property>` on `main_bin`, and `kdenlive:folderid=<id>` on the sequence tractors (PROBA-K: id 5; the id is mapped through `binIdCorresp` and ignored when the folder does not exist, `projectitemmodel.cpp:1427-1433`). T/test-nesting writes `sequenceFolder=-1` and `folderid=-1` (sequences at root); both load. The folder is UI only (clips added through the UI into the sequences folder are redirected to root, `projectitemmodel.cpp:1042`).

**Using sequence B as a clip on A's V1 (V source, melt-verified).**
- The timeline entry references the **sequence tractor id directly**: `<entry producer="{B-uuid}" in= out=>` in a playlist of A's track tractor (T/test-nesting 266-269, 302-305, 475-478). There is NO per-instance producer copy: "Timeline clips always use the master instance" (`projectclip.cpp:1278-1279`); `getTimelineProducer` for `ClipType::Timeline` returns a cut of the master (`projectclip.cpp:978-1000`).
- Entry properties: `kdenlive:id` = B's bin id, `kdenlive:maxduration` = B's length in frames (T/test-nesting `125` = 5 s at 25 fps). `getTimelineProducer` reads `kdenlive:maxduration` from the sequence producer and sets it on the cut (`projectclip.cpp:978-1000`); that it is used as trim limit of the timeline clip is P. Entry `in`/`out` = used part, out inclusive: full length = `out = maxduration-1` frames (`out="00:00:04.960"` for 125 frames at 25 fps).
- control_uuid rule: the loader maps a timeline clip to its bin clip via `clip->parent().get("kdenlive:control_uuid")` (`meltBuilder.cpp:777-830`). For a sequence the "parent" is the sequence tractor itself, so **the sequence tractor must carry `kdenlive:control_uuid` = its own uuid** (PROBA-K does; T/test-nesting predates it, DocumentChecker then generates one and marks the document modified, `documentchecker.cpp:372-392`). The loader also requires the tractor's `kdenlive:producer_type` (17) to equal the bin clip's (`meltBuilder.cpp:811-813`; otherwise the clip is dropped with "Sequence clip not found").
- A sequence embedded in itself is dropped by the loader (`meltBuilder.cpp:799-808`); DocumentChecker removes a `<track>` that references its own tractor (`documentchecker.cpp:443-475`). Do not create A->B->A cycles (not checked beyond that: P).
- File order: **B's tracks and tractor must be defined before A's playlist that references it** (MLT resolves only already-defined ids). T/test-nesting: Sequence 1 {dd00..} is first, Sequence 2 {9228..} (which embeds 1) after it.
- Audio: for a sequence with `hasAudio=1` Kdenlive also places a second entry of the same `{uuid}` on an audio track at the same position, joined by an `AVSplit` group (T/test-nesting: `groups` with `AVSplit` at lines 346-362 and 555-571, audio entry on `tractor5`, video entry on `tractor6`; entry format as 4.2). Video-only use = one entry, no group. The file below declares B as `hasAudio=0` / `clip_type=2` (video-only sequence) so no audio entry is needed; Kdenlive's reaction to hasAudio=0 sequences is P (source: `clipcontroller.cpp:870-893` derives `clip_type` from hasAudio/hasVideo).

**Minimal complete project: sequence A (main) + sequence B, B used on A's V1** (melt-verified: frame 10 = blue clip, frame 50 = red = B's content; Kdenlive load not run). UI-only properties were removed (`kdenlive:trackheight/timeline_active/collapsed/thumbs_format/audio_rec`, `sequenceproperties.zoom/scrollPos/position/disablepreview`, `kdenlive:file_size`, `kdenlive:clipname`, `aspect_ratio`, `seekable`); a variant with all of them also rendered the same. Add `kdenlive:clipname` to name a sequence in the bin. All uuids are placeholders (use real uuid4s). Bin ids: 2 red clip, 3 blue clip, 4 = A, 5 = B, 6 = Sequences folder.
```xml
<?xml version='1.0' encoding='utf-8'?>
<mlt LC_NUMERIC="C" producer="main_bin" root="C:/proj" version="7.43.0">
 <profile colorspace="709" description="HD 720p 30 fps" display_aspect_den="9" display_aspect_num="16" frame_rate_den="1" frame_rate_num="30" height="720" progressive="1" sample_aspect_den="1" sample_aspect_num="1" width="1280"/>
 <producer id="producer0" in="00:00:00.000" out="00:00:01.967">
  <property name="length">00:00:02.000</property>
  <property name="eof">pause</property>
  <property name="resource">0xff0000ff</property>
  <property name="mlt_service">color</property>
  <property name="kdenlive:duration">00:00:02.000</property>
  <property name="kdenlive:folderid">-1</property>
  <property name="kdenlive:id">2</property>
  <property name="kdenlive:control_uuid">{aaaaaaaa-0000-4000-8000-000000000002}</property>
  <property name="kdenlive:clip_type">2</property>
 </producer>
 <producer id="producer1" in="00:00:00.000" out="00:00:00.967">
  <property name="length">00:00:01.000</property>
  <property name="eof">pause</property>
  <property name="resource">0x0000ffff</property>
  <property name="mlt_service">color</property>
  <property name="kdenlive:duration">00:00:01.000</property>
  <property name="kdenlive:folderid">-1</property>
  <property name="kdenlive:id">3</property>
  <property name="kdenlive:control_uuid">{aaaaaaaa-0000-4000-8000-000000000003}</property>
  <property name="kdenlive:clip_type">2</property>
 </producer>
 <producer id="producer2" in="00:00:00.000" out="00:00:03.967">
  <property name="length">2147483647</property>
  <property name="eof">continue</property>
  <property name="resource">black</property>
  <property name="mlt_service">color</property>
  <property name="kdenlive:playlistid">black_track</property>
  <property name="mlt_image_format">rgba</property>
  <property name="set.test_audio">0</property>
 </producer>
 <playlist id="playlist0">
  <property name="kdenlive:audio_track">1</property>
 </playlist>
 <playlist id="playlist1">
  <property name="kdenlive:audio_track">1</property>
 </playlist>
 <tractor id="tractor0" in="00:00:00.000">
  <property name="kdenlive:audio_track">1</property>
  <track hide="video" producer="playlist0"/>
  <track hide="video" producer="playlist1"/>
 </tractor>
 <playlist id="playlist2">
  <entry in="00:00:00.000" out="00:00:01.967" producer="producer0">
   <property name="kdenlive:id">2</property>
  </entry>
 </playlist>
 <playlist id="playlist3"/>
 <tractor id="tractor1" in="00:00:00.000" out="00:00:01.967">
  <track hide="audio" producer="playlist2"/>
  <track hide="audio" producer="playlist3"/>
 </tractor>
 <tractor id="{bbbbbbbb-0000-4000-8000-00000000000b}" in="00:00:00.000" out="00:00:01.967">
  <property name="kdenlive:uuid">{bbbbbbbb-0000-4000-8000-00000000000b}</property>
  <property name="kdenlive:sequenceproperties.hasAudio">0</property>
  <property name="kdenlive:sequenceproperties.hasVideo">1</property>
  <property name="kdenlive:sequenceproperties.activeTrack">1</property>
  <property name="kdenlive:sequenceproperties.tracksCount">2</property>
  <property name="kdenlive:sequenceproperties.documentuuid">{aaaaaaaa-0000-4000-8000-00000000000a}</property>
  <property name="kdenlive:control_uuid">{bbbbbbbb-0000-4000-8000-00000000000b}</property>
  <property name="kdenlive:duration">00:00:02.000</property>
  <property name="kdenlive:maxduration">60</property>
  <property name="kdenlive:producer_type">17</property>
  <property name="kdenlive:id">5</property>
  <property name="kdenlive:clip_type">2</property>
  <property name="kdenlive:folderid">6</property>
  <property name="kdenlive:sequenceproperties.audioTarget">-1</property>
  <property name="kdenlive:sequenceproperties.videoTarget">1</property>
  <property name="kdenlive:sequenceproperties.zonein">0</property>
  <property name="kdenlive:sequenceproperties.zoneout">60</property>
  <property name="kdenlive:sequenceproperties.groups">[
]
</property>
  <property name="kdenlive:sequenceproperties.guides">[
]
</property>
  <track producer="producer2"/>
  <track producer="tractor0"/>
  <track producer="tractor1"/>
  <transition id="transition0">
   <property name="a_track">0</property>
   <property name="b_track">1</property>
   <property name="mlt_service">mix</property>
   <property name="kdenlive_id">mix</property>
   <property name="internal_added">237</property>
   <property name="always_active">1</property>
   <property name="accepts_blanks">1</property>
   <property name="sum">1</property>
  </transition>
  <transition id="transition1">
   <property name="a_track">0</property>
   <property name="b_track">2</property>
   <property name="compositing">0</property>
   <property name="distort">0</property>
   <property name="rotate_center">0</property>
   <property name="mlt_service">qtblend</property>
   <property name="kdenlive_id">qtblend</property>
   <property name="internal_added">237</property>
   <property name="always_active">1</property>
  </transition>
 </tractor>
 <producer id="producer3" in="00:00:00.000" out="00:00:02.967">
  <property name="length">2147483647</property>
  <property name="eof">continue</property>
  <property name="resource">black</property>
  <property name="mlt_service">color</property>
  <property name="kdenlive:playlistid">black_track</property>
  <property name="mlt_image_format">rgba</property>
  <property name="set.test_audio">0</property>
 </producer>
 <playlist id="playlist4">
  <property name="kdenlive:audio_track">1</property>
 </playlist>
 <playlist id="playlist5">
  <property name="kdenlive:audio_track">1</property>
 </playlist>
 <tractor id="tractor2" in="00:00:00.000">
  <property name="kdenlive:audio_track">1</property>
  <track hide="video" producer="playlist4"/>
  <track hide="video" producer="playlist5"/>
 </tractor>
 <playlist id="playlist6">
  <entry in="00:00:00.000" out="00:00:00.967" producer="producer1">
   <property name="kdenlive:id">3</property>
  </entry>
  <entry in="00:00:00.000" out="00:00:01.967" producer="{bbbbbbbb-0000-4000-8000-00000000000b}">
   <property name="kdenlive:maxduration">60</property>
   <property name="kdenlive:id">5</property>
  </entry>
 </playlist>
 <playlist id="playlist7"/>
 <tractor id="tractor3" in="00:00:00.000" out="00:00:02.967">
  <track hide="audio" producer="playlist6"/>
  <track hide="audio" producer="playlist7"/>
 </tractor>
 <tractor id="{aaaaaaaa-0000-4000-8000-00000000000a}" in="00:00:00.000" out="00:00:02.967">
  <property name="kdenlive:uuid">{aaaaaaaa-0000-4000-8000-00000000000a}</property>
  <property name="kdenlive:sequenceproperties.hasAudio">1</property>
  <property name="kdenlive:sequenceproperties.hasVideo">1</property>
  <property name="kdenlive:sequenceproperties.activeTrack">1</property>
  <property name="kdenlive:sequenceproperties.tracksCount">2</property>
  <property name="kdenlive:sequenceproperties.documentuuid">{aaaaaaaa-0000-4000-8000-00000000000a}</property>
  <property name="kdenlive:control_uuid">{aaaaaaaa-0000-4000-8000-00000000000a}</property>
  <property name="kdenlive:duration">00:00:03.000</property>
  <property name="kdenlive:maxduration">90</property>
  <property name="kdenlive:producer_type">17</property>
  <property name="kdenlive:id">4</property>
  <property name="kdenlive:clip_type">0</property>
  <property name="kdenlive:folderid">6</property>
  <property name="kdenlive:sequenceproperties.audioTarget">-1</property>
  <property name="kdenlive:sequenceproperties.videoTarget">1</property>
  <property name="kdenlive:sequenceproperties.zonein">0</property>
  <property name="kdenlive:sequenceproperties.zoneout">90</property>
  <property name="kdenlive:sequenceproperties.groups">[
]
</property>
  <property name="kdenlive:sequenceproperties.guides">[
]
</property>
  <track producer="producer3"/>
  <track producer="tractor2"/>
  <track producer="tractor3"/>
  <transition id="transition2">
   <property name="a_track">0</property>
   <property name="b_track">1</property>
   <property name="mlt_service">mix</property>
   <property name="kdenlive_id">mix</property>
   <property name="internal_added">237</property>
   <property name="always_active">1</property>
   <property name="accepts_blanks">1</property>
   <property name="sum">1</property>
  </transition>
  <transition id="transition3">
   <property name="a_track">0</property>
   <property name="b_track">2</property>
   <property name="compositing">0</property>
   <property name="distort">0</property>
   <property name="rotate_center">0</property>
   <property name="mlt_service">qtblend</property>
   <property name="kdenlive_id">qtblend</property>
   <property name="internal_added">237</property>
   <property name="always_active">1</property>
  </transition>
 </tractor>
 <playlist id="main_bin">
  <property name="kdenlive:folder.-1.6">Sequences</property>
  <property name="kdenlive:sequenceFolder">6</property>
  <property name="kdenlive:docproperties.audioChannels">2</property>
  <property name="kdenlive:docproperties.documentid">1795214000001</property>
  <property name="kdenlive:docproperties.kdenliveversion">26.08.3</property>
  <property name="kdenlive:docproperties.patchversion">1</property>
  <property name="kdenlive:docproperties.profile">atsc_720p_30</property>
  <property name="kdenlive:docproperties.uuid">{aaaaaaaa-0000-4000-8000-00000000000a}</property>
  <property name="kdenlive:docproperties.version">1.1</property>
  <property name="kdenlive:docproperties.opensequences">{aaaaaaaa-0000-4000-8000-00000000000a}</property>
  <property name="kdenlive:docproperties.activetimeline">{aaaaaaaa-0000-4000-8000-00000000000a}</property>
  <property name="xml_retain">1</property>
  <entry in="00:00:00.000" out="00:00:01.967" producer="producer0"/>
  <entry in="00:00:00.000" out="00:00:00.967" producer="producer1"/>
  <entry in="00:00:00.000" out="00:00:02.967" producer="{aaaaaaaa-0000-4000-8000-00000000000a}"/>
  <entry in="00:00:00.000" out="00:00:01.967" producer="{bbbbbbbb-0000-4000-8000-00000000000b}"/>
 </playlist>
 <tractor id="tractor4" in="00:00:00.000" out="00:00:02.967">
  <property name="kdenlive:projectTractor">1</property>
  <track in="00:00:00.000" out="00:00:02.967" producer="{aaaaaaaa-0000-4000-8000-00000000000a}"/>
 </tractor>
</mlt>
```
Length bookkeeping in that file: B = 60 frames -> tractor `out=00:00:01.967`, `kdenlive:duration=00:00:02.000`, `maxduration=60`, `zoneout=60`; A = 30 (blue) + 60 (B) = 90 frames -> `out=00:00:02.967`, `maxduration=90`, project tractor `out=00:00:02.967`. Every track tractor that carries clips needs `out` (gotcha 6).

Black track / transitions in B (V for structure, P for transparency): B's black producer and its `mix`/`qtblend` transitions live inside B's tractor, so a nested B is opaque black wherever B itself has no clip (qtblend `compositing=0` over opaque `black`; not rendered with a gap). `makeBackgroundTrackTransparent` is only applied to the document being rendered at render time (`renderrequest.cpp:190-194`). Kdenlive rebuilds B's internal transitions on load like A's (gotcha 8).

Rules:
1. Each additional sequence adds: 1 black `<producer>`, per track a pair of `<playlist>` + a track `<tractor>`, internal transitions (`a_track=0`, `b_track` = MLT index of each track), the sequence `<tractor>`, one `main_bin` `<entry>`. The project tractor does not change. (V)
2. `kdenlive:sequenceproperties.tracksCount` = tracks excluding black; `activeTrack`/`videoTarget`/`audioTarget` are 0-based positions excluding black (2.4). (V)
3. Ids are global in one MLT document: playlist/tractor/producer/transition ids, `kdenlive:id`, `kdenlive:uuid` must not repeat between sequences (the file above uses `playlist0..7`, `tractor0..4`). (V)
4. If B is listed in `opensequences` Kdenlive opens it as a second tab on load; leave it out to keep one tab. (V source)

### 12.2 Image sequence / slideshow clip

**Resource forms (V).** Both produce `ClipType::SlideShow`:
- Folder ("MIME type" method): `resource = <folder>/.all.<ext>`, e.g. `C:/slides/.all.png` (`slideshowclip.cpp:387-401`: folder + `/` + `.all.` + extension; all `*.<ext>` files of that folder, `QDir::entryList(QDir::Files)` name order, are used).
- Pattern: `resource = <folder>/<base>%0Nd.<ext>`, e.g. `C:/slides/img_%04d.png` (N = digit count of the picked file name), plus `?begin=<first>` appended when the first number is > 0 (`slideshowclip.cpp:402-436`). A file import auto-detects sequences (name ends with a digit, more than one match) and writes the same pattern (`clipcreationdialog.cpp:498-527`).
- Detection on load: `mlt_service` is `qimage` or `pixbuf` and the path contains `/.all.` or `\.all.`, or the base name matches `%\d+d$` (`clipcontroller.cpp:305-317`).
- Loaded as `qimage:<resource>` (`cliploadtask.cpp:463-467`).

**Properties (V: `clipcreationdialog.cpp:309-325, 515-526`, `clipcreator.cpp:28-56, 362-382`).** On the bin `<producer>`: `resource`, `mlt_service=qimage`, `length`, `ttl` (frames per image), `loop` (0/1), `crop` (0/1), `fade` (0/1), `luma_duration` (frames), `luma_file` (path or empty), `softness` (0-100), `animation` (name or empty), `low-pass` (0/1), plus the usual `kdenlive:id`, `kdenlive:control_uuid`, `kdenlive:folderid`, `kdenlive:clipname`, `kdenlive:duration`. The auto-detected import writes only `ttl`, `loop=0`, `crop=0`, `fade=0`, `luma_duration` (= 1 s in frames). Length: `length = ttl x imageCount` frames (`clipcreationdialog.cpp:322, 521`), written by the loader as a clock string, `kdenlive:duration` = same value, `out = length-1` (`cliploadtask.cpp:600-640`). `kdenlive:clip_type`: not written by the loader for qimage; the default branch of `checkAudioVideo` sets video-only `2` (`clipcontroller.cpp:942-946`), so write `2`. `loop=1` makes `hasLimitedDuration()` false, i.e. the timeline clip may be extended past `length` (`clipcontroller.cpp:395-402`).

**Hidden filters (V source; the XML shape is P).** `ClipLoadTask::processSlideShow` (`cliploadtask.cpp:160-212`) attaches to the producer, in this order: (a) `avfilter.avgblur` (fallback `boxblur`) when `low-pass=1`; (b) `affine` with `transition.rect` (geometry from `slideanimations.rc`), `transition.cycle=<ttl>`, `transition.mirror_off=1` when `animation` is set; (c) `luma` with `cycle=<ttl>` (if ttl != 0), `duration=<luma_duration>`, optional `luma.resource`, `luma.softness` (= softness/100) when `fade=1`; (d) `crop` with `center=1` when `crop=1`. Attached filters serialise as `<filter>` children of the `<producer>` without `kdenlive_id`, so the effect stack ignores them (gotcha 9). The properties are the source of truth: omit the `<filter>` children and Kdenlive re-attaches them from `ttl`/`fade`/`crop`/... on load (`processSlideShow` runs at every load of a SlideShow bin clip, `cliploadtask.cpp:653`); if you write them (needed for melt-only rendering), keep them consistent. Animation names in the shipped `data/slideanimations.rc` (group `[slides]`): `Pan`, `Pan and zoom`, `Zoom`; values like `0=0%% 0%% 100%% 100%%;%d=-6%% -6%% 112%% 112%%`; each `%d` slot is replaced by ttl-1, then `floor((i+3)/2)*ttl - (i%2)` (`slideshowclip.cpp:538-556`). How the doubled `%%` reaches the filter is UNVERIFIED; melt accepted single `%`: `0=0% 0% 100% 100%;29=-6% -6% 112% 112%` (Zoom, ttl 30).
```xml
<producer id="producer0" in="00:00:00.000" out="00:00:02.967">
  <property name="length">00:00:03.000</property>
  <property name="eof">pause</property>
  <property name="resource">C:/proj/slides/img_%04d.png</property>
  <property name="ttl">30</property>
  <property name="mlt_service">qimage</property>
  <property name="loop">0</property>
  <property name="crop">0</property>
  <property name="fade">0</property>
  <property name="kdenlive:id">2</property>
  <property name="kdenlive:control_uuid">{...}</property>
  <property name="kdenlive:folderid">-1</property>
  <property name="kdenlive:duration">00:00:03.000</property>
  <property name="kdenlive:clip_type">2</property>
</producer>
```
melt-verified: 3 PNGs (img_0001..3), `ttl=30`, 3 s: frames 10/40/70 = image 1/2/3. The `.all.png` form with `fade=1`, `luma_duration=15`, `animation=Zoom` and the matching `affine` + `luma` `<filter>` children also rendered (frame 40 showed the luma blend). Timeline use: a still-like clip, the entry may reference the bin producer directly like color/image clips (`getTimelineProducer` returns a clone of the master for video-only stills, `projectclip.cpp:994-1004`; PROBA-K images do this).

**Hash (V).** `kdenlive:file_hash` of a slideshow = MD5 of a UTF-8 string from `ProjectClip::getFolderHash(dir, fileName)` (`projectclip.cpp:1617-1634`): `fileName` (`img_%04d.png` or `.all.png`) + `entryList(QDir::Files)` of the folder joined by `,` (all files, not only images) + raw MD5 bytes and size of the first file + (if more than one file) the same for the file at index `size/2` (raw bytes appended via QByteArray->QString, not worth reproducing). **Omit `kdenlive:file_hash`**: with it absent/empty DocumentChecker does not compare; with a wrong value it silently replaces it, no dialog (`documentchecker.cpp:1130-1141`, "For slideshow clips, silently upgrade hash"; for normal files a mismatch opens the Reload dialog). `kdenlive:file_size` is not used.

**DocumentChecker (V).** For `qimage`/`pixbuf` producers where `isSlideshow` is true (resource contains `/.all.`, `\.all.`, `?` or `%`; `documentchecker.cpp:2033-2036`) the checked path is `QFileInfo(resource).absolutePath()` = the **folder** (`documentchecker.cpp:1094-1110`): missing folder -> Missing-clip dialog (relocation search by name pattern, `documentchecker.cpp:1250-1290`). Individual image files are not checked. Relative paths resolve against `root`.

### 12.3 Lottie / Glaxnimate animation clip

**Producer (V source; melt-verified service).** `mlt_service=glaxnimate`, `resource=<file>.json|.rawr|.lottie`. "Create animation" in Kdenlive writes a creation XML with only `type=Animation`, `mlt_service=glaxnimate`, `resource`, `kdenlive:folderid` (`clipcreationdialog.cpp:190-203`). Dropping a `.json` goes through `ClipCreator::getXmlFromUrl` as a plain `<producer>` with only `resource` (no lottie-specific code in this tag, `clipcreator.cpp:274-330`), and MLT's loader picks `glaxnimate` by extension (melt-verified: `melt anim.json` writes `mlt_service=glaxnimate`). `ClipType::Animation` comes from `mlt_service==glaxnimate` (`clipcontroller.cpp:353-355`); it is not in the audio/video probe list, so `kdenlive:clip_type` becomes `2` (`clipcontroller.cpp:942-946`); `hasLimitedDuration()` is true (`clipcontroller.cpp:411-414`): timeline clips cannot exceed the animation length. Shape = melt's serialisation of a real glaxnimate producer plus Kdenlive bin properties (exact bytes of a Kdenlive-saved one: P):
```xml
<producer id="producer0" in="00:00:00.000" out="00:00:01.967">
  <property name="length">60</property>
  <property name="eof">loop</property>
  <property name="resource">C:/proj/anim.json</property>
  <property name="background">#00000000</property>
  <property name="aspect_ratio">1</property>
  <property name="progressive">1</property>
  <property name="seekable">1</property>
  <property name="meta.media.width">1080</property>
  <property name="meta.media.height">1920</property>
  <property name="meta.media.frame_rate">30</property>
  <property name="first_frame">0</property>
  <property name="mlt_service">glaxnimate</property>
  <property name="kdenlive:id">2</property>
  <property name="kdenlive:control_uuid">{...}</property>
  <property name="kdenlive:folderid">-1</property>
  <property name="kdenlive:clip_type">2</property>
</producer>
```
- `length` is in project frames: melt converts the animation fps to the profile fps (a 60-frame 30 fps JSON gives `length=60` at a 30 fps profile, `50` at the default 25 fps PAL profile; V). `meta.media.*`, `first_frame`, `background` are written by MLT; the minimum you need is `mlt_service`, `resource`, `length`/`in`/`out` and the `kdenlive:*` ids (P).
- Hash: checked on load for `glaxnimate` (`documentchecker.cpp:1112, 1130`): MD5 of the whole file if <= 2,000,000 bytes, else MD5 of first+last 1,000,000 bytes (`ProjectClip::calculateHash`, `projectclip.cpp:1692-1716`; same rule as gotcha 5). Omit `kdenlive:file_hash` or compute it exactly (mismatch -> Reload dialog); `kdenlive:file_size` = byte size. The file must exist (Missing dialog, `documentchecker.cpp:1113`).
- **Renders (melt-verified, bundled glaxnimate producer, minimal hand-written Lottie):** at `-profile vertical_hd_30` the 716-byte JSON below gave a 1080x1920 frame; centre pixel at frame 20 = (255,51,26) (the fill colour), corner pixel black (rgba over black). Command: `melt.exe -profile vertical_hd_30 glaxnimate:anim.json in=20 out=20 -silent -consumer avformat:frame.png vcodec=png`.
```json
{"v":"5.7.1","fr":30,"ip":0,"op":60,"w":1080,"h":1920,"nm":"Anim","ddd":0,"assets":[],
"layers":[{"ddd":0,"ind":1,"ty":4,"nm":"Square","sr":1,"ks":{
"o":{"a":0,"k":100},"r":{"a":1,"k":[{"t":0,"s":[0],"i":{"x":[0.5],"y":[1]},"o":{"x":[0.5],"y":[0]}},{"t":60,"s":[360]}]},
"p":{"a":0,"k":[540,960,0]},"a":{"a":0,"k":[0,0,0]},"s":{"a":0,"k":[100,100,100]}},"ao":0,
"shapes":[{"ty":"gr","nm":"G","it":[
{"ty":"rc","nm":"R","p":{"a":0,"k":[0,0]},"s":{"a":0,"k":[600,600]},"r":{"a":0,"k":40}},
{"ty":"fl","nm":"F","c":{"a":0,"k":[1,0.2,0.1,1]},"o":{"a":0,"k":100}},
{"ty":"tr","p":{"a":0,"k":[0,0]},"a":{"a":0,"k":[0,0]},"s":{"a":0,"k":[100,100]},"r":{"a":0,"k":0},"o":{"a":0,"k":100}}]}],
"ip":0,"op":60,"st":0,"bm":0}]}
```
- Kdenlive's own "empty animation" template is a Glaxnimate `.rawr` document (`clipcreationdialog.cpp:152-172`); the Lottie-JSON variant is commented out (173-178).

### 12.4 Time remapping

**Shape (V source; melt-verified).** A time-remapped timeline clip is a `<chain>` (not a `<producer>`) over the file with a `<link>` child: `ProjectClip::getTimelineProducer` (`projectclip.cpp:1124-1133`) does `Mlt::Chain(profile, resource)`, `Mlt::Link("timeremap")` with `time_map` (if non-empty), `pitch`, `image_mode`, then `chain->attach(link)`. Links are direct children of the producer/chain element in the XML (`DocumentChecker::isSequenceWithSpeedEffect` queries them that way, `documentchecker.cpp:2049-2060`). Detection on load: the entry's parent is a chain (`mlt_service_chain_type`) with a link whose `mlt_service` is `timeremap` (`projectclip.cpp:1222-1239`, `clipmodel.cpp:475-490`).
```xml
<chain id="chain0" out="00:00:03.967">
  <property name="length">00:00:04.000</property>
  <property name="eof">pause</property>
  <property name="resource">src.mp4</property>
  <property name="mlt_service">avformat-novalidate</property>
  <property name="kdenlive:id">2</property>
  <property name="kdenlive:control_uuid">{...}</property>
  <property name="set.test_audio">1</property>
  <property name="set.test_image">0</property>
  <link id="link0">
    <property name="mlt_service">timeremap</property>
    <property name="time_map">00:00:00.000=0;00:00:02.000=4</property>
    <property name="pitch">0</property>
    <property name="image_mode">nearest</property>
  </link>
</chain>
<playlist id="playlist0">
  <entry in="00:00:00.000" out="00:00:01.967" producer="chain0">
    <property name="kdenlive:id">2</property>
  </entry>
</playlist>
```
melt-verified with a 4 s, 30 fps countdown clip (this exact `<chain>`/`<link>`/entry in a 1280x720 30 fps project): output 60 frames = 2.000 s; frame 30 showed source second 2, frame 59 source second ~4 (so 2x); the audio copy (`set.test_audio=0`, `set.test_image=1`, `pitch=1`) rendered a 2.000 s wav. The chain's own `length`/`out` stay those of the full source. `<link id="link0">`: the `id` attribute is my spelling of MLT's serialisation (melt accepted it); no Kdenlive-saved time-remap file exists in the repo, so the exact attributes MLT's serialiser adds are U.
- `time_map` (V: writer `RemapView::getKeyframesData`, `timeremap.cpp:1207-1226`; `clipmodel.cpp:620-640`): `;`-separated keyframes `"<output position as clock time>=<source time in seconds>"`. Key = output frame of the **chain** (positions include the entry's in-offset, `timeremap.cpp:590`), written with `frames_to_time(.., mlt_time_clock)`; value = `GenTime(sourceFrame).seconds()` as a plain decimal (not clock). The LAST keyframe is written one frame after its real position (comment "HACK: we always set last keyframe 1 frame after in MLT to ensure we have a correct last frame", `timeremap.cpp:1219-1222`, `clipmodel.cpp:515, 622`), so a clip whose last frame is 59 has its last key at 60 = `00:00:02.000`. Interpolation between keys is MLT's default animation interpolation (linear unless a key carries an interpolation marker: P). `speed_map` is the MLT alternative that "overrides time_map" (`melt -query link=timeremap`); Kdenlive reads and writes only `time_map` (the deprecated `map` is used as a fallback when `time_map` is absent, `projectclip.cpp:1230-1233`).
- `pitch` 0/1 = pitch compensation (audio only matters); Kdenlive sets `pitch=1` when remap is first enabled on an audio clip (`timeremap.cpp:1776-1779`). `image_mode` = `nearest` (default) or `blend` (frame blending checkbox, `timeremap.cpp:1807, 2048`).
- entry in/out are in output frames of the chain, like timewarp (4.5): the entry covers chain frames `in..out`, so timeline length = `out-in+1`. A speed of 2 over a 4 s source gives a 60-frame entry. With a remap the usual `out < length` limit is lifted (`clipmodel.cpp:177, 194`: checks are `&& !hasTimeRemap()`); `getRemapInputDuration` = max key value (frames) - value at `in` (`clipmodel.cpp:653-681`).
- A/V pair: video and audio entries each use their own `<chain>` with the same `time_map`/`pitch`/`image_mode` (the remap panel updates the split partner too, `timeremap.cpp:1950-1956, 2043-2056`); copy flags as 4.2 (video copy `set.test_audio=1`, `set.test_image=0`; audio copy the opposite). Both chains need the bin clip's `kdenlive:control_uuid` and `kdenlive:id` (gotcha 1).
- Exclusions: a clip with a speed (timewarp) effect cannot be remapped (`timelinecontroller.cpp:3191-3200`); remapped clips use `<chain>` + link, speed-changed ones use `<producer mlt_service="timewarp">` (4.5). Images/stills are excluded in the UI (`timelinecontroller.cpp:4602`). The clipboard uses attributes `timemap`/`timepitch`/`timeblend` (`timelinefunctions.cpp:2692-2706`) which are not part of the project file.
- UNVERIFIED: the map Kdenlive writes the moment remap is first enabled (empty `time_map`; the UI creates default keyframes). An identity map for an entry of N frames at in=0 is `00:00:00.000=0;<clock of frame N>=<N/fps seconds>` by the writer rule above.

### 12.5 Render presets

**Where presets come from (V).** `<install>/bin/data/kdenlive/export/profiles.xml` (shipped; parsed by `RenderPresetRepository`, `renderpresetrepository.cpp:105-125`), the user's `customprofiles.xml` (overrides), and presets generated from MLT files under `share/mlt/presets/consumer/avformat/{lossless,ten_bit,stills}` plus `GIF` (`parseMltPresets`, `renderpresetrepository.cpp:266-312`). A `properties=<file>` arg is an MLT preset that the avformat consumer loads itself (`properties=x264-medium`, `properties=WAV`, `properties="ten_bit/ProRes HQ"`); Kdenlive does not expand it. melt prints "Failed to open properties file .../dv_pal/<name>" first (it tries `<profile>/<name>` before `<name>`); harmless, the output is written.

**Expansion algorithm (V: `renderrequest.cpp:64-80, 393-420`; `renderpresetmodel.cpp:38-76, 477-485`).**
1. Split `args` at whitespace followed by `key=` (`insertFromString`, regex `\s+(?=\S*=)`); each `key=value` becomes a consumer attribute (values may contain spaces, quotes).
2. `loadPresetParams` replaces, in this order: `%quality` <- `defaultquality`; `%audioquality` <- `defaultaudioquality`; `%audiobitrate+'k'` <- `<defaultaudiobitrate>k`; `%audiobitrate` <- `defaultaudiobitrate`; `%bitrate+'k'` <- `<defaultbitrate>k`; `%bitrate` <- `defaultbitrate` (the `+'k'` forms must go first). The GUI uses the slider/combo values instead of the defaults.
3. Speed: `speeds="a;b;c"` list; default index = `defaultspeedindex`, or `int((count-1)*0.75)` when absent; the chosen entry (space-separated `k=v`, e.g. `preset=veryfast`) is merged with `insertFromString(.., overwrite=false)`, so it never overrides a key already present.
4. `setDocGeneralParams` builds the `<consumer>` element: `mlt_service=avformat`, `in`, `out` (render range, frames), `rescale` (setting `renderInterp`, default bilinear), `deinterlacer` (setting `renderDeinterlacer`, default onefield), then every param as an attribute; `target=<file>` is added elsewhere. On the melt command line the same thing is `-consumer avformat:<file> k=v k=v ...`. For libx265 `x265-params` is rebuilt by `refreshX265Params` (the `:open-gop=0` suffix inside `crf=%quality:open-gop=0` is part of the value).
5. `%dv_standard` (VOB preset) and `%dar` are not substituted by `loadPresetParams`; `%dv_standard` appears only in an `isDv`-type check (`renderpresetmodel.cpp:625`) and I found no `%dar` use in the files I fetched: substitution UNVERIFIED, avoid those presets.
6. Alpha presets (`pix_fmt` with alpha): Kdenlive makes the black background track transparent in the render copy (`renderrequest.cpp:190-194`); for hand rendering edit or drop the black track yourself.
7. `acodec=vorbis` is rewritten to `libvorbis` (and `aac` to `libfaac`) only when that encoder is listed (`renderpresetmodel.cpp:297-307`); the VP8 command below used `libvorbis` and worked, plain `vorbis` untested.

**Presets in the shipped `profiles.xml` (V, file read in full).** `[group]`; `q` = `defaultquality` (range `qualities`), `aq` = `defaultaudioquality`, `ab` = `defaultaudiobitrate`.

| name | ext | args (placeholders unexpanded) | defaults |
|---|---|---|---|
| [generic] WebM-VP8/Vorbis (libre) | webm | `f=webm vcodec=libvpx crf=%quality vb=8M qcomp=1 g=15 acodec=vorbis aq=%audioquality` | q 15 (5-45), aq 5 |
| [generic] MP4-H264/AAC | mp4 | `f=mp4 movflags=+faststart vcodec=libx264 crf=%quality g=15 acodec=aac ab=%audiobitrate+'k'` | q 23 (15-45), ab 160, speed idx 6 = `preset=veryfast` (9 entries, veryslow..ultrafast) |
| [generic] Matroska-H264/AAC | mkv | same with `f=matroska` | same |
| [generic] MPEG-2 | mpg | `properties=MPEG-2 qscale=%quality aq=%audioquality` | q 5, aq 3 |
| [generic] GIF High Quality | GIF | empty args | behaviour UNVERIFIED (no `f`, upper-case ext); use the MLT `GIF` preset below |
| [4k] WebM-VP9/Opus (libre) | webm | `f=webm vcodec=libvpx-vp9 crf=%quality vb=15M qcomp=1 g=15 row-mt=1 tile-columns=4 frame-parallel=1 acodec=libopus compression_level=%audioquality` | q 25 (15-45), aq 5 |
| [4k] WebM-AV1/Opus (libre-dav1d) | webm | `f=webm acodec=libopus ab=%audiobitrate+'k' crf=%quality vcodec=libsvtav1 vbr=off svtav1-params=scd=1:enable-dg=1:pred-struct=2:lp=0:tile-columns=1:fast-decode=0:tune=0:film-grain=0:film-grain-denoise=0:enable-overlays=1:enable-variance-boost=1:variance-boost-strength=1:variance-octile=7:enable-qm=1:qm-min=0 g=150` | q 32, ab 160, speeds `preset=4;5;6;7;10` |
| [4k] MP4-H265 (HEVC) | mp4 | `properties=x265-medium f=mp4 vcodec=libx265 crf=%quality:open-gop=0 acodec=aac ab=%audiobitrate+'k'` | q 28, ab 160, speed idx 6 |
| [alpha] Alpha VP8 | webm | `f=webm vcodec=libvpx auto-alt-ref=0 crf=%quality vb=10M qcomp=1 g=15 mlt_image_format=rgba pix_fmt=yuva420p acodec=vorbis aq=%audioquality` | q 15, aq 4 |
| [alpha] Alpha VP9 | webm | `f=webm vcodec=libvpx-vp9 crf=%quality vb=20M qcomp=1 g=15 mlt_image_format=rgba pix_fmt=yuva420p acodec=vorbis aq=%audioquality` | q 15 (5-30), aq 4 |
| [alpha] Alpha MOV | mov | `f=mov vcodec=qtrle mlt_image_format=rgba pix_fmt=argb` | - |
| [alpha] FFmpeg FFV1 | mkv | `f=mov vcodec=ffv1 mlt_image_format=rgba pix_fmt=bgra` (as shipped: `f=mov` with ext mkv) | - |
| [sd] VOB (DVD) | vob | `properties=dv_%dv_standard/DVD mlt_profile=dv_%dv_standard f=dvd vcodec=mpeg2video acodec=ac3 qscale=%quality ab=%audiobitrate+'k'` | q 5, ab 160; `%dv_standard` UNVERIFIED |
| [sd] MPEG4-ASP/MP3 (DivX compatible) | avi | `properties=MPEG-4-ASP qscale=%quality aq=%audioquality` | q 5, aq 5 |
| [sd] Windows Media Player | wmv | `f=asf vcodec=wmv2 acodec=wmav2 qscale=%quality aq=%audioquality` | q 5, aq 5 |
| [hw] NVENC AV1 VBR, NVENC H264 ABR/VBR, NVENC H265 ABR, NVENC H265 ABR 10 bit, VideoToolBox H264/H265 ABR, Quick Sync Intel H264/H265, VAAPI H264, AMF H264 | mp4 | `f=mp4 vcodec=<av1_nvenc/h264_nvenc/hevc_nvenc/h264_videotoolbox/hevc_videotoolbox/h264_qsv/hevc_qsv/h264_vaapi/h264_amf> ...` (read the file for exact args; ABR ones use `vb=%bitrate+'k'`, bitrate default 6000 (QSV 20000)) | need that hardware |
| [audio] AC3 | ac3 | `ab=%audiobitrate+'k' vn=1 video_off=1` | ab 160 |
| [audio] ALAC | mov | `f=mov acodec=alac vn=1 video_off=1` | - |
| [audio] FLAC | mka | `f=matroska acodec=flac vn=1 video_off=1` | - |
| [audio] MP3 | mp3 | `aq=%audioquality acodec=libmp3lame vn=1 video_off=1` | aq 5 (3-7) |
| [audio] OGG | ogg | `aq=%audioquality vn=1 video_off=1` | aq 4 |
| [audio] WAV | wav | `properties=WAV video_off=1` | - |
| [image] PNG with alpha | png | `progressive=1 f=image2 vcodec=png an=1 audio_off=1 g=1 bg=0 pix_fmt=rgba` | - |

**ProRes (V): not in `profiles.xml`.** It comes from the MLT presets `share/mlt/presets/consumer/avformat/ten_bit/{ProRes 422, ProRes HQ, ProRes 444}` (`vcodec=prores_ks`, `vprofile=2|3|4`, `pix_fmt=yuv422p10le|yuv444p10le`, `acodec=pcm_s16le`, `qscale=1`, `vendor=apl0`, `movflags=+write_colr`, ext `mov`), which Kdenlive lists in group "10bit" under names like `ProRes HQ (prores_ks+pcm_s16le)` with args `properties=ten_bit/ProRes HQ` (`renderpresetrepository.cpp:286-296`, name built at `renderpresetmodel.cpp:241-253`). **GIF (V):** group image, name `GIF`, args `properties=GIF` (preset file `f=gif vcodec=gif an=1 g=1 bf=0`, ext gif).

**Expanded melt arguments (defaults applied).** Each was run as `melt.exe <project.kdenlive> in=0 out=14 -silent -consumer <args>` and the result inspected with ffprobe (bundled `bin/ffprobe.exe`). Kdenlive additionally sets `rescale=bilinear deinterlacer=onefield`.
- MP4-H264/AAC: `avformat:out.mp4 f=mp4 movflags=+faststart vcodec=libx264 crf=23 g=15 acodec=aac ab=160k preset=veryfast` -> h264 1280x720 + aac (V).
- WebM-VP9/Opus: `avformat:out.webm f=webm vcodec=libvpx-vp9 crf=25 vb=15M qcomp=1 g=15 row-mt=1 tile-columns=4 frame-parallel=1 acodec=libopus compression_level=5` -> vp9 + opus (V; libopus warns "No bit rate set", harmless). WebM-VP8/Vorbis: `avformat:out.webm f=webm vcodec=libvpx crf=15 vb=8M qcomp=1 g=15 acodec=libvorbis aq=5` (V, rendered; codecs not ffprobed).
- ProRes HQ MOV: `avformat:out.mov properties="ten_bit/ProRes HQ"` (quote the space) -> prores + pcm_s16le (V). Equivalent explicit args from the preset file: `f=mov vcodec=prores_ks vb=0 g=1 bf=0 vprofile=3 vendor=apl0 qscale=1 movflags=+write_colr pix_fmt=yuv422p10le acodec=pcm_s16le` (not run separately).
- GIF: `avformat:out.gif properties=GIF` (= `f=gif vcodec=gif an=1 g=1 bf=0`) -> gif 1280x720 (V).
- WAV: `avformat:out.wav properties=WAV video_off=1` (preset = `f=wav acodec=pcm_s16le vn=1 video_off=1`) -> pcm_s16le (V). MP3: `avformat:out.mp3 aq=5 acodec=libmp3lame vn=1 video_off=1` -> mp3 (V).
- PNG sequence: `"avformat:out/png-%04d.png" progressive=1 f=image2 vcodec=png an=1 audio_off=1 g=1 bg=0 pix_fmt=rgba` -> 15 files for `in=0 out=14` (V; the target needs a `%0Nd` pattern for more than one frame; the preset `extension=png` only affects naming in the GUI).
- Range: `in=<first> out=<last>` right after the project path (inclusive frames); Kdenlive puts them in the `<consumer in= out=>` element (9.1).

### 12.6 Verification log for section 12

| Claim | How verified |
|---|---|
| Nested sequence B on A's V1 renders (B tractor referenced by id from A's playlist) | melt 7.43 on the 210-line file above and on a longer variant: frame 10 pixel (0,0,254) blue, frame 50 (255,1,0) red (B) |
| Slideshow `img_%04d.png` and `.all.png` + `ttl`/`affine`/`luma` filters | melt, 3 generated PNGs, `ttl=30`: frames 10/40/70 = image 1/2/3 |
| Glaxnimate renders hand-written Lottie JSON | melt, 1080x1920 frame, centre pixel = fill colour; `length`=60 at 30 fps |
| Time remap `<chain>`+`<link timeremap>` | melt, 2x remap: frame 30 -> source second 2, frame 59 -> ~second 4; audio copy 2.000 s |
| Presets MP4/VP9/VP8/ProRes/GIF/WAV/MP3/PNG | melt `-consumer` lines above, ffprobe codec names |
| Not verified | Kdenlive-side load of any of these files; Kdenlive-saved bytes of slideshow/animation/remap/nested-sequence entries beyond T/test-nesting; `%%` handling in slideanimations.rc; empty-args GIF preset; `%dar`/`%dv_standard` substitution; transparency of an empty nested sequence |
