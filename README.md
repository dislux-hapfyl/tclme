# Tclme

Tclme is a small, hackable, live Tcl/Tk programming environment.

It began as a tiny extensible text editor, but it has grown into something more interesting: a headless Tcl kernel with a command loop, event bus, plugin loader, transcript, and multiple frontends.

The Tk editor is one frontend.

The headless REPL is another frontend.

The plugins are where the system becomes yours.

## How the Tclme Kernel Teaches Tcl

You have built something genuinely rare: a non-trivial Tcl program whose architecture is *driven by* Tcl's semantics rather than fighting them. 

The reason this kernel works as a teaching example is that it does not try to make Tcl look like Python, or JavaScript, or C++. It does not build a class system. It does not build a module system. It does not build a type system.

It uses:

- **strings** for commands
- **lists** for scripts and arguments
- **dicts** for registries and metadata
- **namespaces** for plugins and encapsulation
- **`info commands`** for existence checks
- **`uplevel`** for dynamic scope
- **`catch`** for fault isolation
- **`variable`** for shared state
- **`source`** for code loading

That is the whole toolkit. Everything else is composition.

That is what "using Tcl properly" means: not building abstractions **on top of** Tcl to hide it, but building abstractions _out of_ Tcl's own primitives.

---

## Status

Tclme is pre-1.0.

It is usable, hackable, and actively evolving, but the API may still change. It is primarily a personal live programming environment, not a polished end-user product.

---

## What is Tclme?

Tclme is built around a simple idea:

```text
The editor is not a closed application.
It is a running Tcl image that you can modify while it is alive.
```

You can:

- define new commands while the program is running
- load and reload plugins without restarting
- inspect kernel state live
- extend the editor with Tcl
- run a headless REPL frontend
- build GUI and non-GUI tools on the same kernel

---

## Features

- Small Tcl/Tk 8.6 kernel
- Headless kernel usable from `tclsh`
- Tk editor frontend
- Headless REPL frontend
- Command registry
- Aliases
- Event bus
- Plugin loader
- Hot plugin reload
- Plugin lifecycle hooks
- Plugin state save/restore
- Plugin DSL
- Transcript / REPL output buffer
- Output sink abstraction
- Buffer model with headless stubs
- Minibuffer / ex-command style input
- Extensible status line
- Experimental plugins for editing, navigation, search, highlighting, and more

---

## Architecture

Tclme is split into layers.

```text
tclme.tcl               headless kernel
tclem.tcl               Plugin DSL
tcled.tcl               Tk editor frontend
tclit.tcl               headless REPL frontend
tclus.tcl               GUI launcher
```

The kernel provides:

```text
command registry
event bus
plugin loader
transcript
output sink
logging
dispatch loop
headless buffer stubs
```

The Tk frontend provides:

```text
windows
text widgets
buffers
minibuffer
status line
themes
file operations
keybindings
focus handling
```

The headless REPL provides:

```text
terminal input/output
scripting
testing
kernel debugging
plugin experimentation
```
---

## Requirements

Required:

```text
Tcl 8.6
Tk 8.6
wish8.6
```

---

## Headless REPL

Tclme can also run without Tk.

Inside the REPL:

```text
:help
:plugins
expr 2 + 3
:unload example
:load example
:reload example
```

The headless REPL is useful for testing plugins, kernel changes, and command behavior without starting the GUI.

---

## Default keybindings

Default keybindings depend on the frontend.

Common Tk frontend bindings include:

```text
C-x C-c       quit
C-x C-s       save current buffer
C-x C-f       open file
C-x C-e       evaluate Tcl
C-x b         switch buffer
C-x k         kill buffer
C-x C-r       reload plugins
C-g           cancel prompt
C-l           goto line
```

Plugins may add their own bindings.

---

## Plugins

Plugins live in:

```text
plugins/
```

A plugin file named:

```text
plugins/example.tcl
```

is loaded into:

```tcl
::Tclme::Plugin::example
```

The filename defines the plugin identity.

Plugins should not declare their own internal plugin name.

---

## Writing a plugin

Tclme uses a strict nameless plugin DSL.

Example:

```tcl
Tclme::Plugin {
    description "Example plugin"
    version 0.1.0

    state {
        count 0
    }

    command hello {args} {
        variable state

        dict incr state count

        ::Tclme::Message "Hello from example plugin, count: [dict get $state count]"
    }

    bind <Control-x><Control-h> hello

    on after-save {path} {
        ::Tclme::Print "Saved: $path"
    }

    init {
        ::Tclme::Print "example plugin initialized"
    }

    cleanup {
        ::Tclme::Print "example plugin cleaned up"
    }
}
```

Save it as:

```text
plugins/example.tcl
```

Then reload:

```text
:reload example
```

Run it:

```text
:hello
```

Create a new plugin template with:

```text
:plugin-new myplugin
```

---

## Plugin lifecycle

Plugins may define:

```text
init
cleanup
state
restore
```

Legacy names are also supported by the loader:

```text
load
unload
save-state
restore-state
```

Preferred modern form:

```text
init       called after plugin load and state restore
cleanup    called before unload
state      returns serializable plugin state
restore    restores saved state
```

Plugin state should be plain Tcl data, usually a dict.

Good state:

```tcl
dict create enabled 1 count 0
```

Bad state:

```tcl
widget paths
file channels
sockets
timers
live objects
```

---

## Plugin DSL

The DSL is intentionally small.

Supported directives:

```text
description
version
headless
state
command
bind
on
init
cleanup
do
```

The DSL is sugar.

It expands into normal Tclme APIs.

Raw Tcl is always available through the `do` directive.

The DSL is optional. Raw plugins still work.

---

## Headless-safe plugins

Plugins that do not require Tk can run in both the GUI and the headless REPL.

GUI-only plugins should guard against headless mode:

```tcl
if {[::Tclme::IsHeadless]} {
    return
}

Tclme::Plugin {
    ...
}
```

Plugins are trusted code. They can modify Tclme, create UI, read files, open sockets, and change global state.

---

## Experimental plugins

Depending on the repository state, the plugins directory may include experimental plugins such as:

```text
C syntax highlighting
buffer bar
buffer tiling
line numbers
Dired-style file browser
project grep
procedure sidebar
Markdown preview
find/replace panel
debugger/inspector
Acme-style mouse search
HTTP fetch
IRC client
OpenBSD export helper
```

These plugins are examples and testbeds for the kernel, not guaranteed stable applications.

---

Useful commands:

```text
:help
:log
:plugins
:plugin-show NAME
:plugin-clean
:eval expr 2 + 3
:eval dict keys $::Tclme::commands
:eval dict keys $::Tclme::plugin_meta
:eval info commands ::Tclme::Plugin::NAME::*
```
---

## Contributing

This is a personal hackable environment, but contributions are welcome.

Good contributions:

- preserve the headless kernel
- do not add Tk dependencies to the kernel
- keep plugins reload-safe
- clean up after themselves
- update documentation
- avoid unnecessary magic
- keep Tcl as the extension language

Before submitting changes:

```text
Test the headless REPL.
Test the Tk frontend.
Test plugin reload.
Test plugin unload.
Update docs if behavior changed.
```

---

```text
Released under the MIT License. See LICENSE for details.
```
