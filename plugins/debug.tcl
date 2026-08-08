# plugins/debugger.tcl
# ============================================================================
#  Debugger / inspector plugin for Tclme.
#
#  Commands:
#    :debugger          toggle debugger console
#    :db                alias
#
#  Keybinding:
#    C-x C-g            toggle debugger console
#
#  Console commands:
#    help
#    continue / c
#    where / stack
#    locals
#    vars ?pattern?
#    procs ?pattern?
#    p NAME
#    args PROC
#    body PROC
#    ns ?NAMESPACE?
#    break PROC
#    unbreak PROC
#    breakpoints
#    watch VAR
#    unwatch VAR
#    watches
#    pause on|off
#    watchbreak on|off
#    source FILE
#    eval CODE
#    clear
#    hide
#
#  Manual breakpoint in code:
#    ::Tclme::Plugin::debugger::breakpoint
#    or, if created, simply:
#    dbg
#
#  Notes:
#    - This is an inspector/breakpoint tool, not a full stepping debugger.
#    - Breakpoints wrap procs. Avoid breaking Tclme dispatch internals.
#    - Watchpoints use Tcl variable traces and can be noisy on large dicts.
# ============================================================================

# ----------------------------------------------------------------------------
# State
# ----------------------------------------------------------------------------

variable visible       0
variable paused        1
variable watch_break   0

variable stopped       0
variable continue_flag 0

variable eval_ns       "::"

variable history       {}
variable hist_index    0

variable breakpoints   [dict create]
variable watches       [dict create]

variable stack_snapshot  {}
variable locals_snapshot [dict create]
variable current_proc    ""
variable current_args    [dict create]

variable created_dbg   0
variable load_after    ""
variable last_error    ""

# ----------------------------------------------------------------------------
# Command
# ----------------------------------------------------------------------------

proc cmd-toggle {args} {
    if {[winfo exists .debugger]} {
        Hide
    } else {
        Show
    }
}

# ----------------------------------------------------------------------------
# UI
# ----------------------------------------------------------------------------

proc Show {} {
    variable visible 1

    set bar .debugger

    if {![winfo exists $bar]} {
        BuildUI
    }

    if {[winfo exists .sep1]} {
        pack $bar -fill x -before .sep1
    } elseif {[winfo exists .status]} {
        pack $bar -fill x -before .status
    } else {
        pack $bar -side bottom -fill x
    }

    ConfigureColors
}

proc Hide {} {
    variable visible 0
    variable stopped

    if {$stopped} {
        Continue
    }

    if {[winfo exists .debugger]} {
        destroy .debugger
    }
}

proc ApplyVisibility {} {
    variable load_after ""
    variable visible

    if {$visible} {
        Show
    } else {
        Hide
    }
}

proc BuildUI {} {
    set ns [namespace current]

    frame .debugger
    frame .debugger.bar

    button .debugger.bar.continue     -text Continue     -command [list ${ns}::Continue]
    button .debugger.bar.stack        -text Stack        -command [list ${ns}::Where]
    button .debugger.bar.locals       -text Locals       -command [list ${ns}::Locals]
    button .debugger.bar.watches      -text Watches      -command [list ${ns}::ListWatches]
    button .debugger.bar.breakpoints  -text Breakpoints  -command [list ${ns}::ListBreakpoints]
    button .debugger.bar.clear        -text Clear        -command [list ${ns}::Clear]
    button .debugger.bar.hide         -text Hide         -command [list ${ns}::Hide]

    pack .debugger.bar.continue \
         .debugger.bar.stack \
         .debugger.bar.locals \
         .debugger.bar.watches \
         .debugger.bar.breakpoints \
         .debugger.bar.clear \
         .debugger.bar.hide \
         -side left -padx 2 -pady 2

    text .debugger.out \
        -height 8 \
        -wrap word \
        -state disabled \
        -borderwidth 0 \
        -highlightthickness 0

    frame .debugger.inbar

    label .debugger.inbar.prompt -text "debug>"
    entry .debugger.inbar.entry

    pack .debugger.inbar.prompt -side left -padx {4 0}
    pack .debugger.inbar.entry -side left -fill x -expand 1 -padx 4 -pady 2

    pack .debugger.bar -fill x
    pack .debugger.out -fill both -expand 1
    pack .debugger.inbar -fill x

    bind .debugger.inbar.entry <Return> [list ${ns}::Submit]
    bind .debugger.inbar.entry <Up>     "[list ${ns}::HistoryPrev]; break"
    bind .debugger.inbar.entry <Down>   "[list ${ns}::HistoryNext]; break"

    ConfigureColors

    Output "Tclme Debugger ready. Type 'help'." break
}

proc ConfigureColors {} {
    if {![winfo exists .debugger]} {
        return
    }

    set bg      [::Tclme::GetTheme bg]
    set fg      [::Tclme::GetTheme fg]
    set editor  [::Tclme::GetTheme editor_bg]
    set accent      [::Tclme::GetTheme accent]
    set font    [::Tclme::GetTheme font]
    set active  [::Tclme::GetTheme separator]

    .debugger configure -bg $bg
    .debugger.bar configure -bg $bg
    .debugger.inbar configure -bg $bg

    foreach b [winfo children .debugger.bar] {
        catch {
            $b configure \
                -bg $bg \
                -fg $fg \
                -activebackground $active \
                -activeforeground $fg
        }
    }

    .debugger.out configure \
        -bg $editor \
        -fg $fg \
        -insertbackground $fg \
        -font $font

    .debugger.inbar.prompt configure \
        -bg $bg \
        -fg $accent

    .debugger.inbar.entry configure \
        -bg $editor \
        -fg $fg \
        -insertbackground $fg \
        -borderwidth 0 \
        -highlightthickness 0

    .debugger.out tag configure prompt -foreground $accent
    .debugger.out tag configure error  -foreground #D9534F
    .debugger.out tag configure watch  -foreground #5A9BD5
    .debugger.out tag configure break  -foreground $accent
}

# ----------------------------------------------------------------------------
# Output helpers
# ----------------------------------------------------------------------------

proc Output {text {tag ""}} {
    set out .debugger.out

    if {![winfo exists $out]} {
        return
    }

    $out configure -state normal

    if {$tag eq ""} {
        $out insert end "$text\n"
    } else {
        $out insert end "$text\n" [list $tag]
    }

    $out see end
    $out configure -state disabled
}

proc OutputLines {lines {tag ""}} {
    foreach line $lines {
        Output $line $tag
    }
}

proc Short {s {n 200}} {
    if {[string length $s] > $n} {
        return "[string range $s 0 $n]..."
    }
    return $s
}

proc Clear {} {
    set out .debugger.out
    if {![winfo exists $out]} {
        return
    }

    $out configure -state normal
    $out delete 1.0 end
    $out configure -state disabled
}

# ----------------------------------------------------------------------------
# Console input
# ----------------------------------------------------------------------------

proc Submit {} {
    set in .debugger.inbar.entry

    if {![winfo exists $in]} {
        return
    }

    set line [$in get]
    $in delete 0 end

    set line [string trim $line]
    if {$line eq ""} {
        return
    }

    HistoryAdd $line
    Output "debug> $line" prompt

    ConsoleCommand $line
}

proc HistoryAdd {line} {
    variable history
    variable hist_index

    if {[llength $history] == 0 || [lindex $history end] ne $line} {
        lappend history $line
    }

    if {[llength $history] > 200} {
        set history [lrange $history end-199 end]
    }

    set hist_index [llength $history]
}

proc HistoryPrev {} {
    variable history
    variable hist_index

    set in .debugger.inbar.entry
    if {![winfo exists $in]} {
        return
    }

    set len [llength $history]
    if {$len == 0} {
        return
    }

    if {$hist_index > $len} {
        set hist_index $len
    }

    if {$hist_index > 0} {
        incr hist_index -1
    }

    $in delete 0 end
    $in insert 0 [lindex $history $hist_index]
    $in icursor end
}

proc HistoryNext {} {
    variable history
    variable hist_index

    set in .debugger.inbar.entry
    if {![winfo exists $in]} {
        return
    }

    set len [llength $history]
    if {$len == 0 || $hist_index >= $len} {
        return
    }

    incr hist_index

    if {$hist_index >= $len} {
        set hist_index $len
        $in delete 0 end
    } else {
        $in delete 0 end
        $in insert 0 [lindex $history $hist_index]
        $in icursor end
    }
}

proc ConsoleCommand {line} {
    set line [string trim $line]
    if {$line eq ""} {
        return
    }

    if {[string index $line 0] eq ":"} {
        if {[catch { ::Tclme::RunExCommand [string range $line 1 end] } err]} {
            Output "Tclme error: $err" error
        }
        return
    }

    if {![regexp {^\s*(\S+)\s*(.*)$} $line -> cmd rest]} {
        return
    }

    set rest [string trim $rest]

    switch -- $cmd {
        help {
            Help
        }
        h {
            Help
        }
        continue {
            Continue
        }
        c {
            Continue
        }
        where {
            Where
        }
        w {
            Where
        }
        stack {
            Where
        }
        locals {
            Locals
        }
        l {
            Locals
        }
        vars {
            CmdVars $rest
        }
        procs {
            CmdProcs $rest
        }
        p {
            CmdPrint $rest
        }
        print {
            CmdPrint $rest
        }
        args {
            CmdArgs $rest
        }
        body {
            CmdBody $rest
        }
        watch {
            AddWatch $rest
        }
        unwatch {
            RemoveWatch $rest
        }
        watches {
            ListWatches
        }
        break {
            BreakProc $rest
        }
        unbreak {
            UnbreakProc $rest
        }
        breakpoints {
            ListBreakpoints
        }
        ns {
            CmdNs $rest
        }
        pause {
            CmdPause $rest
        }
        watchbreak {
            CmdWatchBreak $rest
        }
        clear {
            Clear
        }
        hide {
            Hide
        }
        quit {
            Hide
        }
        source {
            CmdSource $rest
        }
        eval {
            EvalRaw $rest
        }
        default {
            EvalRaw $line
        }
    }
}

proc Help {} {
    OutputLines {
        "Debugger commands:"
        "  help                  this help"
        "  continue / c          resume if paused"
        "  where / stack         show captured stack"
        "  locals                show captured locals at breakpoint"
        "  vars ?pattern?        list variables in current namespace"
        "  procs ?pattern?       list procs in current namespace"
        "  p NAME                print variable/value"
        "  args PROC             show proc arguments"
        "  body PROC             show proc body"
        "  ns ?NAMESPACE?        show/set evaluation namespace"
        "  break PROC            set breakpoint"
        "  unbreak PROC          remove breakpoint"
        "  breakpoints           list breakpoints"
        "  watch VAR             watch variable writes"
        "  unwatch VAR           remove watch"
        "  watches               list watches"
        "  pause on|off          pause when breakpoint fires"
        "  watchbreak on|off     pause when watch fires"
        "  source FILE           source file in current namespace"
        "  eval CODE             evaluate CODE directly"
        "  clear                 clear console"
        "  hide                  hide/continue debugger"
        ""
        "Any other input is evaluated in the current namespace."
        "Prefix a line with : to run a Tclme ex-command."
        "Insert `dbg` in code for a manual breakpoint."
    }
}

# ----------------------------------------------------------------------------
# Evaluation / inspection
# ----------------------------------------------------------------------------

proc EvalRaw {code} {
    variable eval_ns
    variable last_error

    set code [string trim $code]
    if {$code eq ""} {
        return
    }

    if {[catch { namespace eval $eval_ns $code } result]} {
        set last_error $::errorInfo
        Output "Error: $result" error
        foreach line [lrange [split $last_error \n] 0 5] {
            Output $line error
        }
    } else {
        if {$result ne ""} {
            Output "=> [Short $result 500]"
        }
    }
}

proc NormalizeVar {name} {
    variable eval_ns

    set name [string trim $name]

    if {[string match ::* $name]} {
        return $name
    }

    if {$eval_ns eq "::"} {
        return "::$name"
    }

    return "${eval_ns}::$name"
}

proc NormalizeProc {name} {
    variable eval_ns

    set name [string trim $name]

    if {[string match ::* $name]} {
        return $name
    }

    if {$eval_ns eq "::"} {
        return "::$name"
    }

    return "${eval_ns}::$name"
}

proc ReadVar {var} {
    if {[uplevel #0 [list array exists $var]]} {
        return [uplevel #0 [list array get $var]]
    }

    return [uplevel #0 [list set $var]]
}

proc CmdVars {pattern} {
    variable eval_ns

    set pattern [string trim $pattern]
    set cmd [list info vars]

    if {$pattern ne ""} {
        lappend cmd $pattern
    }

    if {[catch { set vars [namespace eval $eval_ns $cmd] } err]} {
        Output "Error: $err" error
        return
    }

    if {[llength $vars] == 0} {
        Output "(no variables)"
        return
    }

    OutputLines [lsort $vars]
}

proc CmdProcs {pattern} {
    variable eval_ns

    set pattern [string trim $pattern]
    set cmd [list info procs]

    if {$pattern ne ""} {
        lappend cmd $pattern
    }

    if {[catch { set procs [namespace eval $eval_ns $cmd] } err]} {
        Output "Error: $err" error
        return
    }

    if {[llength $procs] == 0} {
        Output "(no procs)"
        return
    }

    OutputLines [lsort $procs]
}

proc CmdPrint {name} {
    variable locals_snapshot

    set name [string trim $name]
    if {$name eq ""} {
        Output "usage: p VAR"
        return
    }

    if {[dict exists $locals_snapshot $name]} {
        Output "$name = [Short [dict get $locals_snapshot $name] 500]"
        return
    }

    set full [NormalizeVar $name]

    if {[catch { ReadVar $full } value]} {
        Output "Cannot read $full: $value" error
        return
    }

    Output "$full = [Short $value 500]"
}

proc CmdArgs {name} {
    set full [NormalizeProc $name]

    if {![info procs $full]} {
        Output "Not a proc: $full" error
        return
    }

    Output "[info args $full]"
}

proc CmdBody {name} {
    set full [NormalizeProc $name]

    if {![info procs $full]} {
        Output "Not a proc: $full" error
        return
    }

    Output [info body $full]
}

proc CmdNs {name} {
    variable eval_ns

    set name [string trim $name]

    if {$name eq ""} {
        Output "namespace: $eval_ns"
        return
    }

    if {![string match ::* $name]} {
        if {$eval_ns eq "::"} {
            set name "::$name"
        } else {
            set name "${eval_ns}::$name"
        }
    }

    namespace eval $name {}
    set eval_ns $name

    Output "eval namespace: $eval_ns"
}

proc CmdSource {file} {
    variable eval_ns

    set file [string trim $file]
    if {$file eq ""} {
        Output "usage: source FILE"
        return
    }

    if {[catch { namespace eval $eval_ns [list source $file] } result]} {
        Output "Error: $result" error
    } else {
        Output "Sourced $file"
    }
}

# ----------------------------------------------------------------------------
# Stack / locals snapshots
# ----------------------------------------------------------------------------

proc CaptureStack {} {
    set out {}
    set max [info level]

    for {set i 1} {$i <= $max} {incr i} {
        lappend out "$i: [info level $i]"
    }

    return $out
}

proc Where {} {
    variable stopped
    variable stack_snapshot

    if {$stopped && [llength $stack_snapshot] > 0} {
        Output "Captured stack:" break
        OutputLines $stack_snapshot
    } else {
        Output "Current stack:"
        OutputLines [CaptureStack]
    }
}

proc Locals {} {
    variable stopped
    variable locals_snapshot
    variable current_proc

    if {!$stopped} {
        Output "Not stopped at breakpoint."
        return
    }

    Output "Breakpoint: $current_proc" break

    if {[dict size $locals_snapshot] == 0} {
        Output "(no locals captured)"
        return
    }

    dict for {k v} $locals_snapshot {
        Output "$k = [Short $v 300]"
    }
}

# ----------------------------------------------------------------------------
# Breakpoints
# ----------------------------------------------------------------------------

proc BreakHit {proc_name snap} {
    variable stopped
    variable paused
    variable continue_flag
    variable stack_snapshot
    variable locals_snapshot
    variable current_proc
    variable current_args

    if {$stopped} {
        return
    }

    set stopped 1
    set current_proc $proc_name
    set current_args $snap
    set locals_snapshot $snap
    set stack_snapshot [CaptureStack]

    Show

    Output "=== $proc_name ===" break

    if {[dict size $snap] > 0} {
        Output "Locals / args:" break
        dict for {k v} $snap {
            Output "  $k = [Short $v 200]"
        }
    }

    Output "Stack:" break
    OutputLines $stack_snapshot

    if {$paused} {
        set continue_flag 0
        Output "Paused. Type 'continue' or click Continue." break

        set ns [namespace current]
        catch { tkwait variable ${ns}::continue_flag }
    }

    set stopped 0
}

proc breakpoint {{message ""}} {
    set vars [uplevel 1 {info locals}]
    set snap [dict create]

    foreach v $vars {
        if {[uplevel 1 [list array exists $v]]} {
            catch {
                dict set snap $v [uplevel 1 [list array get $v]]
            }
        } else {
            catch {
                dict set snap $v [uplevel 1 [list set $v]]
            }
        }
    }

    if {$message eq ""} {
        set label "manual breakpoint"
    } else {
        set label "manual breakpoint: $message"
    }

    BreakHit $label $snap
}

proc BreakProc {name} {
    variable breakpoints

    set name [string trim $name]
    if {$name eq ""} {
        Output "usage: break PROC"
        return
    }

    set full [NormalizeProc $name]

    if {[dict exists $breakpoints $full]} {
        Output "Already breaking: $full"
        return
    }

    if {[string match ::Tclme::Plugin::debugger::* $full]} {
        Output "Refusing to break debugger internals." error
        return
    }

    if {[string match "*::__dbg_orig_*" $full]} {
        Output "Refusing to break debugger wrapper internals." error
        return
    }

    set deny {
        ::Tclme::Invoke
        ::Tclme::Emit
        ::Tclme::EmitCancelable
        ::Tclme::Collect
        ::Tclme::RefreshStatus
        ::Tclme::DoRefreshStatus
        ::Tclme::QualifyScript
    }

    if {[lsearch -exact $deny $full] >= 0} {
        Output "Refusing to break dangerous Tclme dispatch proc: $full" error
        return
    }

    if {![info procs $full]} {
        Output "Not a proc: $full" error
        return
    }

    set ns [namespace qualifiers $full]
    if {$ns eq ""} {
        set ns "::"
    }

    set tail [namespace tail $full]
    set orig "${ns}::__dbg_orig_${tail}"

    while {[info commands $orig] ne ""} {
        append orig "_"
    }

    if {[catch { rename $full $orig } err]} {
        Output "Cannot rename proc: $err" error
        return
    }

    set args [info args $orig]
    set wrapper_args {}

    set snap_code "set __core_dbg_snap \[list"
    set call_code "set __core_dbg_result \[uplevel 1 \[list [list $orig]"

    foreach a $args {
        if {[info default $orig $a def]} {
            lappend wrapper_args [list $a $def]
        } else {
            lappend wrapper_args $a
        }

        append snap_code " [list $a] \$$a"

        if {$a eq "args" && $a eq [lindex $args end]} {
            append call_code " {*}\$$a"
        } else {
            append call_code " \$$a"
        }
    }

    append snap_code "\]"
    append call_code "\]\]"

    set ns_current [namespace current]

    set body "$snap_code\n"
    append body "${ns_current}::BreakHit [list $full] \$__core_dbg_snap\n"
    append body "$call_code\n"
    append body "return \$__core_dbg_result"

    if {[catch { proc $full $wrapper_args $body } err]} {
        catch { rename $orig $full }
        Output "Failed to create breakpoint: $err" error
        return
    }

    dict set breakpoints $full $orig
    Output "Breakpoint set: $full" break
}

proc UnbreakProc {name} {
    variable breakpoints

    set name [string trim $name]
    if {$name eq ""} {
        Output "usage: unbreak PROC"
        return
    }

    set full [NormalizeProc $name]

    if {![dict exists $breakpoints $full]} {
        Output "No breakpoint: $full"
        return
    }

    set orig [dict get $breakpoints $full]

    catch { rename $full {} }

    if {[info commands $orig] ne ""} {
        catch { rename $orig $full }
    }

    dict unset breakpoints $full
    Output "Breakpoint removed: $full"
}

proc ListBreakpoints {} {
    variable breakpoints

    if {[dict size $breakpoints] == 0} {
        Output "(no breakpoints)"
        return
    }

    foreach name [lsort [dict keys $breakpoints]] {
        Output $name
    }
}

proc Continue {} {
    variable continue_flag
    variable stopped

    set continue_flag 1

    if {$stopped} {
        Output "Continuing..." break
    }
}

proc CmdPause {arg} {
    variable paused

    set arg [string tolower [string trim $arg]]

    if {[lsearch -exact {on 1 true enable} $arg] >= 0} {
        set paused 1
    } else {
        set paused 0
    }

    Output "Breakpoint pause: $paused"
}

# ----------------------------------------------------------------------------
# Watchpoints
# ----------------------------------------------------------------------------

proc AddWatch {name} {
    variable watches

    set name [string trim $name]
    if {$name eq ""} {
        Output "usage: watch VAR"
        return
    }

    set full [NormalizeVar $name]

    if {[string match ::Tclme::Plugin::debugger::* $full]} {
        Output "Refusing to watch debugger internals." error
        return
    }

    if {[dict exists $watches $full]} {
        Output "Already watching: $full"
        return
    }

    set ns [namespace current]
    set cmd [list ${ns}::WatchCallback $full]

    if {[catch { trace add variable $full {write unset} $cmd } err]} {
        Output "Cannot watch: $err" error
        return
    }

    dict set watches $full $cmd
    Output "Watching: $full" watch
}

proc RemoveWatch {name} {
    variable watches

    set name [string trim $name]
    if {$name eq ""} {
        Output "usage: unwatch VAR"
        return
    }

    set full [NormalizeVar $name]

    if {![dict exists $watches $full]} {
        Output "Not watching: $full"
        return
    }

    set cmd [dict get $watches $full]

    catch { trace remove variable $full {write unset} $cmd }

    dict unset watches $full
    Output "Unwatched: $full"
}

proc ListWatches {} {
    variable watches

    if {[dict size $watches] == 0} {
        Output "(no watches)"
        return
    }

    foreach name [lsort [dict keys $watches]] {
        Output $name watch
    }
}

proc WatchCallback {watch_var name1 name2 op} {
    variable watches
    variable watch_break

    set var $name1

    if {![string match ::* $var]} {
        set var "::$var"
    }

    if {$name2 ne ""} {
        set disp "$var($name2)"
    } else {
        set disp $var
    }

    if {$op eq "unset"} {
        Output "WATCH unset: $disp" watch

        if {[dict exists $watches $watch_var]} {
            dict unset watches $watch_var
        }

        return
    }

    set val "<unreadable>"

    catch {
        if {$name2 ne ""} {
            set val [uplevel #0 [list set "$var($name2)"]]
        } else {
            set val [ReadVar $var]
        }
    }

    Output "WATCH write: $disp = [Short $val 200]" watch

    if {$watch_break} {
        BreakHit "watchpoint: $disp" [dict create $disp $val]
    }
}

proc CmdWatchBreak {arg} {
    variable watch_break

    set arg [string tolower [string trim $arg]]

    if {[lsearch -exact {on 1 true enable} $arg] >= 0} {
        set watch_break 1
    } else {
        set watch_break 0
    }

    Output "Watchpoint break: $watch_break"
}

# ----------------------------------------------------------------------------
# Global helper
# ----------------------------------------------------------------------------

proc EnsureDbg {} {
    variable created_dbg

    if {[info commands ::dbg] eq ""} {
        set ns [namespace current]
        proc ::dbg {{message ""}} "${ns}::breakpoint \$message"
        set created_dbg 1
    }
}

# ----------------------------------------------------------------------------
# Events
# ----------------------------------------------------------------------------

proc OnTheme {args} {
    if {[winfo exists .debugger]} {
        ConfigureColors
    }
}

# ----------------------------------------------------------------------------
# Lifecycle
# ----------------------------------------------------------------------------

proc load {} {
    variable load_after

    EnsureDbg

    set ns [namespace current]
    set load_after [after idle [list ${ns}::ApplyVisibility]]
}

proc unload {} {
    variable breakpoints
    variable watches
    variable created_dbg
    variable load_after

    Continue

    if {$load_after ne ""} {
        catch { after cancel $load_after }
        set load_after ""
    }

    foreach full [dict keys $watches] {
        catch {
            trace remove variable $full {write unset} [dict get $watches $full]
        }
    }

    foreach full [dict keys $breakpoints] {
        set orig [dict get $breakpoints $full]
        catch { rename $full {} }
        if {[info commands $orig] ne ""} {
            catch { rename $orig $full }
        }
    }

    if {$created_dbg && [info commands ::dbg] ne ""} {
        catch { rename ::dbg {} }
    }

    if {[winfo exists .debugger]} {
        destroy .debugger
    }
}

proc save-state {} {
    variable visible
    variable paused
    variable watch_break
    variable eval_ns

    return [dict create \
        visible $visible \
        paused $paused \
        watch_break $watch_break \
        eval_ns $eval_ns \
    ]
}

proc restore-state {s} {
    variable visible
    variable paused
    variable watch_break
    variable eval_ns

    if {[catch { dict size $s }]} {
        return
    }

    if {[dict exists $s visible]} {
        set visible [dict get $s visible]
    }

    if {[dict exists $s paused]} {
        set paused [dict get $s paused]
    }

    if {[dict exists $s watch_break]} {
        set watch_break [dict get $s watch_break]
    }

    if {[dict exists $s eval_ns]} {
        set eval_ns [dict get $s eval_ns]
    }
}

# ----------------------------------------------------------------------------
# Registration
# ----------------------------------------------------------------------------

Tclme::On theme-changed OnTheme

Tclme::DefCommand debugger cmd-toggle "Toggle the Tcl debugger console"
Tclme::DefAlias db debugger
Tclme::BindKey debugger <Control-x><Control-g>