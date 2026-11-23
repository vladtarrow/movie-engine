---
name: kdenlive-live
description: Drive the running Kdenlive in this project without disturbing the user — start it, check whether the user has unsaved edits, make it re-read the project after an AI edit, and capture its window. Use whenever an AI change to a .kdenlive project must show up in the open editor, or when you need to see what the editor shows.
---

# Driving the running Kdenlive (Windows, no focus stealing)

Paths below are relative to a Movie Engine folder (a clone of https://github.com/vladtarrow/movie-engine). If the current project has no `engine\kd-ui.ps1`, it is not one: use the `movie-engine-setup` skill first instead of guessing paths.

The user works on the same desktop. Every step here uses UI Automation patterns or window-only capture. Never use SetForegroundWindow, SendKeys, keybd_event, mouse input or desktop screenshots.

## Start

- Agents: `powershell -NoProfile -ExecutionPolicy Bypass -File engine\kdenlive-bg.ps1 projects\<name>\<name>.kdenlive` — minimized, opens through `tools\kd-open.ps1` and returns when the project is loaded (exit 0; 4 not confirmed). **The empty editor takes the focus for about 3 s as it appears: ask before running it while the user works.** First start shows a splash for about 30 s and then a one-time "quick setup" wizard (only on a fresh profile).
- Why `kd-open.ps1`: `kdenlive.exe <project>` restores the panel layout over the fully built timeline (`ProjectManager::doOpenFile` emits `GUISetupDone` last), and each UI Automation event then walks all timeline items (stack samples 2026-11-22). Empty start + File > Recent files avoids it: ~12 min became 139 s on a 1000-clip project. If the menu route fails it says "slow way" and starts directly. A reload (Revert) does not restore the layout and is not affected.
- User: `engine\kdenlive.cmd [project]`.
- Interface language: English by default (`LANGUAGE=en_US`); `MOVIE_ENGINE_UI_LANG=ru` (or another code) changes it. UI Automation names live in `engine\tools\kd-ui.ps1` `$KdNames` (31 interface languages, see `AGENTS.md`); `engine\tools\kd-langcheck.ps1` finds File, Save, Revert and Open Recent in a test instance (verified 2026-11-23 for all 31, `docs\proof\language*.txt`).
- Both redirect USERPROFILE, APPDATA, LOCALAPPDATA and XDG_* to `engine\profile-kdenlive`, so nothing is written to the Windows profile (verified: `kdenliverc` lands in `engine\profile-kdenlive\AppData\Local`).
- Only one Kdenlive at a time: launching `kdenlive.exe file` again starts a second process; it does not hand off to the running one.

## Is the user in the middle of something?

The toolbar button named `Save` (`Сохранить` in Russian, ControlType Button) is enabled only when the document has unsaved changes. Check it before any reload; `engine\kd-reload.ps1` does this and exits 2 if it is enabled.

## Show an AI edit in the open editor

1. Edit with `engine\kdp.ps1`. It pulls first and refuses to write if the user edited meanwhile.
2. With the watcher running the editor reloads by itself. Otherwise run `engine\kd-reload.ps1 -Project <file>`.
3. Trust only exit code 0 / a log line `reload: exit 0 reload confirmed`. Exit 4 means the user may still see the old version: say so and retry, never report it as shown.

How a reload is confirmed (verified 2026-11-22): File > Revert closes and reopens the document, which rebuilds the UI Automation element of class `TimelineWidget`; its runtime id changes. On a big project `Invoke` can throw a timeout after about 60 s while loading goes on for minutes, so neither "Invoke returned" nor "Invoke threw" says anything about success. While the modal "Loading project" window is up the reload is still running: wait, do not click again. Search UI Automation only down the known branches (`Find-KdSaveButton`, `Find-KdFileMenu`, `Find-KdTimeline`): a search through all descendants of the main window freezes a big project for 30-70 s.

Revert asks "delete all changes since the last save?" only with unsaved edits. Never confirm that dialog; the scripts cancel it.

## Other verified UI Automation facts

- Close Kdenlive without focus: `AutomationElement.FromHandle(MainWindowHandle).GetCurrentPattern(WindowPattern).Close()`.
- Menu bar (English UI, verified 2026-11-23): `File | Edit | View | Media | Sequence | Tool | Monitor | Markers | Settings | Help`. The File menu holds New, Open…, Open Recent, Revert, Save, Save As…, Save Copy…, Archive Project…, Render…, OpenTimelineIO import/export, Open Backup File…, Project Settings…, Quit (Russian UI: `Создать`, `Открыть…`, `Последние файлы`, `Восстановить`, `Сохранить`, `Сохранить как…`, …, `Параметры проекта…`, `Выход`). After `Expand()` on File they are found as descendants of the main window.
- The main window title is `<project> / <profile description> - Kdenlive`, e.g. `proba / Vertical HD 30 fps - Kdenlive`.
- `PrintWindow` works on the minimized main window but returns black for Qt popup menus.
- Invoking Save As… on the minimized window did not open a dialog (2026-11-21, cause unknown) — do not rely on it yet.

## Read the user's edits

Run `engine\kd-pull.ps1` before reading or editing the file. It invokes the toolbar Save button when enabled and waits until it turns disabled (verified: a user's unsaved clip move reached the file). InvokePattern.Invoke can time out while Kdenlive shows a modal; the script ignores that and closes "Information" (`Сведения`) notices with WindowPattern.Close.

## Live update (watcher)

`engine\kd-watch.ps1 -Project <file>` polls the file hash and the Save button.

- Hash equals the stamp in `.kdp-history\<project>\last-write.sha256`: an AI write, reload (also right after a save).
- Other change right after enabled -> disabled: Kdenlive's own save, skip.
- Change while the user has unsaved edits: `CONFLICT`, no reload, the AI version is copied to `.kdp-history\<project>\conflict`. Pull, then apply the change again.
- A failed reload is retried 3 times, then `RELOAD FAILED` is logged.

## Several Kdenlive windows

Several Kdenlive processes may run (the user's project plus a test one). `engine\tools\kd-proc.ps1` `Find-KdProcess <project>` picks the one whose title starts with the project name; `kd-pull.ps1`, `kd-reload.ps1`, `kd-watch.ps1` and `kdp.ps1` all take `-Project` and use it.

## Checking a project in a real Kdenlive: use `engine\tools\kd-check.ps1 -Project <file>`

It runs a second Kdenlive on an invisible Windows desktop with a throw-away profile and TEMP, so it cannot take the focus, change the user's layout or leave a crash flag. Exit 0 = clean load, 2 = problem, 124 = timeout.

A Kdenlive started on the user's desktop takes the keyboard focus during load (ForegroundLockTimeout), even minimized. So anything that is only a test goes through `tools\kd-hidden.ps1`; `kdenlive-bg.ps1` is only for opening a project for the user.

Crash flag: Kdenlive creates `%TEMP%\kdenlivelock` while starting. If one is left, the next start waits on its splash with "Во время последнего запуска Kdenlive произошёл сбой". The launchers keep TEMP inside the profile.

Window titles: with several sequences Kdenlive titles the window `<sequence>:<project> / <profile> - Kdenlive`; `Find-KdProcess` handles both forms.

## Modals steal focus

Kdenlive's own modal dialogs (for example the one-time "project file was upgraded" notice when saving a 1.04 file) take focus from the user and block UI Automation. Avoid triggering them: write projects in the current 1.1 format.
