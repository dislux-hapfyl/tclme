# plugins/acme-search.tcl
# ============================================================================
#  Acme-style right-click search.
#
#  Right-click on a word:
#    - extracts the word under the mouse
#    - searches forward for the next occurrence
#    - wraps around if necessary
#    - moves the cursor to the match
#    - selects the match
#
#  If there is an active selection and you right-click inside it, the
#  selected text is used as the search term.
#
#  Command:
#    :acme-search-case     toggle case-sensitive search
# ============================================================================

variable prev_binding   ""
variable use_selection  1
variable case_sensitive 1

# Characters considered part of a "word".
# Adjust this to taste.
variable word_re {[[:alnum:]_:./-]}

# ----------------------------------------------------------------------------
#  Command
# ----------------------------------------------------------------------------

proc cmd-toggle-case {args} {
    variable case_sensitive

    set case_sensitive [expr {!$case_sensitive}]

    if {$case_sensitive} {
        ::Tclme::Message "Right-click search: case-sensitive"
    } else {
        ::Tclme::Message "Right-click search: case-insensitive"
    }
}

# ----------------------------------------------------------------------------
#  Binding lifecycle
# ----------------------------------------------------------------------------

proc load {} {
    variable prev_binding

    set ns  [namespace current]
    set old [bind TclmeText <ButtonRelease-3>]

    # Avoid accidentally stacking our own binding after manual re-source.
    if {[string first $ns $old] >= 0} {
        set old ""
    }

    set prev_binding $old

    bind TclmeText <ButtonRelease-3> [list ${ns}::OnClick %W %x %y]
}

proc unload {} {
    variable prev_binding

    bind TclmeText <ButtonRelease-3> $prev_binding
}

proc save-state {} {
    variable use_selection
    variable case_sensitive

    return [dict create \
        use_selection $use_selection \
        case_sensitive $case_sensitive \
    ]
}

proc restore-state {s} {
    variable use_selection
    variable case_sensitive

    if {[catch { dict size $s }]} {
        return
    }

    if {[dict exists $s use_selection]} {
        set use_selection [dict get $s use_selection]
    }

    if {[dict exists $s case_sensitive]} {
        set case_sensitive [dict get $s case_sensitive]
    }
}

# ----------------------------------------------------------------------------
#  Event entry point
# ----------------------------------------------------------------------------

proc OnClick {w x y} {
    if {[catch { DoClick $w $x $y } err]} {
        ::Tclme::Log error "acme-search: $err"
    }

    # Stop other handlers from also processing this right-click.
    return -code break
}

proc DoClick {w x y} {
    variable use_selection
    variable case_sensitive

    if {![winfo exists $w]} {
        return
    }

    if {$::Tclme::prompting} {
        return
    }

    focus $w
    set ::Tclme::active_widget $w

    set idx [$w index @$x,$y]

    set term  ""
    set start ""
    set end   ""

    # Prefer active selection if the click is inside it.
    if {$use_selection} {
        set sel [SelectionRange $w $idx]

        if {[llength $sel] > 0} {
            lassign $sel term start end
        }
    }

    # Otherwise use the word under the cursor.
    if {$term eq ""} {
        set range [WordRange $w $idx]

        if {[llength $range] == 0} {
            return
        }

        lassign $range term start end
    }

    if {[string trim $term] eq ""} {
        return
    }

    set flags [list -exact]

    if {!$case_sensitive} {
        lappend flags -nocase
    }

    # Search forward from the end of the clicked word/selection.
    set pos [$w search {*}$flags -- $term $end end]

    # Wrap around.
    if {$pos eq ""} {
        set pos [$w search {*}$flags -- $term 1.0 end]
    }

    if {$pos eq ""} {
        ::Tclme::Message "Not found: $term"
        return
    }

    # If we only found the same occurrence, check whether it is the only one.
    if {[$w compare $pos == $start]} {
        set second [$w search {*}$flags -- $term "$pos +1c" end]

        if {$second eq ""} {
            set second [$w search {*}$flags -- $term 1.0 $pos]
        }

        if {$second eq ""} {
            ::Tclme::Message "Only occurrence: $term"
            return
        }
    }

    MoveToMatch $w $pos $term
}

# ----------------------------------------------------------------------------
#  Selection helper
# ----------------------------------------------------------------------------

proc SelectionRange {w idx} {
    if {[catch {
        set sf [$w index sel.first]
        set sl [$w index sel.last]
    }]} {
        return {}
    }

    if {[$w compare $idx >= $sf] && [$w compare $idx <= $sl]} {
        set term [$w get $sf $sl]
        return [list $term $sf $sl]
    }

    return {}
}

# ----------------------------------------------------------------------------
#  Word extraction
# ----------------------------------------------------------------------------

proc WordRange {w idx} {
    variable word_re

    set line_start [$w index "$idx linestart"]
    set line_end   [$w index "$idx lineend"]
    set line       [$w get $line_start $line_end]
    set len        [string length $line]

    if {$len == 0} {
        return {}
    }

    set col [lindex [split [$w index $idx] .] 1]

    if {![string is integer -strict $col]} {
        set col 0
    }

    if {$col >= $len} {
        set col [expr {$len - 1}]
    }

    if {$col < 0} {
        return {}
    }

    # If the click was just after a word, step back one character.
    if {![regexp $word_re [string index $line $col]]} {
        incr col -1

        if {$col < 0 || ![regexp $word_re [string index $line $col]]} {
            return {}
        }
    }

    set start $col
    while {$start > 0 && [regexp $word_re [string index $line [expr {$start - 1}]]]} {
        incr start -1
    }

    set end $col
    while {$end < $len - 1 && [regexp $word_re [string index $line [expr {$end + 1}]]]} {
        incr end
    }

    set word [string range $line $start $end]

    set start_idx [$w index "$line_start + $start chars"]
    set end_idx   [$w index "$line_start + [expr {$end + 1}] chars"]

    return [list $word $start_idx $end_idx]
}

# ----------------------------------------------------------------------------
#  Move / highlight match
# ----------------------------------------------------------------------------

proc MoveToMatch {w pos term} {
    catch { $w mark set insert $pos }
    catch { $w see insert }

    # Select the found text.
    catch { $w tag remove sel 1.0 end }
    catch { $w tag add sel $pos "$pos + [string length $term] chars" }

    ::Tclme::Emit cursor-moved
    ::Tclme::RefreshStatus
}

# ----------------------------------------------------------------------------
#  Registration
# ----------------------------------------------------------------------------

Tclme::DefCommand acme-search-case cmd-toggle-case \
    "Toggle case sensitivity for right-click search"
