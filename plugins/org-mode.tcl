# plugins/org-mode.tcl
# ============================================================================
# Org-mode support for Tclme
#
# Commands:
#   :org-todo           toggle TODO/DONE state at current line
#   :org-next-heading   jump to next heading
#   :org-prev-heading   jump to previous heading
#   :org-narrow         narrow to current subtree
#   :org-widen          widen to full buffer
#   :org-table-align    align org table at point
#   :org-insert-heading insert new heading after current
#   :org-cycle          cycle visibility of current heading
#
# Aliases:
#   :ot     = :org-todo
#   :onh    = :org-next-heading
#   :oph    = :org-prev-heading
#
# Keybindings (when in org mode):
#   C-c C-t           toggle TODO state
#   C-c C-n           next heading
#   C-c C-p           previous heading
#   C-c C-i           insert heading
#   C-c TAB           cycle visibility (if implemented)
#   C-c C-a           align table
#
# Features:
#   - TODO/DOWN cycling: TODO -> DONE -> (none)
#   - Heading navigation
#   - Basic org structure recognition
#   - Table alignment
#   - Subtree narrowing
#
# Notes:
#   - Auto-detects .org files
#   - Uses org-mode keymap when active
# ============================================================================

variable org_todo_states {"TODO" "DONE"}

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

proc IsOrgBuffer {} {
    set name $::Tclme::current_buffer
    if {$name eq ""} {
        return 0
    }

    # Check by extension or buffer name pattern
    if {[string match "*.org" $name] || [string match "*org:*" $name]} {
        return 1
    }

    # Check if content looks like org mode
    set w $::Tclme::active_widget
    if {$w ne "" && [winfo exists $w] && [winfo class $w] eq "Text"} {
        set first [$w get "1.0" "10.0"]
        if {[regexp {^\*+ } $first]} {
            return 1
        }
    }

    return 0
}

proc GetCurrentLine {} {
    set w $::Tclme::active_widget
    if {$w eq "" || ![winfo exists $w]} {
        return ""
    }

    set idx [$w index insert]
    set linenum [lindex [split $idx "."] 0]
    return [$w get "$linenum.0" "$linenum.end"]
}

proc GetHeadingLevel {line} {
    if {[regexp {^(\*+) } $line match stars]} {
        return [string length $stars]
    }
    return 0
}

proc FindNextHeading {direction} {
    set w $::Tclme::active_widget
    if {$w eq "" || ![winfo exists $w]} {
        return
    }

    set current_idx [$w index insert]
    set current_line [lindex [split $current_idx "."] 0]

    if {$direction > 0} {
        set start_line [expr {$current_line + 1}]
        set end_line [$w index "end-1c"]
        set end_linenum [lindex [split $end_line "."] 0]

        for {set l $start_line} {$l <= $end_linenum} {incr l} {
            set line [$w get "$l.0" "$l.end"]
            if {[regexp {^\*+ } $line]} {
                $w mark set insert "$l.0"
                $w see insert
                return
            }
        }
        ::Tclme::Message "No more headings"
    } else {
        set start_line [expr {$current_line - 1}]

        for {set l $start_line} {$l >= 1} {incr l -1} {
            set line [$w get "$l.0" "$l.end"]
            if {[regexp {^\*+ } $line]} {
                $w mark set insert "$l.0"
                $w see insert
                return
            }
        }
        ::Tclme::Message "No previous headings"
    }
}

proc ToggleTodo {} {
    variable org_todo_states

    set w $::Tclme::active_widget
    if {$w eq "" || ![winfo exists $w]} {
        return
    }

    set current_idx [$w index insert]
    set current_line [lindex [split $current_idx "."] 0]
    set line [$w get "$current_line.0" "$current_line.end"]

    # Check if this is a heading with TODO state
    if {[regexp {^(\*+)\s+(TODO|DONE)\s+(.*)$} $line match stars state rest]} {
        # Cycle: TODO -> DONE -> (remove state)
        if {$state eq "TODO"} {
            set new_line "$stars DONE $rest"
        } elseif {$state eq "DONE"} {
            set new_line "$stars $rest"
        }

        $w delete "$current_line.0" "$current_line.end"
        $w insert "$current_line.0" $new_line
        return
    }

    # Check if heading without TODO state - add TODO
    if {[regexp {^(\*+)\s+(.*)$} $line match stars rest]} {
        set new_line "$stars TODO $rest"
        $w delete "$current_line.0" "$current_line.end"
        $w insert "$current_line.0" $new_line
        return
    }

    ::Tclme::Message "Not an org heading"
}

proc InsertHeading {} {
    set w $::Tclme::active_widget
    if {$w eq "" || ![winfo exists $w]} {
        return
    }

    set current_idx [$w index insert]
    set current_line [lindex [split $current_idx "."] 0]
    set line [$w get "$current_line.0" "$current_line.end"]

    set level [GetHeadingLevel $line]

    if {$level == 0} {
        # Not on a heading, insert at same level as context or default to 1
        set level 1
    }

    set stars [string repeat "*" $level]
    set new_heading "$stars \n"

    $w insert "$current_line.end" $new_heading
    $w mark set insert "$current_line.end"
    $w see insert
}

proc AlignTable {} {
    set w $::Tclme::active_widget
    if {$w eq "" || ![winfo exists $w]} {
        return
    }

    set current_idx [$w index insert]
    set current_line [lindex [split $current_idx "."] 0]

    # Find table boundaries (lines starting/containing |)
    set start_line $current_line
    set end_line $current_line

    # Go up to find table start
    while {$start_line > 1} {
        set prev_line [$w get "[expr {$start_line - 1}].0" "[expr {$start_line - 1}].end"]
        if {[regexp {^\s*\|} $prev_line]} {
            incr start_line -1
        } else {
            break
        }
    }

    # Go down to find table end
    set total_lines [lindex [split [$w index "end-1c"] "."] 0]
    while {$end_line < $total_lines} {
        set next_line [$w get "[expr {$end_line + 1}].0" "[expr {$end_line + 1}].end"]
        if {[regexp {^\s*\|} $next_line]} {
            incr end_line
        } else {
            break
        }
    }

    # Collect all rows and calculate column widths
    set rows {}
    set max_cols 0

    for {set l $start_line} {$l <= $end_line} {incr l} {
        set row_text [$w get "$l.0" "$l.end"]
        if {[regexp {^\s*\|(.*)\|\s*$} $row_text match content]} {
            # Split by | and trim
            set cells [split $content "|"]
            set trimmed_cells {}
            foreach cell $cells {
                lappend trimmed_cells [string trim $cell]
            }
            lappend rows $trimmed_cells
            if {[llength $trimmed_cells] > $max_cols} {
                set max_cols [llength $trimmed_cells]
            }
        }
    }

    if {[llength $rows] == 0} {
        ::Tclme::Message "No table found at point"
        return
    }

    # Calculate max width for each column
    set col_widths {}
    for {set c 0} {$c < $max_cols} {incr c} {
        lappend col_widths 0
    }

    foreach row $rows {
        set c 0
        foreach cell $row {
            set len [string length $cell]
            set current [lindex $col_widths $c]
            if {$len > $current} {
                dict set col_widths $c $len
            }
            incr c
        }
    }

    # Rebuild table with aligned columns
    set new_table ""
    foreach row $rows {
        set formatted "|"
        set c 0
        foreach cell $row {
            set width [dict get $col_widths $c]
            set formatted_cell [format "%-${width}s" $cell]
            append formatted " $formatted_cell |"
            incr c
        }
        # Pad missing columns
        while {$c < $max_cols} {
            set width [dict get $col_widths $c]
            set formatted_cell [format "%-${width}s" ""]
            append formatted " $formatted_cell |"
            incr c
        }
        append new_table "$formatted\n"
    }

    # Replace old table with new
    $w delete "$start_line.0" "[expr {$end_line + 1}].0"
    $w insert "$start_line.0" $new_table

    ::Tclme::Message "Table aligned"
}

proc NarrowToSubtree {} {
    set w $::Tclme::active_widget
    if {$w eq "" || ![winfo exists $w]} {
        return
    }

    set current_idx [$w index insert]
    set current_line [lindex [split $current_idx "."] 0]
    set line [$w get "$current_line.0" "$current_line.end"]

    set level [GetHeadingLevel $line]
    if {$level == 0} {
        ::Tclme::Message "Not on a heading"
        return
    }

    # Find start (current heading)
    set start $current_line

    # Find end (next heading at same or higher level, or EOF)
    set total_lines [lindex [split [$w index "end-1c"] "."] 0]
    set end $total_lines

    for {set l [expr {$current_line + 1}]} {$l <= $total_lines} {incr l} {
        set check_line [$w get "$l.0" "$l.end"]
        set check_level [GetHeadingLevel $check_line]
        if {$check_level > 0 && $check_level <= $level} {
            set end [expr {$l - 1}]
            break
        }
    }

    $w tag add narrowed "$start.0" "$end.end"
    $w configure -elide narrowed
    ::Tclme::Message "Narrowed to subtree"
}

proc WidenBuffer {} {
    set w $::Tclme::active_widget
    if {$w eq "" || ![winfo exists $w]} {
        return
    }

    $w tag remove narrowed 1.0 end
    $w configure -elide {}
    ::Tclme::Message "Widened buffer"
}

proc CycleVisibility {} {
    # Simplified cycle: just show/hide immediate children
    set w $::Tclme::active_widget
    if {$w eq "" || ![winfo exists $w]} {
        return
    }

    set current_idx [$w index insert]
    set current_line [lindex [split $current_idx "."] 0]
    set line [$w get "$current_line.0" "$current_line.end"]

    set level [GetHeadingLevel $line]
    if {$level == 0} {
        ::Tclme::Message "Not on a heading"
        return
    }

    set total_lines [lindex [split [$w index "end-1c"] "."] 0]
    set children_start [expr {$current_line + 1}]
    set children_end $total_lines

    # Find extent of children
    for {set l $children_start} {$l <= $total_lines} {incr l} {
        set check_line [$w get "$l.0" "$l.end"]
        set check_level [GetHeadingLevel $check_line]
        if {$check_level > 0 && $check_level <= $level} {
            set children_end [expr {$l - 1}]
            break
        }
    }

    # Check if already folded
    set elided [$w tag ranges elided]

    # Simple toggle: fold children if visible, unfold if folded
    if {[llength $elided] > 0} {
        # Unfold
        $w tag remove elided 1.0 end
        ::Tclme::Message "Expanded"
    } else {
        # Fold children
        if {$children_start <= $children_end} {
            $w tag add elided "$children_start.0" "$children_end.end"
            $w configure -elide elided
            ::Tclme::Message "Folded"
        }
    }
}

# ----------------------------------------------------------------------------
# Commands
# ----------------------------------------------------------------------------

proc cmd-todo {args} {
    if {![IsOrgBuffer]} {
        ::Tclme::Message "Not an org buffer"
        return
    }
    ToggleTodo
}

proc cmd-next-heading {args} {
    if {![IsOrgBuffer]} {
        ::Tclme::Message "Not an org buffer"
        return
    }
    FindNextHeading 1
}

proc cmd-prev-heading {args} {
    if {![IsOrgBuffer]} {
        ::Tclme::Message "Not an org buffer"
        return
    }
    FindNextHeading -1
}

proc cmd-insert-heading {args} {
    if {![IsOrgBuffer]} {
        ::Tclme::Message "Not an org buffer"
        return
    }
    InsertHeading
}

proc cmd-align-table {args} {
    if {![IsOrgBuffer]} {
        ::Tclme::Message "Not an org buffer"
        return
    }
    AlignTable
}

proc cmd-narrow {args} {
    if {![IsOrgBuffer]} {
        ::Tclme::Message "Not an org buffer"
        return
    }
    NarrowToSubtree
}

proc cmd-widen {args} {
    if {![IsOrgBuffer]} {
        ::Tclme::Message "Not an org buffer"
        return
    }
    WidenBuffer
}

proc cmd-cycle {args} {
    if {![IsOrgBuffer]} {
        ::Tclme::Message "Not an org buffer"
        return
    }
    CycleVisibility
}

# ----------------------------------------------------------------------------
# Setup
# ----------------------------------------------------------------------------

proc setup {} {
    # Register commands
    ::Tclme::RegisterCommand "org-todo" [namespace code [list cmd-todo]]
    ::Tclme::RegisterCommand "org-next-heading" [namespace code [list cmd-next-heading]]
    ::Tclme::RegisterCommand "org-prev-heading" [namespace code [list cmd-prev-heading]]
    ::Tclme::RegisterCommand "org-insert-heading" [namespace code [list cmd-insert-heading]]
    ::Tclme::RegisterCommand "org-align-table" [namespace code [list cmd-align-table]]
    ::Tclme::RegisterCommand "org-narrow" [namespace code [list cmd-narrow]]
    ::Tclme::RegisterCommand "org-widen" [namespace code [list cmd-widen]]
    ::Tclme::RegisterCommand "org-cycle" [namespace code [list cmd-cycle]]

    # Aliases
    ::Tclme::RegisterCommand "ot" [namespace code [list cmd-todo]]
    ::Tclme::RegisterCommand "onh" [namespace code [list cmd-next-heading]]
    ::Tclme::RegisterCommand "oph" [namespace code [list cmd-prev-heading]]

    # Create org-mode specific keymap
    array set org_bindings {
        "Control-c Control-t" "org-todo"
        "Control-c Control-n" "org-next-heading"
        "Control-c Control-p" "org-prev-heading"
        "Control-c Control-i" "org-insert-heading"
        "Control-c Tab"       "org-cycle"
        "Control-c Control-a" "org-align-table"
        "Control-c Control-w" "org-widen"
        "Control-c Control-q" "org-narrow"
    }

    # Store keymap for org mode
    variable org_keymap [array get org_bindings]

    ::Tclme::Message "Org mode loaded"
}

# Auto-load for .org files
proc on_buffer_switch {buffer_name} {
    variable org_keymap

    if {[string match "*.org" $buffer_name]} {
        # Apply org-mode keybindings
        foreach {key command} $org_keymap {
            ::Tclme::BindKey $key $command
        }
        ::Tclme::Message "Org mode enabled for $buffer_name"
    }
}

# Register event handler
if {[info commands ::Tclme::OnEvent] ne ""} {
    ::Tclme::OnEvent "buffer-switched" [namespace code [list on_buffer_switch]]
}

# Run setup
setup