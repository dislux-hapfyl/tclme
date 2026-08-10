# Tclme Architecture

Last updated: 2026-08-10

Tclme is a small, hackable, live Tcl kernel with pluggable frontends.

The original implementation began as a Tk text editor, but the system has since been split into its proper layers:

```text
Tclme is not a text editor with a plugin system.

Tclme is a live Tcl command kernel,
event bus,
plugin loader,
and transcript loop.

The Tk editor is one frontend.
The headless REPL is another frontend.
```

This document describes the current architecture after the kernel/frontend split.

---

## 1. Repository layout

The current intended layout is:

```text
tclme/
├── tclme.tcl               # Headless Tclme kernel
├── tcled.tcl               # Tk editor frontend
├── tclit.tcl               # Headless REPL frontend
├── tclus.tcl               # GUI launcher
├── plugins/                

```

The exact frontend filenames may vary, but the important boundary is:

```text
tclme.tcl must not require Tk.
```

The kernel may be loaded by `tclsh`.

The Tk frontend may require Tk and may create widgets.

---

## 2. Core philosophy

Tclme is designed around a small number of principles.

### 2.1 Live image

Tclme is intended to be modified while running.

You should be able to:

```text
define commands
load plugins
reload plugins
inspect state
patch behavior
open new frontends
```

without restarting the process.

---

### 2.2 One command loop

All user-facing actions should flow through the command registry.

Examples:

```text
:help
:eval expr 2 + 3
:reload findbar
:load-plugin example
```

The same dispatch mechanism is used by:

```text
the Tk minibuffer
the headless REPL
keybindings
plugin commands
future frontends
```

---

### 2.3 Frontends are replaceable

The kernel does not require a GUI.

A frontend is responsible for providing:

```text
input
output
visual presentation
buffers, if desired
keybindings, if graphical
file operations, if desired
```

The kernel provides:

```text
commands
events
plugins
transcript
dispatch
logging
```

---

### 2.4 Plugins are trusted code

Plugins are not sandboxed.

A plugin can:

```text
define commands
register hooks
create UI
read and write files
open sockets
modify Tclme state
```

This is intentional. Tclme is a personal live programming environment, not a secure plugin store.

---

## 3. High-level architecture

```text
+---------------------------------------------------------------+
|                         Frontends                             |
|                                                               |
|   Tk editor frontend          Headless REPL frontend          |
|                                                               |
|   widgets                     stdin/stdout                    |
|   minibuffer                  transcript printing             |
|   buffers                     command loop                    |
|   themes                      headless plugin loading         |
|   file operations                                             |
+-------------------------------+-------------------------------+
                                |
                                v
+---------------------------------------------------------------+
|                        Tclme kernel                           |
|                                                               |
|   command registry          event bus                         |
|   aliases                   plugin loader                     |
|   transcript                output sink                       |
|   logging                   DispatchLine                      |
|   EvalInput                 RunExCommand                      |
|   headless buffer stubs     plugin metadata                   |
+---------------------------------------------------------------+
                                |
                                v
+---------------------------------------------------------------+
|                         Plugins                               |
|                                                               |
|   ::Tclme::Plugin::example                                    |
|   ::Tclme::Plugin::findbar                                    |
|   ::Tclme::Plugin::chighlight                                 |
|   ...                                                         |
+---------------------------------------------------------------+
```

---

## 4. The kernel: `tclme.tcl`

The kernel is the headless core of Tclme.

It should be loadable from:

```sh
tclsh
```

It must not require Tk.

The kernel currently lives in:

```text
tclme.tcl
```

It defines the `::Tclme` namespace and the core runtime.

---

## 5. Kernel state

Important kernel variables:

```tcl
::Tclme::listeners
::Tclme::commands
::Tclme::aliases
::Tclme::log
::Tclme::_owner
::Tclme::scriptfile
::Tclme::plugindir
::Tclme::headless
::Tclme::buffers
::Tclme::buffer_order
::Tclme::path_to_buffer
::Tclme::current_buffer
::Tclme::active_widget
::Tclme::transcript
::Tclme::transcript_limit
::Tclme::transcript_buffer
::Tclme::output_sink
::Tclme::echo_input
::Tclme::plugin_meta
::Tclme::theme
::Tclme::initfile
```

Some of these are kernel-level.

Some are frontend-oriented but live in the kernel for compatibility.

The long-term direction is to keep the kernel as frontend-independent as possible.

---

## 6. Headless mode

The kernel defaults to headless mode:

```tcl
variable headless 1
```

Frontends should explicitly set this.

A GUI frontend should set:

```tcl
set Tclme::headless 0
```

A headless frontend should leave it as:

```tcl
set Tclme::headless 1
```

Plugins can test:

```tcl
if {[Tclme::IsHeadless]} {
    return
}
```

UI plugins should usually do this near the top of the plugin file:

```tcl
if {[Tclme::IsHeadless]} {
    return
}
```

This prevents graphical plugins from trying to create widgets in a headless REPL.

---

## 7. Command registry

Commands are stored in:

```tcl
::Tclme::commands
```

Each command entry is a dict:

```tcl
name -> {
    script  ...
    doc     ...
    owner   ...
    keys    ...
}
```

Commands are defined with:

```tcl
Tclme::DefCommand name script "documentation"
```

Example:

```tcl
Tclme::DefCommand hello cmd-hello "Say hello"
```

Commands are invoked through:

```tcl
Tclme::Invoke name args...
```

---

## 8. Aliases

Aliases are stored in:

```tcl
::Tclme::aliases
```

They are defined with:

```tcl
Tclme::DefAlias short full
```

Example:

```tcl
Tclme::DefAlias e eval
```

Now:

```text
:e expr 2 + 3
```

is equivalent to:

```text
:eval expr 2 + 3
```

---

## 9. Command dispatch

The kernel provides:

```tcl
Tclme::DispatchLine line
```

This is the main REPL entry point.

Behavior:

```text
If the line is empty:
    do nothing

If the line begins with ':':
    run it as an ex-command

Otherwise:
    evaluate it as Tcl code
```

Examples:

```text
:help
:plugins
:eval expr 2 + 3
expr 2 + 3
```

The first three are command dispatch.

The last one is direct Tcl evaluation.

---

## 10. Ex-command argument convention

Ex-command arguments are intentionally passed as raw strings.

For example:

```tcl
proc Tclme::RunExCommand {line} {
    ...
    Tclme::Invoke $name $rest
}
```

The command receives the remainder of the line as a raw string.

This is intentional.

It matches the style of many interactive systems:

```text
curated commands for common operations
:eval as the explicit escape hatch into full Tcl
```

Commands should parse their own arguments.

Example:

```tcl
proc cmd-example {args} {
    set arg [string trim [join $args " "]]
    ...
}
```

Do not assume structured argument parsing unless a future argument-parsing layer is added.

---

## 11. Kernel command set

The kernel defines a minimal headless command set.

Current kernel commands:

```text
:eval         evaluate Tcl code
:help         show available commands
:reload       reload plugins
:load-plugin  load a plugin by name
:plugins      list loaded plugins
```

Aliases:

```text
:e -> eval
:h -> help
```

Frontends may define many more commands.

The Tk frontend, for example, adds commands such as:

```text
:write
:edit
:switch
:kill
:list
:log
:theme
:repl
:scratch
:new
```

---

## 12. Event bus

The event bus allows plugins and frontends to react to system activity.

Listeners are stored in:

```tcl
::Tclme::listeners
```

The structure is:

```text
event -> list of listener entries
```

Each listener entry is:

```tcl
{priority callback owner}
```

Listeners are sorted by priority before execution.

Lower priority numbers run earlier.

The default priority is:

```tcl
50
```

---

## 13. Event APIs

Register a listener:

```tcl
Tclme::On event callback
```

Register with priority:

```tcl
Tclme::On event callback 20
```

Remove a listener:

```tcl
Tclme::Off event callback
```

Emit a normal event:

```tcl
Tclme::Emit event args...
```

Emit a cancelable event:

```tcl
Tclme::EmitCancelable event args...
```

Collect results from listeners:

```tcl
Tclme::Collect event args...
```

---

## 14. Event categories

Tclme uses three broad event styles.

---

### 14.1 Normal events

Fire-and-forget.

Example:

```text
buffer-switched
plugin-loaded
after-command
```

Listeners may receive arguments, but their return values are ignored.

---

### 14.2 Cancelable events

Used for veto-style hooks.

Examples:

```text
before-save
before-quit
before-kill-buffer
```

A listener can cancel the action by returning a non-empty string.

Example:

```tcl
proc BeforeSave {path} {
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

Returning:

```tcl
"some reason"
```

cancels the action.

---

### 14.3 Collect events

Used when multiple listeners contribute output.

The main example is:

```text
status-line
```

Each listener may return a string.

The kernel joins all non-empty results.

Example:

```tcl
proc StatusContrib {buffer_name} {
    return "example"
}

Tclme::On status-line StatusContrib
```

---

## 15. Current event inventory

Events emitted by the kernel:

```text
before-command
after-command
plugin-loaded
plugin-unloaded
buffer-created
buffer-switched
```

Events emitted by the Tk frontend, when present:

```text
before-buffer-switch
buffer-switched
buffer-killed
before-file-read
after-file-read
before-file-write
after-file-write
before-save
after-save
before-quit
editor-quit
editor-started
theme-changed
cursor-moved
status-line
minibuffer-prompted
minibuffer-cancelled
```

Some events are emitted by both the kernel and frontend.

For example, the kernel's headless buffer model emits:

```text
buffer-created
buffer-switched
```

The Tk frontend emits richer buffer and file events because it implements real buffers, widgets, and file operations.

---

## 16. Transcript

The transcript is Tclme's persistent session record.

It is stored in:

```tcl
::Tclme::transcript
```

Each transcript entry is:

```tcl
{tag text}
```

Common tags:

```text
repl_input
repl_result
repl_error
message
note
```

The transcript is written through:

```tcl
Tclme::Print text tag
```

Example:

```tcl
Tclme::Print "=> 5" repl_result
```

---

## 17. Output sink

The kernel does not force output into a particular UI.

Instead, it calls an output sink if one exists.

Set the sink with:

```tcl
Tclme::SetOutputSink command
```

The sink receives:

```tcl
text tag
```

Example:

```tcl
proc MySink {text tag} {
    puts stdout $text
}

Tclme::SetOutputSink MySink
```

If no sink is set, `Tclme::Print` writes to stdout.

The Tk frontend sets a sink that appends output to the transcript buffer.

---

## 18. Echo behavior

The variable:

```tcl
::Tclme::echo_input
```

controls whether `DispatchLine` echoes input into the transcript.

When enabled:

```tcl
Tclme::Print "> $line" repl_input
```

When disabled, input is not echoed by `DispatchLine`.

This is useful in a terminal REPL where the terminal already echoes typed input.

---

## 19. Logging

The kernel keeps a small in-memory log:

```tcl
::Tclme::log
```

Entries have the form:

```tcl
{time level message}
```

Log with:

```tcl
Tclme::Log error "something failed"
```

Error-level messages are routed to both:

```tcl
Tclme::Print
Tclme::Message
```

The Tk frontend may also provide a log buffer, usually through:

```text
:log
```

---

## 20. Headless buffer model

The kernel contains a minimal buffer model.

It exists so that plugins and frontends can share buffer metadata even when no GUI exists.

Buffers are stored in:

```tcl
::Tclme::buffers
```

Each buffer is a dict:

```tcl
name -> {
    path     ""
    wid      ""
    readonly 0
    model    {
        text ...
    }
}
```

In headless mode, buffers usually have no widget.

The kernel stubs are:

```tcl
Tclme::WidgetForBuffer
Tclme::GetBufferContent
Tclme::SetBufferContent
Tclme::SwitchToBuffer
Tclme::ShowInBuffer
```

The Tk frontend overrides these with real widget-backed behavior.


```text
Real visible buffers are a frontend thing.

But the idea of a buffer — a named document with metadata — is useful to the
kernel because plugins, commands, events, and frontends need a shared object
to talk about.
```

So the kernel should not own Tk text widgets, focus, packing, scrolling, or drawing.

But it can own a minimal abstract buffer model.

That is what the current buffer stubs are.

---

# The useful distinction

There are really three different things called “buffer”:

```text
1. Buffer identity
   name, path, readonly flag, metadata

2. Buffer content model
   text content, modified state, marks, tags, undo history

3. Buffer view
   Tk text widget, scrollbars, focus, packing, key events
```

The frontend absolutely owns number 3.

The kernel can reasonably own number 1.

Number 2 is the interesting middle layer.

In the current Tclme design, the kernel has a very small headless version of number 2 so plugins and commands have something to operate on even without Tk.

---

# What belongs in the frontend

These are frontend concerns:

```text
Tk text widgets
scrollbars
focus
packing
themes
drawing
cursor display
selection appearance
minibuffer entry widget
status label widget
key event dispatch through Tk bindtags
```

The Tk frontend should create and destroy widgets.

For example:

```text
.ws.b1.txt
.ws.b1.vs
```

That is frontend state.

The kernel should not create those.

---

# What belongs in the kernel

The kernel needs shared coordination state:

```text
What is the current buffer?
What buffers exist?
What is the name/path of this buffer?
What plugins care about buffer events?
What commands operate on buffers?
What is the headless fallback for buffer APIs?
```

That is why the kernel has things like:

```tcl
::Tclme::buffers
::Tclme::buffer_order
::Tclme::current_buffer
::Tclme::active_widget
```

Some of those are more frontend-flavored than others.

For example, `active_widget` is definitely frontend state. It exists because many editor commands and plugins want to know where the user is working.

But the kernel can still store it as a shared frontend-owned value without itself creating widgets.

---

# Why the stubs exist

The stubs exist so the kernel can provide a stable API without requiring Tk.

Example kernel stubs:

```tcl
Tclme::WidgetForBuffer
Tclme::GetBufferContent
Tclme::SetBufferContent
Tclme::SwitchToBuffer
Tclme::ShowInBuffer
```

In headless mode, these do minimal non-GUI things.

In the Tk frontend, the frontend overrides them with real widget-backed behavior.

Conceptually:

```text
Kernel says:
    Here is the buffer API.
    In headless mode, this is a minimal fallback.

Tk frontend says:
    I will override these with real buffer/widget behavior.
```

Example:

```tcl
# Kernel/headless stub.
proc Tclme::WidgetForBuffer {name} {
    return ""
}
```

Tk frontend override:

```tcl
proc Tclme::WidgetForBuffer {name} {
    variable buffers

    if {![dict exists $buffers $name]} {
        return ""
    }

    set info [dict get $buffers $name]

    if {![dict exists $info wid]} {
        return ""
    }

    set w ".ws.[dict get $info wid].txt"

    if {[winfo exists $w]} {
        return $w
    }

    return ""
}
```

So the kernel can remain Tk-free, but plugins can still use the same API.

---

# Why plugins need the abstraction

Plugins often want to say things like:

```text
What buffer am I in?
Get the text of this buffer.
Replace the contents of this buffer.
Show output in a special buffer.
Switch to another buffer.
```

If the kernel had no buffer concept at all, every plugin would need to know:

```text
Is there a GUI?
Which frontend is active?
How do I get the current widget?
How do I create a buffer?
How do I focus it?
How do I switch buffers?
```

That pushes too much complexity into plugins.

The buffer stubs give plugins a stable place to stand.

---

# Why headless mode benefits

The headless REPL is not just a debugging toy.

It lets you do things like:

```text
load plugins
run commands
transform text
run scripts
test plugin logic
inspect kernel state
```

without starting Tk.

For that to be useful, some plugins may need a lightweight buffer/document model.

Example headless-friendly command:

```tcl
command uppercase-current {args} {
    set name $::Tclme::current_buffer
    set text [Tclme::GetBufferContent $name]
    Tclme::SetBufferContent $name [string toupper $text]
}
```

That command can exist conceptually even without Tk.

The Tk frontend can make it visible and interactive.

The headless frontend can still test the logic.

---

# What is slightly impure

You are right that some of this is pragmatic rather than perfectly pure.

For example:

```tcl
::Tclme::active_widget
```

is very frontend-flavored.

It probably should be thought of as:

```text
frontend-owned state stored in a shared place
```

rather than “kernel logic.”

Similarly:

```tcl
Tclme::ShowInBuffer
```

is editor/UI-flavored.

In headless mode it can print text.

In Tk mode it can create/show a buffer.

That is a frontend service exposed through a shared API.

---

# A stricter architecture would look like this

If you wanted a purer split, you could separate the system into:

```text
ktclme.tcl
    command loop
    events
    plugin loader
    output/transcript

tclme-model.tcl
    abstract buffer/document model
    buffer names
    buffer metadata
    content model

tclme-frontend-tk.tcl
    widgets
    views
    focus
    themes
    file operations
```

Then the kernel itself would not even have buffers.

It would only provide command/event/plugin infrastructure.

The buffer model would be a separate library or service.

That is architecturally cleaner.

But it is also more work.

The current design says:

```text
Keep a small headless buffer model in the kernel for convenience.
Let the Tk frontend override the view-specific parts.
```

That is a reasonable pragmatic choice.

---

# A good rule of thumb

Use this rule:

```text
If it is about identity, naming, events, or coordination,
it can live near the kernel.

If it is about widgets, focus, drawing, packing, or user input,
it belongs in the frontend.
```

So:

```text
Buffer name registry          kernel/model
Buffer path metadata          kernel/model
Current buffer name           kernel/model
Tk text widget                frontend
Scrolling                     frontend
Focus                         frontend
Key bindings                  frontend
Syntax highlighting tags      plugin/frontend
Saving files                  frontend/editor feature
Status line widget            frontend
status-line event             kernel/event bus
```

---

# What I would call the current design

I would describe the current architecture like this:

```text
Tclme has a headless kernel with a minimal abstract buffer model.

The Tk frontend provides real buffer views and overrides the buffer-related
stub procedures with widget-backed implementations.

Plugins should use the buffer API instead of assuming Tk widgets exist.
```

That is not contradictory.

It is a practical split.

---

# If you want to make it cleaner later

You can do this in stages.

## Stage 1: Keep current design

This is fine for now.

Just document the boundary:

```text
Kernel stubs are contracts.
Frontends override them.
Plugins use the API.
```

---

## Stage 2: Rename the concept

Instead of saying “buffers in the kernel,” call it:

```text
headless document model
```

or:

```text
buffer service stubs
```

That makes the intent clearer.

---

## Stage 3: Move buffer stubs into a separate file

Create:

```text
tclme-model.tcl
```

Move the abstract buffer model there.

Then `ktclme.tcl` becomes even purer.

---

## Stage 4: Frontend service registration

Eventually frontends could register implementations:

```tcl
Tclme::RegisterService buffers TkBufferService
```

or:

```tcl
Tclme::SetBufferBackend tk
```

That is more advanced and probably not necessary yet.

---

# Bottom line

Your instinct is correct:

```text
Visible, editable buffers are frontend objects.
```

But the kernel still benefits from a tiny abstract buffer model:

```text
buffer names
current buffer
buffer metadata
headless content fallback
shared buffer API
```

The stubs are not the editor UI.

They are contracts that allow commands, plugins, and frontends to agree on what a buffer is.

That is why they exist.
---

## 21. Tk frontend

The Tk frontend provides the graphical editor.

It is responsible for:

```text
Tk widgets
buffers
text widgets
minibuffer
status line
themes
file loading and saving
graphical keybindings
transcript buffer
help buffer
log buffer
```

The Tk frontend should:

1. source the kernel
2. set `Tclme::headless` to `0`
3. override headless stubs
4. build the UI
5. set the output sink
6. initialize commands
7. load plugins
8. load the user init file
9. emit `editor-started`

Conceptually:

```tcl
source tclme.tcl
source tcled.tcl

set Tclme::headless 0

Tclme::InitGUI
```

---

## 22. Tk frontend overrides

The Tk frontend should override these headless kernel stubs:

```tcl
Tclme::Message
Tclme::Note
Tclme::UpdateStatus
Tclme::Prompt
Tclme::BindKey
Tclme::WidgetForBuffer
Tclme::GetBufferContent
Tclme::SetBufferContent
Tclme::SwitchToBuffer
Tclme::ShowInBuffer
```

The Tk implementations provide real UI behavior.

For example:

```tcl
Tclme::Message
```

writes to the minibuffer in the GUI, while in headless mode it prints through `Tclme::Print`.

---

## 23. Tk buffer model

In the Tk frontend, buffers are backed by text widgets.

Each buffer has a container frame:

```text
.ws.<wid>
```

and a text widget:

```text
.ws.<wid>.txt
```

The buffer dict contains:

```tcl
path
wid
readonly
```

Example:

```tcl
buffers = dict

"scratch" -> {
    path     ""
    wid      "b1"
    readonly 0
}
```

The widget path is obtained with:

```tcl
Tclme::WidgetForBuffer $buffer_name
```

---

## 24. Tk keybindings

In headless mode, `Tclme::BindKey` only records metadata.

In the Tk frontend, `Tclme::BindKey` should create actual Tk bindings.

The usual bindtag is:

```text
TclmeText
```

Text widgets are given bindtags like:

```tcl
bindtags $txt [list $txt TclmeText Text [winfo toplevel $txt] all]
```

This allows shared editor bindings.

---

## 25. Keybinding limitations

The current binding model is global.

Bindings attached to:

```text
TclmeText
```

apply to all normal text buffers.

There is not yet a full buffer-local or mode-local keymap system.

For buffer-specific behavior, plugins should bind directly to the buffer's widget when necessary.

Example:

```tcl
set w [Tclme::WidgetForBuffer $buffer_name]

bind $w <Return> [list ::Tclme::Plugin::example::OnReturn $buffer_name]
```

A proper mode/keymap system is future work.

---

## 26. Headless REPL frontend

The headless REPL frontend provides a terminal interface to the kernel.

It should:

1. source the kernel
2. initialize the kernel
3. optionally load plugins
4. read lines from stdin
5. dispatch them through `Tclme::DispatchLine`

Conceptually:

```tcl
#!/usr/bin/env tclsh

source tclme.tcl

set Tclme::headless 1
set Tclme::echo_input 0

Tclme::InitKernel

while {1} {
    puts -nonewline "> "
    flush stdout

    if {[gets stdin line] < 0} {
        break
    }

    Tclme::DispatchLine $line
}
```

The REPL is useful for:

```text
testing plugins
testing commands
scripting Tclme
debugging kernel behavior
running headless utilities
```

---

## 27. Plugins

Plugins live in:

```text
plugins/
```

A plugin file named:

```text
example.tcl
```

is loaded into:

```tcl
::Tclme::Plugin::example
```

Plugins are loaded with:

```tcl
Tclme::LoadPlugin name file
```

or interactively:

```text
:load-plugin example
```

---

## 28. Plugin metadata

Plugin metadata is stored in:

```tcl
::Tclme::plugin_meta
```

Each plugin entry contains:

```tcl
plugin-name -> {
    file     ...
    commands {}
    aliases  {}
    binds    {}
    hooks    {}
    afters   {}
}
```

This metadata allows Tclme to unload plugins cleanly.

---

## 29. Plugin registration

Plugins register behavior using:

```tcl
Tclme::DefCommand
Tclme::DefAlias
Tclme::BindKey
Tclme::On
Tclme::After
Tclme::PluginAfter
```

When a plugin is loaded, the kernel tracks registrations made through these APIs.

This allows unload to remove:

```text
commands
aliases
bindings
hooks
after callbacks
```

---

## 30. Plugin lifecycle

The preferred lifecycle hooks are:

```tcl
init
cleanup
state
restore
```

Legacy hooks are still supported:

```text
init          replaces load
cleanup       replaces unload
state         replaces save-state
restore       replaces restore-state
```

---

## 31. Plugin load order

For a plugin using the new lifecycle:

```text
1. unload existing plugin, if already loaded
2. create plugin metadata
3. create plugin namespace
4. source plugin file
5. restore saved state
6. call init
7. emit plugin-loaded
```

The important part is that `init` runs after restored state is available.

---

## 32. Legacy plugin load order

For plugins that do not define `init`, the legacy behavior is preserved:

```text
1. source plugin file
2. call load
3. restore-state
```

This preserves compatibility with older plugins.

---

## 33. Plugin unload order

When a plugin is unloaded:

```text
1. call cleanup, or unload if cleanup does not exist
2. remove commands owned by the plugin
3. remove aliases owned by the plugin
4. remove bindings registered by the plugin
5. remove hooks registered by the plugin
6. cancel tracked after callbacks
7. delete plugin namespace
8. remove plugin metadata
9. emit plugin-unloaded
```

Cleanup errors are logged, but unload continues.

---

## 34. Plugin state

Plugins may save state across reloads.

New style:

```tcl
proc state {} {
    return [dict create enabled 1]
}

proc restore {saved} {
    variable enabled

    if {[dict exists $saved enabled]} {
        set enabled [dict get $saved enabled]
    }
}
```

State should be serializable Tcl data.

Prefer dicts.

Do not save:

```text
widget paths
channels
sockets
timers
live objects
```

Save names, strings, numbers, lists, and dicts.

---

## 35. Headless-safe plugin rules

Plugins that require Tk should begin with:

```tcl
if {[Tclme::IsHeadless]} {
    return
}
```

Plugins that are headless-safe do not need this guard.

Examples of headless-safe plugins:

```text
command utilities
text processors
parsers
calculators
code analysis tools
non-UI status contributors
```

Examples of GUI plugins:

```text
findbar
buffer bar
line numbers
sidebar panels
debugger panel
tiled workspace
```

---

## 36. Frontend contract

A frontend should provide enough of the editor environment for plugins to be useful.

The Tk frontend provides:

```text
buffers
widgets
file operations
prompts
keybindings
status line
theme application
```

The headless frontend provides:

```text
stdin input
stdout output
command dispatch
plugin loading
headless buffer metadata
```

Frontends should not modify kernel internals unless necessary.

They should prefer:

```text
overriding stubs
registering commands
registering events
setting output sinks
```

---

## 37. Output policy

Tclme has several output mechanisms.

Use them according to intent.

---

### `Tclme::Print`

Persistent transcript output.

Use for:

```text
REPL results
errors
session transcript
command output
```

Example:

```tcl
Tclme::Print "=> $result" repl_result
```

---

### `Tclme::Message`

Frontend message output.

In the Tk frontend, this usually appears in the minibuffer.

In headless mode, it prints through `Tclme::Print`.

Use for:

```text
user-facing messages
command feedback
errors
```

---

### `Tclme::Note`

Transient status output.

Use for:

```text
temporary notes
completion hints
non-destructive status messages
```

---

### `Tclme::Log`

Internal log.

Use for:

```text
errors
plugin failures
hook failures
after failures
```

---

## 38. Theme state

Theme state currently lives in the kernel:

```tcl
::Tclme::theme
```

Theme keys include:

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

The Tk frontend applies the theme.

The headless kernel does not need a visual theme, but the state remains available for frontends and plugins.

Long-term, theme application belongs to the frontend, while theme state may remain shared.

---

## 39. User init file

The user init file is usually:

```text
~/.tclmerc
```

The kernel stores the resolved location in:

```tcl
::Tclme::initfile
```

The frontend is responsible for loading it.

The Tk frontend should load the user init after plugins:

```text
Build UI
Load plugins
Load user init
Emit editor-started
```

The headless frontend may choose to skip the user init file or load a headless-specific init file.

---

## 40. Stable kernel API

The following kernel APIs are considered the stable core.

Changes to these should be backward-compatible unless a major version bump occurs.

### Command and dispatch

```tcl
Tclme::DefCommand
Tclme::DefAlias
Tclme::Invoke
Tclme::RunExCommand
Tclme::EvalInput
Tclme::DispatchLine
```

### Events

```tcl
Tclme::On
Tclme::Off
Tclme::Emit
Tclme::EmitCancelable
Tclme::Collect
```

### Output

```tcl
Tclme::Print
Tclme::SetOutputSink
Tclme::Log
```

### Headless/frontend stubs

```tcl
Tclme::Message
Tclme::Note
Tclme::UpdateStatus
Tclme::Prompt
Tclme::BindKey
Tclme::WidgetForBuffer
Tclme::GetBufferContent
Tclme::SetBufferContent
Tclme::SwitchToBuffer
Tclme::ShowInBuffer
Tclme::IsHeadless
```

### Plugin system

```tcl
Tclme::LoadPlugin
Tclme::UnloadPlugin
Tclme::ReloadPlugin
Tclme::ReloadPlugins
Tclme::LoadAllPlugins
Tclme::LoadPluginByName
Tclme::After
Tclme::PluginAfter
Tclme::PluginNamespace
Tclme::PluginCallFirst
Tclme::PluginSaveState
```

---

## 41. Frontend APIs that may evolve

The following are useful but may evolve as frontends mature:

```tcl
Tclme::SwitchToBuffer
Tclme::ShowInBuffer
Tclme::GetBufferContent
Tclme::SetBufferContent
Tclme::WidgetForBuffer
Tclme::Prompt
Tclme::BindKey
```

These are currently stubs in the kernel and are overridden by frontends.

Their exact semantics may become richer as the frontend contract becomes more formal.

---

## 42. Known limitations

The current architecture is stable enough for active development, but several limitations are known.

---

### 42.1 Global keybindings

The current keybinding model is coarse.

Bindings are generally attached to:

```text
TclmeText
```

There is no complete buffer-local or mode-local keymap system.

---

### 42.2 Event context is limited

Most events do not carry a full context object.

Listeners often rely on arguments or global state such as:

```tcl
::Tclme::current_buffer
::Tclme::active_widget
```

A future version may introduce explicit event context objects.

---

### 42.3 Headless buffer model is minimal

The kernel's buffer model is metadata-oriented.

It does not provide:

```text
file loading
file saving
marks
tags
undo
widgets
line numbers
syntax highlighting
```

Those are frontend or plugin concerns.

---

### 42.4 Prompting is unavailable in headless mode

The kernel prompt stub prints an error.

A future headless frontend could implement line-based prompts, but the current REPL uses direct line dispatch.

---

### 42.5 Theme state is in the kernel

Theme state is currently kernel-resident even though it is mostly visual.

This is acceptable for now, but future splits may move theme application entirely into frontends.

---

### 42.6 Plugins must manually guard headless mode

UI plugins must check:

```tcl
Tclme::IsHeadless
```

A future plugin manifest format could declare capabilities:

```text
requires-ui
headless-safe
version
dependencies
```

---

## 43. Plugin design rules

Plugins should follow these rules.

---

### 43.1 Use the lifecycle hooks

Prefer:

```tcl
init
cleanup
state
restore
```

Do not create UI at source time.

Create UI in `init`.

Destroy UI in `cleanup`.

---

### 43.2 Clean up everything

Plugins should clean up:

```text
widgets
timers
sockets
channels
bindings
tags
event hooks
commands
aliases
```

If the plugin creates it, the plugin should know how to remove it.

---

### 43.3 Use dicts for state

Prefer:

```tcl
dict create
dict set
dict get
dict exists
dict unset
```

Avoid scattered global variables.

---

### 43.4 Capture context before async work

Do not rely on global state inside delayed callbacks.

Bad:

```tcl
after idle {
    DoSomethingWithCurrentBuffer
}
```

Better:

```tcl
set buffer_name $::Tclme::current_buffer

after idle [list DoSomethingWithBuffer $buffer_name]
```

---

### 43.5 Debounce expensive operations

Do not run heavy work on every cursor movement or key release.

Use:

```tcl
after
```

to debounce.

---

## 44. Debugging

The headless REPL is now a first-class debugging environment.

Useful commands:

```text
:help
:plugins
:load-plugin NAME
:eval expr 2 + 3
:reload NAME
```

Useful introspection:

```tcl
:eval dict keys $::Tclme::commands
:eval dict keys $::Tclme::aliases
:eval dict keys $::Tclme::plugin_meta
:eval dict keys $::Tclme::listeners
:eval info commands ::Tclme::Plugin::example::*
```

Errors are written to:

```tcl
Tclme::Print
Tclme::Message
```

and stored in:

```tcl
::Tclme::log
```

In the Tk frontend, use:

```text
:log
```

to inspect recent errors.

---

## 45. Testing strategy

The split makes testing much easier.

---

### Kernel tests

Use the headless REPL to test:

```text
command registration
alias resolution
event emission
plugin loading
plugin reload
plugin unload
transcript output
```

No GUI is required.

---

### Plugin tests

Headless-safe plugins can be loaded interactively:

```text
:load-plugin example
:plugins
:reload example
```

UI plugins should be tested in the Tk frontend.

---

### Frontend tests

The Tk frontend should be tested manually for:

```text
buffer switching
file open/save
themes
panels
keybindings
prompts
focus behavior
```

---

## 46. Versioning policy

A reasonable policy is:

```text
Major version:
    breaking changes to kernel API,
    event contract,
    plugin lifecycle,
    frontend contract

Minor version:
    backward-compatible additions

Patch version:
    bug fixes
```

The current kernel API should be treated as frozen for plugin development.

Frontends may continue to evolve.

---

## 47. Freeze boundary

The freeze boundary is the kernel loop and plugin system.

Freeze:

```text
command registry
aliases
event bus
plugin loader
transcript
DispatchLine
EvalInput
RunExCommand
Print
output sink
headless stubs
```

Do not freeze frontend details too tightly.

The Tk frontend may continue to improve:

```text
buffers
widgets
themes
tabs
tiling
panels
status line
minibuffer
```

---

## 48. Future roadmap

Likely future work includes:

```text
buffer-local keymaps
mode-local keymaps
event context objects
command argument parsing
plugin manifests
headless plugin capability declarations
session persistence
session restoration
frontend capability negotiation
rich headless prompts
test harness
buffer model formalization
moving theme application fully into frontends
```

---

## 49. Summary

Tclme is now a split system.

The kernel provides:

```text
a live command loop
an event bus
a plugin loader
a transcript
a headless buffer stub model
frontend-independent output
```

The Tk frontend provides:

```text
the graphical editor
buffers
widgets
themes
file operations
minibuffer
status line
```

The headless REPL provides:

```text
terminal interaction
scripting
testing
kernel debugging
```

This is the correct architecture for the project.

Tclme is no longer merely a text editor with plugins.

It is a live Tcl environment with multiple frontends.
```