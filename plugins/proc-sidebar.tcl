# plugins/proc-sidebar.tcl
# ============================================================================
#  proc-sidebar.tcl - Tcl procedure list sidebar for Tclme
#
#  Commands:
#    :proc-sidebar           toggle sidebar
#    :proc-sidebar-refresh   refresh sidebar
#    :proc-sidebar-sort      toggle sort mode
#
#  Keybinding:
#    C-x p                   toggle sidebar
#
#  Sidebar interactions:
#    double-click            jump to proc definition
#    Return                  jump to selected proc
#    g / r                   refresh
#    s                       toggle sort
#
#  Filter box:
#    type to filter proc names/args
#    Return                  jump to first match
#    Escape                  clear filter
# ============================================================================

# ----------------------------------------------------------------------------
# State
# ----------------------------------------------------------------------------

variable visible          0
variable procs            {}
variable display_entries  {}
variable filter           ""
variable sort_by_name     0

variable refresh_after    ""
variable display_after    ""
variable load_after       ""

variable last_fingerprint ""
variable last_buffer      ""

variable bindtag          ""
variable bound_keys       {}

variable max_scan_lines   50000

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

proc Theme {key default} {
    if {[catch { set v [::Tclme::GetTheme $key] }]} {
        return $default
    }

    if {$v eq ""} {
        return $default
    }

    return $v
}

proc ShortName {s n} {
    if {[string length $s] > $n} {
        return "[string range $s 0 [expr {$n - 4}]]..."
    }

    return $s
}

proc RegexpEscape {s} {
    regsub -all {[][{}()^$.|*+?\\]} $s {\\&} s
    return $s
}

proc SetCommandKey {cmd key} {
    upvar #0 ::Tclme::commands commands

    if {[dict exists $commands $cmd]} {
        dict set commands $cmd keys $key
    }
}

proc CurrentText {} {
    set w $::Tclme::active_widget

    if {$w eq "" || ![winfo exists $w]} {
        return ""
    }

    if {[winfo class $w] ne "Text"} {
        return ""
    }

    return $w
}

proc CancelTimers {} {
    variable refresh_after
    variable display_after

    if {$refresh_after ne ""} {
        catch { after cancel $refresh_after }
        set refresh_after ""
    }

    if {$display_after ne ""} {
        catch { after cancel $display_after }
        set display_after ""
    }
}

# ----------------------------------------------------------------------------
# Commands
# ----------------------------------------------------------------------------

proc cmd-toggle {args} {
    Toggle
}

proc cmd-refresh {args} {
    if {![winfo exists .proc_sidebar]} {
        Show
    } else {
        RefreshAll 1
    }
}

proc cmd-sort {args} {
    ToggleSort
}

proc Toggle {} {
    variable visible

    if {$visible} {
        Hide
    } else {
        Show
    }
}

# ----------------------------------------------------------------------------
# UI construction
# ----------------------------------------------------------------------------

proc Show {} {
    variable visible 1

    if {![winfo exists .proc_sidebar]} {
        BuildUI
    }

    if {[winfo exists .ws]} {
        pack .proc_sidebar -side left -fill y -before .ws
    } else {
        pack .proc_sidebar -side left -fill y
    }

    RefreshAll 1
}

proc Hide {} {
    variable visible 0
    variable procs
    variable display_entries
    variable last_fingerprint
    variable last_buffer

    CancelTimers

    if {[winfo exists .proc_sidebar]} {
        destroy .proc_sidebar
    }

    set procs            {}
    set display_entries  {}
    set last_fingerprint ""
    set last_buffer      ""
}

proc BuildUI {} {
    set ns [namespace current]

    frame .proc_sidebar
    frame .proc_sidebar.top

    label .proc_sidebar.top.title -text "Procs"

    entry .proc_sidebar.top.filter \
        -textvariable ${ns}::filter \
        -borderwidth 0 \
        -highlightthickness 0

    button .proc_sidebar.top.refresh \
        -text "R" \
        -command [list ${ns}::cmd-refresh]

    button .proc_sidebar.top.sort \
        -text "S" \
        -command [list ${ns}::ToggleSort]

    text .proc_sidebar.list \
        -state disabled \
        -wrap none \
        -width 32 \
        -borderwidth 0 \
        -highlightthickness 0 \
        -exportselection 0

    scrollbar .proc_sidebar.sb \
        -orient vertical \
        -command [list .proc_sidebar.list yview]

    .proc_sidebar.list configure \
        -yscrollcommand [list .proc_sidebar.sb set]

    pack .proc_sidebar.top.refresh .proc_sidebar.top.sort -side right -padx 1
    pack .proc_sidebar.top.title -side left
    pack .proc_sidebar.top.filter -side left -fill x -expand 1 -padx 4
    pack .proc_sidebar.top -side top -fill x

    pack .proc_sidebar.sb -side right -fill y
    pack .proc_sidebar.list -side left -fill both -expand 1

    set list   .proc_sidebar.list
    set filter .proc_sidebar.top.filter

    bind $list <Double-Button-1> [list ${ns}::OnActivateClick %x %y]
    bind $list <Return>          [list ${ns}::OnActivateKey]
    bind $list g                 [list ${ns}::RefreshForce]
    bind $list r                 [list ${ns}::RefreshForce]
    bind $list s                 [list ${ns}::ToggleSort]

    bind $filter <KeyRelease> [list ${ns}::OnFilterChanged]
    bind $filter <Return>     [list ${ns}::OnFilterReturn]
    bind $filter <Escape>     [list ${ns}::ClearFilter]

    ConfigureColors
}

proc ConfigureColors {} {
    if {![winfo exists .proc_sidebar]} {
        return
    }

    set bg     [Theme bg          "#E0E0E0"]
    set fg     [Theme fg          "#333333"]
    set editor [Theme editor_bg   "#F5F5F5"]
    set accent [Theme accent      "#4A7CFE"]
    set scroll [Theme scrollbar   "#D8D8D8"]
    set font   [Theme status_font {Consolas 9}]

    .proc_sidebar configure -bg $bg
    .proc_sidebar.top configure -bg $bg

    .proc_sidebar.top.title configure \
        -bg $bg \
        -fg $accent

    .proc_sidebar.top.filter configure \
        -bg $editor \
        -fg $fg \
        -insertbackground $fg

    foreach b {.proc_sidebar.top.refresh .proc_sidebar.top.sort} {
        catch {
            $b configure \
                -bg $bg \
                -fg $fg \
                -activebackground $bg \
                -activeforeground $fg
        }
    }

    .proc_sidebar.list configure \
        -bg $editor \
        -fg $fg \
        -font $font \
        -insertbackground $fg

    .proc_sidebar.sb configure -bg $scroll

    .proc_sidebar.list tag configure ps_selected \
        -background $accent \
        -foreground $editor
}

# ----------------------------------------------------------------------------
# Refresh / scan
# ----------------------------------------------------------------------------

proc ScheduleRefresh {{delay 250}} {
    variable refresh_after

    if {$refresh_after ne ""} {
        catch { after cancel $refresh_after }
    }

    set ns [namespace current]
    set refresh_after [after $delay [list ${ns}::DoRefresh]]
}

proc DoRefresh {} {
    variable refresh_after ""
    variable visible

    if {$visible} {
        RefreshAll 0
    }
}

proc RefreshForce {} {
    RefreshAll 1
    return -code break
}

proc Fingerprint {txt} {
    set chars 0
    set lines 0
    set mod   0

    catch { set chars [$txt count -chars 1.0 end] }
    catch { set lines [lindex [split [$txt index end] .] 0] }
    catch { set mod [$txt edit modified] }

    return "$chars:$lines:$mod"
}

proc RefreshAll {{force 0}} {
    variable procs
    variable last_fingerprint
    variable last_buffer

    if {![winfo exists .proc_sidebar.list]} {
        return
    }

    set txt [CurrentText]
    set buf $::Tclme::current_buffer

    if {$txt eq ""} {
        set procs            {}
        set last_fingerprint ""
        set last_buffer      $buf

        DisplayList
        return
    }

    set fp [Fingerprint $txt]

    if {!$force && $fp eq $last_fingerprint && $buf eq $last_buffer} {
        return
    }

    set procs [ScanProcs $txt]

    set last_fingerprint $fp
    set last_buffer      $buf

    DisplayList
}

proc ScanProcs {txt} {
    variable max_scan_lines

    set content [$txt get 1.0 end-1c]

    set procs   {}
    set lineNum 1

    # Braces prevent Tcl from treating [...] as command substitution.
    set re {^\s*proc\s+([^[:space:]]+)\s*(.*)$}

    foreach line [split $content \n] {
        if {$lineNum > $max_scan_lines} {
            break
        }

        if {[regexp $re $line -> rawname rest]} {
            set name [string trim $rawname]

            if {[string length $name] >= 2 &&
                [string index $name 0] eq "{" &&
                [string index $name end] eq "}"} {
                set name [string range $name 1 end-1]
            }

            set args [ExtractArgs $rest]

            lappend procs [list $name $lineNum $args]
        }

        incr lineNum
    }

    return $procs
}

proc ExtractArgs {rest} {
    set rest [string trim $rest]

    if {$rest eq ""} {
        return ""
    }

    set first [string index $rest 0]

    if {$first eq "\{"} {
        set depth 0
        set i     0
        set len   [string length $rest]

        while {$i < $len} {
            set c [string index $rest $i]

            if {$c eq "\\"} {
                incr i 2
                continue
            }

            if {$c eq "\{"} {
                incr depth
            }

            if {$c eq "\}"} {
                incr depth -1

                if {$depth == 0} {
                    return [string trim [string range $rest 1 [expr {$i - 1}]]]
                }
            }

            incr i
        }

        return [string trim [string range $rest 1 end]]
    }

    set brace [string first "\{" $rest]

    if {$brace >= 0} {
        return [string trim [string range $rest 0 [expr {$brace - 1}]]]
    }

    return $rest
}

# ----------------------------------------------------------------------------
# Display list / filter
# ----------------------------------------------------------------------------

proc ScheduleDisplay {} {
    variable display_after

    if {$display_after ne ""} {
        catch { after cancel $display_after }
    }

    set ns [namespace current]
    set display_after [after 80 [list ${ns}::DisplayList]]
}

proc DisplayList {} {
    variable procs
    variable display_entries
    variable filter
    variable sort_by_name

    set list .proc_sidebar.list

    if {![winfo exists $list]} {
        return
    }

    set f [string tolower [string trim $filter]]

    set entries {}

    foreach p $procs {
        lassign $p name line args

        set lname [string tolower $name]
        set largs [string tolower $args]

        if {$f eq "" ||
            [string first $f $lname] >= 0 ||
            [string first $f $largs] >= 0} {
            lappend entries $p
        }
    }

    if {$sort_by_name} {
        set entries [lsort -dictionary -index 0 $entries]
    }

    set display_entries $entries

    $list configure -state normal
    $list delete 1.0 end

    if {[llength $entries] == 0} {
        if {[llength $procs] == 0} {
            $list insert end "(no procs)\n"
        } else {
            $list insert end "(no matches)\n"
        }
    } else {
        foreach e $entries {
            lassign $e name line args

            set disp [ShortName $name 26]

            $list insert end [format "%-26s %5d\n" $disp $line]
        }
    }

    $list configure -state disabled

    UpdateTitle
}

proc UpdateTitle {} {
    variable procs
    variable display_entries

    set label .proc_sidebar.top.title

    if {![winfo exists $label]} {
        return
    }

    set total [llength $procs]
    set shown [llength $display_entries]

    $label configure -text "Procs $shown/$total"
}

proc ToggleSort {} {
    variable sort_by_name

    set sort_by_name [expr {!$sort_by_name}]

    DisplayList

    if {$sort_by_name} {
        ::Tclme::Message "Proc sidebar: sort by name"
    } else {
        ::Tclme::Message "Proc sidebar: sort by file order"
    }
}

# ----------------------------------------------------------------------------
# Filter handlers
# ----------------------------------------------------------------------------

proc OnFilterChanged {args} {
    ScheduleDisplay
}

proc OnFilterReturn {} {
    variable display_entries

    if {[llength $display_entries] > 0} {
        ActivateEntryIndex 0
    }
}

proc ClearFilter {} {
    variable filter

    set filter ""

    DisplayList

    set txt [CurrentText]

    if {$txt ne ""} {
        focus $txt
    }
}

# ----------------------------------------------------------------------------
# Activation / jumping
# ----------------------------------------------------------------------------

proc OnActivateClick {x y} {
    set list .proc_sidebar.list

    if {![winfo exists $list]} {
        return
    }

    set idx  [$list index @$x,$y]
    set line [lindex [split $idx .] 0]

    ActivateTextLine $line
}

proc OnActivateKey {} {
    set list .proc_sidebar.list

    if {![winfo exists $list]} {
        return
    }

    set line [lindex [split [$list index insert] .] 0]

    ActivateTextLine $line
}

proc ActivateTextLine {line} {
    variable display_entries

    if {![string is integer -strict $line]} {
        return
    }

    set idx [expr {$line - 1}]

    if {$idx < 0 || $idx >= [llength $display_entries]} {
        return
    }

    ActivateEntryIndex $idx
}

proc ActivateEntryIndex {idx} {
    variable display_entries

    if {$idx < 0 || $idx >= [llength $display_entries]} {
        return
    }

    set entry [lindex $display_entries $idx]

    lassign $entry name line args

    SelectSidebarLine [expr {$idx + 1}]
    JumpToProc $name $line
}

proc SelectSidebarLine {line} {
    set list .proc_sidebar.list

    if {![winfo exists $list]} {
        return
    }

    $list configure -state normal

    $list tag remove ps_selected 1.0 end

    catch {
        $list tag add ps_selected "$line.0" "$line.0 lineend"
    }

    $list tag raise ps_selected

    $list configure -state disabled
}

proc JumpToProc {name line} {
    set txt [CurrentText]

    if {$txt eq ""} {
        ::Tclme::Message "No active text buffer"
        return
    }

    set pos ""

    # First try the remembered line.
    if {[string is integer -strict $line] && $line > 0} {
        catch {
            set ltext [$txt get "$line.0" "$line.0 lineend"]

            if {[regexp "proc\\s+.*[RegexpEscape $name]" $ltext]} {
                set pos "$line.0"
            }
        }
    }

    # Fallback: search the buffer.
    if {$pos eq ""} {
        set pat "proc\\s+.*[RegexpEscape $name]"

        catch {
            set pos [$txt search -regexp -- $pat 1.0]
        }
    }

    if {$pos eq ""} {
        ::Tclme::Message "Cannot locate proc: $name"
        return
    }

    catch {
        $txt mark set insert $pos
        $txt see insert
        focus $txt
    }

    catch { ::Tclme::RefreshStatus }
    catch { ::Tclme::Emit cursor-moved }
}

# ----------------------------------------------------------------------------
# Event handlers
# ----------------------------------------------------------------------------

proc OnBufferEvent {args} {
    variable visible

    if {$visible} {
        ScheduleRefresh 50
    }
}

proc OnCommandEvent {args} {
    variable visible

    if {$visible} {
        ScheduleRefresh 300
    }
}

proc OnCursorEvent {args} {
    variable visible

    if {$visible} {
        ScheduleRefresh 700
    }
}

proc OnTheme {args} {
    ConfigureColors
}

# ----------------------------------------------------------------------------
# Lifecycle
# ----------------------------------------------------------------------------

proc load {} {
    variable load_after

    set ns [namespace current]
    set load_after [after idle [list ${ns}::ApplyState]]
}

proc ApplyState {} {
    variable load_after ""
    variable visible

    if {$visible} {
        Show
    }
}

proc unload {} {
    variable load_after
    variable bindtag
    variable bound_keys

    if {$load_after ne ""} {
        catch { after cancel $load_after }
        set load_after ""
    }

    CancelTimers

    if {[winfo exists .proc_sidebar]} {
        destroy .proc_sidebar
    }

    foreach key $bound_keys {
        foreach tag [list $bindtag TclmeText CoreText] {
            catch { bind $tag $key {} }
        }
    }

    catch {
        if {[winfo exists $::Tclme::active_widget]} {
            focus $::Tclme::active_widget
        }
    }
}

proc save-state {} {
    variable visible
    variable sort_by_name

    return [dict create \
        visible $visible \
        sort_by_name $sort_by_name \
    ]
}

proc restore-state {s} {
    variable visible
    variable sort_by_name

    if {[catch { dict size $s }]} {
        return
    }

    if {[dict exists $s visible]} {
        set visible [dict get $s visible]
    }

    if {[dict exists $s sort_by_name]} {
        set sort_by_name [dict get $s sort_by_name]
    }
}

# ----------------------------------------------------------------------------
# Registration
# ----------------------------------------------------------------------------

Tclme::DefCommandAndBind proc-sidebar  cmd-toggle <Control-x>p "Toggle Tcl procedure sidebar"
Tclme::DefCommand proc-sidebar-refresh cmd-refresh "Refresh Tcl procedure sidebar"
Tclme::DefCommand proc-sidebar-sort    cmd-sort    "Toggle proc sidebar sort mode"

if {[info commands ::Tclme::DefAlias] ne ""} {
    catch { ::Tclme::DefAlias ps proc-sidebar }
}

Tclme::On buffer-switched OnBufferEvent
Tclme::On after-file-read OnBufferEvent
Tclme::On after-save      OnBufferEvent
Tclme::On after-command   OnCommandEvent
Tclme::On cursor-moved    OnCursorEvent
Tclme::On theme-changed   OnTheme
