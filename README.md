# tclme
TCL malleable environment

Absolutely. I’ll teach you in the context of your Core editor, because that gives you a real plugin API, real UI, and immediate feedback. The goal is not just “make a plugin” — it’s to build the mental model that lets you write *any* plugin.

---

# 1. The mental model of a Core plugin

A plugin is just a Tcl file:

```text
plugins/myplugin.tcl
```

Core loads it into its own namespace:

```tcl
::Core::Plugin::myplugin
```

So if your plugin defines:

```tcl
proc hello {} {
    return "hi"
}
```

the real proc name becomes:

```tcl
::Core::Plugin::myplugin::hello
```

You usually do not need to type that everywhere because Core tracks the current plugin owner and resolves your bare proc names when commands/hooks fire.

A plugin usually does some combination of these:

1. **Defines commands**

   ```tcl
   Core::DefCommand my-command my-proc "Do something"
   ```

2. **Binds keys**

   ```tcl
   Core::BindKey my-command <Control-x><Control-y>
   ```

3. **Listens to events**

   ```tcl
   Core::On after-save MyAfterSaveHandler
   ```

4. **Stores state**

   ```tcl
   variable enabled 1
   variable settings [dict create]
   ```

5. **Cleans up after itself**

   ```tcl
   proc unload {} {
       # destroy widgets, cancel timers, etc.
   }
   ```

---

# 2. The Tcl fundamentals you need first

You do not need to know all of Tcl to start, but these are the core concepts.

## 2.1 Tcl syntax is command-based

Almost everything is:

```tcl
command argument1 argument2 argument3
```

Example:

```tcl
set name "World"
puts "Hello, $name"
```

Important: Tcl performs substitutions **before** the command runs.

For example:

```tcl
set x 5
puts $x
```

`$x` becomes `5`, then `puts` receives `5`.

---

## 2.2 Braces, quotes, and substitution

Braces prevent substitution:

```tcl
puts {$x}      ;# prints literally: $x
puts "$x"      ;# prints: 5
```

Command substitution uses brackets:

```tcl
set now [clock seconds]
puts [clock format $now -format {%Y-%m-%d}]
```

A common beginner mistake is over-substituting or under-substituting.

Rule of thumb:

- Use `{...}` when you want literal code or expressions.
- Use `"..."` when you want variables substituted.
- Use `[...]` when you want the result of another command.

---

## 2.3 Lists

Tcl lists are everywhere.

```tcl
set items [list a b c]
lappend items d
puts [llength $items]
puts [lindex $items 0]

foreach x $items {
    puts $x
}
```

Important:

```tcl
set cmd [list Core::SwitchToBuffer $bufname]
```

is safer than:

```tcl
set cmd "Core::SwitchToBuffer $bufname"
```

because `list` handles spaces and quoting correctly.

---

## 2.4 Dicts

Dicts are the best default data structure for plugin state.

```tcl
variable state [dict create]

dict set state enabled 1
dict set state user:name "Alice"

if {[dict exists $state enabled]} {
    puts [dict get $state enabled]
}

dict unset state enabled
```

You can iterate:

```tcl
dict for {key value} $state {
    puts "$key => $value"
}
```

---

## 2.5 Procs

```tcl
proc add {a b} {
    return [expr {$a + $b}]
}
```

Use `args` to collect extra arguments:

```tcl
proc log-all {args} {
    puts "Got: $args"
}

log-all a b c
```

This matters because Core events often pass arguments, and your callback can absorb them with `args`.

---

## 2.6 Namespaces and `variable`

Inside a plugin, use `variable`, not `global`.

```tcl
variable enabled 1

proc toggle {} {
    variable enabled
    set enabled [expr {!$enabled}]
}
```

Important: `variable enabled` inside a proc links the proc to the namespace variable.

---

## 2.7 Errors

Use `catch` to handle failures:

```tcl
if {[catch {
    set fp [open "does-not-exist" r]
} err]} {
    puts "Failed: $err"
}
```

In Core plugins, log errors like this:

```tcl
if {[catch { do-something } err]} {
    Core::Log error "myplugin: $err"
}
```

---

## 2.8 Tk basics

Tk widgets have path names:

```tcl
button .mybutton -text "Click me" -command { puts clicked }
pack .mybutton
```

Important functions:

```tcl
winfo exists .mybutton
destroy .mybutton
after 1000 { puts "one second later" }
bind .mybutton <Button-1> { puts "left click" }
```

Core’s editor buffers are Tk text widgets.

For a buffer named `foo`, the widget path is usually:

```tcl
.ws.<widget-id>.txt
```

You can get it from Core state:

```tcl
set info [dict get $::Core::buffers $buffer_name]
set wid  [dict get $info wid]
set txt  ".ws.$wid.txt"
```

---

# 3. Your first real plugin: word count

Let’s build a useful plugin from scratch.

It will:

- show word count in the status line
- toggle with `:word-count`
- have alias `:wc`

Create:

```text
plugins/wordcount.tcl
```

Paste this:

```tcl
# plugins/wordcount.tcl
# ============================================================================
#  Word count plugin for Core.
#
#  Adds a word count to the status line.
#  Toggle with :word-count or :wc.
# ============================================================================

variable enabled 1

# ----------------------------------------------------------------------------
#  Helper: get the text widget for a buffer name
# ----------------------------------------------------------------------------
proc WidgetFor {buffer_name} {
    if {![dict exists $::Core::buffers $buffer_name]} {
        return ""
    }

    set info [dict get $::Core::buffers $buffer_name]
    set wid  [dict get $info wid]

    return ".ws.$wid.txt"
}

# ----------------------------------------------------------------------------
#  Count words in a buffer
# ----------------------------------------------------------------------------
proc CountWords {buffer_name} {
    set w [WidgetFor $buffer_name]

    if {$w eq "" || ![winfo exists $w]} {
        return 0
    }

    set text [$w get 1.0 end-1c]

    # Count sequences of non-whitespace characters.
    return [regexp -all {\S+} $text]
}

# ----------------------------------------------------------------------------
#  Status-line contribution
#
#  Core calls this with the current buffer name.
# ----------------------------------------------------------------------------
proc OnStatus {buffer_name} {
    variable enabled

    if {!$enabled} {
        return ""
    }

    if {$buffer_name ne $::Core::current_buffer} {
        return ""
    }

    set count [CountWords $buffer_name]

    return "$count words"
}

# ----------------------------------------------------------------------------
#  Command implementation
# ----------------------------------------------------------------------------
proc cmd-toggle {args} {
    variable enabled

    set enabled [expr {!$enabled}]

    ::Core::RefreshStatus

    if {$enabled} {
        ::Core::Message "Word count enabled"
    } else {
        ::Core::Message "Word count disabled"
    }
}

# ----------------------------------------------------------------------------
#  Registration
# ----------------------------------------------------------------------------

Core::On status-line OnStatus

Core::DefCommand word-count cmd-toggle "Toggle word count in status line"
Core::DefAlias wc word-count
```

Reload it:

```text
:reload wordcount
```

Open a buffer and type some text. You should see something like:

```text
scratch   Ln 3, Col 12   |  42 words
```

Toggle it:

```text
:wc
```

---

# 4. What that plugin teaches you

That small plugin demonstrates almost every major plugin idea.

## 4.1 State

```tcl
variable enabled 1
```

This lives in:

```tcl
::Core::Plugin::wordcount::enabled
```

You can inspect it from the minibuffer:

```text
:eval set ::Core::Plugin::wordcount::enabled
```

---

## 4.2 Reading Core state

We used:

```tcl
$::Core::buffers
$::Core::current_buffer
```

Notice the leading `::`.

Use fully qualified Core variables from plugins:

```tcl
$::Core::buffers
```

Not:

```tcl
$Core::buffers
```

The second form can fail because it may be interpreted relative to your plugin namespace.

---

## 4.3 Event hooks

```tcl
Core::On status-line OnStatus
```

`status-line` is a special event where Core collects strings from all listeners and joins them.

That’s why returning:

```tcl
return "$count words"
```

makes it appear in the status bar.

---

## 4.4 Commands

```tcl
Core::DefCommand word-count cmd-toggle "Toggle word count in status line"
```

This creates:

```text
:word-count
```

The implementation proc receives arguments:

```tcl
proc cmd-toggle {args} {
    ...
}
```

Core’s ex-command parser often passes the remainder as one string, so using `args` is defensive.

---

# 5. Learn the Core event model

Core has three important hook styles.

## 5.1 Fire-and-forget events

Most events are just notifications.

Examples:

```text
buffer-switched
buffer-created
buffer-killed
after-save
after-file-read
theme-changed
cursor-moved
editor-started
```

You register like:

```tcl
Core::On after-save OnAfterSave

proc OnAfterSave {args} {
    set path [lindex $args 0]
    Core::Message "Saved: $path"
}
```

---

## 5.2 Cancelable events

Some events let you veto an action.

Examples:

```text
before-save
before-quit
before-kill-buffer
```

If your hook returns a non-empty string, the action is cancelled.

Example: refuse to save `.bak` files.

Create `plugins/no-bak-save.tcl`:

```tcl
# plugins/no-bak-save.tcl

proc BeforeSave {path} {
    if {[string match "*.bak" $path]} {
        return "Refusing to save .bak files"
    }

    # Empty string means "allow".
    return ""
}

Core::On before-save BeforeSave
```

Reload:

```text
:reload no-bak-save
```

Then try:

```text
:save-as test.bak
```

It should refuse.

---

## 5.3 Collecting events

Some events collect contributions from multiple plugins.

The main one is:

```text
status-line
```

Your wordcount plugin used it.

Another plugin could also return a string, and both would appear.

Example:

```tcl
proc StatusTime {args} {
    return [clock format [clock seconds] -format {%H:%M}]
}

Core::On status-line StatusTime
```

That would add the current time to the status line.

---

# 6. Plugin skeleton to copy

Use this whenever you start a new plugin.

Create `plugins/skeleton.tcl`:

```tcl
# plugins/skeleton.tcl
# ============================================================================
#  Short description of what this plugin does.
# ============================================================================

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------
variable enabled 1

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

proc CurrentWidget {} {
    set w $::Core::active_widget

    if {$w eq "" || ![winfo exists $w]} {
        return ""
    }

    return $w
}

# ---------------------------------------------------------------------------
# Command implementation
# ---------------------------------------------------------------------------

proc cmd-toggle {args} {
    variable enabled

    set enabled [expr {!$enabled}]

    if {$enabled} {
        ::Core::Message "Plugin enabled"
    } else {
        ::Core::Message "Plugin disabled"
    }
}

# ---------------------------------------------------------------------------
# Event handlers
# ---------------------------------------------------------------------------

proc OnBufferSwitched {args} {
    set buffer_name [lindex $args 0]
    # Do something when buffers switch.
}

proc OnAfterSave {args} {
    set path [lindex $args 0]
    # Do something after save.
}

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

proc load {} {
    # Called after the plugin file is sourced.
}

proc unload {} {
    # Called before the plugin namespace is deleted.
    # Cancel timers, destroy widgets, remove manual bindings here.
}

proc save-state {} {
    variable enabled
    return $enabled
}

proc restore-state {saved} {
    variable enabled
    set enabled $saved
}

# ---------------------------------------------------------------------------
# Registration
# ---------------------------------------------------------------------------

Core::On buffer-switched OnBufferSwitched
Core::On after-save      OnAfterSave

Core::DefCommand skeleton cmd-toggle "Toggle skeleton plugin"
Core::DefAlias sk skeleton
```

---

# 7. The most useful Core APIs to memorize

## Commands

```tcl
Core::DefCommand name script "documentation"
Core::DefAlias short full
Core::BindKey command-name "<Control-x><Control-y>"
```

## Messages

```tcl
Core::Message "Temporary minibuffer message"
Core::Note "Status-line note that does not clobber prompts"
Core::Log error "Something failed"
```

## Status

```tcl
Core::RefreshStatus
Core::UpdateStatus "temporary status text"
```

## Events

```tcl
Core::On event-name handler-proc
```

## Prompting

```tcl
Core::Prompt "Label: " MyCallback

proc MyCallback {input} {
    Core::Message "You typed: $input"
}
```

## Buffers

```tcl
$::Core::buffers
$::Core::buffer_order
$::Core::current_buffer
$::Core::active_widget
```

---

# 8. Debugging plugins like an expert

This is where you level up.

## 8.1 Run wish from a terminal

If you launch Core from a terminal, `puts` output is visible:

```tcl
puts "debug: reached here"
puts stderr "error details here"
```

---

## 8.2 Use `:log`

Core logs errors.

```text
:log
```

---

## 8.3 Use `:eval` constantly

Examples:

```text
:eval dict keys $::Core::buffers
:eval dict get $::Core::buffers scratch
:eval set ::Core::current_buffer
:eval info commands ::Core::Plugin::wordcount::*
:eval set ::Core::Plugin::wordcount::enabled
```

This is the fastest way to understand what is happening.

---

## 8.4 Inspect available commands

```text
:eval dict keys $::Core::commands
```

Or:

```text
:help
```

---

## 8.5 Use `catch` while developing

Instead of this:

```tcl
set data [read-some-file $path]
```

Do this while learning:

```tcl
if {[catch {
    set data [read-some-file $path]
} err]} {
    Core::Log error "myplugin read failed: $err"
    return
}
```

For deeper debugging:

```tcl
if {[catch {
    do-dangerous-thing
} err]} {
    Core::Log error "myplugin: $err"
    puts stderr $::errorInfo
}
```

---

# 9. Common beginner mistakes

## Mistake 1: Forgetting `variable`

Bad:

```tcl
proc toggle {} {
    set enabled [expr {!$enabled}]
}
```

Good:

```tcl
proc toggle {} {
    variable enabled
    set enabled [expr {!$enabled}]
}
```

---

## Mistake 2: Using `$var::`

This is dangerous:

```tcl
set cmd "$ns::DoThing"
```

Tcl may parse `$ns::` as a weird variable name.

Use:

```tcl
set cmd "${ns}::DoThing"
```

Or:

```tcl
set cmd [list ${ns}::DoThing $arg]
```

---

## Mistake 3: Callbacks with the wrong number of arguments

If an event passes arguments, your proc must accept them.

If you do not care:

```tcl
proc OnSomething {args} {
    # ignore arguments
}
```

If you want the first argument:

```tcl
proc OnSomething {args} {
    set name [lindex $args 0]
}
```

Or if you know the exact arity:

```tcl
proc OnBufferSwitched {name} {
    ...
}
```

---

## Mistake 4: Assuming widget paths exist

Always check:

```tcl
if {[winfo exists $w]} {
    ...
}
```

---

## Mistake 5: Forgetting cleanup

If your plugin creates widgets, timers, or manual bindings, remove them in `unload`.

Example:

```tcl
proc unload {} {
    variable timer

    if {$timer ne ""} {
        catch { after cancel $timer }
    }

    if {[winfo exists .myplugin]} {
        destroy .myplugin
    }
}
```

---

## Mistake 6: Blocking the UI

Avoid long-running loops.

Use:

```tcl
after 100 ...
after idle ...
```

For expensive work, break it into chunks.

---

# 10. Timers: a pattern you will use often

Suppose you want an autosave plugin.

You need `after`.

Pattern:

```tcl
variable timer ""

proc Start {} {
    Schedule
}

proc Schedule {} {
    variable timer

    if {$timer ne ""} {
        catch { after cancel $timer }
    }

    set ns [namespace current]
    set timer [after 30000 [list ${ns}::Tick]]
}

proc Tick {} {
    # Do work here.
    Core::Message "Autosave tick"

    # Reschedule.
    Schedule
}

proc unload {} {
    variable timer

    if {$timer ne ""} {
        catch { after cancel $timer }
    }
}
```

Notice:

```tcl
[list ${ns}::Tick]
```

That gives you a fully qualified command callback.

---

# 11. UI plugins: the pattern

If you create UI, follow this structure:

```tcl
proc Show {} {
    if {[winfo exists .myplugin]} {
        return
    }

    frame .myplugin -bg [::Core::GetTheme bg]

    label .myplugin.label -text "My Plugin"

    pack .myplugin.label -side left

    if {[winfo exists .ws]} {
        pack .myplugin -fill x -before .ws
    } else {
        pack .myplugin -side top -fill x
    }
}

proc Hide {} {
    if {[winfo exists .myplugin]} {
        destroy .myplugin
    }
}
```

Rules:

1. Check `winfo exists`.
2. Use theme colors.
3. Pack relative to Core widgets carefully.
4. Destroy UI in `unload`.

Your buffer bar plugin follows exactly this pattern.

---

# 12. Text-widget skills you should learn

Since Core is a text editor, becoming strong with the Tk `text` widget is a superpower.

Important concepts:

## Indices

```tcl
1.0
end
end-1c
insert
5.10
insert linestart
insert lineend
```

## Getting text

```tcl
$w get 1.0 end
$w get 1.0 end-1c
$w get insert "insert lineend"
```

## Inserting text

```tcl
$w insert insert "hello"
```

## Deleting text

```tcl
$w delete 1.0 end
```

## Tags

```tcl
$w tag configure warning -foreground red
$w tag add warning 1.0 1.0 lineend
$w tag remove warning 1.0 end
```

## Cursor position

```tcl
$w index insert
```

## Searching

```tcl
$w search -nocase "foo" insert end
```

If you master the Tk text widget, you can build:

- highlighters
- linters
- snippet systems
- diff markers
- code folding
- inline diagnostics
- multiple cursors
- mini IDE features

---

# 13. A practical learning ladder

Here is a good sequence of plugins to make you dangerous.

## Level 1: Hello plugin

Goal: command + message.

Features:

```text
:hello
```

shows:

```text
Hello from my plugin
```

Skills:

- `Core::DefCommand`
- `Core::Message`

---

## Level 2: Word count

You already have this.

Skills:

- status line
- reading buffer text
- toggle state

---

## Level 3: Insert date

Goal:

```text
:insert-date
```

inserts current date/time at cursor.

Skills:

- active widget
- text insertion
- read-only checking

Try this:

```tcl
proc cmd-insert-date {args} {
    set w $::Core::active_widget

    if {$w eq "" || ![winfo exists $w]} {
        return
    }

    if {[$w cget -state] eq "disabled"} {
        ::Core::Message "Buffer is read-only"
        return
    }

    set stamp [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]

    $w insert insert $stamp
    $w edit modified 1
    ::Core::RefreshStatus
}

Core::DefCommand insert-date cmd-insert-date "Insert current date/time at cursor"
```

---

## Level 4: Save guard

Goal: prevent saving certain files.

Skills:

- cancelable hooks
- `before-save`

You already saw the `.bak` example.

Try:

- refuse saving files named `TODO.tmp`
- warn if saving a file larger than 1 MB
- block saving unless file ends with newline

---

## Level 5: Autosave

Goal: save dirty buffers every N seconds.

Skills:

- timers
- iterating buffers
- checking modified state
- avoiding readonly/special buffers

Hint:

```tcl
dict for {name info} $::Core::buffers {
    set txt ".ws.[dict get $info wid].txt"

    if {[winfo exists $txt] && [$txt edit modified]} {
        # save logic
    }
}
```

---

## Level 6: Trailing whitespace highlighter

Goal: highlight trailing spaces.

Skills:

- text tags
- regular expressions
- buffer updates
- debouncing

Hard part:

- do not re-highlight on every keystroke without debouncing

---

## Level 7: Fuzzy buffer switcher

Goal:

```text
:fz
```

prompts and switches to a matching buffer.

Skills:

- `Core::Prompt`
- completion
- filtering
- buffer switching

---

## Level 8: Grep plugin

Goal:

```text
:grep pattern
```

runs external grep/ripgrep and shows results in a buffer.

Skills:

- `exec`
- output buffers
- parsing file:line:text
- opening files from result lines

---

## Level 9: Git branch status

Goal: show current git branch in status line.

Skills:

- `exec git`
- caching
- error handling
- status-line event

---

## Level 10: Project drawer

Goal: file browser sidebar.

Skills:

- tree or list UI
- directory traversal
- opening files
- refresh
- keybindings
- cleanup

This is basically Dired-lite.

---

# 14. The Tcl expert syllabus

If you want to become truly expert, study these deliberately.

## Core language

- `string`
- `list`
- `dict`
- `regexp`
- `array`
- `expr`
- `format`
- `scan`
- `clock`
- `file`
- `glob`
- `exec`
- `namespace`
- `proc`
- `apply`
- `uplevel`
- `upvar`
- `trace`
- `catch`
- `return`
- `error`
- `info`

## Tk

- `bind`
- `bindtags`
- `after`
- `event`
- `focus`
- `grab`
- `pack`
- `grid`
- `place`
- `winfo`
- `wm`
- `text`
- `canvas`
- `ttk`
- virtual events

## Advanced topics

- TclOO
- coroutines
- event loop design
- `chan` and sockets
- `interp` and sandboxes
- `tcltest`
- profiling with `time`
- package management
- safe eval
- Tk text widget internals
- custom widget construction

---

# 15. The expert mindset

The difference between “I can write Tcl” and “I am good at Tcl” is mostly this:

## 1. Build commands as lists

Prefer:

```tcl
set cmd [list ::Core::OpenFile $path]
```

over:

```tcl
set cmd "::Core::OpenFile $path"
```

Lists prevent quoting bugs.

---

## 2. Keep state in dicts

Prefer:

```tcl
variable state [dict create]
```

over lots of scattered variables.

---

## 3. Make handlers tolerant

Use:

```tcl
proc handler {args} {
    ...
}
```

until you know exactly what arguments an event passes.

---

## 4. Make operations idempotent

If your plugin rebuilds UI, it should be safe to call the rebuild function multiple times.

Example:

```tcl
proc Rebuild {} {
    if {![winfo exists .myplugin]} return

    foreach child [winfo children .myplugin] {
        destroy $child
    }

    # recreate children
}
```

---

## 5. Clean up completely

Ask:

- Did I create widgets?
- Did I bind events?
- Did I start timers?
- Did I modify Core state?
- Did I change widget options?
- Did I add tags?
- Did I open files or channels?

If yes, undo it in `unload`.

---

# 16. A strong first assignment for you

Build this plugin:

## Plugin name

```text
charcount
```

## Features

1. Shows character count in status line.
2. Toggle with `:charcount`.
3. Alias `:cc`.
4. Ignores disabled buffers gracefully.
5. Reload-safe.

Start from the wordcount plugin.

You need to change:

```tcl
return [regexp -all {\S+} $text]
```

to something like:

```tcl
return [string length $text]
```

Then decide if you want to count:

- all characters
- visible characters only
- characters excluding newlines

That decision is your first plugin design decision.

---

# 17. A second assignment: combine two counters

Make a plugin called:

```text
stats
```

It shows:

```text
123 words, 845 chars
```

This teaches you:

- combining logic
- status-line composition
- command arguments, maybe:

```text
:stats words
:stats chars
:stats both
```

---

# 18. A third assignment: make it per-buffer

Right now `wordcount` has one global enabled flag.

Make it per-buffer.

Instead of:

```tcl
variable enabled 1
```

Use:

```tcl
variable enabled [dict create]
```

Then:

```tcl
dict set enabled $buffer_name 1
```

Toggle should affect only the current buffer.

This teaches you state modeling — a key expert skill.

---

# 19. How to read man pages effectively

Tcl’s documentation is excellent. Use it like this:

For any command you do not understand, ask:

```text
What does it return?
What arguments does it take?
What happens on error?
What edge cases does it mention?
```

Important man pages to read early:

```text
string
list
dict
regexp
proc
namespace
catch
after
bind
text
```

In a terminal:

```sh
nroc string
nroc dict
nroc text
```

Or use online Tcl/Tk docs.

---

# 20. What “expert” actually looks like

An expert Tcl programmer in your Core environment can:

1. Look at an error and know whether it is:
   - syntax
   - substitution
   - list structure
   - namespace resolution
   - widget state
   - event timing

2. Write plugins that:
   - load cleanly
   - reload cleanly
   - unload cleanly
   - do not leak timers or widgets
   - do not corrupt Core state

3. Use the event system naturally:
   - fire-and-forget
   - veto
   - collect

4. Build UI without fighting Tk:
   - check widget existence
   - pack carefully
   - use themes
   - debounce redraws

5. Debug interactively:
   - `:eval`
   - `:log`
   - `puts`
   - `catch`
   - inspect dicts and namespaces

---

# 21. The shortest path forward

Do this in order:

1. Create `plugins/hello.tcl`.
2. Create `plugins/wordcount.tcl`.
3. Create `plugins/charcount.tcl`.
4. Combine them into `plugins/stats.tcl`.
5. Make stats per-buffer.
6. Add a timer-based feature.
7. Add a UI bar.
8. Add a hook that vetoes something.
9. Add a prompt-based command.
10. Build one plugin you personally miss from another editor.

That last one is the most important.

You become expert fastest when you build the thing you actually want.

If you want, next I can turn this into a structured mini-course: **Lesson 1: your first five Core plugins**, with exercises, expected output, and solutions.
