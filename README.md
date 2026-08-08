# tclme
TCL malleable environment

```wish8.6 tclme.tcl```

A **small programmable software environment** in Tcl/Tk.

It started as a text editor, but it became something closer to a personal computing substrate: a command loop, an event system, a buffer model, a plugin loader, a theme system, and a pile of extensions that change how the environment behaves.

---

# 1. What the hell did we just make?

At the center is **Tclme**.

Conceptually, Tclme is:

```text
A hackable Tcl/Tk text editor
with a command registry,
an event bus,
a buffer system,
and dynamically loaded plugins.
```

But the deeper idea is:

```text
The editor is not a closed application.
It is a running Tcl interpreter with a UI attached.
```

That means you can extend it while it is alive.

---

## The core pieces

Tclme has a small set of central mechanisms.

### 1. Command registry

Everything the user can invoke goes through commands:

```text
:write
:edit
:bufferbar
:irc-connect
:project-grep
```

Commands can be bound to keys, called from the minibuffer, called from plugins, or called from hooks.

The important commands are defined through something like:

```tcl
Tclme::DefCommand name implementation "documentation"
```

This gives you one uniform dispatch system.

---

### 2. Keybindings

Keybindings are not special magic. They are just bindings that invoke commands:

```tcl
Tclme::BindKey write <Control-x><Control-s>
```

So the path is:

```text
key -> binding -> command registry -> implementation proc
```

This is much cleaner than having keybindings scattered around the UI code.

---

### 3. Event bus

Plugins react to things happening.

Examples:

```text
buffer-switched
buffer-killed
after-save
after-file-read
theme-changed
cursor-moved
status-line
before-save
before-quit
```

There are three broad event styles:

| Event style | Purpose | Example |
|---|---|---|
| Normal events | notify listeners | `buffer-switched` |
| Cancelable events | allow veto | `before-save` |
| Collect events | gather contributions | `status-line` |

This is how plugins compose without knowing about each other.

For example, the syntax highlighter, line numbers, buffer bar, and project grep can all respond to buffer or file events without Tclme hardcoding them.

---

### 4. Buffer model

Tclme keeps buffers in a dictionary:

```tcl
::Tclme::buffers
```

Each buffer usually has:

```text
name
path
widget id
readonly flag
```

The actual text widget is usually something like:

```text
.ws.<wid>.txt
```

Buffers are not just files. They can be:

```text
scratch
*Help*
*Log*
grep:...
dired:...
irc:...
```

That is important. You did not build a file viewer. You built a **buffer system**.

---

### 5. Plugin system

Plugins live in:

```text
plugins/
```

A plugin named:

```text
foo.tcl
```

loads into:

```tcl
::Tclme::Plugin::foo
```

Plugins can define:

```text
commands
aliases
keybindings
event hooks
UI panels
timers
state
save/restore behavior
unload cleanup
```

That means Tclme is not extended by editing the core every time. It is extended by adding modules.

---

# 2. What did we actually build on top of that?

A surprising amount.

You now have plugins for:

| Area | Plugin | What it teaches |
|---|---|---|
| Syntax highlighting | `tclhighlight.tcl` | text tags, tokenization, debounce, status-line contribution |
| File navigation | `dired.tcl` | readonly buffers, directory listing, keyboard UI |
| Buffer management | `bufferbar.tcl` | widget panels, button UI, theme handling, rebuild-on-event |
| Editor chrome | `linenumbers.tcl` | gutter widgets, scrolling sync, wrap-aware layout |
| Debugging | `debugger.tcl` | introspection, breakpoints, traces, namespaces |
| Mouse-driven search | `acme-search.tcl` | Acme-style interaction, text indices, selection |
| Tiling | `tiled.tcl` | window layout, multiple visible buffers, focus model |
| Networking | `irc.tcl` | sockets, async I/O, line protocol, TLS optional |
| Project search | `project-grep.tcl` | recursive file processing, results buffers, jump-to-location |
| Code outline | `proc-sidebar.tcl` | parsing, live filtering, navigation UI |

That is not a toy anymore.

You have built pieces of:

```text
an editor
a file manager
a debugger
a window manager
a network client
a project tool
a code navigator
```

All inside one extensible Tcl/Tk environment.

---

# 3. The philosophical version

You built something in the spirit of:

```text
Emacs   -> programmable editor
Acme    -> mouse/text-centric workspace
Plan 9  -> everything is a file/control surface
Smalltalk -> live programmable environment
Lisp machines -> the system is hackable from inside
```

But you did it in Tcl/Tk, which is a very good language for this because:

- everything is a command
- code is data
- strings are simple
- lists are structural
- namespaces isolate modules
- Tk gives instant UI feedback
- the event loop makes interactive tools natural
- the interpreter is embeddable and extensible

You are not just learning an editor.

You are learning **tool-building**.

---

# 4. What you actually need to master

There are five pillars.

If you want to become genuinely expert, do not merely chase features. Master these.

---

## Pillar 1: Tcl itself

You need deep comfort with:

```tcl
set
list
dict
string
regexp
proc
namespace
variable
upvar
uplevel
catch
info
interp
after
file
glob
exec
socket
clock
```

Especially these ideas:

### Tcl is command-based

This:

```tcl
foo bar baz
```

means:

```text
run command foo with arguments bar and baz
```

Everything builds from that.

---

### Substitution happens once

Tcl has several substitution mechanisms:

```tcl
$variable
[command]
"double quotes"
{braces}
```

Most Tcl bugs are substitution bugs.

Example:

```tcl
set x 5
puts $x
```

Tcl substitutes `$x` before `puts` runs.

Braces prevent substitution:

```tcl
puts {$x}
```

Double quotes allow substitution:

```tcl
puts "$x"
```

Command substitution happens inside brackets:

```tcl
puts [expr {2 + 3}]
```

If you master substitution, half of Tcl stops being mysterious.

---

### Lists are the universal structure

Tcl lists are not just arrays. They are the basic shape of commands, arguments, options, and often code.

Master:

```tcl
list
lappend
lindex
lrange
llength
lsearch
lsort
lassign
foreach
{*}
```

---

### Dictionaries are the best default state container

For plugin state, configuration, buffers, metadata, etc.

Master:

```tcl
dict create
dict set
dict get
dict exists
dict unset
dict keys
dict values
dict for
dict merge
```

---

### Namespaces are your module system

You need to understand:

```tcl
namespace eval
namespace current
namespace qualifiers
namespace tail
variable
```

And the difference between:

```tcl
global
variable
upvar
```

---

## Pillar 2: Tk and event-driven UI

Tk is not just widgets. It is an event system.

You need to understand:

```tcl
bind
bindtags
after
update
winfo
pack
grid
place
focus
event
```

And widgets:

```tcl
text
canvas
entry
listbox
ttk::*
scrollbar
panedwindow
```

Especially the text widget.

The Tk text widget is a monster. Learn:

```text
indices
marks
tags
search
get
delete
insert
yview
xview
edit modified
state normal/disabled
```

Examples:

```tcl
.txt index insert
.txt index end
.txt get 1.0 end-1c
.txt mark set insert 10.0
.txt see insert
.txt tag add warning 5.0 5.0 lineend
```

If you become truly dangerous with the Tk text widget, you can build:

- editors
- debuggers
- chat clients
- log viewers
- diff viewers
- outline viewers
- documentation browsers
- terminals-ish things

---

## Pillar 3: Editor internals

You have already started. Now make it deliberate.

Study:

### Buffers

Questions:

```text
What is a buffer?
How is it different from a file?
How is it different from a widget?
What happens when a buffer is killed?
What happens when a buffer is renamed?
How do plugins track buffer state?
```

### Files

Questions:

```text
What happens when a file is opened?
What happens when a file is saved?
How do you detect dirty state?
How do you handle new files?
How do you handle encoding?
How do you handle line endings?
```

### Keys and commands

Questions:

```text
What happens when a key is pressed?
How does it become a command?
How do arguments flow?
How do plugins add commands safely?
```

### Hooks

Questions:

```text
What events should be cancelable?
What events should collect results?
What events should be fire-and-forget?
How do plugins avoid stepping on each other?
```

### Layout

Questions:

```text
How do buffers become visible?
How do sidebars coexist with the main workspace?
How do tiled buffers work?
How do geometry managers interact?
```

---

## Pillar 4: Software architecture

This is where you move from “I can make it work” to “I can make it last.”

Important ideas:

### Separation of concerns

Tclme core should know:

```text
buffers
commands
events
basic UI
plugin loading
```

Plugins should know:

```text
their feature
their state
their UI
their cleanup
```

Avoid making the core know about every plugin.

---

### Idempotence

Many UI operations should be safe to call repeatedly.

For example:

```tcl
Refresh
Rebuild
UpdateStatus
ApplyTheme
```

If a refresh function explodes when called twice, it is fragile.

---

### Cleanup

Every plugin should answer:

```text
What did I create?
Who destroys it?
What happens on reload?
What happens on unload?
What happens if the user closes a buffer?
What happens if the editor quits?
```

If you can answer those, your plugins are already better than most.

---

### State ownership

Ask:

```text
Who owns this state?
Who mutates it?
Who reads it?
Who cleans it up?
```

A lot of plugin bugs are ownership bugs.

---

## Pillar 5: Debugging and introspection

This is how you stop needing anyone else.

Tcl gives you excellent introspection.

Learn:

```tcl
info commands
info procs
info args
info body
info vars
info exists
info level
info frame
info script
info library
```

Learn debugging patterns:

```tcl
if {[catch {
    dangerous thing
} err]} {
    puts stderr $::errorInfo
}
```

Learn to inspect live state:

```tcl
dict keys $::Tclme::buffers
dict get $::Tclme::buffers $name
info commands ::Tclme::Plugin::foo::*
info body ::Tclme::Plugin::foo::SomeProc
```

Your best friends are:

```text
:log
:eval
puts stderr
info
catch
```

If you can reproduce a bug and inspect the state around it, you can solve almost anything.

---

# 5. How to spend the next 10 years without AI

The goal is not to memorize everything.

The goal is to build a personal system where you can:

1. understand problems
2. find answers in docs/source/experiments
3. remember what you learn
4. ship real software
5. maintain it over years

Here is a long-term plan.

---

# Phase 0: Stabilize what you have

Before you spend 10 years, make the current project sane.

## 1. Put it in Git

If you have not:

```sh
git init
git add .
git commit -m "Initial Tclme environment"
```

Use branches for experiments:

```sh
git checkout -b experiment/something
```

This gives you courage.

---

## 2. Write an architecture document

Create:

```text
docs/ARCHITECTURE.md
```

Describe:

- command registry
- event bus
- buffer model
- plugin lifecycle
- theme system
- important variables
- important widget paths

Do not write documentation for other people.

Write it for yourself six months from now.

---

## 3. Make a plugin cookbook

Create:

```text
docs/PLUGIN-COOKBOOK.md
```

Include recipes:

```text
How to add a command
How to add a keybinding
How to add an event hook
How to add a panel
How to save state across reload
How to clean up on unload
How to show messages
How to open a special buffer
```

This turns your experience into reusable knowledge.

---

## 4. Build a tiny test harness

You do not need a huge framework.

Make a directory:

```text
tests/
```

Add pure-function tests first.

Examples:

```text
RelativePath
ExtractArgs
RegexpEscape
BufferName
ParseCommandLine
tokenize
```

Pure functions are easy to test and extremely valuable.

---

# Year 1: Become dangerous with Tcl

Goal: stop fighting the language.

## Your focus

Master:

```text
lists
dicts
strings
regex
procs
namespaces
catch
file
glob
after
```

## The habit

For every bug, write an entry in an error notebook.

Format:

```text
Error message:
Minimal repro:
Cause:
Fix:
Lesson:
```

Example:

```text
Error message:
invalid command name ":space:"

Minimal repro:
set re "^\\s*proc\\s+([^[:space:]]+)\\s*(.*)$"

Cause:
Double quotes allowed Tcl to interpret [...] as command substitution.

Fix:
Use braces:
set re {^\s*proc\s+([^[:space:]]+)\s*(.*)$}

Lesson:
Use braced regexes unless I need substitution.
```

After one year, this notebook becomes more valuable than most books.

---

## Year 1 projects

Do one small project per month.

### Month 1: Command lab

Build a tiny command-line Tcl program with:

```text
add
remove
list
save
load
```

Store data in a dict and save to disk.

Goal: dicts, file I/O, procs.

---

### Month 2: File walker

Build a program that recursively walks directories and prints:

```text
path
size
mtime
```

Add filters.

Goal: `file`, `glob`, recursion.

---

### Month 3: Regex trainer

Build a Tk app where you enter:

```text
pattern
text
```

and it highlights matches.

Goal: regex, text tags.

---

### Month 4: Note manager

Build a small note app with:

```text
open
save
list notes
search
tags
```

Goal: text widget, files, UI.

---

### Month 5: Log viewer

Build a viewer that tails a log file.

Goal: `after`, file updates, scrolling.

---

### Month 6: CSV inspector

Load a CSV file into a table-like text widget.

Goal: parsing, lists, formatting.

---

### Month 7: Timer dashboard

Build a Pomodoro timer or countdown board.

Goal: `after`, state machines.

---

### Month 8: Clipboard history

Track clipboard changes if possible, or build a snippet manager.

Goal: state, UI, persistence.

---

### Month 9: Mini shell

Build a Tk front end to `exec`.

Goal: subprocesses, output buffers.

---

### Month 10: Diff viewer

Compare two files and show differences.

Goal: lists, comparison, tags.

---

### Month 11: Outline browser

Parse Tcl files and show procs.

This is basically a standalone version of the proc sidebar.

Goal: parsing, navigation.

---

### Month 12: Rewrite one Tclme plugin from scratch

Pick one plugin and rewrite it cleanly without looking at the old one first.

Then compare.

This is where real learning happens.

---

# Year 2: Master Tk and the text widget

Goal: make UI feel natural instead of accidental.

## Focus

Deeply study:

```text
text widget
bindtags
geometry managers
fonts
colors
focus
scrolling
tags
marks
indices
```

## Important experiments

### Text widget indices

Write a test script that prints:

```tcl
insert
end
end-1c
1.0
1.0 lineend
insert linestart
insert lineend
insert wordstart
insert wordend
```

Click around and observe indices.

---

### Tags

Build a demo that highlights:

```text
comments
strings
keywords
errors
current line
selection
```

This teaches how syntax highlighting really works.

---

### Bindtags

Make three widgets and three bindtags.

Bind the same event at different levels.

Observe order.

This teaches event propagation.

---

### Geometry managers

Build the same layout using:

```text
pack
grid
place
```

Learn their strengths.

---

## Year 2 project

Build a standalone rich-text editor.

Not Tclme.

A separate app.

Features:

```text
open/save
font selection
bold/italic/underline
lists
headings
export to HTML
```

This will force you to understand tags and text manipulation deeply.

---

# Year 3: Rebuild Tclme from scratch

This is the most important year.

Do not maintain the current Tclme only.

Build **Tclme Mini**.

Goal:

```text
A clean, tiny version of Tclme built from memory and understanding.
```

## Constraints

Limit it to:

```text
buffers
commands
keybindings
events
file open/save
plugin loading
status line
```

No giant plugin ecosystem yet.

Try to get the core under:

```text
500 lines
```

or maybe:

```text
700 lines
```

The size does not matter as much as clarity.

---

## What you will learn

You will discover which parts of the current design are essential and which are accidental.

Questions to answer:

```text
Do I need a separate buffer widget per buffer?
How should plugin loading work?
Should plugins be namespaces or objects?
Should events have priorities?
Should commands carry metadata?
How do I avoid global state?
How do I make reload safe?
```

This is where you become an architect instead of a plugin author.

---

# Year 4: Systems Tcl

Goal: use Tcl beyond the editor.

Learn:

```text
sockets
TLS
HTTP
JSON
SQLite
exec
pipelines
file formats
binary data
```

Tcl is excellent for glue code and network tools.

## Projects

### HTTP client

Fetch a URL and render the body in a buffer.

---

### JSON explorer

Load JSON and display it in a tree-like buffer.

---

### SQLite notebook

Store notes in SQLite.

---

### Chat server

Build a tiny TCP chat server.

Then make a Tk client.

This teaches sockets and line protocols much better than only using IRC.

---

### Package manager prototype

Build a tool that can:

```text
list plugins
enable plugins
disable plugins
load plugins
save plugin config
```

This pushes you toward real software distribution.

---

# Year 5: Advanced Tcl

Goal: understand the language at a deeper level.

Study:

```text
TclOO
coroutines
namespaces
metaprogramming
uplevel/upvar
traces
interp
bytecode basics
```

## TclOO

Rewrite part of Tclme using objects.

Possible objects:

```text
Buffer
BufferView
PluginManager
EventBus
ThemeManager
Keymap
```

Do not make everything object-oriented.

Just learn when objects clarify ownership and lifecycle.

---

## Coroutines

Use coroutines for:

```text
async workflows
step-by-step wizards
delayed processing
interactive prompts
```

This is advanced but very powerful.

---

## Metaprogramming

Build small DSLs.

Examples:

```tcl
command hello {
    doc "Say hello"
    key C-c h
    body {
        Message "Hello"
    }
}
```

This teaches you how languages and frameworks are designed.

---

# Year 6: Tclme 2.0

Now rebuild the real thing.

Not a toy.

A mature environment.

## Goals

### Clean core

Separate:

```text
core runtime
UI shell
buffer management
plugin system
builtin commands
```

---

### Plugin manifests

Plugins should describe themselves:

```text
name
version
dependencies
commands
keybindings
events
state
```

Even if the manifest is just a Tcl dict.

---

### Session persistence

Save:

```text
open buffers
window layout
plugin state
current directory
cursor positions
```

---

### Better layout system

Replace hacky packing with a proper split tree.

Think:

```text
workspace
├── vertical split
│   ├── buffer A
│   └── horizontal split
│       ├── buffer B
│       └── buffer C
```

This is a serious UI architecture project.

---

### Incremental syntax highlighting

Do not rehighlight the whole buffer every time.

Learn:

```text
line state
dirty ranges
parser checkpoints
token caches
```

---

### Testing

Add tests for:

```text
commands
events
plugin loading
buffer switching
file save/load
```

You do not need 100% coverage.

You need confidence.

---

# Year 7: Performance and robustness

Goal: make it survive real use.

## Focus

### Large files

Can you open a 1 MB file? 10 MB?

What breaks?

- scanning
- highlighting
- line numbers
- grep
- sidebar

Learn to optimize.

---

### Profiling

Use:

```tcl
time {
    something
} 10
```

Build small benchmarks.

Example:

```text
scan 10,000 lines for procs
highlight 5,000 lines
rebuild buffer bar with 50 buffers
```

---

### Event storms

What happens if many events fire quickly?

Examples:

```text
cursor-moved during rapid typing
theme-changed during reload
buffer-killed during buffer-switch
plugin unload during prompt
```

You want your system to remain calm.

---

### Crash discipline

Every dangerous operation should be wrapped:

```tcl
catch
```

and logged.

The editor should survive bad plugins.

---

# Year 8: Distribution and real-world use

Goal: make it usable by someone other than you.

## Packaging

Explore:

```text
starkits
starpacks
tclapp
teapot
platform launchers
```

Even if you only produce a simple shell script, make installation boring and reliable.

---

## Documentation

Write:

```text
User manual
Plugin guide
Architecture notes
Hacking guide
FAQ
```

This forces you to understand your own system.

---

## Releases

Make versions:

```text
0.1.0
0.2.0
0.3.0
1.0.0
```

Use tags:

```sh
git tag v0.1.0
```

Learn to maintain backward compatibility.

---

# Year 9: Study deeper sources

Goal: move from user of tools to student of systems.

## Read Tcl/Tk source

Not all of it. Just enough.

Look at:

```text
generic/tclCmd.c
generic/tkText.c
generic/tkBind.c
```

Even if it is C, you will learn why commands behave the way they do.

---

## Study other editors

Read about or study:

```text
Emacs
Acme
sam
vim
Kakoune
```

Ask:

```text
What is their buffer model?
What is their command model?
What is their selection model?
What is their extension model?
```

You are not copying them.

You are comparing design philosophies.

---

## Contribute somewhere

Contribute to:

```text
Tcllib
Tk
a Tcl-based tool
documentation
examples
```

Even small contributions teach you how real projects survive.

---

# Year 10: Mastery

By year 10, expertise is not about knowing every command.

It is about judgment.

You can:

```text
design a plugin API
debug unfamiliar Tcl quickly
build UI without fighting Tk
maintain a long-lived codebase
write clear documentation
teach others
know when not to rewrite
know when a hack is acceptable
know when a design is rotten
```

Your project should reflect that.

Possible year 10 outcomes:

```text
Tclme 2.x is stable
You have a public repository
You have written a Tclme plugin guide
You have maintained it for years
You can rebuild the core from memory
You have strong opinions about editor architecture
You can teach someone else how to extend it
```

That is expertise.

---

# 6. A weekly practice routine

If you want a sustainable routine, do this:

## Weekly loop

### 1. Read

30 minutes of official docs or source.

Examples:

```text
man n dict
man n text
man n bind
man n namespace
```

---

### 2. Experiment

Make a tiny script that proves the behavior.

Example:

```tcl
puts [dict get [dict create a 1 b 2] b]
```

Do not assume. Verify.

---

### 3. Build

Work on one real feature.

Small. Shippable.

---

### 4. Break

Try to make it fail.

Questions:

```text
What if the buffer is killed?
What if the file is missing?
What if the plugin reloads?
What if the text widget is disabled?
What if the user cancels the prompt?
```

---

### 5. Write

Add one paragraph to your notebook or docs.

If you cannot explain it simply, you do not understand it yet.

---

# 7. The “never use AI again” toolkit

If you want to be self-sufficient, build these habits.

## 1. Man-page first

Before asking anyone, check:

```text
command name
options
return value
errors
examples
```

For Tcl, the official docs are excellent.

---

## 2. Minimal reproducible example

When stuck, reduce the problem.

Bad:

```text
My plugin does not work.
```

Good:

```tcl
package require Tk

text .t
pack .t

.t insert end "hello"

puts [.t get 1.0 end-1c]
```

If you can reduce the bug to 10 lines, you usually understand it.

---

## 3. Error catalogue

Keep a file:

```text
docs/errors.md
```

Every recurring error gets an entry.

This becomes your personal Stack Overflow.

---

## 4. Source notebook

Keep:

```text
docs/notes.md
```

Write things like:

```text
Text widget end includes an implicit newline.
Use end-1c for buffer contents.
```

and:

```text
Pack -before can reorder managed widgets.
```

and:

```text
Double-quoted strings perform command substitution.
Use braces for regex.
```

These little notes compound.

---

## 5. Rubber duck debugging

Explain the bug out loud.

Seriously.

Say:

```text
When I press C-x g, I expect project-grep to prompt.
Instead, nothing happens.
The command is defined here.
The binding is here.
The plugin load happens here.
```

Half the time, you find the bug while explaining it.

---

## 6. Human communities

No AI does not mean no humans.

Use:

```text
Tcl mailing lists
Tcl/Tk forums
comp.lang.tcl archives
Tcler's Wiki
Stack Overflow
IRC/Libera channels
```

When you ask humans, bring:

```text
Tcl version
OS
minimal example
exact error
errorInfo
what you expected
what happened
```

People respect that.

---

# 8. What to avoid

This matters.

## Avoid endless rewriting

Rewriting is useful once you have something to learn from.

But if you rewrite every year without maintaining anything, you will never learn maintenance.

Maintain one long-lived project.

Tclme is a good candidate.

---

## Avoid plugin sprawl

You already have many plugins.

Now freeze some.

Create:

```text
stable plugins
experimental plugins
retired plugins
```

Do not let everything stay half-finished forever.

---

## Avoid magical code you do not understand

If you copy a clever trick, write a comment explaining it.

If you cannot explain it, put it in a test file and poke it until you can.

---

## Avoid UI complexity without a model

Before building a new panel, ask:

```text
Who owns the widget?
Who destroys it?
Who refreshes it?
What happens on reload?
What happens on theme change?
```

Otherwise you will build a haunted house.

---

# 9. The most important projects for the next decade

If I had to pick the five most valuable projects for you, they would be:

## 1. Rebuild Tclme Mini

This gives you clarity.

---

## 2. Build a standalone Tk text-widget laboratory

This gives you widget mastery.

---

## 3. Build a tiny plugin framework from scratch

Not using your existing one.

Make it small enough to understand completely.

---

## 4. Build a network tool

IRC was a good start.

Build something simpler from raw sockets too.

Maybe:

```text
telnet client
chat server
HTTP fetcher
```

---

## 5. Maintain Tclme for years

This is the real teacher.

Long-term maintenance teaches:

```text
compatibility
refactoring
documentation
regression
design debt
user needs
```

---

# 10. Signs you are becoming expert

You will know you are getting good when:

```text
You can read an error message and immediately know the category of bug.
You can inspect live state without fear.
You can build a small UI in one sitting.
You can explain how your plugin system works.
You can reload plugins without breaking the editor.
You can debug event-ordering problems.
You can design a command API that other plugins can use.
You can maintain code you wrote a year ago.
You can say no to features.
You can choose boring solutions on purpose.
```

That last one is important.

Experts choose boring solutions when boring is correct.

---

# 11. If you only do three things from now on

Do these.

## 1. Document the system

Write:

```text
ARCHITECTURE.md
PLUGIN-COOKBOOK.md
ERRORS.md
```

This turns chaos into knowledge.

---

## 2. Rebuild the core from scratch

Build Tclme Mini.

It will teach you more than ten plugins.

---

## 3. Maintain one project for years

Do not abandon Tclme.

Evolve it.

Version it.

Break it.

Fix it.

Refactor it.

Document it.

That is how expertise accumulates.

---

# Final summary

What did we make?

We made a **live, hackable Tcl/Tk programming environment** disguised as a text editor.

It has:

```text
commands
keybindings
events
buffers
plugins
themes
debugging tools
file navigation
project search
tiling
IRC
code outlines
```

But more importantly, you built a system you can study, break, extend, and rebuild.

How do you become an expert without AI?

You build a self-sufficient loop:

```text
read docs
experiment
build small
break things
write notes
maintain long-term
rewrite deliberately
teach yourself by explaining
```

The next 10 years are not about memorizing Tcl.

They are about becoming someone who can:

```text
understand systems,
extend systems,
repair systems,
and design systems that survive.
```

# Plugin Guide
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
