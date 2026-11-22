# UI Automation of a running Kdenlive: save the user's edits (pull) and re-read the file (reload).
# No focus changes, keystrokes or mouse input. UTF-8 with BOM (it holds the Russian fallback names).
# PowerShell variable names ignore case: do not add a $t next to a $T.
. (Join-Path $PSScriptRoot 'kd-state.ps1')
. (Join-Path $PSScriptRoot 'kd-proc.ps1')
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes
$script:KdAE = [System.Windows.Automation.AutomationElement]
$script:KdScope = [System.Windows.Automation.TreeScope]

function New-KdResult([int]$code, [string]$message) { [pscustomobject]@{ Code = $code; Message = $message } }

# UI Automation names of the Kdenlive items we use, English first (the launchers start Kdenlive in English,
# see Set-KdEnvironment), then Russian for an editor started in a Russian Windows without them.
$script:KdNames = @{
    File    = @('File', 'Файл')
    Save    = @('Save', 'Сохранить')
    Revert  = @('Revert', 'Восстановить')
    Recent  = @('Open Recent', 'Последние файлы')
    Folder  = @('Create Folder', 'Создать папку')
}
$script:KdInfoTitle = '^(Information|Сведения)'               # KMessageBox::information, safe to close
$script:KdRevertTitle = '^(Revert|Restore|Восстан|Верн)'        # the "discard unsaved changes?" question
function New-KdNameCondition([string]$key) {
    $conds = @($script:KdNames[$key] | ForEach-Object { New-Object System.Windows.Automation.PropertyCondition($script:KdAE::NameProperty, $_) })
    if ($conds.Count -eq 1) { return $conds[0] }
    New-Object System.Windows.Automation.OrCondition(, [System.Windows.Automation.Condition[]]$conds)
}
# Descendant search by name key. Only for small roots (a menu, a dialog, the menu bar), never the main window of a big project.
function Find-KdNamed($root, [string]$key) { $root.FindFirst($script:KdScope::Descendants, (New-KdNameCondition $key)) }
function Find-KdElement($root, $property, $value) {
    $root.FindFirst($script:KdScope::Descendants, (New-Object System.Windows.Automation.PropertyCondition($property, $value)))
}
# Never search the whole main window: that makes Qt walk every timeline item, and on a 1000-clip project
# one such search froze the editor for 30-70 s (measured 2026-11-22). Go down only the known branches.
function Get-KdChildren($el, $condition = [System.Windows.Automation.Condition]::TrueCondition) {
    $el.FindAll($script:KdScope::Children, $condition)
}
function Find-KdSaveButton($root) {
    $bars = New-Object System.Windows.Automation.PropertyCondition($script:KdAE::ControlTypeProperty, [System.Windows.Automation.ControlType]::ToolBar)
    $cond = New-Object System.Windows.Automation.AndCondition(
        (New-KdNameCondition 'Save'),
        (New-Object System.Windows.Automation.PropertyCondition($script:KdAE::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button)))
    foreach ($bar in Get-KdChildren $root $bars) {
        $button = $bar.FindFirst($script:KdScope::Children, $cond)
        if ($button) { return $button }
    }
}
function Find-KdFileMenu($root) {
    $bars = New-Object System.Windows.Automation.PropertyCondition($script:KdAE::ControlTypeProperty, [System.Windows.Automation.ControlType]::MenuBar)
    $named = New-KdNameCondition 'File'
    foreach ($bar in Get-KdChildren $root $bars) {
        $item = $bar.FindFirst($script:KdScope::Children, $named)
        if ($item) { return $item }
    }
}
# The containers between the main window and the timeline. The search never enters the timeline itself.
$script:KdContainers = '(MainWindow|DropArea|::Group|::Stack|QStackedWidget|DockWidget|TimelineTabs|QSplitter|MultiSplitter)$|^QWidget$'
function Find-KdTimeline($root) {
    $queue = New-Object System.Collections.Queue
    $queue.Enqueue($root)
    while ($queue.Count) {
        foreach ($child in Get-KdChildren ($queue.Dequeue())) {
            $class = [string]$child.Current.ClassName
            if ($class -eq 'TimelineWidget') { return $child }
            if ($class -match $script:KdContainers) { $queue.Enqueue($child) }
        }
    }
}
# $true / $false, or $null when Kdenlive cannot answer. "Cannot answer" must never be read as "no edits".
function Get-KdUnsaved($main) {
    try {
        $button = Find-KdSaveButton ($script:KdAE::FromHandle($main.Handle))
        if ($button) { return [bool]$button.Current.IsEnabled }
    } catch { }
    return $null
}
# A busy Kdenlive does not answer UI Automation. Wait for it instead of guessing.
function Wait-KdUnsaved($main, [int]$timeoutSec) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    do {
        $state = Get-KdUnsaved $main
        if ($null -ne $state) { return $state }
        Start-Sleep -Milliseconds 700
    } while ($clock.Elapsed.TotalSeconds -lt $timeoutSec)
    return $null
}
# The timeline widget is rebuilt by every real reload (verified 2026-11-22), so a changed runtime id proves one.
function Get-KdTimelineId($main) {
    try {
        $widget = Find-KdTimeline ($script:KdAE::FromHandle($main.Handle))
        if ($widget) { return ($widget.GetRuntimeId() -join '.') }
    } catch { }
    return $null
}
# Kdenlive's modal progress window while it loads. It is work in progress, not a question to the user.
$script:KdProgressTitle = '^(Загрузка проекта|Loading project)'
function Test-KdLoading($main) {
    [bool](Get-KdTopWindows $main.ProcessId | Where-Object { $_.Title -match $script:KdProgressTitle })
}
function Wait-KdLoaded($main, [int]$timeoutSec) {
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while (Test-KdLoading $main) {
        if ($clock.Elapsed.TotalSeconds -ge $timeoutSec) { return $false }
        Start-Sleep -Milliseconds 700
    }
    return $true
}
function Get-KdDialogs($main) {
    if ([KdNative]::IsWindowEnabled($main.Handle)) { return }   # not disabled = no modal dialog
    Get-KdTopWindows $main.ProcessId | Where-Object { $_.Handle -ne $main.Handle -and $_.Title -and $_.Title -notmatch '^Splash Screen' -and $_.Title -notmatch $script:KdProgressTitle }
}
function Close-KdWindow($window) {
    try { $script:KdAE::FromHandle($window.Handle).GetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern).Close(); return $true } catch { return $false }
}

# 0 file is current, 3 not running, 4 could not be confirmed.
function Invoke-KdPull([string]$project, [int]$timeoutSec = 600) {
    try { $main = Find-KdWindow $project } catch { return New-KdResult 4 $_.Exception.Message }
    if (-not $main) { return New-KdResult 3 'Kdenlive with this project is not running' }
    if (-not (Wait-KdLoaded $main $timeoutSec)) { return New-KdResult 4 "Kdenlive was still loading after $timeoutSec s" }
    foreach ($dialog in @(Get-KdDialogs $main)) {
        if ($dialog.Title -match $script:KdInfoTitle) { [void](Close-KdWindow $dialog) }
        else { return New-KdResult 4 "a dialog is open in Kdenlive: '$($dialog.Title)'" }
    }
    $unsaved = Wait-KdUnsaved $main $timeoutSec
    if ($null -eq $unsaved) { return New-KdResult 4 'Kdenlive did not say whether it has unsaved edits (busy, or Save button not found)' }
    if (-not $unsaved) { return New-KdResult 0 'nothing to save: file already matches the editor' }
    try { (Find-KdSaveButton ($script:KdAE::FromHandle($main.Handle))).GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }
    catch { }   # Invoke blocks until the save ends and may time out; the result is checked below
    $clock = [Diagnostics.Stopwatch]::StartNew()
    while ($clock.Elapsed.TotalSeconds -lt $timeoutSec) {
        Start-Sleep -Milliseconds 400
        foreach ($dialog in @(Get-KdDialogs $main)) {
            if ($dialog.Title -match $script:KdInfoTitle) { [void](Close-KdWindow $dialog) }
            elseif ($clock.Elapsed.TotalSeconds -gt 8) { return New-KdResult 4 "saving is blocked by a dialog: '$($dialog.Title)'" }
        }
        if ((Get-KdUnsaved $main) -eq $false) { return New-KdResult 0 "saved the user's edits to the project file" }
    }
    return New-KdResult 4 "save was not confirmed within $timeoutSec s"
}

# 0 reload CONFIRMED, 2 unsaved edits (nothing done), 3 not running, 4 failed or not confirmed.
function Invoke-KdReload([string]$project, [int]$timeoutSec = 1500) {
    try { $main = Find-KdWindow $project } catch { return New-KdResult 4 $_.Exception.Message }
    if (-not $main) { return New-KdResult 3 'Kdenlive with this project is not running' }
    if (-not (Wait-KdLoaded $main $timeoutSec)) { return New-KdResult 4 "Kdenlive was still loading after $timeoutSec s" }
    $open = @(Get-KdDialogs $main)
    if ($open) { return New-KdResult 4 "a dialog is open in Kdenlive: '$($open[0].Title)'" }
    $unsaved = Wait-KdUnsaved $main $timeoutSec
    if ($null -eq $unsaved) { return New-KdResult 4 'Kdenlive did not say whether it has unsaved edits' }
    if ($unsaved) { return New-KdResult 2 'UNSAVED: the user has unsaved edits; nothing was reloaded' }
    $before = Get-KdTimelineId $main
    if (-not $before) { return New-KdResult 4 'timeline not found, so a reload could not be confirmed' }

    $clock = [Diagnostics.Stopwatch]::StartNew()
    $lastError = ''
    foreach ($attempt in 1..3) {
        $invoked = $false
        $busy = $false
        try {
            $root = $script:KdAE::FromHandle($main.Handle)
            $file = Find-KdFileMenu $root
            if (-not $file) { throw 'File menu not found' }
            $menu = $file.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
            try { $menu.Expand() } catch { $lastError = $_.Exception.Message }
            $item = $null
            for ($i = 0; $i -lt 30 -and -not $item; $i++) {
                Start-Sleep -Milliseconds 200
                $item = Find-KdNamed $file 'Revert'     # inside this menu only
            }
            if (-not $item -or -not $item.Current.IsEnabled) {
                try { $menu.Collapse() } catch { }
                throw 'Revert item not found or disabled'
            }
            # the user may have started editing while the menu was opening
            if ((Get-KdUnsaved $main) -ne $false) {
                try { $menu.Collapse() } catch { }
                return New-KdResult 2 'UNSAVED: the user started editing; nothing was reloaded'
            }
            $invoked = $true
            $item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        } catch {
            $lastError = $_.Exception.Message
            $busy = $invoked   # Invoke times out after about 60 s while a big project is still loading
        }
        if (-not $invoked) { Start-Sleep -Seconds 1; continue }

        # Invoke threw: a load is probably running, so wait and never start a second one on top of it.
        # Invoke returned and nothing changed for 20 s: the click was lost, try again.
        $waitSec = if ($busy) { $timeoutSec } else { 20 }
        $wait = [Diagnostics.Stopwatch]::StartNew()
        $blockedSince = $null
        while ($wait.Elapsed.TotalSeconds -lt $waitSec -and $clock.Elapsed.TotalSeconds -lt $timeoutSec) {
            Start-Sleep -Milliseconds 500
            if (-not (Get-Process -Id $main.ProcessId -ErrorAction SilentlyContinue)) { return New-KdResult 4 'Kdenlive exited during the reload' }
            if (Test-KdLoading $main) {
                # our click worked: wait for the end, never click again and never confirm in the middle
                $busy = $true; $waitSec = $timeoutSec; $blockedSince = $null
                continue
            }
            $dialogs = @(Get-KdDialogs $main)
            if ($dialogs) {
                if ($null -eq $blockedSince) { $blockedSince = $wait.Elapsed.TotalSeconds }
                if ($wait.Elapsed.TotalSeconds - $blockedSince -gt 4) {
                    # The "delete all changes since the last save?" question has Cancel as the close action.
                    # Never confirm it: confirming throws away the user's edits.
                    if ($dialogs[0].Title -match $script:KdRevertTitle) {
                        [void](Close-KdWindow $dialogs[0])
                        return New-KdResult 2 "UNSAVED: cancelled '$($dialogs[0].Title)' to keep the user's edits"
                    }
                    return New-KdResult 4 "reload is blocked by a dialog: '$($dialogs[0].Title)'"
                }
                continue
            }
            $blockedSince = $null
            $now = Get-KdTimelineId $main
            if (-not $now) { $waitSec = $timeoutSec; continue }   # loading
            if ($now -ne $before) {
                $title = [KdNative]::Title($main.Handle)
                if ($title -notmatch (Get-KdTitlePattern $project)) { return New-KdResult 4 "Kdenlive reloaded into another document: '$title'" }
                $note = if ((Get-KdUnsaved $main) -eq $true) { ' (NOTE: Kdenlive changed the document while loading it)' } else { '' }
                return New-KdResult 0 ("reload confirmed in {0:N0} s{1}" -f $clock.Elapsed.TotalSeconds, $note)
            }
        }
        if ($busy -or $clock.Elapsed.TotalSeconds -ge $timeoutSec) { break }
    }
    return New-KdResult 4 ("NOT reloaded or not confirmed after {0:N0} s. {1}" -f $clock.Elapsed.TotalSeconds, $lastError)
}
