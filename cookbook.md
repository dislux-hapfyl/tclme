# Tclme Plugin Cookbook

This cookbook shows how to write plugins for Tclme using the current plugin system and the strict nameless DSL.

Tclme plugins can:

- define commands
- bind keys
- listen to events
- keep state across reloads
- create UI panels
- extend the status line
- manipulate buffers
- run headless-safe or GUI-only

---

## Plugin model

A plugin is a file inside:

```text
plugins/
```

Example:

```text
plugins/example.tcl
```

It is loaded into:

```tcl
::Tclme::Plugin::example
```

The plugin filename defines the plugin identity.

Plugins should use the DSL:

```tcl
Tclme::Plugin {
    ...
}
```

The DSL must not be given a plugin name.

Correct:

```tcl
Tclme::Plugin {
    description "Example"
}
```

Incorrect:

```tcl
Tclme::Plugin example {
    description "Example"
}
```

The nameless form is required for long-term stability.

---

## Creating a new plugin

Use:

```text
:plugin-new myplugin
```

This creates:

```text
plugins/myplugin.tcl
```

Then reload:

```text
:reload myplugin
```

---

## Minimal plugin

```tcl
Tclme::Plugin {
    description "Minimal example plugin"
    version 0.1.0

    command hello {args} {
        ::Tclme::Message "Hello from myplugin"
    }
}
```

Reload and run:

```text
:reload myplugin
:hello
```

---

## Plugin directives

The DSL supports:

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

---

## `description`

Metadata only.

```tcl
description "Does something useful"
```

---

## `version`

Metadata only.

```tcl
version 0.1.0
```

---

## `headless`

Metadata only in DSL v2.

```tcl
headless safe
```

or:

```tcl
headless ui
```

For plugins that require Tk, also guard the file:

```tcl
if {[::Tclme::IsHeadless]} {
    return
}

Tclme::Plugin {
    ...
}
```

---

## `state`

Plugins should store state in a dict.

```tcl
Tclme::Plugin {
    description "State example"

    state {
        enabled 1
        count 0
    }

    command bump {args} {
        variable state

        dict incr state count

        ::Tclme::Message "Count: [dict get $state count]"
    }
}
```

The DSL generates:

```tcl
proc state {} { ... }
proc restore {saved} { ... }
```

so state can survive reloads.

---

## Defining commands

```tcl
command mycommand {args} {
    ::Tclme::Message "mycommand ran"
}
```

With documentation:

```tcl
command mycommand {args} {
    ::Tclme::Message "mycommand ran"
} "Run mycommand"
```

Command argument parsing is manual.

Example:

```tcl
command greet {args} {
    set name [string trim [join $args " "]]

    if {$name eq ""} {
        set name "world"
    }

    ::Tclme::Message "Hello, $name"
} "Greet someone"
```

Usage:

```text
:greet Alice
```

---

## Keybindings

Define the command first, then bind it.

```tcl
Tclme::Plugin {
    description "Keybinding example"

    command hello {args} {
        ::Tclme::Message "Hello"
    }

    bind <Control-x><Control-h> hello
}
```

Bindings registered through `bind` use `Tclme::BindKey` underneath.

---

## Events

Use `on` to listen to events.

```tcl
on after-save {path} {
    ::Tclme::Print "Saved: $path"
}
```

Example with priority:

```tcl
on after-save {path} {
    ::Tclme::Print "Saved: $path"
} 20
```

Lower priority numbers run earlier.

---

## Cancelable hooks

Some events are cancelable.

Example: refuse to save `.bak` files.

```tcl
on before-save {path} {
    if {[string match "*.bak" $path]} {
        return "Refusing to save .bak files"
    }

    return ""
}
```

Returning an empty string allows the action.

Returning a non-empty string cancels it.

---

## Contributing to the status line

The `status-line` event collects strings from all listeners.

```tcl
on status-line {buffer_name} {
    return "example"
}
```

Multiple plugins can contribute to the status line at the same time.

---

## Prompts

Prompts are frontend-provided.

In the Tk frontend, use:

```tcl
::Tclme::Prompt
```

Example:

```tcl
Tclme::Plugin {
    description "Prompt example"

    command ask-name {args} {
        ::Tclme::Prompt "Name: " [namespace current]::got-name
    }

    do {
        proc got-name {input} {
            set input [string trim $input]

            if {$input eq ""} {
                ::Tclme::Message "No name given"
                return
            }

            ::Tclme::Message "Hello, $input"
        }
    }
}
```

In headless mode, prompts are unavailable unless a frontend implements them.

---

## Reading and writing buffer text

Prefer the buffer API over poking widgets directly.

```tcl
set text [::Tclme::GetBufferContent $::Tclme::current_buffer]
```

Example command:

```tcl
command uppercase {args} {
    set name $::Tclme::current_buffer

    if {$name eq ""} {
        ::Tclme::Message "No current buffer"
        return
    }

    set text [::Tclme::GetBufferContent $name]
    ::Tclme::SetBufferContent $name [string toupper $text]
}
```

---

## Special output buffers

Use:

```tcl
::Tclme::ShowInBuffer
```

Example:

```tcl
command show-note {args} {
    ::Tclme::ShowInBuffer "*Note*" "This is a read-only note buffer.\n" 1
}
```

The third argument makes the buffer read-only.

---

## UI panels

UI plugins should guard against headless mode.

```tcl
if {[::Tclme::IsHeadless]} {
    return
}

Tclme::Plugin {
    description "Example panel"
    headless ui

    init {
        build-panel
    }

    cleanup {
        destroy-panel
    }

    do {
        proc build-panel {} {
            if {[winfo exists .example_panel]} {
                return
            }

            ::frame .example_panel

            ::button .example_panel.hello \
                -text "Say Hello" \
                -command [namespace current]::say-hello

            pack .example_panel.hello -side left -padx 4 -pady 2
            pack .example_panel -fill x -before .sep1
        }

        proc destroy-panel {} {
            if {[winfo exists .example_panel]} {
                destroy .example_panel
            }
        }

        proc say-hello {} {
            ::Tclme::Message "Hello from panel"
        }
    }
}
```

Rules for UI plugins:

- create widgets in `init`
- destroy widgets in `cleanup`
- check `winfo exists`
- use theme colors where possible
- do not assume `.sep1`, `.status`, or `.minibar` exist unless you check

---

## Timers

If you create timers, cancel them in `cleanup`.

```tcl
Tclme::Plugin {
    description "Timer example"

    do {
        variable timer ""

        proc start-ticker {} {
            variable timer

            stop-ticker

            set timer [after 1000 [namespace current]::tick]]
        }

        proc stop-ticker {} {
            variable timer

            if {$timer ne ""} {
                catch { after cancel $timer }
                set timer ""
            }
        }

        proc tick {} {
            variable timer

            ::Tclme::Print "tick"

            set timer [after 1000 [namespace current]::tick]
        }
    }

    init {
        start-ticker
    }

    cleanup {
        stop-ticker
    }
}
```

If you want Tclme to help track one-shot timers, use:

```tcl
::Tclme::PluginAfter
```

But repeating timers should still be canceled in `cleanup`.

---

## Headless-safe plugins

Headless-safe plugins should avoid Tk.

Good headless-safe plugin behavior:

```text
commands only
event hooks only
text processing
parsing
calculations
headless buffer metadata
```

Example:

```tcl
Tclme::Plugin {
    description "Headless-safe plugin"

    command now {args} {
        ::Tclme::Print [clock format [clock seconds]]
    }
}
```

---

## GUI-only plugins

GUI-only plugins should return early in headless mode.

```tcl
if {[::Tclme::IsHeadless]} {
    return
}

Tclme::Plugin {
    description "GUI-only plugin"
    headless ui

    init {
        # Create UI here.
    }

    cleanup {
        # Destroy UI here.
    }
}
```

---

## Debugging plugins

Useful commands:

```text
:plugins
:plugin-show myplugin
:log
:reload myplugin
```

Useful eval commands:

```text
:eval dict keys $::Tclme::plugin_meta
:eval info commands ::Tclme::Plugin::myplugin::*
:eval set ::Tclme::Plugin::myplugin::__dsl_body
```

Use:

```tcl
::Tclme::Print "debug message"
```

for transcript output.

Use:

```tcl
::Tclme::Log error "something failed"
```

for errors.

---

## Common plugin mistakes

### 1. Creating UI in headless mode

Always guard:

```tcl
if {[::Tclme::IsHeadless]} {
    return
}
```

---

### 2. Forgetting cleanup

If your plugin creates it, your plugin should destroy it.

Clean up:

- widgets
- timers
- sockets
- bindings
- tags
- hooks

---

### 3. Using raw global variables

Prefer plugin state:

```tcl
state {
    enabled 1
}
```

and:

```tcl
variable state
```

---

### 4. Binding before defining the command

Define commands before binding them.

Bad:

```tcl
bind <Control-x><Control-h> hello

command hello {args} {
    ...
}
```

Good:

```tcl
command hello {args} {
    ...
}

bind <Control-x><Control-h> hello
```

---

### 5. Assuming prompts exist in headless mode

Prompts are frontend-provided.

Guard or degrade gracefully.

---

### 6. Using `after` without canceling

Always cancel timers in `cleanup`.

---

### 7. Forgetting that events are frontend-dependent

Some events only exist in the Tk frontend.

Examples:

```text
before-save
after-save
buffer-killed
theme-changed
cursor-moved
status-line
```

The headless kernel emits some of these, but graphical frontends emit more.

---

## Plugin checklist

Before shipping a plugin:

```text
Does it load cleanly?
Does it reload cleanly?
Does it unload cleanly?
Does it work headless if marked headless-safe?
Does it guard against headless mode if GUI-only?
Does it clean up widgets/timers/bindings?
Does it use Tclme::Print for persistent output?
Does it use Tclme::Message for user-facing messages?
Does it avoid writing directly to widgets when buffer APIs exist?
Does it handle missing buffers/widgets defensively?
```
