# Tclme Plugin Cookbook

This cookbook is a practical guide to writing plugins for Tclme.

It is meant to be used while hacking. It contains copy-paste recipes, patterns, warnings, debugging tricks, and full examples.

If your editor still uses the old `Core::` namespace instead of `Tclme::`, substitute `Core::` for `Tclme::` throughout.

---

## Table of Contents

1. [What a Tclme plugin is](#1-what-a-tclme-plugin-is)
2. [Golden rules](#2-golden-rules)
3. [Plugin file skeleton](#3-plugin-file-skeleton)
4. [Creating commands](#4-creating-commands)
5. [Creating aliases](#5-creating-aliases)
6. [Creating keybindings](#6-creating-keybindings)
7. [Listening to events](#7-listening-to-events)
8. [Cancelable hooks](#8-cancelable-hooks)
9. [Contributing to the status line](#9-contributing-to-the-status-line)
10. [Prompting the user](#10-prompting-the-user)
11. [Reading the current buffer](#11-reading-the-current-buffer)
12. [Modifying the current buffer](#12-modifying-the-current-buffer)
13. [Creating special read-only buffers](#13-creating-special-read-only-buffers)
14. [Creating UI panels](#14-creating-ui-panels)
15. [Theme-aware widgets](#15-theme-aware-widgets)
16. [Using timers and debouncing](#16-using-timers-and-debouncing)
17. [Saving and restoring plugin state](#17-saving-and-restoring-plugin-state)
18. [Cleaning up on unload](#18-cleaning-up-on-unload)
19. [Working with text tags](#19-working-with-text-tags)
20. [Searching text](#20-searching-text)
21. [Opening files](#21-opening-files)
22. [Returning focus to the editor](#22-returning-focus-to-the-editor)
23. [Debugging plugins](#23-debugging-plugins)
24. [Common pitfalls](#24-common-pitfalls)
25. [Full example: word count plugin](#25-full-example-word-count-plugin)
26. [Full example: scratch buffer plugin](#26-full-example-scratch-buffer-plugin)
27. [Plugin release checklist](#27-plugin-release-checklist)

---

# 1. What a Tclme plugin is

A Tclme plugin is usually a single file inside:

```text
plugins/
```

Example:

```text
plugins/example.tcl
```

When Tclme loads it, the plugin is sourced into its own namespace:

```tcl
::Tclme::Plugin::example
```

Plugins can register:

- commands
- aliases
- keybindings
- event hooks
- UI panels
- timers
- state
- lifecycle handlers

A good plugin is:

- reload-safe
- unload-safe
- theme-aware
- non-blocking
- defensive about missing widgets
- careful about cleanup

---

# 2. Golden rules

These rules prevent most Tclme plugin bugs.

## Rule 1: Put state in namespace variables

Use:

```tcl
variable enabled 1
```

Inside procs:

```tcl
proc example {} {
    variable enabled
}
```

Avoid global variables unless you have a very good reason.

---

## Rule 2: Use `{*}` and lists for command construction

Prefer:

```tcl
set cmd [list ${ns}::DoThing $arg]
```

over fragile string construction.

---

## Rule 3: Do not write `$ns::`

Dangerous:

```tcl
set callback "$ns::DoThing"
```

Tcl can misparse `$ns::`.

Use:

```tcl
set callback [list ${ns}::DoThing]
```

or:

```tcl
set callback "${ns}::DoThing"
```

---

## Rule 4: Make event handlers accept `args`

Many events pass arguments.

Safe:

```tcl
proc OnBufferSwitched {args} {
    set buffer_name [lindex $args 0]
}
```

---

## Rule 5: Check widget existence

Before using a widget:

```tcl
if {[winfo exists $w]} {
    ...
}
```

---

## Rule 6: Cancel timers on unload

If you create an `after` timer, cancel it in `unload`.

---

## Rule 7: Destroy UI on unload

If your plugin creates:

```text
.example_panel
```

destroy it in `unload`.

---

## Rule 8: Do not block the event loop

Avoid long synchronous operations.

Use:

```tcl
after
fileevent
exec ... &
```

or chunked processing.

---

# 3. Plugin file skeleton

This is a good starting point.

```tcl
# plugins/example.tcl
# ============================================================================
# example.tcl - short description
#
# Commands:
#   :example
#
# Events used:
#   buffer-switched
# ============================================================================

# ----------------------------------------------------------------------------
# State
# ----------------------------------------------------------------------------

variable enabled 1

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

proc CurrentText {} {
    set w $::Tclme::active_widget

    if {$w eq "" || ![winfo exists $w]} {
        return ""
    }

    if {[winfo class $w] ne "Text"} {
        return ""
    }

    return $w
}

# ----------------------------------------------------------------------------
# Commands
# ----------------------------------------------------------------------------

proc cmd-example {args} {
    variable enabled

    set enabled [expr {!$enabled}]

    if {$enabled} {
        ::Tclme::Message "Example enabled"
    } else {
        ::Tclme::Message "Example disabled"
    }
}

# ----------------------------------------------------------------------------
# Events
# ----------------------------------------------------------------------------

proc OnBufferSwitched {args} {
    set buffer_name [lindex $args 0]

    # Do something when buffers switch.
}

# ----------------------------------------------------------------------------
# Lifecycle
# ----------------------------------------------------------------------------

proc load {} {
    # Optional initialization.
}

proc unload {} {
    # Optional cleanup.
}

proc save-state {} {
    variable enabled

    return [dict create enabled $enabled]
}

proc restore-state {saved} {
    variable enabled

    if {[dict exists $saved enabled]} {
        set enabled [dict get $saved enabled]
    }
}

# ----------------------------------------------------------------------------
# Registration
# ----------------------------------------------------------------------------

Tclme::DefCommand example cmd-example "Toggle example plugin"

Tclme::On buffer-switched OnBufferSwitched
```

Reload it:

```text
:reload example
```

Run it:

```text
:example
```

---

# 4. Creating commands

Commands are the main user-facing extension point.

## Basic command

```tcl
proc cmd-hello {args} {
    ::Tclme::Message "Hello from plugin"
}

Tclme::DefCommand hello cmd-hello "Say hello"
```

Now the user can run:

```text
:hello
```

---

## Command with arguments

Tclme usually passes the remainder of the command line as arguments.

```tcl
proc cmd-echo {args} {
    set text [string trim [join $args " "]]

    if {$text eq ""} {
        ::Tclme::Message "Usage: :echo TEXT"
        return
    }

    ::Tclme::Message $text
}

Tclme::DefCommand echo cmd-echo "Echo text"
```

Usage:

```text
:echo hello world
```

---

# 5. Creating aliases

Aliases are shortcuts for commands.

```tcl
Tclme::DefCommand hello cmd-hello "Say hello"

if {[info commands ::Tclme::DefAlias] ne ""} {
    catch { ::Tclme::DefAlias hi hello }
}
```

Now:

```text
:hi
```

means:

```text
:hello
```

---

# 6. Creating keybindings

## Simple binding

```tcl
Tclme::DefCommand hello cmd-hello "Say hello"
Tclme::BindKey hello <Control-x><Control-h>
```

Now:

```text
C-x C-h
```

runs:

```text
:hello
```

---

## Binding with a helper

If you want to be defensive about the bindtag, use a helper.

```tcl
proc GuessBindTag {} {
    set w $::Tclme::active_widget

    if {$w ne "" && [winfo exists $w]} {
        set tags [bindtags $w]

        if {[lsearch -exact $tags TclmeText] >= 0} {
            return "TclmeText"
        }

        if {[lsearch -exact $tags CoreText] >= 0} {
            return "CoreText"
        }
    }

    return "TclmeText"
}

proc BindCommand {cmd keys} {
    set tag [GuessBindTag]

    if {[catch { ::Tclme::BindKey $cmd $keys $tag }]} {
        catch { ::Tclme::BindKey $cmd $keys }
    }
}
```

Then:

```tcl
Tclme::DefCommand hello cmd-hello "Say hello"
BindCommand hello <Control-x><Control-h>
```

---

# 7. Listening to events

Plugins react to editor activity using events.

## Basic event hook

```tcl
proc OnBufferSwitched {args} {
    set buffer_name [lindex $args 0]

    ::Tclme::Message "Switched to: $buffer_name"
}

Tclme::On buffer-switched OnBufferSwitched
```

Common events:

```text
editor-started
buffer-created
buffer-switched
buffer-killed
after-file-read
after-save
before-save
before-quit
cursor-moved
theme-changed
status-line
```

The exact event list depends on your Tclme core.

---

# 8. Cancelable hooks

Some events allow plugins to cancel an action.

Common cancelable events:

```text
before-save
before-quit
before-kill-buffer
```

Example: refuse to save `.bak` files.

```tcl
proc BeforeSave {args} {
    set path [lindex $args 0]

    if {[string match "*.bak" $path]} {
        return "Refusing to save .bak files"
    }

    return ""
}

Tclme::On before-save BeforeSave
```

Returning:

```tcl
""
```

allows the action.

Returning any non-empty string cancels it.

---

# 9. Contributing to the status line

The status line usually uses a collect-style event.

Example:

```tcl
proc OnStatus {args} {
    set buffer_name [lindex $args 0]

    return "example"
}

Tclme::On status-line OnStatus
```

Multiple plugins can contribute to the status line at the same time.

A more realistic example:

```tcl
proc OnStatus {args} {
    variable enabled

    if {!$enabled} {
        return ""
    }

    set buffer_name [lindex $args 0]

    if {$buffer_name ne $::Tclme::current_buffer} {
        return ""
    }

    return "example"
}

Tclme::On status-line OnStatus
```

---

# 10. Prompting the user

Use `Tclme::Prompt` to ask for input.

```tcl
proc cmd-ask-name {args} {
    set ns [namespace current]

    ::Tclme::Prompt "Name: " ${ns}::GotName
}

proc GotName {input} {
    set input [string trim $input]

    if {$input eq ""} {
        ::Tclme::Message "No name given"
        return
    }

    ::Tclme::Message "Hello, $input"
}

Tclme::DefCommand ask-name cmd-ask-name "Ask for a name"
```

Usage:

```text
:ask-name
```

The callback receives the user's input as one argument.

---

# 11. Reading the current buffer

A safe helper for getting the current text widget:

```tcl
proc CurrentText {} {
    set w $::Tclme::active_widget

    if {$w eq "" || ![winfo exists $w]} {
        return ""
    }

    if {[winfo class $w] ne "Text"} {
        return ""
    }

    return $w
}
```

Get all buffer text:

```tcl
proc GetBufferText {} {
    set w [CurrentText]

    if {$w eq ""} {
        return ""
    }

    return [$w get 1.0 end-1c]
}
```

Example command:

```tcl
proc cmd-count-lines {args} {
    set text [GetBufferText]

    if {$text eq ""} {
        ::Tclme::Message "No buffer text"
        return
    }

    set lines [llength [split $text \n]]

    ::Tclme::Message "Lines: $lines"
}

Tclme::DefCommand count-lines cmd-count-lines "Count lines in current buffer"
```

---

# 12. Modifying the current buffer

Before modifying a buffer, check whether it is writable.

```tcl
proc InsertAtCursor {text} {
    set w [CurrentText]

    if {$w eq ""} {
        return
    }

    if {[$w cget -state] eq "disabled"} {
        ::Tclme::Message "Buffer is read-only"
        return
    }

    catch { $w edit separator }

    $w insert insert $text

    catch { $w edit separator }

    catch { ::Tclme::RefreshStatus }
}
```

Example command:

```tcl
proc cmd-insert-date {args} {
    set stamp [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]

    InsertAtCursor $stamp
}

Tclme::DefCommand insert-date cmd-insert-date "Insert current date/time"
```

---

# 13. Creating special read-only buffers

Special buffers are useful for:

- logs
- grep results
- help
- previews
- lists

If your Tclme has `Tclme::ShowInBuffer`, use it.

```tcl
proc ShowTextBuffer {name text} {
    if {[info commands ::Tclme::ShowInBuffer] ne ""} {
        catch { ::Tclme::ShowInBuffer $name $text 1 }
        return
    }

    # Fallback if ShowInBuffer does not exist.
    ::Tclme::SwitchToBuffer $name

    set w $::Tclme::active_widget

    if {$w eq "" || ![winfo exists $w]} {
        return
    }

    $w configure -state normal
    $w delete 1.0 end
    $w insert end $text
    $w edit modified 0
    $w configure -state disabled

    catch {
        upvar #0 ::Tclme::buffers buffers

        if {[dict exists $buffers $name]} {
            dict set buffers $name readonly 1
        }
    }
}
```

Example command:

```tcl
proc cmd-buffer-list {args} {
    set lines {}

    if {[info exists ::Tclme::buffer_order]} {
        foreach b $::Tclme::buffer_order {
            lappend lines $b
        }
    }

    if {[llength $lines] == 0} {
        ShowTextBuffer "*Buffer List*" "(no buffers)"
    } else {
        ShowTextBuffer "*Buffer List*" [join $lines \n]
    }
}

Tclme::DefCommand buffer-list cmd-buffer-list "Show buffer list"
```

---

# 14. Creating UI panels

Panels are frames packed into the main Tclme window.

Good places to pack panels:

```text
-before .sep1     ;# above status line
-before .ws       ;# beside workspace
```

## Basic panel

```tcl
variable visible 0

proc ShowPanel {} {
    variable visible 1

    set ns [namespace current]

    if {[winfo exists .example_panel]} {
        destroy .example_panel
    }

    ::frame .example_panel

    ::label .example_panel.label -text "Example Panel"

    ::button .example_panel.close \
        -text "Close" \
        -command [list ${ns}::HidePanel]

    pack .example_panel.label -side left -padx 4
    pack .example_panel.close -side right -padx 4

    if {[winfo exists .sep1]} {
        pack .example_panel -fill x -before .sep1
    } else {
        pack .example_panel -side bottom -fill x
    }
}

proc HidePanel {} {
    variable visible 0

    if {[winfo exists .example_panel]} {
        destroy .example_panel
    }
}

proc TogglePanel {} {
    variable visible

    if {$visible} {
        HidePanel
    } else {
        ShowPanel
    }
}

proc cmd-example-panel {args} {
    TogglePanel
}

Tclme::DefCommand example-panel cmd-example-panel "Toggle example panel"
```

---

# 15. Theme-aware widgets

Use the Tclme theme where possible.

Helper:

```tcl
proc Theme {key default} {
    if {[catch { set v [::Tclme::GetTheme $key] }]} {
        return $default
    }

    if {$v eq ""} {
        return $default
    }

    return $v
}
```

Apply colors defensively:

```tcl
proc ConfigurePanelColors {} {
    if {![winfo exists .example_panel]} {
        return
    }

    set bg [Theme bg "#E0E0E0"]
    set fg [Theme fg "#222222"]

    catch { .example_panel configure -bg $bg }
    catch { .example_panel.label configure -bg $bg -fg $fg }

    catch {
        .example_panel.close configure \
            -bg $bg \
            -fg $fg
    }
}
```

Listen for theme changes:

```tcl
proc OnTheme {args} {
    ConfigurePanelColors
}

Tclme::On theme-changed OnTheme
```

---

# 16. Using timers and debouncing

Do not run expensive work on every event.

Debounce with `after`.

```tcl
variable job ""

proc ScheduleWork {} {
    variable job

    if {$job ne ""} {
        catch { after cancel $job }
    }

    set ns [namespace current]

    set job [after 250 [list ${ns}::DoWork]]
}

proc DoWork {} {
    variable job ""

    # Expensive work happens here.
}

proc OnCursorMoved {args} {
    ScheduleWork
}

Tclme::On cursor-moved OnCursorMoved
```

Cancel timers on unload:

```tcl
proc unload {} {
    variable job

    if {$job ne ""} {
        catch { after cancel $job }
        set job ""
    }
}
```

---

# 17. Saving and restoring plugin state

Use `save-state` and `restore-state` to survive plugin reloads.

```tcl
variable enabled 1
variable pattern ""

proc save-state {} {
    variable enabled
    variable pattern

    return [dict create \
        enabled $enabled \
        pattern $pattern \
    ]
}

proc restore-state {saved} {
    variable enabled
    variable pattern

    if {[catch { dict size $saved }]} {
        return
    }

    if {[dict exists $saved enabled]} {
        set enabled [dict get $saved enabled]
    }

    if {[dict exists $saved pattern]} {
        set pattern [dict get $saved pattern]
    }
}
```

Prefer dicts for saved state.

---

# 18. Cleaning up on unload

Every plugin should define `unload`.

Good unload checklist:

```text
Destroy panels.
Cancel timers.
Close sockets.
Remove raw bindings.
Remove tags created in buffers, if necessary.
Clear plugin-specific buffer metadata.
```

Example:

```tcl
proc unload {} {
    variable job

    if {$job ne ""} {
        catch { after cancel $job }
        set job ""
    }

    if {[winfo exists .example_panel]} {
        destroy .example_panel
    }
}
```

If your plugin binds shared tags directly, remove those bindings.

Example:

```tcl
proc load {} {
    bind TclmeText <Control-x><Control-e> [list [namespace current]::SomeHandler]
}

proc unload {} {
    catch { bind TclmeText <Control-x><Control-e> {} }
}
```

Prefer `Tclme::BindKey` when possible because the plugin loader can track and remove it.

---

# 19. Working with text tags

Tags are used for highlighting and styling.

## Create tags

```tcl
proc EnsureTags {w} {
    if {![winfo exists $w]} {
        return
    }

    set accent [Theme accent "#4A7CFE"]
    set sep    [Theme separator "#D8D8D8"]

    $w tag configure example_highlight \
        -background $sep

    $w tag configure example_current \
        -background $accent

    $w tag raise example_current
}
```

## Apply tags

```tcl
proc HighlightFirstLine {w} {
    EnsureTags $w

    catch {
        $w tag remove example_highlight 1.0 end
        $w tag add example_highlight 1.0 "1.0 lineend"
    }
}
```

## Remove tags

```tcl
proc ClearTags {w} {
    catch {
        $w tag remove example_highlight 1.0 end
        $w tag remove example_current 1.0 end
    }
}
```

---

# 20. Searching text

Tk text widgets have a built-in search command.

Simple forward search:

```tcl
proc SearchForward {w pattern} {
    if {$w eq "" || ![winfo exists $w]} {
        return ""
    }

    set pattern [string trim $pattern]

    if {$pattern eq ""} {
        return ""
    }

    set pos [$w search -nocase -- $pattern insert+1c end]

    if {$pos eq ""} {
        set pos [$w search -nocase -- $pattern 1.0 end]
    }

    return $pos
}
```

Move to match:

```tcl
proc GotoMatch {w pos} {
    if {$pos eq ""} {
        return
    }

    catch {
        $w mark set insert $pos
        $w see $pos
    }
}
```

---

# 21. Opening files

Use Tclme's file opener if available.

```tcl
proc OpenFileSafely {path} {
    set path [string trim $path]

    if {$path eq ""} {
        ::Tclme::Message "No file given"
        return
    }

    if {[info commands ::Tclme::OpenFile] ne ""} {
        ::Tclme::OpenFile $path
    } else {
        ::Tclme::Message "Tclme::OpenFile is unavailable"
    }
}
```

---

# 22. Returning focus to the editor

If your plugin has entries or buttons, return focus to the text widget when hiding.

```tcl
proc ReturnFocusToText {} {
    set w [CurrentText]

    if {$w eq "" && [info exists ::Tclme::buffers]} {
        set name $::Tclme::current_buffer

        if {$name ne "" && [dict exists $::Tclme::buffers $name]} {
            set info [dict get $::Tclme::buffers $name]
            set candidate ".ws.[dict get $info wid].txt"

            if {[winfo exists $candidate]} {
                set w $candidate
            }
        }
    }

    if {$w ne "" && [winfo exists $w]} {
        catch { focus -force $w }
    }
}
```

Use it in `Hide`:

```tcl
proc HidePanel {} {
    variable visible 0

    if {[winfo exists .example_panel]} {
        destroy .example_panel
    }

    ReturnFocusToText
}
```

---

# 23. Debugging plugins

## Use `:log`

If your Tclme has a log buffer:

```text
:log
```

---

## Use `:eval`

Useful commands:

```text
:eval info commands ::Tclme::*
:eval info commands ::Tclme::Plugin::*
:eval dict keys $::Tclme::buffers
:eval dict keys $::Tclme::commands
:eval set $::Tclme::current_buffer
```

---

## Inspect a plugin proc

```text
:eval info body ::Tclme::Plugin::example::cmd-example
```

---

## Print to stderr

If you launched Tclme from a terminal:

```tcl
puts stderr "debug: reached here"
```

---

## Log errors safely

```tcl
if {[catch {
    risky operation
} err]} {
    catch { ::Tclme::Log error "example: $err" }
}
```

---

# 24. Common pitfalls

## Pitfall 1: `$ns::` misparsing

Bad:

```tcl
set cb "$ns::Handler"
```

Good:

```tcl
set cb [list ${ns}::Handler]
```

---

## Pitfall 2: Duplicate widget paths

Bad:

```tcl
::entry .panel.input
::button .panel.input
```

Good:

```tcl
::entry .panel.entry
::button .panel.button
```

---

## Pitfall 3: Proc argument and variable collision

Bad:

```tcl
proc Connect {host} {
    variable host
}
```

Good:

```tcl
proc Connect {hostname} {
    variable host
    set host $hostname
}
```

---

## Pitfall 4: Regex in double quotes

Often bad:

```tcl
set re "^\\s*proc\\s+([a-zA-Z0-9_:]+)"
```

Usually better:

```tcl
set re {^\s*proc\s+([a-zA-Z0-9_:]+)}
```

---

## Pitfall 5: Forgetting `winfo exists`

Bad:

```tcl
$w configure -state normal
```

Good:

```tcl
if {[winfo exists $w]} {
    $w configure -state normal
}
```

---

## Pitfall 6: Event handler argument mismatch

Bad:

```tcl
proc OnBufferSwitched {} {
    ...
}
```

Good:

```tcl
proc OnBufferSwitched {args} {
    set name [lindex $args 0]
}
```

---

## Pitfall 7: Leaving timers behind

Bad:

```tcl
after 1000 [list DoThing]
```

Good:

```tcl
variable job [after 1000 [list [namespace current]::DoThing]]
```

Then cancel in `unload`.

---

# 25. Full example: word count plugin

This plugin adds a word count to the status line.

Save as:

```text
plugins/wordcount.tcl
```

```tcl
# plugins/wordcount.tcl
# ============================================================================
# wordcount.tcl - show word count in the Tclme status line
#
# Commands:
#   :wordcount
#
# Events used:
#   status-line
# ============================================================================

variable enabled 1

proc CurrentText {} {
    set w $::Tclme::active_widget

    if {$w eq "" || ![winfo exists $w]} {
        return ""
    }

    if {[winfo class $w] ne "Text"} {
        return ""
    }

    return $w
}

proc CountWords {} {
    set w [CurrentText]

    if {$w eq ""} {
        return 0
    }

    set text [$w get 1.0 end-1c]

    return [regexp -all {\S+} $text]
}

proc cmd-toggle {args} {
    variable enabled

    set enabled [expr {!$enabled}]

    catch { ::Tclme::RefreshStatus }

    if {$enabled} {
        ::Tclme::Message "Word count enabled"
    } else {
        ::Tclme::Message "Word count disabled"
    }
}

proc OnStatus {args} {
    variable enabled

    if {!$enabled} {
        return ""
    }

    set buffer_name [lindex $args 0]

    if {$buffer_name ne $::Tclme::current_buffer} {
        return ""
    }

    set n [CountWords]

    return "$n words"
}

proc save-state {} {
    variable enabled

    return [dict create enabled $enabled]
}

proc restore-state {saved} {
    variable enabled

    if {[dict exists $saved enabled]} {
        set enabled [dict get $saved enabled]
    }
}

Tclme::DefCommand wordcount cmd-toggle "Toggle word count in status line"

Tclme::On status-line OnStatus
```

Reload:

```text
:reload wordcount
```

Toggle:

```text
:wordcount
```

---

# 26. Full example: scratch buffer plugin

This plugin adds a quick scratch buffer command.

Save as:

```text
plugins/scratch.tcl
```

```tcl
# plugins/scratch.tcl
# ============================================================================
# scratch.tcl - quick scratch buffer for Tclme
#
# Commands:
#   :scratch
#   :new
# ============================================================================

proc UniqueBufferName {base} {
    if {![info exists ::Tclme::buffers]} {
        return $base
    }

    set buffers $::Tclme::buffers

    set base [string trim $base]

    if {$base eq ""} {
        set base "scratch"
    }

    if {![dict exists $buffers $base]} {
        return $base
    }

    set n 2

    while {[dict exists $buffers "$base<$n>"]} {
        incr n
    }

    return "$base<$n>"
}

proc cmd-scratch {args} {
    if {[info commands ::Tclme::SwitchToBuffer] eq ""} {
        ::Tclme::Message "Tclme::SwitchToBuffer is unavailable"
        return
    }

    ::Tclme::SwitchToBuffer "scratch"
}

proc cmd-new {args} {
    if {[info commands ::Tclme::SwitchToBuffer] eq ""} {
        ::Tclme::Message "Tclme::SwitchToBuffer is unavailable"
        return
    }

    set name [string trim [join $args " "]]

    if {$name eq ""} {
        set name "scratch"
    }

    set target [UniqueBufferName $name]

    ::Tclme::SwitchToBuffer $target

    ::Tclme::Message "New buffer: $target"
}

Tclme::DefCommand scratch cmd-scratch "Switch to scratch buffer"
Tclme::DefCommand new     cmd-new     "Create a new buffer, default scratch"

if {[info commands ::Tclme::DefAlias] ne ""} {
    catch { ::Tclme::DefAlias sc scratch }
    catch { ::Tclme::DefAlias n  new }
}
```

Reload:

```text
:reload scratch
```

Use:

```text
:scratch
:new
:new notes
```

---

# 27. Plugin release checklist

Before considering a plugin finished, check:

## Basic behavior

- [ ] The plugin loads without errors.
- [ ] The plugin reloads without errors.
- [ ] The plugin unloads without errors.
- [ ] Commands appear and work.
- [ ] Keybindings work.
- [ ] Event hooks fire.
- [ ] UI appears and disappears cleanly.

---

## State

- [ ] Plugin state survives reload if intended.
- [ ] Plugin state does not leak after unload.
- [ ] Buffer-specific state is cleaned on `buffer-killed`.

---

## UI

- [ ] Widget paths are unique.
- [ ] Panel destroys on unload.
- [ ] Panel survives repeated show/hide.
- [ ] Theme changes update the panel.
- [ ] Focus returns to the editor when appropriate.

---

## Performance

- [ ] Expensive work is debounced.
- [ ] Large buffers do not freeze the editor.
- [ ] Cursor movement does not trigger heavy scans directly.

---

## Robustness

- [ ] Missing widgets do not crash the plugin.
- [ ] Read-only buffers are respected.
- [ ] Invalid user input is handled politely.
- [ ] Errors are logged, not swallowed silently.

---

## Documentation

- [ ] The plugin file header explains commands.
- [ ] Important keybindings are documented.
- [ ] Known limitations are documented.
- [ ] Any required external tools are documented.

---

## Final rule

A great Tclme plugin is not just one that works once.

It is one that can be:

```text
loaded
used
hidden
shown
reloaded
unloaded
```

without damaging the editor.
```