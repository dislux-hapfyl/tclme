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
#  Lifecycle
# ----------------------------------------------------------------------------

proc load {} {
    set ns [namespace current]
    after idle [list ${ns}::ApplyVisibility]
}

proc unload {} {
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

# Cursor movement is used mostly to refresh dirty markers, so debounce harder.
Tclme::On cursor-moved    OnSoon

Tclme::DefCommandAndBind buffer-bar cmd-toggle <Control-x><Control-b> "Toggle the buffer button bar"
Tclme::DefAlias tabs buffer-bar