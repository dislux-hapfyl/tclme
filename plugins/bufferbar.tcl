# plugins/bufferbar.tcl
# ============================================================================
#  Buffer bar: clickable buffer buttons above the workspace.
#
#  Interactions:
#    Left click        switch to buffer
#    Middle/right click kill buffer
#
#  Commands:
#    :buffer-bar       toggle the bar
#    :tabs             alias for :buffer-bar
#
#  Keybinding:
#    C-x C-b           toggle the bar
#
#  The bar rebuilds itself on buffer events, saves, theme changes, and
#  (debounced) cursor movement so dirty markers stay reasonably fresh.
# ============================================================================

variable visible 1
variable pending ""
variable pending_delay 0

# Buffer back/forward history.
variable hist_back {}
variable hist_forward {}
variable hist_current ""
variable hist_nav_target ""
variable hist_nav_timer ""
variable hist_limit 100

# ----------------------------------------------------------------------------
#  Command
# ----------------------------------------------------------------------------

proc cmd-toggle {args} {
    variable visible

    if {$visible} {
        Hide
        ::Tclme::Message "Buffer bar hidden"
    } else {
        Show
        ::Tclme::Message "Buffer bar visible"
    }
}

# ----------------------------------------------------------------------------
#  Show / hide
# ----------------------------------------------------------------------------

proc Show {} {
    variable visible 1

    set bar .bufferbar

    if {![winfo exists $bar]} {
        frame $bar -bg [::Tclme::GetTheme bg]
    }

    if {[winfo exists .ws]} {
        pack $bar -fill x -before .ws
    } else {
        pack $bar -side top -fill x
    }

    DoRebuild
}

proc Hide {} {
    variable visible 0
    variable pending
    variable pending_delay

    if {$pending ne ""} {
        catch { after cancel $pending }
    }

    set pending ""
    set pending_delay 0

    if {[winfo exists .bufferbar]} {
        destroy .bufferbar
    }
}

proc ApplyVisibility {} {
    variable visible

    if {$visible} {
        Show
    } else {
        Hide
    }
}

# ----------------------------------------------------------------------------
#  Debounced rebuild scheduling
# ----------------------------------------------------------------------------

proc Schedule {delay} {
    variable visible
    variable pending
    variable pending_delay

    if {!$visible} {
        return
    }

    # Do not let a slower event delay an already-scheduled faster rebuild.
    if {$pending ne "" && $delay > $pending_delay} {
        return
    }

    if {$pending ne ""} {
        catch { after cancel $pending }
    }

    set ns [namespace current]
    set pending [after $delay [list ${ns}::DoRebuild]]
    set pending_delay $delay
}

proc OnNow {args} {
    Schedule 20
}

proc OnSoon {args} {
    Schedule 300
}

# ----------------------------------------------------------------------------
#  Rendering
# ----------------------------------------------------------------------------

proc DisplayName {name} {
    if {[string match "dired:*" $name]} {
        set dir [string range $name 6 end]
        set tail [file tail $dir]

        if {$tail eq "" || $tail eq "/"} {
            return $dir
        }

        return "$tail/"
    }

    if {[string length $name] > 24} {
        return "[string range $name 0 20]..."
    }

    return $name
}

proc DoRebuild {} {
    variable pending ""
    variable pending_delay 0

    set bar .bufferbar

    if {![winfo exists $bar]} {
        return
    }

    $bar configure -bg [::Tclme::GetTheme bg]

    foreach child [winfo children $bar] {
        destroy $child
    }

    set bg       [::Tclme::GetTheme bg]
    set fg       [::Tclme::GetTheme fg]
    set activebg [::Tclme::GetTheme separator]
    set curbg    [::Tclme::GetTheme accent]
    set curfg    [::Tclme::GetTheme editor_bg]
    set cur      $::Tclme::current_buffer
    set ns       [namespace current]

    set i 0

    foreach name $::Tclme::buffer_order {
        if {![dict exists $::Tclme::buffers $name]} {
            continue
        }

        set info [dict get $::Tclme::buffers $name]
        set txt  ".ws.[dict get $info wid].txt"

        set dirty 0
        if {[winfo exists $txt]} {
            set dirty [$txt edit modified]
        }

        set label [DisplayName $name]
        if {$dirty} {
            set label "* $label"
        }

        set btn $bar.tab$i

        button $btn \
            -text $label \
            -command [list ::Tclme::SwitchToBuffer $name] \
            -bg $bg \
            -fg $fg \
            -activebackground $activebg \
            -activeforeground $fg \
            -relief flat \
            -bd 0 \
            -highlightthickness 0 \
            -padx 6 \
            -pady 2 \
            -cursor hand2

        if {$name eq $cur} {
            $btn configure \
                -bg $curbg \
                -fg $curfg \
                -activebackground $curbg \
                -activeforeground $curfg \
                -relief sunken
        }

        bind $btn <ButtonRelease-2> [list ${ns}::Kill $name]
        bind $btn <ButtonRelease-3> [list ${ns}::Kill $name]
        pack $btn -side left -padx 1 -pady 0
        incr i
    }
}

# ----------------------------------------------------------------------------
#  Button interactions
# ----------------------------------------------------------------------------

proc Kill {name} {
    ::Tclme::KillBuffer $name
    return -code break
}

# ----------------------------------------------------------------------------
#  Buffer history: back / forward
# ----------------------------------------------------------------------------

proc HistoryInit {args} {
    variable hist_current

    if {$hist_current eq ""} {
        set hist_current $::Tclme::current_buffer
    }

    HistoryPrune
}

proc HistoryDisarmNav {} {
    variable hist_nav_target ""
    variable hist_nav_timer ""
}

proc HistoryArmNav {target} {
    variable hist_nav_target
    variable hist_nav_timer

    set hist_nav_target $target

    if {$hist_nav_timer ne ""} {
        catch { after cancel $hist_nav_timer }
    }

    set ns [namespace current]
    set hist_nav_timer [after 500 [list ${ns}::HistoryDisarmNav]]
}

proc HistoryRemoveFromList {lst name} {
    set out {}

    foreach b $lst {
        if {$b ne $name} {
            lappend out $b
        }
    }

    return $out
}

proc HistoryPushBack {name} {
    variable hist_back
    variable hist_limit

    if {$name eq ""} {
        return
    }

    if {![info exists ::Tclme::buffers]} {
        return
    }

    if {![dict exists $::Tclme::buffers $name]} {
        return
    }

    lappend hist_back $name

    if {$hist_limit > 0} {
        set excess [expr {[llength $hist_back] - $hist_limit}]

        if {$excess > 0} {
            set hist_back [lrange $hist_back $excess end]
        }
    }
}

proc HistoryPushForward {name} {
    variable hist_forward
    variable hist_limit

    if {$name eq ""} {
        return
    }

    if {![info exists ::Tclme::buffers]} {
        return
    }

    if {![dict exists $::Tclme::buffers $name]} {
        return
    }

    lappend hist_forward $name

    if {$hist_limit > 0} {
        set excess [expr {[llength $hist_forward] - $hist_limit}]

        if {$excess > 0} {
            set hist_forward [lrange $hist_forward $excess end]
        }
    }
}

proc HistoryPrune {} {
    variable hist_back
    variable hist_forward
    variable hist_current
    variable hist_limit

    if {![info exists ::Tclme::buffers]} {
        set hist_back {}
        set hist_forward {}
        return
    }

    set nb {}
    foreach b $hist_back {
        if {[dict exists $::Tclme::buffers $b]} {
            lappend nb $b
        }
    }
    set hist_back $nb

    set nf {}
    foreach b $hist_forward {
        if {[dict exists $::Tclme::buffers $b]} {
            lappend nf $b
        }
    }
    set hist_forward $nf

    if {$hist_limit > 0} {
        set excess [expr {[llength $hist_back] - $hist_limit}]
        if {$excess > 0} {
            set hist_back [lrange $hist_back $excess end]
        }

        set excess [expr {[llength $hist_forward] - $hist_limit}]
        if {$excess > 0} {
            set hist_forward [lrange $hist_forward $excess end]
        }
    }

    if {![dict exists $::Tclme::buffers $hist_current]} {
        set hist_current $::Tclme::current_buffer
    }
}

proc OnHistorySwitched {args} {
    variable hist_back
    variable hist_forward
    variable hist_current
    variable hist_nav_target

    set name [lindex $args 0]

    if {$name eq ""} {
        set name $::Tclme::current_buffer
    }

    if {$name eq ""} {
        return
    }

    # A programmatic back/forward switch is in progress.
    if {$hist_nav_target ne ""} {
        if {$name eq $hist_nav_target} {
            HistoryDisarmNav
            set hist_current $name
            return
        }

        HistoryDisarmNav
    }

    if {$hist_current eq $name} {
        set hist_current $name
        return
    }

    HistoryPushBack $hist_current
    set hist_forward {}
    set hist_current $name
}

proc OnHistoryKilled {args} {
    variable hist_back
    variable hist_forward
    variable hist_current

    set name [lindex $args 0]

    if {$name eq ""} {
        return
    }

    set hist_back    [HistoryRemoveFromList $hist_back    $name]
    set hist_forward [HistoryRemoveFromList $hist_forward $name]

    if {$hist_current eq $name} {
        set hist_current ""
    }
}

proc SwitchInOrder {delta} {
    if {![info exists ::Tclme::buffer_order]} {
        ::Tclme::Message "No buffers"
        return
    }

    set order {}

    foreach b $::Tclme::buffer_order {
        if {[info exists ::Tclme::buffers] && [dict exists $::Tclme::buffers $b]} {
            lappend order $b
        }
    }

    set n [llength $order]

    if {$n == 0} {
        ::Tclme::Message "No buffers"
        return
    }

    if {$n == 1} {
        ::Tclme::Message "Only one buffer"
        return
    }

    set cur $::Tclme::current_buffer
    set idx [lsearch -exact $order $cur]

    if {$idx < 0} {
        set idx 0
    }

    set idx [expr {($idx + $delta) % $n}]
    set target [lindex $order $idx]

    # If we landed on the current buffer, step once more.
    if {$target eq $cur} {
        set idx [expr {($idx + $delta) % $n}]
        set target [lindex $order $idx]
    }

    catch { ::Tclme::SwitchToBuffer $target }
}

proc PrevBuffer {} {
    variable hist_back
    variable hist_forward
    variable hist_current

    HistoryPrune

    while {[llength $hist_back] > 0} {
        set target [lindex $hist_back end]
        set hist_back [lrange $hist_back 0 end-1]

        if {![info exists ::Tclme::buffers]} {
            break
        }

        if {![dict exists $::Tclme::buffers $target]} {
            continue
        }

        if {$target eq $hist_current} {
            continue
        }

        HistoryPushForward $hist_current

        set old_current $hist_current
        set hist_current $target

        HistoryArmNav $target

        if {[catch { ::Tclme::SwitchToBuffer $target } err]} {
            set hist_current $old_current
            HistoryDisarmNav
            ::Tclme::Message "Cannot switch buffer: $err"
        }

        return
    }

    # Fallback: cycle through visible buffer order.
    SwitchInOrder -1
}

proc NextBuffer {} {
    variable hist_back
    variable hist_forward
    variable hist_current

    HistoryPrune

    while {[llength $hist_forward] > 0} {
        set target [lindex $hist_forward end]
        set hist_forward [lrange $hist_forward 0 end-1]

        if {![info exists ::Tclme::buffers]} {
            break
        }

        if {![dict exists $::Tclme::buffers $target]} {
            continue
        }

        if {$target eq $hist_current} {
            continue
        }

        HistoryPushBack $hist_current

        set old_current $hist_current
        set hist_current $target

        HistoryArmNav $target

        if {[catch { ::Tclme::SwitchToBuffer $target } err]} {
            set hist_current $old_current
            HistoryDisarmNav
            ::Tclme::Message "Cannot switch buffer: $err"
        }

        return
    }

    # Fallback: cycle through visible buffer order.
    SwitchInOrder 1
}

proc cmd-buffer-prev {args} {
    PrevBuffer
}

proc cmd-buffer-next {args} {
    NextBuffer
}

# ----------------------------------------------------------------------------
#  Lifecycle
# ----------------------------------------------------------------------------
proc load {} {
    set ns [namespace current]

    after idle [list ${ns}::ApplyVisibility]
    after idle [list ${ns}::HistoryInit]
}

proc unload {} {
    variable pending
    variable pending_delay
    variable hist_nav_timer

    if {$pending ne ""} {
        catch { after cancel $pending }
    }

    set pending ""
    set pending_delay 0

    if {$hist_nav_timer ne ""} {
        catch { after cancel $hist_nav_timer }
    }

    set hist_nav_timer ""

    if {[winfo exists .bufferbar]} {
        destroy .bufferbar
    }
}

proc save-state {} {
    variable visible
    return $visible
}

proc restore-state {s} {
    variable visible
    set visible $s
}

# ----------------------------------------------------------------------------
#  Registration
# ----------------------------------------------------------------------------

Tclme::On buffer-switched OnNow
Tclme::On buffer-created  OnNow
Tclme::On buffer-killed   OnNow
Tclme::On after-save      OnNow
Tclme::On after-file-read OnNow
Tclme::On theme-changed   OnNow
Tclme::On editor-started  OnNow
Tclme::On buffer-switched OnHistorySwitched
Tclme::On buffer-killed   OnHistoryKilled
Tclme::On editor-started  HistoryInit

# Cursor movement is used mostly to refresh dirty markers, so debounce harder.
Tclme::On cursor-moved    OnSoon

Tclme::DefCommandAndBind buffer-bar  cmd-toggle      <Control-x><Control-l> "Toggle the buffer button bar"
Tclme::DefCommandAndBind buffer-prev cmd-buffer-prev <Control-x><Control-b> "Switch to previous buffer"
Tclme::DefCommandAndBind buffer-next cmd-buffer-next <Control-x><Control-v> "Switch to next buffer"
Tclme::DefAlias tabs buffer-bar

