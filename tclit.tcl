#!/usr/bin/env tclsh
# ============================================================================
# tclit.tcl
#
# Headless REPL frontend for the Tclme kernel.
# ============================================================================

source [file join [file dirname [info script]] tclme.tcl]
source [file join [file dirname [info script]] tclem.tcl]

# Headless mode is already the kernel default, but be explicit.
set Tclme::headless 1

# Do not double-echo input.
# The terminal already echoes what you type.
set Tclme::echo_input 0

Tclme::InitKernel

puts "Tclit: tclme headless REPL"
puts "Type :help for commands."
puts "Load plugins with :load NAME."
puts ""

# Optional: automatically load headless-safe plugins and/or your init file
# here, the same way a Tk frontend would at boot.
#
# Tclme::LoadPluginByName "example"
# Tclme::LoadUserInit

proc Tclme::ReplPrompt {} {
    puts -nonewline "> "
    flush stdout
}

# A blocking `while {[gets stdin line] >= 0}` loop never lets Tcl service
# its own event loop, which means any Tclme::After-scheduled plugin
# callback -- an autosave timer, anything self-rescheduling -- would load
# fine and simply never fire under this frontend. fileevent + vwait
# services the event loop between lines, so timers behave the same here
# as they would under a Tk frontend.
proc Tclme::ReplRead {} {
    if {[eof stdin]} {
        exit 0
    }

    gets stdin line
    Tclme::DispatchLine $line
    Tclme::ReplPrompt
}

Tclme::ReplPrompt
fileevent stdin readable Tclme::ReplRead
vwait forever
