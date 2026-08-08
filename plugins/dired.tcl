# plugins/dired.tcl
# ============================================================================
#  Dired: a directory browser for Tclme.
#
#  Keybindings (in a dired buffer):
#    n / p        next / previous line
#    Return       open file, or enter directory
#    u            up to parent directory
#    g            refresh listing
#    q            quit (kill this dired buffer)
#    .            toggle hidden files
#    s            cycle sort: name -> size -> mtime
#    d            toggle detailed listing
#    m / U        mark / unmark line
#    x            delete marked items
#    r            rename entry under cursor
#    +            create directory
#    y            copy full path to clipboard
#    h            show help
#
#  Open with C-x d, or :dired /some/path
# ============================================================================

# bufname -> dict(dir entries showhidden sort detail marked)
variable state [dict create]

# ----------------------------------------------------------------------------
#  Small helpers
# ----------------------------------------------------------------------------

proc DiredBuffers {} {
    set out {}
    foreach b [dict keys $::Tclme::buffers] {
        if {[string match "dired:*" $b]} { lappend out $b }
    }
    return $out
}

proc Widget {bufname} {
    if {![dict exists $::Tclme::buffers $bufname]} {
        error "no such buffer: $bufname"
    }
    return ".ws.[dict get [dict get $::Tclme::buffers $bufname] wid].txt"
}

proc SetReadonly {bufname val} {
    upvar #0 ::Tclme::buffers buffers
    if {[dict exists $buffers $bufname]} {
        dict set buffers $bufname readonly $val
    }
}

proc FirstLine {} { return 2 }            ;# line 1 is the header
proc LastLine {txt} {
    return [expr {[lindex [split [$txt index end] .] 0] - 1}]
}
proc EntryIndex {txt} {                    ;# 0-based index into entries, -1 = header
    set line [lindex [split [$txt index insert] .] 0]
    return [expr {$line - [FirstLine]}]
}

proc HumanSize {n} {
    if {$n < 1024} { return "${n}B" }
    set val [expr {double($n)}]
    foreach u {K M G T} {
        set val [expr {$val / 1024.0}]
        if {$val < 1024 || $u eq "T"} { return [format "%.1f%s" $val $u] }
    }
    return [format "%.1fT" $val]
}

proc FileSize {full} {
    if {[catch {file size $full} n]} { return 0 }
    return $n
}

proc FormatDate {full} {
    if {[catch {file mtime $full} mt]} { return "" }
    return [clock format $mt -format {%Y-%m-%d %H:%M}]
}

proc TypeChar {full} {
    if {[file isdirectory $full]} { return "d" }
    if {[catch {file type $full} t]} { return "-" }
    if {$t eq "link"} { return "l" }
    return "-"
}

# ----------------------------------------------------------------------------
#  Listing construction
# ----------------------------------------------------------------------------

proc SortNames {names dir mode} {
    if {[llength $names] == 0} { return {} }
    if {$mode eq "name"} { return [lsort -dictionary -nocase $names] }
    set keyed {}
    foreach e $names {
        set full [file join $dir $e]
        set k 0
        if {$mode eq "size"}  { if {[catch {file size  $full} k]} { set k 0 } }
        if {$mode eq "mtime"} { if {[catch {file mtime $full} k]} { set k 0 } }
        lappend keyed [list $k $e]
    }
    set keyed [lsort -integer -decreasing -index 0 $keyed]
    return [lmap p $keyed { lindex $p 1 }]
}

proc BuildEntries {bufname} {
    variable state
    set s        [dict get $state $bufname]
    set dir      [dict get $s dir]
    set hidden   [dict get $s showhidden]
    set sortmode [dict get $s sort]

    if {[catch {glob -nocomplain -directory $dir -tails *} cands]} { set cands {} }
    if {$hidden} {
        if {[catch {glob -nocomplain -directory $dir -tails .*} hs]} { set hs {} }
        foreach h $hs {
            if {$h ne "." && $h ne ".."} { lappend cands $h }
        }
    }

    set dirs {}; set files {}
    foreach e $cands {
        if {[file isdirectory [file join $dir $e]]} { lappend dirs $e } else { lappend files $e }
    }
    set dirs  [SortNames $dirs  $dir $sortmode]
    set files [SortNames $files $dir $sortmode]
    return [concat $dirs $files]
}

# ----------------------------------------------------------------------------
#  Rendering
# ----------------------------------------------------------------------------

proc EnsureTags {txt} {
    set accent [Tclme::GetTheme accent]
    $txt tag configure dired_current -background $accent
    $txt tag configure dired_header  -foreground $accent
    $txt tag raise dired_current
    $txt tag raise dired_header
}

proc InsertListing {bufname} {
    variable state
    set txt     [Widget $bufname]
    set s       [dict get $state $bufname]
    set dir     [dict get $s dir]
    set detail  [dict get $s detail]
    set marked  [dict get $s marked]

    set entries [BuildEntries $bufname]
    dict set state $bufname entries $entries

    EnsureTags $txt
    $txt configure -state normal
    $txt delete 1.0 end

    # header (line 1)
    $txt insert end "  $dir\n"
    $txt tag add dired_header 1.0 "1.0 lineend"

    if {[llength $entries] == 0} {
        $txt insert end "  (empty)\n"
    } else {
        foreach name $entries {
            set full  [file join $dir $name]
            set isdir [file isdirectory $full]
            set mark  [expr {[dict exists $marked $name] ? "*" : " "}]
            set slash [expr {$isdir ? "/" : ""}]
            if {$detail} {
                set line [format "%1s %1s %8s %16s  %s%s" \
                    $mark [TypeChar $full] \
                    [expr {$isdir ? "-" : [HumanSize [FileSize $full]]}] \
                    [FormatDate $full] $name $slash]
            } else {
                set line [format "%1s %s%s" $mark $name $slash]
            }
            $txt insert end "$line\n"
        }
    }

    $txt delete "end-1c" end
    $txt edit modified 0
    $txt configure -state disabled
}

proc Highlight {bufname} {
    if {[catch {Widget $bufname} txt]} return
    if {![winfo exists $txt]} return
    EnsureTags $txt
    $txt tag remove dired_current 1.0 end
    set line [lindex [split [$txt index insert] .] 0]
    $txt tag add dired_current "$line.0" "$line.0 lineend"
}

# ----------------------------------------------------------------------------
#  Bindings
# ----------------------------------------------------------------------------

proc SetupBindings {bufname} {
    set txt [Widget $bufname]
    set ns  [namespace current]

    foreach seq {<Return> q g u n p m U x r d s y h
                 <period> <plus> <KP_Add> <ButtonRelease-1> <KeyRelease>} {
        catch { bind $txt $seq {} }
    }

    bind $txt <Return>          [list ${ns}::Enter        $bufname]
    bind $txt q                 [list ${ns}::Quit         $bufname]
    bind $txt g                 [list ${ns}::Refresh      $bufname]
    bind $txt u                 [list ${ns}::Parent       $bufname]
    bind $txt n                 [list ${ns}::NextLine     $bufname]
    bind $txt p                 [list ${ns}::PrevLine     $bufname]
    bind $txt m                 [list ${ns}::Mark         $bufname]
    bind $txt U                 [list ${ns}::Unmark       $bufname]
    bind $txt x                 [list ${ns}::DeleteMarked $bufname]
    bind $txt r                 [list ${ns}::Rename       $bufname]
    bind $txt d                 [list ${ns}::ToggleDetail $bufname]
    bind $txt s                 [list ${ns}::CycleSort    $bufname]
    bind $txt y                 [list ${ns}::CopyPath     $bufname]
    bind $txt h                 [list ${ns}::ShowHelp     $bufname]
    bind $txt <period>          [list ${ns}::ToggleHidden $bufname]
    bind $txt <plus>            [list ${ns}::Mkdir        $bufname]
    bind $txt <KP_Add>          [list ${ns}::Mkdir        $bufname]
    bind $txt <ButtonRelease-1> [list ${ns}::Click        $bufname %x %y]
    bind $txt <KeyRelease>      [list ${ns}::OnKey        $bufname]
}

proc OnKey {bufname} {
    Highlight $bufname
    return -code break
}
proc Click {bufname x y} {
    set txt [Widget $bufname]
    $txt mark set insert [$txt index @$x,$y]
    Highlight $bufname
    return -code break
}

# ----------------------------------------------------------------------------
#  Entry point
# ----------------------------------------------------------------------------

proc dired {{dir ""}} {
    variable state

    if {$dir eq ""} { set dir [pwd] }
    if {[file isfile $dir]} { set dir [file dirname $dir] }
    if {![file isdirectory $dir]} { Tclme::Message "Not a directory: $dir"; return }
    set dir [file normalize $dir]
    set bufname "dired:$dir"

    if {[dict exists $::Tclme::buffers $bufname]} {
        Tclme::SwitchToBuffer $bufname
        Refresh $bufname
        return
    }

    Tclme::SwitchToBuffer $bufname
    SetReadonly $bufname 1
    dict set state $bufname [dict create \
        dir $dir entries {} showhidden 0 sort name detail 1 marked [dict create]]

    InsertListing $bufname
    SetupBindings $bufname

    set txt [Widget $bufname]
    $txt mark set insert "[FirstLine].0"
    $txt see insert
    Highlight $bufname
}

proc Refresh {bufname} {
    variable state
    set txt     [Widget $bufname]
    set entries [dict get [dict get $state $bufname] entries]

    set idx [EntryIndex $txt]
    set selname ""
    if {$idx >= 0 && $idx < [llength $entries]} { set selname [lindex $entries $idx] }

    InsertListing $bufname

    set newentries [dict get [dict get $state $bufname] entries]
    set pos [lsearch -exact $newentries $selname]
    if {$pos >= 0} {
        $txt mark set insert "[expr {$pos + [FirstLine]}].0"
    } else {
        $txt mark set insert "[FirstLine].0"
    }
    $txt see insert
    Highlight $bufname
}

# ----------------------------------------------------------------------------
#  Navigation / actions
# ----------------------------------------------------------------------------

proc NextLine {bufname} {
    set txt  [Widget $bufname]
    set cur  [lindex [split [$txt index insert] .] 0]
    set last [LastLine $txt]
    set min  [FirstLine]
    if {$cur < $min}  { set cur $min }
    if {$cur < $last} { incr cur }
    $txt mark set insert "$cur.0"
    $txt see insert
    Highlight $bufname
    return -code break
}

proc PrevLine {bufname} {
    set txt [Widget $bufname]
    set cur [lindex [split [$txt index insert] .] 0]
    set min [FirstLine]
    if {$cur > $min} { incr cur -1 }
    if {$cur < $min} { set cur $min }
    $txt mark set insert "$cur.0"
    $txt see insert
    Highlight $bufname
    return -code break
}

proc Enter {bufname} {
    variable state
    set txt     [Widget $bufname]
    set s       [dict get $state $bufname]
    set entries [dict get $s entries]
    set idx     [EntryIndex $txt]
    if {$idx < 0 || $idx >= [llength $entries]} { return -code break }

    set name [lindex $entries $idx]
    set full [file join [dict get $s dir] $name]

    if {[file isdirectory $full]} {
        after idle [list [namespace current]::dired $full]
    } elseif {[file exists $full]} {
        Tclme::OpenFile $full
    }
    return -code break
}

proc Parent {bufname} {
    variable state
    set dir    [dict get [dict get $state $bufname] dir]
    set parent [file dirname $dir]
    if {$parent ne $dir} {
        after idle [list [namespace current]::dired $parent]
    }
    return -code break
}

proc Quit {bufname} {
    Tclme::KillBuffer $bufname
    return -code break
}

# ----------------------------------------------------------------------------
#  View toggles
# ----------------------------------------------------------------------------

proc ToggleHidden {bufname} {
    variable state
    set v [dict get [dict get $state $bufname] showhidden]
    dict set state $bufname showhidden [expr {!$v}]
    Refresh $bufname
    return -code break
}

proc CycleSort {bufname} {
    variable state
    set order {name size mtime}
    set cur   [dict get [dict get $state $bufname] sort]
    set i     [lsearch -exact $order $cur]
    dict set state $bufname sort [lindex $order [expr {($i + 1) % [llength $order]}]]
    Refresh $bufname
    return -code break
}

proc ToggleDetail {bufname} {
    variable state
    set v [dict get [dict get $state $bufname] detail]
    dict set state $bufname detail [expr {!$v}]
    Refresh $bufname
    return -code break
}

# ----------------------------------------------------------------------------
#  Marking / file operations
# ----------------------------------------------------------------------------

proc Mark {bufname} {
    variable state
    set txt     [Widget $bufname]
    set entries [dict get [dict get $state $bufname] entries]
    set idx     [EntryIndex $txt]
    if {$idx < 0 || $idx >= [llength $entries]} { return -code break }

    dict set state $bufname marked [lindex $entries $idx] 1
    InsertListing $bufname

    set last [LastLine $txt]
    set line [expr {[FirstLine] + $idx + 1}]
    if {$line > $last} { set line $last }
    $txt mark set insert "$line.0"
    $txt see insert
    Highlight $bufname
    return -code break
}

proc Unmark {bufname} {
    variable state
    set txt     [Widget $bufname]
    set entries [dict get [dict get $state $bufname] entries]
    set idx     [EntryIndex $txt]
    if {$idx < 0 || $idx >= [llength $entries]} { return -code break }

    dict unset state $bufname marked [lindex $entries $idx]
    InsertListing $bufname
    $txt mark set insert "[expr {[FirstLine] + $idx}].0"
    $txt see insert
    Highlight $bufname
    return -code break
}

proc DeleteMarked {bufname} {
    variable state
    set s      [dict get $state $bufname]
    set marked [dict get $s marked]
    set names  [dict keys $marked]
    if {[llength $names] == 0} { Tclme::Message "No marked items"; return -code break }

    set dir [dict get $s dir]
    set ans [tk_messageBox -type yesno -icon warning -title "Dired delete" \
        -message "Delete [llength $names] item(s)?\n\n[join $names \n]"]
    if {$ans ne "yes"} { return -code break }

    foreach name $names {
        if {[catch {file delete -force [file join $dir $name]} err]} {
            Tclme::Message "delete failed: $err"
        }
    }
    dict set state $bufname marked [dict create]
    Refresh $bufname
    return -code break
}

proc Rename {bufname} {
    variable state
    set txt     [Widget $bufname]
    set entries [dict get [dict get $state $bufname] entries]
    set idx     [EntryIndex $txt]
    if {$idx < 0 || $idx >= [llength $entries]} { return -code break }

    set name [lindex $entries $idx]
    Tclme::Prompt "rename $name -> " [list [namespace current]::DoRename $bufname $name]
    return -code break
}

proc DoRename {bufname oldname newname} {
    variable state
    set newname [string trim $newname]
    if {$newname eq "" || $newname eq $oldname} { return }
    set dir [dict get [dict get $state $bufname] dir]
    if {[catch {file rename [file join $dir $oldname] [file join $dir $newname]} err]} {
        Tclme::Message "rename failed: $err"
    } else {
        Refresh $bufname
    }
}

proc Mkdir {bufname} {
    Tclme::Prompt "mkdir: " [list [namespace current]::DoMkdir $bufname]
    return -code break
}

proc DoMkdir {bufname name} {
    variable state
    set name [string trim $name]
    if {$name eq ""} { return }
    set dir [dict get [dict get $state $bufname] dir]
    if {[catch {file mkdir [file join $dir $name]} err]} {
        Tclme::Message "mkdir failed: $err"
    } else {
        Refresh $bufname
    }
}

proc CopyPath {bufname} {
    variable state
    set txt     [Widget $bufname]
    set entries [dict get [dict get $state $bufname] entries]
    set idx     [EntryIndex $txt]
    if {$idx < 0 || $idx >= [llength $entries]} { return -code break }

    set dir  [dict get [dict get $state $bufname] dir]
    set full [file join $dir [lindex $entries $idx]]
    if {[catch { clipboard clear; clipboard append $full } err]} {
        Tclme::Message "clipboard failed: $err"
    } else {
        Tclme::Message "Copied: $full"
    }
    return -code break
}

proc ShowHelp {bufname} {
    set lines {
        "Dired keybindings" ""
        "n / p        next / previous line"
        "Return       open file, or enter directory"
        "u            up to parent directory"
        "g            refresh listing"
        "q            quit (kill this dired buffer)"
        ".            toggle hidden files"
        "s            cycle sort: name -> size -> mtime"
        "d            toggle detailed listing"
        "m / U        mark / unmark line"
        "x            delete marked items"
        "r            rename entry under cursor"
        "+            create directory"
        "y            copy full path to clipboard"
        "h            show this help"
    }
    Tclme::ShowInBuffer "*Dired Help*" [join $lines \n] 1
    return -code break
}

# ----------------------------------------------------------------------------
#  Hooks / status
# ----------------------------------------------------------------------------

proc OnStatus {name} {
    variable state
    if {![dict exists $state $name]} { return "" }
    set s [dict get $state $name]
    set out "[file tail [dict get $s dir]]/  [llength [dict get $s entries]] items"
    set m [llength [dict keys [dict get $s marked]]]
    if {$m > 0} { append out "  $m marked" }
    return $out
}

proc OnBufferKilled {name} {
    variable state
    if {[dict exists $state $name]} { dict unset state $name }
}

# ----------------------------------------------------------------------------
#  Lifecycle
# ----------------------------------------------------------------------------

proc load {} {
    foreach b [DiredBuffers] {
        catch { SetupBindings $b }
        catch { Highlight $b }
    }
}

proc unload {} {
    foreach b [DiredBuffers] {
        if {[catch {Widget $b} txt]} continue
        foreach seq {<Return> q g u n p m U x r d s y h
                     <period> <plus> <KP_Add> <ButtonRelease-1> <KeyRelease>} {
            catch { bind $txt $seq {} }
        }
    }
}

proc save-state {}  { variable state; return $state }
proc restore-state {s} { variable state; set state $s }

# ----------------------------------------------------------------------------
#  Registration
# ----------------------------------------------------------------------------

Tclme::On buffer-killed OnBufferKilled
Tclme::On status-line   OnStatus

Tclme::DefCommandAndBind dired dired <Control-x>d "Open a directory browser (arg = dir)"