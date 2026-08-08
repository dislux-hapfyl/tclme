# plugins/linenum.tcl
# ============================================================================
#  Line numbers for Tclme buffers.
#
#  Commands:
#    :line-numbers          toggle for current buffer
#    :line-numbers on       enable for current buffer
#    :line-numbers off      disable for current buffer
#
#  Alias:
#    :ln
#
#  Keybinding:
#    C-x C-n                toggle line numbers
#
#  Notes:
#    - Uses a separate disabled text widget as the gutter.
#    - Syncs scrolling with the main buffer.
#    - Handles wrapped lines by adding blank continuation lines.
#    - Highlights the current logical line number.
# ============================================================================

variable enabled       [dict create]   ;# buffer name -> 1
variable maps          [dict create]   ;# buffer name -> list: logical line -> gutter line
variable orig_scroll   [dict create]   ;# buffer name -> original -yscrollcommand
variable pending_update ""
variable pending_delay  0
variable load_after     ""

# ----------------------------------------------------------------------------
#  Command
# ----------------------------------------------------------------------------

proc cmd-toggle {args} {
    variable enabled

    set name $::Tclme::current_buffer
    if {$name eq ""} {
        return
    }

    set arg [string tolower [string trim [join $args " "]]]

    if {$arg eq "on" || $arg eq "1" || $arg eq "enable"} {
        EnableBuffer $name
        ::Tclme::Message "Line numbers on: $name"
    } elseif {$arg eq "off" || $arg eq "0" || $arg eq "disable"} {
        DisableBuffer $name
        ::Tclme::Message "Line numbers off: $name"
    } else {
        if {[dict exists $enabled $name]} {
            DisableBuffer $name
            ::Tclme::Message "Line numbers off: $name"
        } else {
            EnableBuffer $name
            ::Tclme::Message "Line numbers on: $name"
        }
    }
}

# ----------------------------------------------------------------------------
#  Helpers
# ----------------------------------------------------------------------------

proc Container {name} {
    if {![dict exists $::Tclme::buffers $name]} {
        return ""
    }

    return ".ws.[dict get [dict get $::Tclme::buffers $name] wid]"
}

# ----------------------------------------------------------------------------
#  Enable / disable
# ----------------------------------------------------------------------------

proc EnableBuffer {name} {
    variable enabled

    set container [Container $name]
    if {$container eq ""} {
        return
    }

    set txt "$container.txt"
    if {![winfo exists $txt]} {
        return
    }

    dict set enabled $name 1

    EnsureAttached $name
    UpdateGutter $name
}

proc DisableBuffer {name} {
    variable enabled
    variable maps
    variable orig_scroll

    if {[dict exists $enabled $name]} {
        dict unset enabled $name
    }

    if {[dict exists $maps $name]} {
        dict unset maps $name
    }

    set container [Container $name]

    if {$container ne ""} {
        set txt "$container.txt"

        if {[winfo exists $txt]} {
            catch { bind $txt <Configure> {} }

            set cmd ""
            if {[dict exists $orig_scroll $name]} {
                set cmd [dict get $orig_scroll $name]
            }

            if {$cmd eq ""} {
                set cmd [list $container.vs set]
            }

            catch { $txt configure -yscrollcommand $cmd }
        }

        if {[winfo exists "$container.ln"]} {
            destroy "$container.ln"
        }
    }

    if {[dict exists $orig_scroll $name]} {
        dict unset orig_scroll $name
    }
}

# ----------------------------------------------------------------------------
#  Gutter construction / attachment
# ----------------------------------------------------------------------------

proc EnsureAttached {name} {
    variable orig_scroll

    set container [Container $name]
    if {$container eq ""} {
        return
    }

    set txt "$container.txt"
    if {![winfo exists $txt]} {
        return
    }

    if {![dict exists $orig_scroll $name]} {
        dict set orig_scroll $name [$txt cget -yscrollcommand]
    }

    EnsureGutter $name

    set ns [namespace current]
    $txt configure -yscrollcommand [list ${ns}::OnYScroll $container]
}

proc EnsureGutter {name} {
    set container [Container $name]
    if {$container eq ""} {
        return
    }

    set txt "$container.txt"
    if {![winfo exists $txt]} {
        return
    }

    set g "$container.ln"

    if {![winfo exists $g]} {
        text $g \
            -width 4 \
            -state disabled \
            -wrap none \
            -takefocus 0 \
            -borderwidth 0 \
            -highlightthickness 0 \
            -padx 4 \
            -pady 4 \
            -cursor arrow

        pack $g -side left -fill y -before $txt
    }

    $g configure \
        -font [::Tclme::GetTheme font] \
        -bg [::Tclme::GetTheme bg] \
        -fg [::Tclme::GetTheme fg]

    $g tag configure ln_cur \
        -background [::Tclme::GetTheme accent] \
        -foreground [::Tclme::GetTheme editor_bg]

    set ns [namespace current]
    bind $txt <Configure> [list ${ns}::OnConfigure $name]
}

# ----------------------------------------------------------------------------
#  Scrolling
# ----------------------------------------------------------------------------

proc OnYScroll {container first last} {
    catch { $container.vs set $first $last }

    if {[winfo exists $container.ln]} {
        catch { $container.ln yview moveto $first }
    }
}

proc SyncScroll {name} {
    set container [Container $name]
    if {$container eq ""} {
        return
    }

    set txt "$container.txt"
    set g   "$container.ln"

    if {![winfo exists $txt] || ![winfo exists $g]} {
        return
    }

    set frac [lindex [$txt yview] 0]
    if {$frac ne ""} {
        catch { $g yview moveto $frac }
    }
}

# ----------------------------------------------------------------------------
#  Rendering
# ----------------------------------------------------------------------------

proc UpdateGutter {name} {
    variable enabled
    variable maps

    if {![dict exists $enabled $name]} {
        return
    }

    set container [Container $name]
    if {$container eq ""} {
        return
    }

    set txt "$container.txt"
    set g   "$container.ln"

    if {![winfo exists $txt] || ![winfo exists $g]} {
        return
    }

    $g configure -state normal
    $g configure \
        -font [::Tclme::GetTheme font] \
        -bg [::Tclme::GetTheme bg] \
        -fg [::Tclme::GetTheme fg]

    $g tag configure ln_cur \
        -background [::Tclme::GetTheme accent] \
        -foreground [::Tclme::GetTheme editor_bg]

    $g delete 1.0 end

    set last [lindex [split [$txt index end] .] 0]
    set n [expr {$last - 1}]
    if {$n < 1} {
        set n 1
    }

    $g configure -width [expr {[string length $n] + 2}]

    set wrap [$txt cget -wrap]
    set map  {}
    set gline 1

    for {set i 1} {$i <= $n} {incr i} {
        set vis 1

        # For wrapped text, insert blank continuation lines so the gutter
        # stays vertically aligned with visual lines.
        if {$wrap ne "none"} {
            set c ""
            if {![catch {$txt count -displaylines "$i.0" "$i.end"} c] &&
                [string is integer -strict $c]} {
                set vis [expr {$c + 1}]
            }
        }

        if {$vis < 1} {
            set vis 1
        }

        lappend map $gline

        $g insert end "$i\n"

        for {set k 1} {$k < $vis} {incr k} {
            $g insert end "\n"
        }

        set gline [expr {$gline + $vis}]
    }

    # Remove the extra trailing newline.
    $g delete "end-1c" end

    $g configure -state disabled

    dict set maps $name $map

    SyncScroll $name
    HighlightCurrent $name
}

proc HighlightCurrent {name} {
    variable enabled
    variable maps

    if {![dict exists $enabled $name]} {
        return
    }

    set container [Container $name]
    if {$container eq ""} {
        return
    }

    set txt "$container.txt"
    set g   "$container.ln"

    if {![winfo exists $txt] || ![winfo exists $g]} {
        return
    }

    $g tag remove ln_cur 1.0 end

    if {![dict exists $maps $name]} {
        return
    }

    set map [dict get $maps $name]
    set cur [lindex [split [$txt index insert] .] 0]
    set idx [expr {$cur - 1}]

    if {$idx < 0 || $idx >= [llength $map]} {
        return
    }

    set gline [lindex $map $idx]

    catch {
        $g tag add ln_cur "$gline.0" "$gline.end"
    }
}

proc HighlightCurrentCurrent {} {
    set name $::Tclme::current_buffer
    if {$name ne ""} {
        HighlightCurrent $name
    }
}

# ----------------------------------------------------------------------------
#  Update scheduling
# ----------------------------------------------------------------------------

proc ScheduleUpdate {delay} {
    variable pending_update
    variable pending_delay

    if {$pending_update ne ""} {
        # Do not let a slower update delay a faster one that is already queued.
        if {$delay > $pending_delay} {
            return
        }

        catch { after cancel $pending_update }
    }

    set ns [namespace current]
    set pending_update [after $delay [list ${ns}::UpdateCurrent]]
    set pending_delay $delay
}

proc UpdateCurrent {} {
    variable pending_update ""
    variable pending_delay 0
    variable enabled

    set name $::Tclme::current_buffer
    if {$name eq ""} {
        return
    }

    if {[dict exists $enabled $name]} {
        EnsureAttached $name
        UpdateGutter $name
    }
}

proc UpdateAll {} {
    variable enabled

    foreach name [dict keys $enabled] {
        if {![dict exists $::Tclme::buffers $name]} {
            DisableBuffer $name
            continue
        }

        EnsureAttached $name
        UpdateGutter $name
    }
}

# ----------------------------------------------------------------------------
#  Event callbacks
# ----------------------------------------------------------------------------

proc OnFast {args} {
    ScheduleUpdate 20
}

proc OnCursor {args} {
    HighlightCurrentCurrent
    ScheduleUpdate 200
}

proc OnTheme {args} {
    UpdateAll
}

proc OnConfigure {name args} {
    variable enabled

    if {[dict exists $enabled $name] && $name eq $::Tclme::current_buffer} {
        ScheduleUpdate 150
    }
}

proc OnKilled {args} {
    set name [lindex $args 0]
    if {$name eq ""} {
        return
    }

    variable enabled
    variable maps
    variable orig_scroll

    if {[dict exists $enabled $name]} {
        dict unset enabled $name
    }

    if {[dict exists $maps $name]} {
        dict unset maps $name
    }

    if {[dict exists $orig_scroll $name]} {
        dict unset orig_scroll $name
    }
}

# ----------------------------------------------------------------------------
#  Lifecycle
# ----------------------------------------------------------------------------

proc load {} {
    variable load_after

    set ns [namespace current]
    set load_after [after idle [list ${ns}::ApplyAll]]
}

proc ApplyAll {} {
    variable load_after ""

    UpdateAll
}

proc unload {} {
    variable pending_update
    variable pending_delay
    variable load_after
    variable enabled
    variable maps
    variable orig_scroll

    if {$pending_update ne ""} {
        catch { after cancel $pending_update }
    }

    if {$load_after ne ""} {
        catch { after cancel $load_after }
    }

    foreach name [dict keys $enabled] {
        DisableBuffer $name
    }

    set pending_update ""
    set pending_delay 0
    set load_after ""
    set enabled [dict create]
    set maps [dict create]
    set orig_scroll [dict create]
}

proc save-state {} {
    variable enabled
    return $enabled
}

proc restore-state {s} {
    variable enabled

    if {[catch { dict size $s }]} {
        set enabled [dict create]
    } else {
        set enabled $s
    }
}

# ----------------------------------------------------------------------------
#  Registration
# ----------------------------------------------------------------------------

Tclme::On buffer-switched OnFast
Tclme::On after-file-read OnFast
Tclme::On after-command   OnFast
Tclme::On cursor-moved    OnCursor
Tclme::On theme-changed   OnTheme
Tclme::On buffer-killed   OnKilled

Tclme::DefCommand line-numbers cmd-toggle \
    "Toggle line numbers for current buffer (arg: on/off)"

Tclme::DefAlias ln line-numbers
Tclme::BindKey line-numbers <Control-x><Control-n>