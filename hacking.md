# Tclme Kernel Hacking Guide

This guide is for modifying the Tclme kernel itself.

The kernel is the headless core of Tclme.

It lives in:

```text
ktclme.tcl
```

It must remain loadable from plain `tclsh`.

The kernel should not require Tk.

---

## Kernel/frontends split

Tclme is split into layers:

```text
ktclme.tcl               headless kernel
tclme-dsl.tcl            optional plugin DSL
tclme-frontend-tk.tcl    Tk editor frontend
tclme-repl.tcl           headless REPL frontend
tclme.tcl                GUI launcher
plugins/                 plugins
```

The kernel provides:

```text
command registry
aliases
event bus
plugin loader
transcript
output sink
logging
dispatch loop
headless buffer stubs
```

Frontends provide:

```text
UI
widgets
themes
file operations
prompts
keybindings
real buffer widgets
```

The kernel is not a text editor by itself.

It is a live Tcl command kernel with pluggable frontends.

---

## Freeze boundary

The kernel API is the stable boundary.

Stable kernel APIs include:

```text
Tclme::DefCommand
Tclme::DefAlias
Tclme::Invoke
Tclme::RunExCommand
Tclme::EvalInput
Tclme::DispatchLine

Tclme::On
Tclme::Off
Tclme::Emit
Tclme::EmitCancelable
Tclme::Collect

Tclme::Print
Tclme::SetOutputSink
Tclme::Log

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

Tclme::LoadPlugin
Tclme::UnloadPlugin
Tclme::ReloadPlugin
Tclme::ReloadPlugins
Tclme::LoadAllPlugins
Tclme::PluginAfter
```

Changes to these should be backward-compatible unless a major version bump is acceptable.

---

## Kernel state

Important kernel variables:

```tcl
::Tclme::listeners
::Tclme::commands
::Tclme::aliases
::Tclme::log
::Tclme::_owner
::Tclme::plugindir
::Tclme::headless
::Tclme::buffers
::Tclme::buffer_order
::Tclme::current_buffer
::Tclme::active_widget
::Tclme::transcript
::Tclme::output_sink
::Tclme::plugin_meta
```

Plugins may read many of these.

Plugins should not write kernel internals unless the API is documented.

---

## Adding a new kernel command

If the command is headless-safe, add it to the kernel.

Example:

```tcl
proc Tclme::CmdTime {args} {
    Tclme::Print [clock format [clock seconds]]
}
```

Register it in `Tclme::InitKernel`:

```tcl
Tclme::DefCommand time Tclme::CmdTime "Show current time"
```

If the command is GUI-specific, add it in the Tk frontend instead.

---

## Adding a new frontend command

GUI commands belong in the frontend.

Example:

```tcl
proc Tclme::CmdSplitRight {args} {
    # Tk-specific behavior here.
}
```

Register it in the frontend init:

```tcl
Tclme::DefCommand split-right Tclme::CmdSplitRight "Split right"
```

Do not put Tk dependencies in the kernel just to support a GUI command.

---

## Adding a new event

Use events when plugins should react to something.

Example:

```tcl
Tclme::Emit my-event arg1 arg2
```

Document the event payload.

Example documentation:

```text
my-event
    arg1: buffer name
    arg2: file path
```

If the event is cancelable, use:

```tcl
set reason [Tclme::EmitCancelable before-my-action]

if {$reason ne ""} {
    Tclme::Message "Cancelled: $reason"
    return
}
```

Cancelable handlers should return:

```text
""       allow
"reason" cancel
```

If the event collects output, use:

```tcl
set extra [Tclme::Collect my-collect-event]
```

---

## Event categories

Tclme uses three event styles.

### Normal events

```tcl
Tclme::Emit buffer-switched $name
```

Return values are ignored.

---

### Cancelable events

```tcl
set reason [Tclme::EmitCancelable before-save $path]

if {$reason ne ""} {
    return
}
```

First non-empty result cancels.

---

### Collect events

```tcl
set extra [Tclme::Collect status-line $buffer_name]
```

All non-empty results are joined.

---

## Current event inventory

Kernel-emitted events:

```text
before-command
after-command
plugin-loaded
plugin-unloaded
buffer-created
buffer-switched
```

Frontend-emitted events may include:

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

When adding events, document them.

---

## Adding a new buffer API

If you need a new buffer operation, add a headless stub in the kernel.

Example:

```tcl
proc Tclme::BufferFoo {name} {
    # Headless fallback.
    return ""
}
```

Then the Tk frontend overrides it:

```tcl
proc Tclme::BufferFoo {name} {
    # Real widget-backed implementation.
}
```

This keeps the kernel headless-safe.

---

## Adding buffer metadata

Buffers are stored in:

```tcl
::Tclme::buffers
```

Each buffer entry is a dict.

Current common fields:

```text
path
wid
readonly
```

If you add a new field:

1. update buffer creation
2. update kill behavior
3. update frontend assumptions
4. document the field
5. avoid breaking existing plugins

Example:

```tcl
dict set buffers $name my_field "value"
```

Do not store live widgets in buffer metadata unless the frontend owns them.

---

## Changing the plugin loader

Be very careful here.

The plugin loader owns:

```text
plugin namespaces
plugin metadata
ownership tracking
state save/restore
unload order
```

Important rules:

```text
The loader namespace is the source of truth for plugin identity.
The DSL must not override plugin identity.
Cleanup must run before namespace deletion.
State must be restored before init.
Unload must continue even if cleanup fails.
```

If you modify `Tclme::LoadPlugin`, test:

```text
load
reload
unload
broken plugin init
broken plugin cleanup
missing plugin file
plugin with state
plugin with UI
headless loading
```

---

## Plugin lifecycle order

For new-style plugins:

```text
source plugin file
restore state
call init
emit plugin-loaded
```

For unload:

```text
call cleanup
remove commands
remove aliases
remove bindings
remove hooks
cancel tracked afters
delete namespace
remove plugin metadata
emit plugin-unloaded
```

Do not change this order casually.

---

## Output model

Use:

```tcl
Tclme::Print
```

for persistent transcript output.

Use:

```tcl
Tclme::Message
```

for user-facing messages.

Use:

```tcl
Tclme::Note
```

for transient notes.

Use:

```tcl
Tclme::Log
```

for internal logging.

The kernel's `Print` stores transcript entries and calls the active output sink.

The output sink receives:

```tcl
text tag
```

Example sink:

```tcl
proc MySink {text tag} {
    puts stdout $text
}

Tclme::SetOutputSink MySink
```

The Tk frontend should set a sink that appends to the transcript buffer.

---

## Modifying the Tk frontend

The Tk frontend may override kernel stubs.

Common overrides:

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

When hacking the frontend:

```text
Keep the kernel headless.
Keep frontend overrides idempotent.
Do not assume buffers have widgets in headless mode.
Do not put file/widget assumptions into the kernel.
```

---

## Debugging the kernel

Use the headless REPL first.

```sh
./tclme-repl.tcl
```

Then:

```text
:help
:plugins
:eval dict keys $::Tclme::commands
:eval dict keys $::Tclme::listeners
:eval dict keys $::Tclme::plugin_meta
```

For GUI debugging:

```text
:log
:eval winfo children .
:eval winfo children .ws
:eval bindtags $::Tclme::active_widget
```

Use:

```tcl
Tclme::Log error "message"
```

for kernel errors.

---

## Dangerous areas

Be especially careful in these areas.

### 1. Plugin unload

Unload must remove everything the plugin registered.

Missing cleanup causes duplicate hooks, stale commands, and ghost bindings.

---

### 2. Keybindings

`Tclme::BindKey` is global.

Buffer-local keymaps are not fully solved yet.

If you add buffer-local bindings, prefer widget-specific bindings and clean them up carefully.

---

### 3. Focus

Focus bugs are common.

Rules:

```text
Do not steal focus during prompts.
Do not steal focus during completion.
Return focus to the appropriate widget after commands.
Check winfo exists before focusing.
```

---

### 4. Geometry management

Do not mix `pack` and `grid` inside the same container.

Be careful when inserting panels before `.sep1`, `.status`, or `.ws`.

---

### 5. After callbacks

Use `after` carefully.

Cancel timers on unload.

Avoid repeated unbounded timers.

---

### 6. Event recursion

Do not emit events from inside listeners for the same event unless you know what you are doing.

Example danger:

```text
status-line listener calls RefreshStatus
RefreshStatus emits status-line
```

Avoid recursive event loops.

---

## Kernel style guide

Use:

```text
Tclme::ProcName       for kernel procedures
lower-case            for commands
lower-case-with-dash  for user commands
snake_case            for variables
```

Prefer:

```text
small procs
dict state
catch around risky operations
explicit error logging
frontend stubs for UI-dependent behavior
```

Avoid:

```text
global variables
Tk calls in kernel
hidden magic
silent failures
plugin-specific knowledge in kernel
```

---

## Kernel patch checklist

Before committing a kernel change:

```text
Does ktclme.tcl still load in tclsh?
Does the headless REPL still start?
Does the Tk frontend still start?
Do existing plugins load?
Do plugins reload cleanly?
Do prompts still work?
Does focus behave correctly?
Did you update ARCHITECTURE.md?
Did you update PLUGIN-COOKBOOK.md if plugin-facing behavior changed?
Did you avoid adding Tk dependencies to the kernel?
```

---

## Versioning policy

Suggested policy:

```text
Major:
    breaking kernel API change
    breaking plugin lifecycle change
    breaking event contract change

Minor:
    backward-compatible new kernel APIs
    new events
    new commands

Patch:
    bug fixes
    documentation fixes
```

The DSL is separate from the kernel.

It can have its own version:

```text
DSL v2
```

---

## Kernel roadmap ideas

Possible future work:

```text
buffer-local keymaps
mode-local keymaps
event context objects
command argument parsing
session persistence
frontend capability negotiation
rich headless prompts
plugin manifests
plugin dependency metadata
headless plugin capability declarations
test harness
buffer model formalization
```

When adding new features, prefer additive changes first.

---

## Golden rule

The kernel's job is:

```text
read a line
dispatch or evaluate it
print the result
fire hooks around the whole thing
keep the live image running
```

Everything else is a frontend or a plugin.
```