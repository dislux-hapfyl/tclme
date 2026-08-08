# plugins/findbar.tcl
# ============================================================================
# findbar.tcl - search and replace UI plugin for Tclme
#
# Commands:
#   :find
#   :search
#   :find-replace
#
# Keybindings:
#   C-s       open/find next
#   C-f       open find
#   C-r       open find/replace focus
#
# Panel keys:
#   Return        find next
#   Shift-Return  find previous
#   C-s           find next
#   C-r           find previous / replace current
#   Escape        hide panel
# ============================================================================

# ----------------------------------------------------------------------------
# State replace
# ----------------------------------------------------------------------------

variable visible 0

variable pattern       ""
variable replacement   ""

variable ignore_case   1
variable whole_word    0
variable use_regexp    0
variable wrap          1

variable current_start ""
variable current_end   ""

variable last_widget   ""
variable last_pattern  ""

variable last_highlight_widget ""

variable match_count   0
variable max_highlight 2000

variable highlight_after ""
variable load_after      ""

variable bindtag    ""
variable bound_keys {}

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

proc Status {msg} {
    if {[winfo exists .findbar.status]} {
        catch { .findbar.status configure -text $msg }
    }
}

proc RegexpEscape {s} {
    regsub -all {[][{}()^$.|*+?\\]} $s {\\&} s
    return $s
}

proc BuildRegexpPattern {} {
    variable pattern
    variable use_regexp
    variable whole_word

    if {$pattern eq ""} {
        return ""
    }

    if {$use_regexp} {
        set re $pattern
    } else {
        set re [RegexpEscape $pattern]
    }

    if {$whole_word} {
        set re "\\m(?:$re)\\M"
    }

    return $re
}

proc LiteralRegsubReplacement {s} {
    set map [list "\\" "\\\\" "&" "\\&"]
    return [string map $map $s]
}

# ----------------------------------------------------------------------------
# UI
# ----------------------------------------------------------------------------

proc Show {} {
    variable visible 1
    variable pattern

    if {![winfo exists .findbar]} {
        BuildUI
    }

    if {[winfo exists .sep1]} {
        pack .findbar -fill x -before .sep1
    } else {
        pack .findbar -side bottom -fill x
    }

    # If the old core search had a saved pattern, inherit it once.
    if {$pattern eq "" && [info exists ::Tclme::last_search]} {
        set pattern $::Tclme::last_search
    }

    ConfigureColors
    ScheduleHighlight
}

proc ReturnFocusToText {} {
    set w [CurrentText]

    # Fallback: use the current buffer's text widget if active_widget is not usable.
    if {$w eq "" && [info exists ::Tclme::buffers]} {
        set name $::Tclme::current_buffer

        if {$name ne "" && [dict exists $::Tclme::buffers $name]} {
            set info [dict get $::Tclme::buffers $name]
            set candidate ".ws.[dict get $info wid].txt"

            if {[winfo exists $candidate]} {
                set w $candidate
            }
        }
    }

    if {$w ne "" && [winfo exists $w]} {
        catch { focus -force $w }
    }
}

proc Hide {} {
    variable visible 0

    CancelScheduledHighlight

    set w [CurrentText]

    if {$w ne ""} {
        ClearHighlights $w
    }

    if {[winfo exists .findbar]} {
        destroy .findbar
    }

    ReturnFocusToText
}

proc Toggle {} {
    variable visible

    if {$visible} {
        Hide
    } else {
        Show
    }
}

proc BuildUI {} {
    set ns [namespace current]

    # Important: remove any old/partial panel first.
    if {[winfo exists .findbar]} {
        destroy .findbar
    }

    ::frame .findbar

    # Create the status label exactly once.
    ::label .findbar.status -text ""

    ::frame .findbar.optrow
    ::frame .findbar.findrow
    ::frame .findbar.replrow

    # Options row -------------------------------------------------------------

    ::checkbutton .findbar.optrow.icase \
        -text "Ignore case" \
        -variable ${ns}::ignore_case \
        -command [list ${ns}::OptionsChanged]

    ::checkbutton .findbar.optrow.word \
        -text "Whole word" \
        -variable ${ns}::whole_word \
        -command [list ${ns}::OptionsChanged]

    ::checkbutton .findbar.optrow.regexp \
        -text "Regex" \
        -variable ${ns}::use_regexp \
        -command [list ${ns}::OptionsChanged]

    ::checkbutton .findbar.optrow.wrap \
        -text "Wrap" \
        -variable ${ns}::wrap \
        -command [list ${ns}::OptionsChanged]

    pack .findbar.optrow.icase \
         .findbar.optrow.word \
         .findbar.optrow.regexp \
         .findbar.optrow.wrap \
         -side left -padx 6

    # Find row ----------------------------------------------------------------

    ::label .findbar.findrow.label -text "Find:"

    ::entry .findbar.findrow.pattern \
        -textvariable ${ns}::pattern

    ::button .findbar.findrow.prev \
        -text "Prev" \
        -command [list ${ns}::FindPrev]

    ::button .findbar.findrow.next \
        -text "Next" \
        -command [list ${ns}::FindNext]

    ::button .findbar.findrow.all \
        -text "All" \
        -command [list ${ns}::HighlightAll]

    pack .findbar.findrow.label   -side left -padx {4 2}
    pack .findbar.findrow.pattern -side left -fill x -expand 1
    pack .findbar.findrow.prev    -side left -padx 2
    pack .findbar.findrow.next    -side left -padx 2
    pack .findbar.findrow.all     -side left -padx {2 4}

    # Replace row ---------------------------------------------------------------

    ::label .findbar.replrow.label -text "Replace:"

    ::entry .findbar.replrow.entry \
        -textvariable ${ns}::replacement

    ::button .findbar.replrow.replace \
        -text "Replace" \
        -command [list ${ns}::ReplaceCurrent]

    ::button .findbar.replrow.replace_all \
        -text "Replace All" \
        -command [list ${ns}::ReplaceAll]

    pack .findbar.replrow.label       -side left -padx {4 2}
    pack .findbar.replrow.entry       -side left -fill x -expand 1
    pack .findbar.replrow.replace     -side left -padx 2
    pack .findbar.replrow.replace_all -side left -padx {2 4}

    # Assemble -----------------------------------------------------------------

    pack .findbar.status  -side bottom -padx 1 -anchor nw
    pack .findbar.optrow  -side top -fill x
    pack .findbar.findrow -side top -fill x
    pack .findbar.replrow -side top -fill x

    # Bindings -----------------------------------------------------------------

    set find_entry    .findbar.findrow.pattern
    set replace_entry .findbar.replrow.entry

    bind $find_entry <Return>        [list ${ns}::FindNext]
    bind $find_entry <Shift-Return>  [list ${ns}::FindPrev]
    bind $find_entry <Control-s>     [list ${ns}::FindNext]
    bind $find_entry <Control-r>     [list ${ns}::FindPrev]
    bind $find_entry <Escape>        [list ${ns}::Hide]
    bind $find_entry <KeyRelease>    [list ${ns}::OnPatternKey %K]

    bind $replace_entry <Return>     [list ${ns}::ReplaceCurrent]
    bind $replace_entry <Control-s>  [list ${ns}::FindNext]
    bind $replace_entry <Control-r>  [list ${ns}::ReplaceCurrent]
    bind $replace_entry <Escape>     [list ${ns}::Hide]
}

proc ConfigureColors {} {
    if {![winfo exists .findbar]} {
        return
    }

    set bg     [Theme bg          "#E0E0E0"]
    set fg     [Theme fg          "#222222"]
    set editor [Theme editor_bg   "#FFFFFF"]
    set accent [Theme accent      "#4A7CFE"]
    set active [Theme separator   "#D8D8D8"]

    .findbar configure -bg $bg

    foreach f {.findbar.optrow .findbar.findrow .findbar.replrow} {
        $f configure -bg $bg
    }

    foreach lbl {.findbar.findrow.label .findbar.replrow.label .findbar.status} {
        if {[winfo exists $lbl]} {
            $lbl configure -bg $bg -fg $fg
        }
    }

    foreach b {.findbar.findrow.prev .findbar.findrow.next .findbar.findrow.all
               .findbar.replrow.replacebtn .findbar.replrow.replace_all} {
        if {[winfo exists $b]} {
            $b configure \
                -bg $bg \
                -fg $fg 
        }
    }

    foreach cb {.findbar.optrow.icase .findbar.optrow.word
                .findbar.optrow.regexp .findbar.optrow.wrap} {
        if {[winfo exists $cb]} {
            catch {
                $cb configure \
                    -bg $bg \
                    -fg $fg \
                    -selectcolor $editor
            }
        }
    }

    foreach e {.findbar.findrow.pattern .findbar.replrow.entry} {
        if {[winfo exists $e]} {
            $e configure \
                -bg $editor \
                -fg $fg \
                -insertbackground $fg
        }
    }

    .findbar.status configure -fg $accent
}

# ----------------------------------------------------------------------------
# Commands
# ----------------------------------------------------------------------------

proc cmd-find {args} {
    variable pattern

    Show

    set arg [string trim [join $args " "]]

    if {$arg eq ""} {
        if {[winfo exists .findbar.findrow.pattern]} {
            focus .findbar.findrow.pattern
        }
        return
    }

    if {[string equal -nocase $arg "clear"]} {
        set pattern ""

        set w [CurrentText]
        if {$w ne ""} {
            ClearHighlights $w
        }

        Status "Search cleared"
        return
    }

    if {$arg eq "!" || $arg eq "-new"} {
        set pattern ""

        if {[winfo exists .findbar.findrow.pattern]} {
            focus .findbar.findrow.pattern
        }

        return
    }

    if {[string match "--*" $arg]} {
        set arg [string trim [string range $arg 2 end]]
    }

    set pattern $arg

    FindNext
}

proc cmd-find-replace {args} {
    variable replacement

    Show

    set arg [string trim [join $args " "]]

    if {$arg ne ""} {
        set replacement $arg
    }

    if {[winfo exists .findbar.replrow.entry]} {
        focus .findbar.replrow.entry
    }
}

# ----------------------------------------------------------------------------
# Search engine
# ----------------------------------------------------------------------------

proc FindNext {} {
    variable pattern
    variable wrap
    variable last_widget
    variable last_pattern
    variable current_end
    variable ignore_case

    CancelScheduledHighlight

    set w [CurrentText]

    if {$w eq ""} {
        Status "No text buffer"
        return
    }

    set re [BuildRegexpPattern]

    if {$re eq ""} {
        Status "Empty search pattern"
        return
    }

    if {[catch { regexp -- $re "" } err]} {
        Status "Invalid regexp: $err"
        return
    }

    set flags {-regexp}

    if {$ignore_case} {
        lappend flags -nocase
    }

    set start [$w index insert+1c]

    if {$last_widget eq $w && $last_pattern eq $pattern && $current_end ne ""} {
        if {![catch { $w compare $current_end >= 1.0 }]} {
            set start $current_end
        }
    }

    set len 0
    set pos [$w search -count len {*}$flags -- $re $start end]

    if {$pos eq "" && $wrap} {
        set pos [$w search -count len {*}$flags -- $re 1.0 end]
    }

    if {$pos eq ""} {
        Status "Not found: $pattern"
        return
    }

    SetCurrentMatch $w $pos $len
    Status "Found: $pattern"
}

proc FindPrev {} {
    variable pattern
    variable wrap
    variable last_widget
    variable last_pattern
    variable current_start
    variable ignore_case

    CancelScheduledHighlight

    set w [CurrentText]

    if {$w eq ""} {
        Status "No text buffer"
        return
    }

    set re [BuildRegexpPattern]

    if {$re eq ""} {
        Status "Empty search pattern"
        return
    }

    if {[catch { regexp -- $re "" } err]} {
        Status "Invalid regexp: $err"
        return
    }

    set flags {-regexp}

    if {$ignore_case} {
        lappend flags -nocase
    }

    set start [$w index insert]

    if {$last_widget eq $w && $last_pattern eq $pattern && $current_start ne ""} {
        if {![catch { $w compare $current_start >= 1.0 }]} {
            set start $current_start
        }
    }

    catch {
        set start [$w index "$start -1c"]
    }

    set len 0
    set pos [$w search -count len -backward {*}$flags -- $re $start 1.0]

    if {$pos eq "" && $wrap} {
        set pos [$w search -count len -backward {*}$flags -- $re end 1.0]
    }

    if {$pos eq ""} {
        Status "Not found: $pattern"
        return
    }

    SetCurrentMatch $w $pos $len
    Status "Found: $pattern"
}

proc SetCurrentMatch {w pos len} {
    variable current_start
    variable current_end
    variable last_widget
    variable last_pattern
    variable pattern

    EnsureTags $w

    if {$last_widget ne "" && $last_widget ne $w && [winfo exists $last_widget]} {
        catch { $last_widget tag remove find_current 1.0 end }
    }

    if {$len <= 0} {
        set len 1
    }

    set end [$w index "$pos + $len chars"]

    set current_start $pos
    set current_end   $end
    set last_widget   $w
    set last_pattern  $pattern

    catch {
        $w tag remove find_current 1.0 end
        $w tag add find_current $pos $end
        $w tag raise find_current
    }

    catch {
        $w mark set insert $pos
        $w see $pos
    }
}

# ----------------------------------------------------------------------------
# Highlight all matches
# ----------------------------------------------------------------------------

proc ScheduleHighlight {} {
    variable highlight_after

    if {$highlight_after ne ""} {
        catch { after cancel $highlight_after }
    }

    set ns [namespace current]
    set highlight_after [after 250 [list ${ns}::HighlightAll]]
}

proc CancelScheduledHighlight {} {
    variable highlight_after

    if {$highlight_after ne ""} {
        catch { after cancel $highlight_after }
        set highlight_after ""
    }
}

proc OnPatternKey {key} {
    if {[lsearch -exact {
        Return Escape Tab
        Shift_L Shift_R
        Control_L Control_R
        Alt_L Alt_R
        Meta_L Meta_R
        Caps_Lock
    } $key] >= 0} {
        return
    }

    ScheduleHighlight
}

proc OptionsChanged {} {
    ScheduleHighlight
}

proc HighlightAll {} {
    variable visible
    variable pattern
    variable ignore_case
    variable max_highlight
    variable last_widget
    variable last_pattern
    variable last_highlight_widget
    variable match_count

    if {!$visible} {
        return
    }

    set w [CurrentText]

    if {$w eq ""} {
        return
    }

    EnsureTags $w

    set re [BuildRegexpPattern]

    if {$re eq ""} {
        ClearHighlights $w
        Status ""
        return
    }

    if {[catch { regexp -- $re "" } err]} {
        Status "Invalid regexp: $err"
        return
    }

    if {$last_highlight_widget ne "" &&
        $last_highlight_widget ne $w &&
        [winfo exists $last_highlight_widget]} {
        catch {
            $last_highlight_widget tag remove find_all 1.0 end
            $last_highlight_widget tag remove find_current 1.0 end
        }
    }

    set last_highlight_widget $w

    ClearHighlights $w

    set last_widget  $w
    set last_pattern $pattern

    set flags {-regexp}

    if {$ignore_case} {
        lappend flags -nocase
    }

    set idx   1.0
    set count 0

    while {$count < $max_highlight} {
        set len 0
        set pos [$w search -count len {*}$flags -- $re $idx end]

        if {$pos eq ""} {
            break
        }

        if {$len <= 0} {
            set idx [$w index "$pos +1c"]
            continue
        }

        $w tag add find_all $pos "$pos + $len chars"

        incr count

        set idx [$w index "$pos + $len chars"]
    }

    catch { $w tag raise find_current }

    set match_count $count

    if {$count >= $max_highlight} {
        Status "$count+ matches"
    } else {
        Status "$count matches"
    }
}

proc ClearHighlights {w} {
    variable current_start
    variable current_end
    variable match_count

    catch {
        $w tag remove find_all 1.0 end
        $w tag remove find_current 1.0 end
    }

    set current_start ""
    set current_end   ""
    set match_count   0
}

proc EnsureTags {w} {
    if {![winfo exists $w]} {
        return
    }

    set accent [Theme accent    "#4A7CFE"]
    set editor [Theme editor_bg "#FFFFFF"]
    set sep    [Theme separator "#D8D8D8"]

    $w tag configure find_all \
        -background $sep \
        -underline 1

    $w tag configure find_current \
        -background $accent \
        -foreground $editor

    $w tag raise find_all
    $w tag raise find_current
}
# ----------------------------------------------------------------------------
# Replace engine
# ----------------------------------------------------------------------------

proc ReplaceCurrent {} {
    variable current_start
    variable current_end
    variable last_widget
    variable last_pattern
    variable pattern
    variable replacement

    CancelScheduledHighlight

    set w [CurrentText]

    if {$w eq ""} {
        Status "No text buffer"
        return
    }

    if {[$w cget -state] eq "disabled"} {
        Status "Buffer is read-only"
        return
    }

    # If we do not have a live current match, find one first.
    if {$last_widget ne $w || $last_pattern ne $pattern ||
        $current_start eq "" || $current_end eq ""} {
        FindNext

        if {$current_start eq "" || $current_end eq ""} {
            return
        }
    }

    set match [$w get $current_start $current_end]

    if {[catch {
        set new [ComputeReplacement $match]
    } err]} {
        Status "Replace error: $err"
        return
    }

    catch { $w edit separator }

    $w delete $current_start $current_end
    $w insert $current_start $new

    catch { $w edit separator }

    set new_end [$w index "$current_start + [string length $new] chars"]

    catch {
        $w mark set insert $new_end
        $w see insert
    }

    ClearHighlights $w

    Status "Replaced; searching next"

    FindNext
}

proc ReplaceAll {} {
    variable pattern
    variable replacement
    variable ignore_case
    variable use_regexp

    CancelScheduledHighlight

    set w [CurrentText]

    if {$w eq ""} {
        Status "No text buffer"
        return
    }

    if {[$w cget -state] eq "disabled"} {
        Status "Buffer is read-only"
        return
    }

    set re [BuildRegexpPattern]

    if {$re eq ""} {
        Status "Empty search pattern"
        return
    }

    if {[catch { regexp -- $re "" } err]} {
        Status "Invalid regexp: $err"
        return
    }

    set text [$w get 1.0 end-1c]

    set flags {}

    if {$ignore_case} {
        lappend flags -nocase
    }

    set rep $replacement

    if {!$use_regexp} {
        set rep [LiteralRegsubReplacement $rep]
    }

    if {[catch {
        set n [regsub -all {*}$flags -- $re $text $rep newtext]
    } err]} {
        Status "Replace all error: $err"
        return
    }

    if {$n == 0} {
        Status "No matches replaced"
        return
    }

    catch { $w edit separator }

    $w delete 1.0 end
    $w insert end $newtext

    catch { $w edit separator }

    catch {
        $w mark set insert 1.0
        $w see 1.0
    }

    ClearHighlights $w

    Status "Replaced $n matches"
}

proc ComputeReplacement {match} {
    variable replacement
    variable use_regexp
    variable ignore_case

    if {!$use_regexp} {
        return $replacement
    }

    set re [BuildRegexpPattern]

    set flags {}

    if {$ignore_case} {
        lappend flags -nocase
    }

    set n [regsub {*}$flags -- $re $match $replacement out]

    if {$n == 0} {
        return $replacement
    }

    return $out
}

# ----------------------------------------------------------------------------
# Events
# ----------------------------------------------------------------------------

proc OnBufferEvent {args} {
    variable visible

    if {$visible} {
        ScheduleHighlight
    }
}

proc OnTheme {args} {
    ConfigureColors

    set w [CurrentText]

    if {$w ne ""} {
        EnsureTags $w
    }
}

# ----------------------------------------------------------------------------
# Keybinding setup
# ----------------------------------------------------------------------------

proc BindKeys {} {
    variable bindtag
    variable bound_keys

    set bindtag "TclmeText"

    set pairs [list \
        [list search       <Control-/>] 
    ]

    foreach pair $pairs {
        lassign $pair cmd key

        if {[catch { ::Tclme::BindKey $cmd $key $bindtag }]} {
            catch { ::Tclme::BindKey $cmd $key }
        }

        if {[lsearch -exact $bound_keys $key] < 0} {
            lappend bound_keys $key
        }
    }
}

# ----------------------------------------------------------------------------
# Lifecycle
# ----------------------------------------------------------------------------

proc load {} {
    variable load_after

    BindKeys

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
    variable highlight_after
    variable bound_keys
    variable bindtag

    if {$load_after ne ""} {
        catch { after cancel $load_after }
        set load_after ""
    }

    if {$highlight_after ne ""} {
        catch { after cancel $highlight_after }
        set highlight_after ""
    }

    Hide

    foreach key $bound_keys {
        foreach tag [list $bindtag TclmeText] {
            catch { bind $tag $key {} }
        }
    }

    set bound_keys {}
}

proc save-state {} {
    variable visible
    variable ignore_case
    variable whole_word
    variable use_regexp
    variable wrap

    return [dict create \
        visible     $visible     \
        ignore_case $ignore_case \
        whole_word  $whole_word  \
        use_regexp  $use_regexp  \
        wrap        $wrap        \
    ]
}

proc restore-state {s} {
    variable visible
    variable ignore_case
    variable whole_word
    variable use_regexp
    variable wrap

    if {[catch { dict size $s }]} {
        return
    }

    if {[dict exists $s visible]} {
        set visible [dict get $s visible]
    }

    if {[dict exists $s ignore_case]} {
        set ignore_case [dict get $s ignore_case]
    }

    if {[dict exists $s whole_word]} {
        set whole_word [dict get $s whole_word]
    }

    if {[dict exists $s use_regexp]} {
        set use_regexp [dict get $s use_regexp]
    }

    if {[dict exists $s wrap]} {
        set wrap [dict get $s wrap]
    }
}

# ----------------------------------------------------------------------------
# Registration
# ----------------------------------------------------------------------------

Tclme::DefCommand find         cmd-find         "Open search/replace panel"
Tclme::DefCommand search       cmd-find         "Open search/replace panel"
Tclme::DefCommand find-replace cmd-find-replace "Open search/replace panel and focus replace"

if {[info commands ::Tclme::DefAlias] ne ""} {
    catch { ::Tclme::DefAlias f  find }
    catch { ::Tclme::DefAlias fr find-replace }
}

Tclme::On buffer-switched OnBufferEvent
Tclme::On after-file-read OnBufferEvent
Tclme::On theme-changed   OnTheme