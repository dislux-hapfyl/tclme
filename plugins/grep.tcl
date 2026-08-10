# plugins/grep.tcl
# ============================================================================
#  project-grep.tcl - recursive grep for Tclme
#
#  Commands:
#    :project-grep PATTERN
#    :project-grep @dir PATTERN
#    :project-grep-dir DIR
#    :project-grep-case
#
#  Default keybindings:
#    C-x g       grep from current file directory or pwd
#    C-x G       choose directory first, then pattern
#
#  Result buffer keys:
#    Return      open match
#    n           next match
#    p           previous match
#    r           rerun grep
#    q           kill grep buffer
#
#  Notes:
#    - Pattern is a Tcl regular expression.
#    - Search is case-insensitive by default.
#    - Skips common VCS/cache directories.
#    - Skips files larger than max_file_size.
#    - Stops after max_matches.
# ============================================================================

# ----------------------------------------------------------------------------
# State
# ----------------------------------------------------------------------------

variable state        [dict create]
variable pending_dir  ""

variable skip_dirs [dict create \
    .git 1 \
    .svn 1 \
    .hg 1 \
    .bzr 1 \
    .fossil 1 \
    node_modules 1 \
    __pycache__ 1 \
    .cache 1 \
    .venv 1 \
    venv 1 \
]

variable max_file_size 1048576   ;# 1 MB
variable max_matches   2000
variable match_count   0
variable case_sensitive 0

variable bindtag    ""
variable bound_keys {}

# ----------------------------------------------------------------------------
# Small helpers
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

proc PromptMaybe {label cb {completer ""}} {
    if {$completer eq ""} {
        catch { ::Tclme::Prompt $label $cb }
        return
    }

    if {[catch { ::Tclme::Prompt $label $cb $completer }]} {
        catch { ::Tclme::Prompt $label $cb }
    }
}

proc GuessBindTag {} {
    set w $::Tclme::active_widget

    if {$w ne "" && [winfo exists $w]} {
        set tags [bindtags $w]

        if {[lsearch -exact $tags TclmeText] >= 0} {
            return "TclmeText"
        }

        if {[lsearch -exact $tags CoreText] >= 0} {
            return "CoreText"
        }
    }

    return "TclmeText"
}

proc DefaultDir {} {
    set name $::Tclme::current_buffer

    if {$name ne "" && [dict exists $::Tclme::buffers $name]} {
        set path [dict get [dict get $::Tclme::buffers $name] path]

        if {$path ne "" && [file exists $path]} {
            return [file dirname $path]
        }
    }

    return [pwd]
}

proc WidgetForBuffer {bufname} {
    if {![dict exists $::Tclme::buffers $bufname]} {
        return ""
    }

    set info [dict get $::Tclme::buffers $bufname]
    set txt  ".ws.[dict get $info wid].txt"

    if {[winfo exists $txt]} {
        return $txt
    }

    return ""
}

proc SetReadonly {bufname val} {
    upvar #0 ::Tclme::buffers buffers

    if {[dict exists $buffers $bufname]} {
        dict set buffers $bufname readonly $val
    }
}

proc BufferName {dir pattern} {
    set tail [file tail $dir]

    if {$tail eq ""} {
        set tail $dir
    }

    set p $pattern

    if {[string length $p] > 40} {
        set p "[string range $p 0 36]..."
    }

    return "grep:$tail:$p"
}

proc RelativePath {base full} {
    if {[catch {
        set base [file normalize $base]
        set full [file normalize $full]

        set b [file split $base]
        set f [file split $full]

        while {[llength $b] && [llength $f] && [lindex $b 0] eq [lindex $f 0]} {
            set b [lrange $b 1 end]
            set f [lrange $f 1 end]
        }

        if {[llength $f] == 0} {
            return [file tail $full]
        }

        return [file join {*}$f]
    } rel]} {
        return $full
    }

    return $rel
}

# ----------------------------------------------------------------------------
# Commands
# ----------------------------------------------------------------------------

proc cmd-grep {args} {
    set arg [string trim [join $args " "]]

    if {$arg ne ""} {
        HandleGrepInput $arg
        return
    }

    set ns [namespace current]

    PromptMaybe "Grep (@dir pattern): " ${ns}::HandleGrepInput
}

proc cmd-grep-dir {args} {
    set arg [string trim [join $args " "]]

    if {$arg ne ""} {
        HandleDirInput $arg
        return
    }

    set ns [namespace current]

    set completer ""
    if {[info commands ::Tclme::CompleteFile] ne ""} {
        set completer ::Tclme::CompleteFile
    }

    PromptMaybe "Directory: " ${ns}::HandleDirInput $completer
}

proc cmd-case {args} {
    variable case_sensitive

    set case_sensitive [expr {!$case_sensitive}]

    if {$case_sensitive} {
        ::Tclme::Message "Project grep: case-sensitive"
    } else {
        ::Tclme::Message "Project grep: case-insensitive"
    }
}

# ----------------------------------------------------------------------------
# Prompt handlers
# ----------------------------------------------------------------------------

proc HandleGrepInput {input} {
    set input [string trim $input]

    if {$input eq ""} {
        return
    }

    set dir [DefaultDir]
    set pattern $input

    if {[string index $input 0] eq "@"} {
        set sp [string first " " $input]

        if {$sp == -1} {
            ::Tclme::Message "Usage: @dir pattern"
            return
        }

        set dir     [string trim [string range $input 1 [expr {$sp - 1}]]]
        set pattern [string trim [string range $input [expr {$sp + 1}] end]]

        if {$pattern eq ""} {
            ::Tclme::Message "No pattern supplied"
            return
        }
    }

    if {$dir eq ""} {
        set dir [pwd]
    }

    set dir [file normalize $dir]

    if {![file isdirectory $dir]} {
        ::Tclme::Message "Not a directory: $dir"
        return
    }

    RunGrep $dir $pattern
}

proc HandleDirInput {dir} {
    variable pending_dir

    set dir [string trim $dir]

    if {$dir eq ""} {
        return
    }

    set dir [file normalize $dir]

    if {![file isdirectory $dir]} {
        ::Tclme::Message "Not a directory: $dir"
        return
    }

    set pending_dir $dir

    set ns [namespace current]

    PromptMaybe "Pattern in $dir: " ${ns}::HandlePatternInput
}

proc HandlePatternInput {pattern} {
    variable pending_dir

    set pattern [string trim $pattern]

    if {$pattern eq ""} {
        ::Tclme::Message "Grep cancelled"
        return
    }

    if {$pending_dir eq ""} {
        ::Tclme::Message "No directory selected"
        return
    }

    set dir $pending_dir
    set pending_dir ""

    RunGrep $dir $pattern
}

# ----------------------------------------------------------------------------
# Grep engine
# ----------------------------------------------------------------------------

proc RunGrep {dir pattern} {
    variable match_count
    variable max_matches

    set dir     [file normalize $dir]
    set pattern [string trim $pattern]

    if {$pattern eq ""} {
        ::Tclme::Message "No pattern"
        return
    }

    if {[catch { regexp -- $pattern "" } err]} {
        ::Tclme::Message "Invalid pattern: $err"
        return
    }

    ::Tclme::Message "Searching for '$pattern' in $dir ..."

    set match_count 0

    if {[catch { set results [RecursiveGrep $dir $pattern] } err]} {
        ::Tclme::Log error "project-grep: $err"
        ::Tclme::Message "Grep failed: $err"
        return
    }

    set truncated [expr {$match_count >= $max_matches}]

    ShowResults $dir $pattern $results $truncated
}

proc RecursiveGrep {dir pattern} {
    variable skip_dirs
    variable max_file_size
    variable case_sensitive
    variable match_count
    variable max_matches

    set results {}

    if {$match_count >= $max_matches} {
        return $results
    }

    # Files in this directory.
    if {[catch { glob -nocomplain -directory $dir -types f * } files]} {
        set files {}
    }

    foreach full $files {
        if {$match_count >= $max_matches} {
            break
        }

        if {[catch { file size $full } size]} {
            continue
        }

        if {$size > $max_file_size} {
            continue
        }

        if {[catch { open $full r } fp]} {
            continue
        }

        catch {
            fconfigure $fp -encoding utf-8 -translation auto
        }

        set rel [RelativePath $dir $full]

        set ln 0
        set file_results {}

        while {1} {
            if {[catch { gets $fp line } n]} {
                break
            }

            if {$n < 0} {
                break
            }

            incr ln

            if {$case_sensitive} {
                set ok [regexp -- $pattern $line]
            } else {
                set ok [regexp -nocase -- $pattern $line]
            }

            if {$ok} {
                lappend file_results [list $rel $ln $line $full]

                incr match_count

                if {$match_count >= $max_matches} {
                    break
                }
            }
        }

        close $fp

        if {$match_count <= $max_matches} {
            lappend results {*}$file_results
        }
    }

    if {$match_count >= $max_matches} {
        return $results
    }

    # Subdirectories.
    if {[catch { glob -nocomplain -directory $dir -types d * } dirs]} {
        set dirs {}
    }

    foreach d $dirs {
        if {$match_count >= $max_matches} {
            break
        }

        set name [file tail $d]

        if {[dict exists $skip_dirs $name]} {
            continue
        }

        if {[catch { file type $d } type]} {
            continue
        }

        # Avoid symlinked directory loops.
        if {$type eq "link"} {
            continue
        }

        set sub [RecursiveGrep $d $pattern]

        if {[llength $sub] > 0} {
            lappend results {*}$sub
        }
    }

    return $results
}

# ----------------------------------------------------------------------------
# Results buffer
# ----------------------------------------------------------------------------

proc ShowResults {dir pattern results {truncated 0}} {
    variable state
    variable max_matches

    set bufname [BufferName $dir $pattern]

    if {[catch { ::Tclme::SwitchToBuffer $bufname } err]} {
        ::Tclme::Message "Cannot open grep buffer: $err"
        return
    }

    set txt [WidgetForBuffer $bufname]

    if {$txt eq ""} {
        set txt $::Tclme::active_widget
    }

    if {$txt eq "" || ![winfo exists $txt]} {
        return
    }

    SetupBindings $txt $bufname
    EnsureTags $txt

    $txt configure -state normal
    $txt delete 1.0 end

    set count [llength $results]

    set header "Results for '$pattern' in $dir"

    if {$count == 0} {
        append header ": no matches"
    } else {
        append header " ($count match"

        if {$count != 1} {
            append header "es"
        }

        if {$truncated} {
            append header ", truncated at $max_matches"
        }

        append header ")"
    }

    $txt insert end "$header\n" grep_header

    foreach r $results {
        lassign $r rel ln line full

        $txt insert end "$rel:$ln: $line\n" grep_match
    }

    $txt edit modified 0
    $txt configure -state disabled

    SetReadonly $bufname 1

    dict set state $bufname [dict create \
        dir $dir \
        pattern $pattern \
        matches $results \
    ]

    if {$count > 0} {
        catch {
            $txt mark set insert 2.0
            $txt see insert
        }
    }

    HighlightCurrent $txt
}

proc SetupBindings {txt bufname} {
    set ns [namespace current]

    bind $txt <Return>          [list ${ns}::OpenMatch $bufname]
    bind $txt n                 [list ${ns}::NextMatch $bufname]
    bind $txt p                 [list ${ns}::PrevMatch $bufname]
    bind $txt q                 [list ${ns}::QuitBuffer $bufname]
    bind $txt r                 [list ${ns}::Rerun $bufname]
    bind $txt <ButtonRelease-1> [list ${ns}::OnClick $bufname %x %y]
}

proc EnsureTags {txt} {
    if {![winfo exists $txt]} {
        return
    }

    set accent [Theme accent "#4A7CFE"]
    set fg     [Theme fg "#222222"]
    set bg     [Theme editor_bg "#FFFFFF"]

    $txt tag configure grep_header  -foreground $accent
    $txt tag configure grep_current -background $accent -foreground $bg

    $txt tag raise grep_current
}

proc HighlightCurrent {txt} {
    if {![winfo exists $txt]} {
        return
    }

    EnsureTags $txt

    $txt tag remove grep_current 1.0 end

    set line [lindex [split [$txt index insert] .] 0]

    if {[string is integer -strict $line] && $line >= 2} {
        $txt tag add grep_current "$line.0" "$line.0 lineend"
        $txt tag raise grep_current
    }
}

# ----------------------------------------------------------------------------
# Result navigation
# ----------------------------------------------------------------------------

proc OpenMatch {bufname} {
    variable state

    set txt [WidgetForBuffer $bufname]

    if {$txt eq ""} {
        return -code break
    }

    if {![dict exists $state $bufname]} {
        return -code break
    }

    set line [lindex [split [$txt index insert] .] 0]
    set idx  [expr {$line - 2}]

    set matches [dict get $state $bufname matches]

    if {$idx < 0 || $idx >= [llength $matches]} {
        return -code break
    }

    lassign [lindex $matches $idx] rel ln line_text full

    if {![file exists $full]} {
        ::Tclme::Message "File not found: $full"
        return -code break
    }

    ::Tclme::OpenFile $full

    set ns [namespace current]
    after idle [list ${ns}::JumpToLine $full $ln]

    return -code break
}

proc JumpToLine {file lnum} {
    set w $::Tclme::active_widget

    if {$w eq "" || ![winfo exists $w]} {
        return
    }

    catch {
        $w mark set insert "$lnum.0"
        $w see insert
    }

    catch { focus $w }
    catch { ::Tclme::RefreshStatus }
}

proc NextMatch {bufname} {
    set txt [WidgetForBuffer $bufname]

    if {$txt eq ""} {
        return -code break
    }

    set cur  [lindex [split [$txt index insert] .] 0]
    set last [expr {[lindex [split [$txt index end] .] 0] - 1}]

    if {$cur < $last} {
        incr cur
        $txt mark set insert "$cur.0"
        $txt see insert
        HighlightCurrent $txt
    }

    return -code break
}

proc PrevMatch {bufname} {
    set txt [WidgetForBuffer $bufname]

    if {$txt eq ""} {
        return -code break
    }

    set cur  [lindex [split [$txt index insert] .] 0]
    set last [expr {[lindex [split [$txt index end] .] 0] - 1}]

    if {$cur > 2} {
        incr cur -1
        $txt mark set insert "$cur.0"
        $txt see insert
        HighlightCurrent $txt
    } elseif {$cur == 1 && $last >= 2} {
        $txt mark set insert 2.0
        $txt see insert
        HighlightCurrent $txt
    }

    return -code break
}

proc QuitBuffer {bufname} {
    catch { ::Tclme::KillBuffer $bufname }
    return -code break
}

proc Rerun {bufname} {
    variable state

    if {![dict exists $state $bufname]} {
        return -code break
    }

    set dir     [dict get $state $bufname dir]
    set pattern [dict get $state $bufname pattern]

    RunGrep $dir $pattern

    return -code break
}

proc OnClick {bufname x y} {
    set txt [WidgetForBuffer $bufname]

    if {$txt eq ""} {
        return
    }

    catch {
        $txt mark set insert [$txt index @$x,$y]
    }

    HighlightCurrent $txt
}

# ----------------------------------------------------------------------------
# Events / lifecycle
# ----------------------------------------------------------------------------

proc OnBufferKilled {args} {
    variable state

    set name [lindex $args 0]

    if {$name ne "" && [dict exists $state $name]} {
        dict unset state $name
    }
}

proc OnTheme {args} {
    variable state

    foreach bufname [dict keys $state] {
        set txt [WidgetForBuffer $bufname]

        if {$txt ne ""} {
            EnsureTags $txt
        }
    }
}

proc BindKeys {} {
    variable bindtag
    variable bound_keys

    set bindtag [GuessBindTag]

    set pairs [list \
        [list project-grep     <Control-x>g] \
        [list project-grep-dir <Control-x>G] \
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

proc load {} {
    BindKeys
}

proc unload {} {
    variable state
    variable bindtag
    variable bound_keys

    foreach key $bound_keys {
        foreach tag [list $bindtag TclmeText CoreText] {
            catch { bind $tag $key {} }
        }
    }

    foreach bufname [dict keys $state] {
        set txt [WidgetForBuffer $bufname]

        if {$txt ne ""} {
            foreach seq {<Return> n p q r <ButtonRelease-1>} {
                catch { bind $txt $seq {} }
            }
        }
    }

    set state      [dict create]
    set bound_keys {}
}

# ----------------------------------------------------------------------------
# Registration
# ----------------------------------------------------------------------------

Tclme::DefCommand project-grep      cmd-grep      "Recursive grep (@dir pattern)"
Tclme::DefCommand project-grep-dir  cmd-grep-dir  "Recursive grep in a chosen directory"
Tclme::DefCommand project-grep-case cmd-case      "Toggle case sensitivity for project grep"

if {[info commands ::Tclme::DefAlias] ne ""} {
    catch { ::Tclme::DefAlias pg  project-grep }
    catch { ::Tclme::DefAlias pgd project-grep-dir }
    catch { ::Tclme::DefAlias pgc project-grep-case }
}

Tclme::On buffer-killed OnBufferKilled
Tclme::On theme-changed OnTheme
