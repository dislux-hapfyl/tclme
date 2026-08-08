Below is a detailed `ARCHITECTURE.md` you can save in the repository and use as a study document.

```md
# Tclme Architecture

This document describes the architecture of Tclme, a small, hackable, event-driven text editor written in Tcl/Tk.

It is written for humans who want to understand the system, extend it with plugins, refactor it safely, or study it as a long-term programming project.

If your code still uses the old `Core::` namespace instead of `Tclme::`, mentally substitute `Core` for `Tclme`.

---

## 1. Purpose

Tclme is not intended to be a closed, feature-complete editor.

It is intended to be:

```text
A small editor kernel
+ a plugin system
+ a live Tcl/Tk programmable environment
```

The editor should provide only the essential primitives:

- buffers
- text widgets
- file loading/saving
- commands
- keybindings
- events
- minibuffer prompts
- status line
- plugin loading
- theming
- logging

Almost everything else should live in plugins.

Examples of plugin-level features:

- syntax highlighting
- search and replace
- buffer bar
- line numbers
- project grep
- procedure sidebar
- Markdown preview
- tiling
- IRC
- debugger
- Dired-style file browser

---

## 2. Core philosophy

### 2.1 One dispatch system

Keys, minibuffer commands, plugin actions, and user-defined commands should all resolve through the same command registry.

A command is not a special keybinding and not a special menu item.

It is a named callable registered in:

```tcl
::Tclme::commands
```

This keeps the system simple and inspectable.

---

### 2.2 Events over hardcoded features

The kernel should not know about every possible feature.

Instead, it announces what is happening:

```text
buffer-switched
after-save
before-quit
cursor-moved
theme-changed
status-line
```

Plugins decide what to do with those events.

---

### 2.3 Plugins are trusted code

Plugins are not sandboxed.

A plugin can:

- create UI
- bind keys
- define commands
- modify editor state
- open sockets
- read/write files
- rename core procs if it really wants to

This is intentional. Tclme is a personal programmable environment, not a secure plugin store.

---

### 2.4 The editor is a running Tcl interpreter

The running editor is a live Tcl/Tk process.

That means you can inspect and modify it while it runs:

```text
:eval dict keys $::Tclme::buffers
:eval info commands ::Tclme::*
:eval info body ::Tclme::SwitchToBuffer
:log
```

This is one of the most important architectural features.

---

## 3. Repository layout

A typical repository layout looks like this:

```text
tclme/
├── tclme.tcl              # editor kernel
├── ARCHITECTURE.md        # this document
├── Summary.md             # project summary for humans/AI tools
├── plugins/
│   ├── findbar.tcl
│   ├── tclhighlight.tcl
│   ├── bufferbar.tcl
│   ├── dired.tcl
│   ├── linenumbers.tcl
│   ├── proc-sidebar.tcl
│   ├── project-grep.tcl
│   ├── markdown-preview.tcl
│   ├── tiled.tcl
│   ├── debugger.tcl
│   ├── irc.tcl
│   └── openbsd-export.tcl
└── docs/
    ├── PLUGIN-COOKBOOK.md
    ├── ERRORS.md
    └── STUDY-NOTES.md
```

The kernel should remain small.

If a feature can be moved into a plugin, it probably should be.

---

## 4. High-level architecture

```text
+---------------------------------------------------------------+
|                             Tclme                             |
|                                                               |
|  +------------------+       +-----------------------------+   |
|  |   Tclme kernel   |       |          Plugins            |   |
|  |                  |       |                             |   |
|  | buffers          |<----->| findbar                     |   |
|  | commands         | events| tclhighlight                |   |
|  | keybindings      |       | bufferbar                   |   |
|  | minibuffer       |       | dired                       |   |
|  | file I/O         |       | linenumbers                 |   |
|  | event bus        |       | proc-sidebar                |   |
|  | theme            |       | project-grep                |   |
|  | plugin loader    |       | markdown-preview            |   |
|  | status line      |       | tiled                       |   |
|  | logging          |       | debugger                    |   |
|  +------------------+       | irc                         |   |
|           ^                 | openbsd-export              |   |
|           |                 +-----------------------------+   |
|           |                              ^                    |
|           |                              |                    |
|           +------------------------------+                    |
|                   Tcl/Tk widget layer                         |
+---------------------------------------------------------------+
```

The kernel owns the fundamental editor state.

Plugins extend behavior by registering:

- commands
- aliases
- keybindings
- event listeners
- UI panels
- timers
- state

---

## 5. Runtime process model

Tclme runs as a single-threaded Tk event loop.

Important consequences:

1. Long-running synchronous operations block the UI.
2. Network I/O should be event-driven.
3. Expensive UI work should be debounced.
4. Plugins should avoid blocking loops.
5. `after` is the primary timer mechanism.

Examples:

```tcl
after 200 [list ::Tclme::Plugin::findbar::HighlightAll]
```

```tcl
fileevent $sock readable [list ::Tclme::Plugin::irc::OnReadable $sock]
```

---

## 6. Namespace layout

The main namespace is:

```tcl
::Tclme
```

Plugins live under:

```tcl
::Tclme::Plugin::<plugin-name>
```

Example:

```text
plugins/findbar.tcl -> ::Tclme::Plugin::findbar
plugins/irc.tcl     -> ::Tclme::Plugin::irc
plugins/tiled.tcl   -> ::Tclme::Plugin::tiled
```

This gives each plugin a private namespace for:

- procs
- variables
- state
- helper commands

Plugin unload can delete the whole namespace:

```tcl
namespace delete ::Tclme::Plugin::findbar
```

This is one of the reasons plugin code should live inside its plugin namespace.

---

## 7. Important global state

The kernel keeps most important state in namespace variables.

Common variables include:

```tcl
::Tclme::buffers
::Tclme::buffer_order
::Tclme::current_buffer
::Tclme::active_widget
::Tclme::commands
::Tclme::aliases
::Tclme::listeners
::Tclme::plugin_meta
::Tclme::theme
::Tclme::log
```

Not every implementation will have exactly these, but these are the conceptual containers.

---

## 8. Buffer model

A buffer is a named text container.

A buffer is not necessarily a file.

Examples of buffers:

```text
scratch
*Help*
*Log*
grep:pattern
dired:/home/user/src
irc:server
*markdown: README.md*
```

### 8.1 Buffer dictionary

Buffers are usually stored in:

```tcl
::Tclme::buffers
```

Conceptually:

```tcl
buffers = dict

buffer-name -> {
    path     "/full/path/to/file"
    wid      "b7"
    readonly 0
}
```

The `wid` field identifies the widget container for the buffer.

---

### 8.2 Buffer widget paths

Each buffer gets a container frame inside the workspace:

```text
.ws.<wid>
```

Inside that container:

```text
.ws.<wid>.txt
.ws.<wid>.vs
```

Example:

```text
.ws.b3.txt
.ws.b3.vs
```

The text widget is the actual editing surface.

---

### 8.3 Buffer order

Buffer order is stored separately:

```tcl
::Tclme::buffer_order
```

This is a list of buffer names in creation/usage order.

It is useful for:

- buffer switchers
- buffer bars
- next/previous buffer commands
- session restoration

---

### 8.4 Current buffer and active widget

The current buffer name:

```tcl
::Tclme::current_buffer
```

The currently focused text widget:

```tcl
::Tclme::active_widget
```

Plugins should usually prefer:

```tcl
set w [CurrentText]
```

where `CurrentText` is a helper that verifies the widget exists and is a text widget.

---

## 9. Command registry

Commands are stored in:

```tcl
::Tclme::commands
```

Each command entry usually contains:

```tcl
script
doc
owner
keys
```

Example conceptual entry:

```tcl
find -> {
    script cmd-find
    doc    "Open search/replace panel"
    owner  findbar
    keys   <Control-f>
}
```

---

### 9.1 Defining commands

Plugins define commands like this:

```tcl
Tclme::DefCommand find cmd-find "Open search/replace panel"
```

The implementation proc is usually in the plugin namespace:

```tcl
proc cmd-find {args} {
    ...
}
```

When the command is invoked, Tclme qualifies the proc using the plugin owner.

---

### 9.2 Command invocation

Commands can be invoked from:

- minibuffer:

```text
:find
```

- keybindings
- other Tcl code
- plugin UI buttons
- plugin hooks

Internally, command invocation goes through something equivalent to:

```tcl
Tclme::Invoke find
```

---

### 9.3 Aliases

Aliases are alternate names for commands.

Example:

```tcl
Tclme::DefAlias f find
```

Now:

```text
:f
```

means:

```text
:find
```

Aliases should be tracked so plugin unload can remove them.

---

## 10. Keybinding model

Keybindings are Tk bindings installed on a shared bindtag.

Common bindtag names:

```text
TclmeText
CoreText
```

Newer Tclme code should prefer:

```text
TclmeText
```

Text widgets are usually given bindtags like:

```tcl
bindtags $txt [list $txt TclmeText Text [winfo toplevel $txt] all]
```

This means:

1. widget-specific bindings run first
2. shared editor bindings run next
3. Tk Text class bindings run after that
4. toplevel and all bindings run last

---

### 10.1 Binding commands

A keybinding usually invokes a command:

```tcl
Tclme::BindKey find <Control-f>
```

This creates a binding similar to:

```tcl
bind TclmeText <Control-f> {
    Tclme::Invoke find
    break
}
```

The `break` prevents further bindings from also handling the key.

---

### 10.2 Plugin-specific widget bindings

Plugins may also bind directly to widgets they create.

Example from findbar:

```tcl
bind $find_entry <Return> [list ${ns}::FindNext]
```

These bindings disappear when the widget is destroyed.

However, if a plugin binds shared tags such as:

```tcl
TclmeText
```

or global widgets, it must clean those bindings during unload.

---

## 11. Minibuffer model

The minibuffer is the small input line at the bottom of the editor.

It handles:

- messages
- prompts
- ex-style commands

Conceptually:

```text
.status
.minibar.prompt
.minibar.entry
```

---

### 11.1 Messages

Display temporary text:

```tcl
Tclme::Message "Saved file"
```

Messages usually appear in the minibuffer.

If a prompt is active, a well-behaved kernel should avoid destroying prompt input. Some implementations use `Tclme::Note` for non-destructive status notes.

---

### 11.2 Prompts

Prompt the user for input:

```tcl
Tclme::Prompt "Open: " ::Tclme::OpenFile
```

The callback receives the user's input as an argument.

Example:

```tcl
proc GotInput {input} {
    Tclme::Message "You typed: $input"
}

Tclme::Prompt "Enter something: " GotInput
```

Prompts can optionally use completers.

---

### 11.3 Ex-style commands

If the minibuffer input starts with `:`, it is treated as a command.

Examples:

```text
:find
:write
:edit tclme.tcl
:search foo
```

The parser usually extracts the first word as the command name and passes the remainder as arguments.

---

## 12. Event bus

The event bus is one of the central extension mechanisms.

Plugins subscribe with:

```tcl
Tclme::On event-name handler-proc
```

Example:

```tcl
Tclme::On after-save MyAfterSaveHandler
```

---

### 12.1 Listener storage

Listeners are usually stored in:

```tcl
::Tclme::listeners
```

Conceptually:

```tcl
listeners = dict

event-name -> list of listener entries
```

Each listener entry contains:

```text
priority
callback
owner
```

Example:

```tcl
after-save -> {
    {50 ::Tclme::Plugin::findbar::OnAfterSave findbar}
    {50 ::Tclme::Plugin::tclhighlight::OnAfterSave tclhighlight}
}
```

Listeners are usually sorted by priority before execution.

Lower numbers run earlier. Default priority is commonly `50`.

---

### 12.2 Event categories

There are three broad event categories.

---

#### Normal events

Fire-and-forget.

Examples:

```text
buffer-switched
buffer-created
buffer-killed
after-save
after-file-read
cursor-moved
theme-changed
editor-started
```

Return values are ignored.

---

#### Cancelable events

Used for veto-style hooks.

Examples:

```text
before-save
before-quit
before-kill-buffer
```

A handler can cancel the action by returning a non-empty string.

Example:

```tcl
proc BeforeSave {path} {
    if {[string match *.bak $path]} {
        return "Refusing to save .bak files"
    }

    return ""
}

Tclme::On before-save BeforeSave
```

Empty string means allow.

Non-empty string means cancel and usually display the message.

---

#### Collect events

Used when multiple plugins contribute values.

The main example is:

```text
status-line
```

Each handler can return a string. The kernel collects and joins them.

Example:

```tcl
proc StatusContrib {buffer_name} {
    return "tcl"
}

Tclme::On status-line StatusContrib
```

The status line may show:

```text
scratch  Ln 10, Col 4  |  tcl  123 words
```

where different plugins contributed different parts.

---

## 13. Plugin loader

Plugins are usually loaded from:

```text
plugins/
```

Each plugin file name determines the plugin name.

Example:

```text
plugins/findbar.tcl -> findbar
```

The plugin is sourced inside:

```tcl
::Tclme::Plugin::findbar
```

---

### 13.1 Plugin metadata

The kernel tracks plugin registrations in:

```tcl
::Tclme::plugin_meta
```

Conceptually:

```tcl
plugin_meta = dict

plugin-name -> {
    file     "/path/to/plugins/findbar.tcl"
    commands {find search find-replace}
    aliases  {f fr}
    binds    {{TclmeText <Control-f>}}
    hooks    {{status-line ::Tclme::Plugin::findbar::StatusHandler}}
}
```

This allows unload to remove what the plugin registered.

---

### 13.2 Plugin load order

A typical plugin load sequence is:

```text
1. create namespace
2. set current plugin owner
3. source plugin file
4. restore saved plugin state, if any
5. call plugin load proc, if defined
```

The exact order can vary slightly by implementation, but the important idea is:

```text
source file -> registrations happen -> lifecycle hooks run
```

---

### 13.3 Plugin unload order

A typical plugin unload sequence is:

```text
1. call plugin unload proc, if defined
2. remove commands
3. remove aliases
4. remove keybindings
5. remove event hooks
6. cancel tracked after callbacks, if supported
7. delete plugin namespace
8. remove plugin metadata
```

Plugins that create raw UI, raw bindings, raw sockets, or raw timers must clean those up in their own `unload` proc.

---

### 13.4 Optional lifecycle procs

Plugins may define:

```tcl
proc load {} {
    # called after plugin is loaded
}

proc unload {} {
    # called before plugin namespace is deleted
}

proc save-state {} {
    # return state to preserve across reload
    return $some_state_dict
}

proc restore-state {saved} {
    # restore state returned by save-state
}
```

These are optional but strongly recommended for nontrivial plugins.

---

## 14. Plugin state model

Plugin state should usually live in namespace variables.

Good:

```tcl
variable visible 0
variable pattern ""
variable options [dict create]
```

Inside procs:

```tcl
proc example {} {
    variable visible
    variable pattern
}
```

Avoid using global variables unless absolutely necessary.

---

### 14.1 State ownership

Every piece of plugin state should have an owner.

Ask:

```text
Who creates it?
Who reads it?
Who mutates it?
Who destroys it?
```

If you cannot answer these questions, the plugin design is incomplete.

---

### 14.2 Reload-safe state

If a plugin has state that should survive reload, implement:

```tcl
proc save-state {} {
    variable visible
    variable pattern

    return [dict create visible $visible pattern $pattern]
}

proc restore-state {saved} {
    variable visible
    variable pattern

    if {[dict exists $saved visible]} {
        set visible [dict get $saved visible]
    }

    if {[dict exists $saved pattern]} {
        set pattern [dict get $saved pattern]
    }
}
```

State should usually be a dict.

---

## 15. UI architecture

Tclme uses Tk widgets.

The main layout usually looks like this:

```text
+---------------------------------------------------------------+
|                        workspace .ws                          |
|                                                               |
|                                                               |
|                                                               |
|                                                               |
+---------------------------------------------------------------+
|                         separator .sep1                       |
+---------------------------------------------------------------+
|                         status .status                        |
+---------------------------------------------------------------+
|                         separator .sep2                       |
+---------------------------------------------------------------+
|                       minibuffer .minibar                     |
+---------------------------------------------------------------+
```

Plugins may add panels.

Examples:

```text
.findbar
.proc_sidebar
.debugger
.irc
.bufferbar
```

---

## 16. Geometry management rules

Tclme generally uses `pack`.

Plugins should not mix `pack` and `grid` inside the same parent container.

---

### 16.1 Bottom panels

Bottom panels are often packed before the status separator:

```tcl
pack .findbar -fill x -before .sep1
```

This puts the panel above the status line.

---

### 16.2 Sidebars

Sidebars are often packed before the workspace:

```text
pack .proc_sidebar -side left -fill y -before .ws
```

This puts the sidebar to the left of the main editing area.

---

### 16.3 Destroy on unload

If a plugin creates a panel:

```tcl
.findbar
```

it should destroy it on unload:

```tcl
if {[winfo exists .findbar]} {
    destroy .findbar
}
```

Otherwise stale UI can remain after reload.

---

## 17. Text widget architecture

The Tk text widget is the heart of the editor.

Important concepts:

- indices
- marks
- tags
- selection
- scroll view
- edit modified flag
- state normal/disabled

---

### 17.1 Important indices

```text
1.0
end
end-1c
insert
insert linestart
insert lineend
insert wordstart
insert wordend
```

`end-1c` is commonly used to get buffer contents without the implicit final newline.

```tcl
set text [$w get 1.0 end-1c]
```

---

### 17.2 Tags

Tags are used for styling and interaction.

Examples:

```text
find_all
find_current
hl_comment
hl_string
hl_keyword
grep_match
md_h1
md_bold
```

Tags can configure:

```tcl
-font
-foreground
-background
-underline
-spacing1
-spacing3
-lmargin1
-lmargin2
```

Tag priority matters.

If two tags set the same option, the higher-priority tag wins.

---

### 17.3 Marks

The main mark is:

```text
insert
```

Move it:

```tcl
$w mark set insert 10.0
$w see insert
```

---

### 17.4 Read-only buffers

Special buffers are often made read-only by setting:

```tcl
$w configure -state disabled
```

and marking the buffer metadata readonly:

```tcl
dict set ::Tclme::buffers $bufname readonly 1
```

Search plugins should still be able to search read-only buffers, but replace plugins must refuse to modify them.

---

## 18. File I/O model

Opening and saving files are core operations.

Conceptual flow for opening:

```text
user asks to open file
-> normalize path
-> find existing buffer for path, if any
-> create/switch buffer
-> read file contents
-> insert into text widget
-> clear modified flag
-> emit after-file-read
```

Conceptual flow for saving:

```text
user asks to save
-> emit before-save
-> if canceled, stop
-> write text widget contents to disk
-> clear modified flag
-> update buffer path
-> emit after-save
```

---

## 19. Status line architecture

The status line is composed from:

- buffer name
- dirty flag
- cursor position
- file path
- plugin contributions

Plugin contributions come through:

```text
status-line
```

collect events.

Example:

```tcl
proc OnStatus {buffer_name} {
    return "tcl"
}

Tclme::On status-line OnStatus
```

Multiple plugins may contribute.

---

## 20. Theme architecture

Theme values are stored in a dict.

Common keys:

```text
bg
fg
editor_bg
editor_fg
status_bg
status_fg
minibuf_bg
minibuf_fg
accent
separator
scrollbar
cursor
font
status_font
```

Plugins should not hardcode colors if possible.

Use:

```tcl
Tclme::GetTheme accent
Tclme::GetTheme editor_bg
```

When the theme changes, the kernel emits:

```text
theme-changed
```

Plugins with custom UI should listen to this event and reconfigure their widgets.

---

## 21. Logging and error handling

Errors should not disappear silently.

Kernel code and plugin code should use:

```tcl
Tclme::Log error "message"
```

The log can be viewed with:

```text
:log
```

Plugins should wrap risky operations:

```tcl
if {[catch {
    dangerous operation
} err]} {
    Tclme::Log error "findbar: $err"
}
```

Useful debugging variables:

```tcl
$::errorInfo
```

Useful debugging commands:

```text
:eval info commands ::Tclme::*
:eval dict keys $::Tclme::buffers
:eval info body ::Tclme::Plugin::findbar::BuildUI
```

---

## 22. Control flow: startup

Typical startup sequence:

```text
1. Define Tclme namespace variables
2. Define core helper procs
3. Build UI
4. Create scratch buffer
5. Load plugins
6. Load user init file
7. Emit editor-started
```

Important idea:

Plugins load after the basic UI exists, so they can safely create panels and bind keys.

---

## 23. Control flow: keypress

Example: user presses:

```text
C-s
```

Sequence:

```text
1. Tk delivers event to text widget bindtags
2. TclmeText binding fires
3. Binding calls Tclme::Invoke search
4. Command registry finds search command
5. Command implementation runs
6. Plugin or core action happens
7. Status line may refresh
8. Event hooks may fire
```

If the command opens a panel, the panel may take focus.

---

## 24. Control flow: minibuffer command

User types:

```text
:find foo
```

Sequence:

```text
1. Minibuffer Return handler runs
2. Input begins with ':'
3. Parser extracts command name: find
4. Parser extracts arguments: foo
5. Tclme::Invoke find foo
6. find command implementation runs
7. Panel opens and searches for foo
```

---

## 25. Control flow: opening a file

User runs:

```text
:edit README.md
```

Sequence:

```text
1. edit command receives filename
2. Tclme::OpenFile is called
3. Path is normalized
4. Existing buffer for path is checked
5. Buffer is created if needed
6. Buffer is switched
7. File is read
8. Text widget contents are replaced
9. Modified flag is cleared
10. after-file-read event fires
```

Plugins may respond to `after-file-read`.

Examples:

- syntax highlighter highlights file
- line numbers refresh
- project grep refreshes if needed
- findbar live highlight updates

---

## 26. Control flow: saving a file

User runs:

```text
:write
```

Sequence:

```text
1. write command runs
2. Current buffer path is checked
3. If no path, prompt Save As
4. before-save event fires
5. If canceled, stop
6. Text widget contents are written
7. Modified flag is cleared
8. Buffer path metadata is updated
9. after-save event fires
10. Status line refreshes
```

Plugins can veto save:

```text
before-save
```

Plugins can react after save:

```text
after-save
```

---

## 27. Control flow: switching buffers

User runs:

```text
:switch scratch
```

Sequence:

```text
1. switch command runs
2. Tclme::SwitchToBuffer is called
3. Buffer exists or is created
4. Current widget container is hidden
5. Target buffer container is packed
6. current_buffer is updated
7. active_widget is updated
8. Focus moves to text widget
9. Status line refreshes
10. buffer-switched event fires
```

Plugins respond:

- bufferbar highlights current buffer button
- line numbers refresh
- proc sidebar refreshes
- findbar may refresh highlights
- tiled plugin may relayout

---

## 28. Control flow: killing a buffer

User runs:

```text
:kill
```

Sequence:

```text
1. kill command runs
2. before-kill-buffer event fires
3. If canceled, stop
4. If buffer is dirty, confirm with user
5. Remove buffer metadata
6. Emit buffer-killed
7. Destroy widget container
8. Switch to another buffer if needed
```

Plugins should clean buffer-specific state on `buffer-killed`.

---

## 29. Control flow: plugin reload

User runs:

```text
:reload findbar
```

Typical sequence:

```text
1. Save plugin state
2. Call plugin unload proc
3. Remove plugin commands
4. Remove plugin aliases
5. Remove plugin bindings
6. Remove plugin hooks
7. Delete plugin namespace
8. Load plugin file again
9. Call plugin load proc
10. Restore plugin state
```

This is why plugins must clean up after themselves.

If a plugin leaves behind:

- widgets
- bindings
- after callbacks
- sockets
- renamed core procs
- global variables

then repeated reloads will eventually break the editor.

---

## 30. Plugin design rules

These rules are important for maintaining Tclme over time.

---

### 30.1 Every plugin should be reload-safe

Reload should not leak state.

If a plugin creates it, the plugin should know how to destroy it.

---

### 30.2 Every plugin should be disable-safe

If the plugin is unloaded, the editor should continue working.

No command should refer to deleted procs.

No binding should point to nonexistent callbacks.

No panel should remain if it cannot function.

---

### 30.3 Expensive operations should be debounced

Bad:

```tcl
Tclme::On cursor-moved HeavyFullBufferScan
```

Better:

```tcl
Tclme::On cursor-moved ScheduleHeavyScan

proc ScheduleHeavyScan {args} {
    variable after_id

    if {$after_id ne ""} {
        catch { after cancel $after_id }
    }

    set after_id [after 250 [namespace current]::HeavyFullBufferScan]
}
```

---

### 30.4 Plugins should not block the event loop

If an operation might take more than a few milliseconds, consider:

- chunking with `after`
- using external commands asynchronously
- using sockets with `fileevent`
- showing progress
- allowing cancellation

---

### 30.5 Plugins should not assume focus

A plugin should usually operate on:

```tcl
::Tclme::active_widget
```

or the current buffer, not whatever widget currently has keyboard focus.

---

### 30.6 Plugins should respect read-only buffers

Search and inspection are usually allowed.

Modification should check:

```tcl
$w cget -state
```

and/or:

```tcl
dict get $::Tclme::buffers $bufname readonly
```

---

## 31. Common plugin patterns

### 31.1 Panel plugin

Examples:

- findbar
- debugger
- IRC
- proc sidebar

Pattern:

```text
Show:
    build UI if needed
    pack panel
    configure colors
    refresh content

Hide:
    cancel timers
    destroy panel
    return focus if appropriate

Reload:
    save state
    destroy UI
    reload
    restore state
```

---

### 31.2 Buffer decoration plugin

Examples:

- line numbers
- syntax highlighting

Pattern:

```text
listen to buffer-switched
listen to after-file-read
listen to cursor-moved or text-change events
debounce refresh
modify text widget tags
clean tags on unload
```

---

### 31.3 Results-buffer plugin

Examples:

- project grep
- proc sidebar navigation
- debugger log
- Markdown preview

Pattern:

```text
create special buffer
insert generated text
make buffer read-only
bind navigation keys inside buffer
store metadata per buffer
clean metadata on buffer-killed
```

---

### 31.4 Network plugin

Examples:

- IRC

Pattern:

```text
open socket asynchronously
use fileevent readable
read line-by-line
parse protocol
append output to panel or buffer
send user input
clean socket on unload
```

---

## 32. Case study: findbar plugin

The findbar plugin is a good reference plugin because it combines many architectural concerns.

It has:

- UI panel
- text widget tags
- command registration
- keybindings
- debounced live highlighting
- current-buffer awareness
- theme support
- focus management
- reload-safe state

---

### 32.1 Responsibilities

The findbar plugin provides:

```text
:find
:search
:find-replace
```

It also binds keys such as:

```text
C-s
C-f
C-r
```

---

### 32.2 State

Important state includes:

```tcl
pattern
replacement
ignore_case
whole_word
use_regexp
wrap
current_start
current_end
last_widget
last_pattern
```

---

### 32.3 UI widgets

```text
.findbar
.findbar.status
.findbar.optrow
.findbar.findrow
.findbar.replrow
.findbar.findrow.pattern
.findbar.replrow.entry
```

---

### 32.4 Search flow

```text
user types pattern
-> live highlight scheduled
-> user presses Return
-> FindNext runs
-> pattern compiled into regex
-> text widget searched
-> match tagged find_current
-> cursor moved
-> status updated
```

---

### 32.5 Replace flow

```text
user presses Replace
-> current match located
-> replacement computed
-> text deleted/inserted
-> current match cleared
-> next match found
```

Replace All:

```text
build regex
read full buffer
regsub all matches
replace full buffer text
clear highlights
report count
```

---

## 33. Case study: tclhighlight plugin

The syntax highlighter demonstrates text tags and event-driven refresh.

Responsibilities:

- detect whether buffer is Tcl
- tokenize text
- apply tags
- update on buffer switch
- update after file read
- update on text changes, debounced
- respond to theme changes

Important tags:

```text
hl_comment
hl_string
hl_keyword
hl_variable
hl_number
hl_brace
hl_subst
hl_procname
```

Important design constraint:

Highlighting large buffers can be expensive. The plugin should debounce and avoid rescanning unnecessarily.

---

## 34. Case study: proc-sidebar plugin

The proc sidebar demonstrates parsing and navigation.

Responsibilities:

- scan current buffer for proc definitions
- display list in sidebar
- filter list live
- jump to definition
- refresh on buffer switch
- refresh on save
- preserve visibility across reload

Important state:

```text
procs
display_entries
filter
sort_by_name
visible
```

Important architectural lesson:

The sidebar does not own the text buffer. It only derives a view from it.

---

## 35. Case study: project-grep plugin

The project grep plugin demonstrates batch processing and results buffers.

Responsibilities:

- choose source directory
- recursively scan files
- search for pattern
- produce results buffer
- allow jump to match
- clean line endings for export tools, if relevant

Important state:

```text
results buffer -> source directory
results buffer -> match metadata
```

Important architectural lesson:

Do not parse the visible results buffer if you can store structured metadata instead.

For example, store:

```tcl
match -> {file line text}
```

Then use the line number in the results buffer as an index into that metadata.

---

## 36. Case study: Markdown preview plugin

The Markdown preview plugin demonstrates rendering text into styled Tk text.

Responsibilities:

- read Markdown source buffer
- parse blocks
- parse inline formatting
- insert styled text into preview buffer
- make preview buffer read-only
- refresh on demand

Important architectural lesson:

Rendering is a transformation from source text to styled view text.

The source buffer and preview buffer are separate.

---

## 37. Case study: tiled plugin

The tiling plugin demonstrates window layout management.

Responsibilities:

- show multiple buffers at once
- split horizontally/vertically
- focus panes
- close panes
- survive buffer switching
- clean up on unload

Important architectural risk:

Tiling often requires wrapping or modifying core buffer-switch behavior.

Any plugin that wraps core behavior must be careful about:

- reload order
- multiple wrappers
- restoring original behavior on unload
- not breaking other plugins

Tiling is one of the most architecturally dangerous plugins because it changes the fundamental visibility model of buffers.

---

## 38. Case study: IRC plugin

The IRC plugin demonstrates event-driven network I/O.

Responsibilities:

- open socket
- handle connection asynchronously
- parse IRC lines
- respond to PING
- display messages
- send user input
- handle TLS optionally
- clean socket on unload

Important architectural lesson:

Network code must never block the Tk event loop.

Use:

```tcl
socket -async
fileevent
after
```

---

## 39. Kernel/plugin boundary

The kernel should own:

```text
buffers
basic file operations
command registry
event bus
plugin loader
minibuffer
status line
theme
logging
```

Plugins should own:

```text
feature-specific commands
feature-specific UI
feature-specific state
feature-specific hooks
feature-specific timers
```

If a plugin needs something from the kernel, prefer:

1. existing command
2. existing event
3. existing variable read
4. small kernel helper
5. last resort: wrapper/patch

Avoid making plugins depend on internal implementation details unless necessary.

---

## 40. Invariants

These are architectural invariants worth preserving.

---

### 40.1 There is one active buffer

At any time:

```tcl
::Tclme::current_buffer
```

names the active buffer.

Plugins may display other buffers, but the core editing focus should still have a single current buffer.

---

### 40.2 Each buffer has one primary text widget

A buffer may be displayed in multiple places in the future, but the simple model is:

```text
one buffer -> one text widget
```

This makes state management much easier.

---

### 40.3 Commands are the stable user-facing API

Keybindings may change.

UI may change.

Commands should remain stable.

Examples:

```text
:find
:write
:edit
:kill
:bufferbar
:project-grep
```

---

### 40.4 Events are the stable plugin API

Plugins should prefer events over reaching into internals.

Events express intent:

```text
after-save
buffer-switched
before-quit
```

They are easier to preserve across refactors.

---

### 40.5 Plugin unload must restore the editor

After unloading a plugin:

- its commands should be gone
- its aliases should be gone
- its bindings should be gone
- its hooks should be gone
- its UI should be gone
- its timers should be canceled
- its sockets should be closed
- its namespace should be deleted

If any of these remain, the plugin is not unload-safe.

---

## 41. Important Tcl concepts used by Tclme

To understand Tclme deeply, you need to understand these Tcl/Tk concepts.

---

### 41.1 Commands and arguments

Everything is a command:

```tcl
command arg1 arg2 arg3
```

---

### 41.2 Substitution

Tcl performs substitution before commands run.

Important forms:

```tcl
$variable
[command]
"double quotes"
{braces}
```

Many Tcl bugs are substitution bugs.

---

### 41.3 Lists

Lists are used everywhere:

```tcl
set items [list a b c]
lappend items d
foreach x $items { ... }
```

Command arguments are often lists.

The `{*}` operator expands a list into words:

```tcl
{*}$list
```

---

### 41.4 Dicts

Dicts are the preferred state container.

```tcl
dict set state key value
dict get $state key
dict exists $state key
dict unset state key
dict for {k v} $state { ... }
```

---

### 41.5 Namespaces

Plugins live in namespaces.

```tcl
namespace eval ::Tclme::Plugin::example {
    variable enabled 1

    proc hello {} {
        variable enabled
    }
}
```

Inside a proc, use:

```tcl
variable name
```

not:

```tcl
global name
```

---

### 41.6 `uplevel` and `upvar`

These are powerful but dangerous.

Use them carefully.

They are common in command dispatch and variable tracing.

---

### 41.7 Tk bindtags

Understanding bindtags is essential for keybinding behavior.

```tcl
bindtags $w
```

Order matters.

---

### 41.8 `after`

`after` is used for timers and debouncing.

```tcl
after 200 [list SomeProc]
```

Cancel:

```tcl
after cancel $id
```

---

## 42. Common pitfalls

### 42.1 `$var::` parsing bug

Dangerous:

```tcl
set cmd "$ns::DoThing"
```

Tcl may misparse `$ns::`.

Use:

```tcl
set cmd [list ${ns}::DoThing]
```

or:

```tcl
set cmd "${ns}::DoThing"
```

---

### 42.2 Proc argument and variable collision

Dangerous:

```tcl
proc example {host} {
    variable host
}
```

This can fail because the proc argument `host` already exists.

Use different names:

```tcl
proc example {hostname} {
    variable host
    set host $hostname
}
```

---

### 42.3 Regex in double quotes

Dangerous:

```tcl
set re "^\\s*proc\\s+([^[:space:]]+)"
```

Often safer:

```tcl
set re {^\s*proc\s+([^[:space:]]+)}
```

Braces prevent Tcl from interpreting brackets and backslashes too early.

---

### 42.4 Widget path collisions

Dangerous:

```tcl
entry .panel.replace
button .panel.replace
```

Widget paths must be unique.

Use:

```tcl
entry .panel.replace_entry
button .panel.replace_button
```

or:

```tcl
entry .panel.entry
button .panel.replace
```

---

### 42.5 Forgetting cleanup

If a plugin creates:

```tcl
after 1000 ...
bind TclmeText <Key> ...
socket ...
frame .panel
```

it must clean them up.

---

### 42.6 Blocking the UI

Avoid:

```tcl
exec long-running-command
```

without asynchronous handling.

Prefer:

```tcl
exec ... &
```

or socket/fileevent mechanisms, or chunked processing.

---

## 43. Debugging architecture

Useful debugging entry points:

```text
:log
:eval
```

Useful introspection:

```tcl
info commands
info procs
info args
info body
info vars
info exists
info level
info frame
```

Useful state inspection:

```tcl
dict keys $::Tclme::buffers
dict get $::Tclme::buffers $::Tclme::current_buffer
dict keys $::Tclme::commands
dict keys $::Tclme::listeners
```

Useful widget inspection:

```tcl
winfo exists .findbar
winfo children .findbar
bindtags $::Tclme::active_widget
```

---

## 44. How to trace a bug

A good debugging loop in Tclme:

```text
1. Reproduce the bug
2. Open :log
3. Identify the command or event involved
4. Inspect relevant state with :eval
5. Add temporary puts or Tclme::Log messages
6. Reduce to a minimal plugin or command
7. Fix
8. Add a note to docs/ERRORS.md
```

Example questions:

```text
Is the command registered?
Is the keybinding installed?
Is the event hook registered?
Does the widget exist?
Is the buffer metadata correct?
Is the plugin namespace still alive?
Did unload leave stale state behind?
```

---

## 45. How to add a new plugin

Basic process:

```text
1. Create plugins/example.tcl
2. Add state variables
3. Add helper procs
4. Add command procs
5. Register commands
6. Add optional keybindings
7. Add optional event hooks
8. Add optional UI
9. Add load/unload/save-state/restore-state
10. Reload and test
```

Minimal skeleton:

```tcl
# plugins/example.tcl

variable enabled 1

proc cmd-toggle {args} {
    variable enabled

    set enabled [expr {!$enabled}]

    if {$enabled} {
        Tclme::Message "Example enabled"
    } else {
        Tclme::Message "Example disabled"
    }
}

proc OnBufferSwitched {args} {
    set buffer_name [lindex $args 0]
    # Do something here.
}

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

Tclme::DefCommand example cmd-toggle "Toggle example plugin"

Tclme::On buffer-switched OnBufferSwitched
```

---

## 46. How to add a new core event

If you are extending the kernel, adding an event is often better than adding a hardcoded feature.

Example:

```tcl
Tclme::Emit after-buffer-rename $old_name $new_name
```

Then plugins can subscribe:

```tcl
Tclme::On after-buffer-rename HandleRename
```

Good events are:

- specific
- named clearly
- documented
- emitted at stable points
- given useful arguments

---

## 47. How to refactor safely

Before refactoring:

```text
1. Write down current behavior
2. Add small manual test steps
3. Make one small change
4. Reload plugins
5. Test key flows
6. Commit
```

Key flows to test:

```text
open file
save file
switch buffer
kill buffer
reload plugins
toggle major plugins
search
quit
```

If a refactor breaks plugin reload, treat it as serious.

---

## 48. Testing strategy

Full automated UI testing is hard.

A practical strategy is:

1. Pure-function tests for parsers and helpers.
2. Manual test scripts for UI flows.
3. Error catalogue for recurring failures.
4. Reload torture testing.

Examples of pure functions worth testing:

```text
RelativePath
ExtractArgs
RegexpEscape
BuildRegexpPattern
ParseIRCLine
Markdown block parser
Buffer name uniquifier
```

Reload torture test:

```text
1. Load all plugins
2. Open several buffers
3. Toggle panels
4. Reload each plugin
5. Reload all plugins
6. Kill buffers
7. Quit
```

If errors appear in `:log`, investigate.

---

## 49. Performance considerations

Common performance hazards:

- scanning whole buffer on every keystroke
- rebuilding UI on every cursor move
- recursive grep over huge directories
- highlighting huge files
- replacing whole buffer unnecessarily
- synchronous network operations

Use:

- debounce with `after`
- fingerprints such as buffer length and modified flag
- limits such as max file size and max matches
- incremental processing where possible
- external tools for heavy searching

---

## 50. Security considerations

Tclme plugins are trusted.

Still, be careful with:

- `eval`
- `subst`
- user input interpolated into commands
- executing shell commands
- opening arbitrary files
- network input

Prefer building command lists:

```tcl
[list command arg1 arg2]
```

over string interpolation:

```tcl
"command $arg1 $arg2"
```

---

## 51. Long-term maintenance principles

Tclme will stay healthy if you preserve these principles:

```text
Small kernel.
Stable commands.
Stable events.
Reload-safe plugins.
Clear ownership of state.
No silent errors.
No feature-specific core bloat.
Documentation updated as architecture changes.
```

If a feature violates these principles, consider moving it to a plugin.

---

## 52. Known architectural risks

### 52.1 Plugins wrapping core procs

Some plugins may wrap or rename core procs.

Examples:

- tiling
- debugger
- advanced buffer managers

This is powerful but fragile.

If two plugins wrap the same proc, unload order matters.

---

### 52.2 UI layout contention

Multiple plugins may try to pack panels before the same widget.

This can cause layout surprises.

Possible future solution:

- layout manager
- named dock regions
- explicit panel slots

---

### 52.3 Event storms

Events such as:

```text
cursor-moved
after-command
```

can fire frequently.

Plugins must debounce expensive work.

---

### 52.4 Large buffers

The Tk text widget is good, but huge buffers can expose performance problems in:

- highlighting
- line numbers
- search highlighting
- parsing

Future improvements may require incremental algorithms.

---

## 53. Future architectural ideas

These are not required, but they are good long-term projects.

---

### 53.1 Layout manager

Replace ad-hoc packing with a proper layout tree:

```text
root
├── left sidebar
├── main
│   ├── vertical split
│   │   ├── buffer A
│   │   └── buffer B
└── bottom panels
    ├── findbar
    └── shell/output
```

---

### 53.2 Session persistence

Save:

- open buffers
- current buffer
- cursor positions
- scroll positions
- panel visibility
- plugin state
- window size

---

### 53.3 Incremental syntax engine

Instead of rescanning whole buffers, maintain:

```text
line states
dirty ranges
parser checkpoints
token caches
```

---

### 53.4 Async job manager

Manage long-running operations:

```text
grep
git status
file indexing
network operations
```

Show progress and allow cancellation.

---

### 53.5 Plugin manifests

Plugins could describe themselves with metadata:

```tcl
dict create \
    name findbar \
    version 0.3.0 \
    requires {} \
    commands {find search find-replace} \
    bindings {<Control-s> <Control-f>}
```

This would improve reload, dependency handling, and documentation.

---

## 54. Glossary

### Buffer

A named text container, not necessarily tied to a file.

### Widget

A Tk UI object.

### Text widget

The Tk widget used for editing text.

### Tag

A named set of display/behavior properties applied to text ranges.

### Mark

A named position in a text widget.

### Command

A named action registered in Tclme's command registry.

### Hook

A callback registered for an event.

### Panel

A plugin-created UI region, such as a search bar or sidebar.

### Reload-safe

A plugin can be unloaded and loaded again without leaking state.

### Collect event

An event where multiple handlers contribute values.

### Cancelable event

An event where a handler can veto the action.

---

## 55. Study plan

If you want to study this architecture deeply, do this in order.

---

### Stage 1: Read the kernel

Read `tclme.tcl` top to bottom.

Focus on:

```text
variables
command registry
buffer switching
file open/save
event bus
plugin loader
```

Do not worry about plugins yet.

---

### Stage 2: Trace one command

Pick:

```text
:write
```

Trace the whole path:

```text
minibuffer
-> command parsing
-> command registry
-> save proc
-> file write
-> events
-> status refresh
```

Write down what you learn.

---

### Stage 3: Trace one event

Pick:

```text
buffer-switched
```

Find every place that emits it and every plugin that listens to it.

---

### Stage 4: Build a tiny plugin

Build a plugin that adds:

```text
:hello
```

and displays a message.

Then add:

```text
Tclme::On buffer-switched
```

and print the buffer name.

---

### Stage 5: Build a panel plugin

Build a panel with:

```text
one label
one button
one entry
```

Make it toggle with a command.

Make it destroy cleanly on unload.

---

### Stage 6: Modify findbar

Add one small feature to findbar.

Ideas:

- show match index: `3 of 17`
- add a `Close` button
- remember last 5 search patterns
- highlight current line only
- add a case-sensitive shortcut

---

### Stage 7: Build a results-buffer plugin

Create a command that lists open buffers in a special buffer.

Press Return on a line to switch to that buffer.

This teaches:

- special buffers
- read-only text
- line-based navigation
- metadata mapping

---

### Stage 8: Refactor something small

Pick one messy proc and improve it without changing behavior.

Add notes explaining why the new version is better.

---

## 56. Questions to test your understanding

You understand the architecture when you can answer these.

1. What happens when I type `:find` and press Return?
2. What happens when I press `C-s`?
3. How does a plugin register a command?
4. How does Tclme know which commands to remove when a plugin unloads?
5. How does a plugin listen for buffer switches?
6. How does a plugin create a panel and clean it up?
7. What is the difference between `Tclme::Emit`, `Tclme::EmitCancelable`, and `Tclme::Collect`?
8. Why is `buffer-killed` important for plugins?
9. Why do plugins use namespace variables instead of globals?
10. Why is reload-safety architecturally important?
11. What is the relationship between `::Tclme::current_buffer` and `::Tclme::active_widget`?
12. Why does the status line use a collect event instead of a normal event?
13. Why should expensive operations be debounced?
14. Why should plugins avoid blocking the Tk event loop?
15. What makes a plugin dangerous to the kernel?

---

## 57. Final summary

Tclme is built around a small number of powerful ideas:

```text
The editor is a Tcl interpreter.
Commands are the user-facing primitive.
Events are the extension primitive.
Buffers are generic text containers.
Plugins are trusted namespaces.
Reload-safety is a core discipline.
The UI is live Tk widgets.
The system should remain small enough to understand.
```

If you preserve those ideas, Tclme can grow without becoming unmanageable.

The long-term goal is not to add features blindly.

The goal is to build a personal programming environment that you fully understand, can repair, can extend, and can rely on for years.
```
