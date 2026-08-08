# plugins/tclhighlight.tcl
# ============================================================================
#  Tcl syntax highlighter plugin for Tclme.
#  v2: hardened variable handling (self-initializing, one-per-line).
# ============================================================================

variable enabled        1
variable max_size       300000
variable pending        [dict create]
variable forced         [dict create]
variable seen           [dict create]
variable extra_exts     {}
variable extra_keywords [dict create]

variable tags {comment string keyword variable number brace subst procname}

variable specials " \t\r\n;{}\"\$\[\\]"
append specials ]

variable palette_dark [dict create \
    comment  [list #6A9955 1]  string   [list #CE9178 0] \
    keyword  [list #569CD6 0]  variable [list #9CDCFE 0] \
    number   [list #B5CEA8 0]  brace    [list #D7BA7D 0] \
    subst    [list #C586C0 0]  procname [list #DCDCAA 0] \
]
variable palette_light [dict create \
    comment  [list #008000 1]  string   [list #A31515 0] \
    keyword  [list #0000FF 0]  variable [list #001080 0] \
    number   [list #098658 0]  brace    [list #800000 0] \
    subst    [list #AF00DB 0]  procname [list #795E26 0] \
]

variable keywords [dict create]
foreach k {
    after append apply array break case catch cd chan class clock close
    concat continue coroutine destroy dict else elseif encoding eof error
    eval exec exit expr fblocked fconfigure fcopy file fileevent flush for
    foreach format gets glob global history if incr info interp join lappend
    lassign lindex linsert list llength lmap lrange lrepeat lreplace lreverse
    lsearch lset lsort my namespace oo::class oo::define open package pid proc
    puts pwd read regexp regsub rename return scan seek self set socket
    source split string subst switch tell throw time trace try unset uplevel
    upvar variable vwait while yield
    bind bindtags button canvas checkbutton clipboard entry event frame grid
    label listbox menu menubutton message pack panedwindow place radiobutton
    scale scrollbar spinbox text toplevel wm winfo focus grab raise lower
    ttk::button ttk::frame ttk::label ttk::entry ttk::treeview tk_messageBox
} { dict set keywords $k 1 }

# ----------------------------------------------------------------------------
#  Helpers
# ----------------------------------------------------------------------------

proc is-dark {} {
    set bg [Tclme::GetTheme editor_bg]
    if {[catch {scan $bg "#%2x%2x%2x" r g b}]} { return 0 }
    return [expr {(0.2126*$r + 0.7152*$g + 0.0722*$b) < 128}]
}

proc colors {} {
    variable palette_dark
    variable palette_light
    if {[is-dark]} { return $palette_dark }
    return $palette_light
}

proc widget-for-buffer {name} {
    if {![dict exists $::Tclme::buffers $name]} { return "" }
    return ".ws.[dict get [dict get $::Tclme::buffers $name] wid].txt"
}

proc buffer-for-widget {w} {
    dict for {name info} $::Tclme::buffers {
        if {".ws.[dict get $info wid].txt" eq $w} { return $name }
    }
    return ""
}

proc should-highlight {name w} {
    variable forced
    variable extra_exts
    if {![info exists forced]}     { set forced [dict create] }
    if {![info exists extra_exts]} { set extra_exts {} }

    if {[dict exists $forced $name]} { return [dict get $forced $name] }

    set path [dict get [dict get $::Tclme::buffers $name] path]
    set tail [string tolower [file tail $path]]
    if {$tail eq ""} { set tail [string tolower $name] }

    foreach ext [concat {.tcl .tk .expect} $extra_exts] {
        if {[string match "*$ext" $tail]} { return 1 }
    }
    if {$tail eq ".corerc"} { return 1 }

    if {$w ne "" && [winfo exists $w]} {
        set first [$w get 1.0 "1.end"]
        if {[regexp {^#!.*(tclsh|wish)} $first]} { return 1 }
    }
    return 0
}

proc is-number {w} {
    if {[string is integer -strict $w]} { return 1 }
    if {[string is double  -strict $w]} { return 1 }
    if {[regexp {^0x[0-9a-fA-F]+$} $w]} { return 1 }
    if {[regexp {^0b[01]+$}        $w]} { return 1 }
    if {[regexp {^0o[0-7]+$}       $w]} { return 1 }
    return 0
}

# ----------------------------------------------------------------------------
#  Tokenizer: single pass, returns list of {tag start end} char ranges.
# ----------------------------------------------------------------------------
proc tokenize {text} {
    variable specials
    variable keywords
    variable extra_keywords
    if {![info exists extra_keywords]} { set extra_keywords [dict create] }

    set ranges {}
    set n [string length $text]
    set i 0
    set cmdstart 1
    set expect_procname 0

    while {$i < $n} {
        set ch [string index $text $i]

        if {$ch eq "\\"} {
            set cmdstart 0; set expect_procname 0
            incr i 2
            continue
        }
        if {$ch eq "\n" || $ch eq ";"} {
            set cmdstart 1; set expect_procname 0
            incr i
            continue
        }
        if {$ch eq " " || $ch eq "\t" || $ch eq "\r"} { incr i; continue }

        if {$ch eq "#" && $cmdstart} {
            set j [string first "\n" $text $i]
            if {$j < 0} { set j $n }
            lappend ranges [list comment $i $j]
            set i $j
            continue
        }
        if {$ch eq "\""} {
            set j [expr {$i + 1}]
            while {$j < $n} {
                set c2 [string index $text $j]
                if {$c2 eq "\\"} { incr j 2; continue }
                incr j
                if {$c2 eq "\""} break
            }
            lappend ranges [list string $i $j]
            set i $j
            set cmdstart 0; set expect_procname 0
            continue
        }
        if {$ch eq "\$"} {
            set j [expr {$i + 1}]
            if {$j < $n && [string index $text $j] eq "\{"} {
                set close [string first "\}" $text $j]
                set j [expr {$close < 0 ? $n : $close + 1}]
            } else {
                while {$j < $n} {
                    set c2 [string index $text $j]
                    if {[string is alnum $c2] || $c2 eq "_" || $c2 eq ":"} {
                        incr j; continue
                    }
                    break
                }
                if {$j < $n && [string index $text $j] eq "("} {
                    set close [string first ")" $text $j]
                    set j [expr {$close < 0 ? $n : $close + 1}]
                }
            }
            if {$j > $i + 1} { lappend ranges [list variable $i $j] }
            set i $j
            set cmdstart 0; set expect_procname 0
            continue
        }
        if {$ch eq "\[" || $ch eq "\]"} {
            lappend ranges [list subst $i [expr {$i + 1}]]
            set cmdstart [expr {$ch eq "\["}]
            incr i
            continue
        }
        if {$ch eq "\{" || $ch eq "\}"} {
            lappend ranges [list brace $i [expr {$i + 1}]]
            set cmdstart [expr {$ch eq "\{"}]
            incr i
            continue
        }

        set j $i
        while {$j < $n && [string first [string index $text $j] $specials] < 0} {
            incr j
        }
        set word [string range $text $i [expr {$j - 1}]]

        if {$expect_procname} {
            lappend ranges [list procname $i $j]
            set expect_procname 0
        } elseif {$cmdstart && ([dict exists $keywords $word]
                             || [dict exists $extra_keywords $word])} {
            lappend ranges [list keyword $i $j]
            if {$word eq "proc"} { set expect_procname 1 }
        } elseif {[is-number $word]} {
            lappend ranges [list number $i $j]
        }
        set i $j
        set cmdstart 0
    }
    return $ranges
}

# ----------------------------------------------------------------------------
#  Applying highlights
# ----------------------------------------------------------------------------

proc ensure-tags {w} {
    variable tags
    lassign [Tclme::GetTheme font] fam size
    set pal [colors]
    foreach t $tags {
        lassign [dict get $pal $t] fg italic
        if {$italic} {
            $w tag configure hl_$t -foreground $fg -font [list $fam $size italic]
        } else {
            $w tag configure hl_$t -foreground $fg
        }
    }
}

proc clear-widget {w} {
    variable tags
    if {![winfo exists $w]} return
    foreach t $tags { $w tag remove hl_$t 1.0 end }
}

proc highlight-widget {w} {
    variable enabled
    variable max_size
    variable tags
    variable seen
    variable pending

    if {!$enabled || ![winfo exists $w]} return
    set text [$w get 1.0 end-1c]
    if {[string length $text] > $max_size} return

    ensure-tags $w
    foreach t $tags { $w tag remove hl_$t 1.0 end }
    foreach r [tokenize $text] {
        lassign $r tag s e
        $w tag add hl_$tag "1.0 + $s chars" "1.0 + $e chars"
    }
    dict set seen $w [string length $text]
    if {[dict exists $pending $w]} { dict unset pending $w }
}

proc highlight-current {} {
    set name $::Tclme::current_buffer
    if {$name eq ""} return
    set w [widget-for-buffer $name]
    if {$w eq "" || ![winfo exists $w]} return
    if {[should-highlight $name $w]} {
        highlight-widget $w
    } else {
        clear-widget $w
    }
}

# ----------------------------------------------------------------------------
#  Event hooks
# ----------------------------------------------------------------------------

proc on-file-read  {path} { highlight-current }
proc on-save       {path} { highlight-current }
proc on-switch     {name} {
    set w [widget-for-buffer $name]
    if {$w ne "" && [should-highlight $name $w]} { highlight-widget $w }
}
proc on-theme-changed {args} {
    dict for {name info} $::Tclme::buffers {
        set w ".ws.[dict get $info wid].txt"
        if {[winfo exists $w]} { ensure-tags $w }
    }
}
proc on-status {name} {
    set w [widget-for-buffer $name]
    if {$w eq "" || ![winfo exists $w]} { return "" }
    if {[should-highlight $name $w]} { return "tcl" }
    return ""
}

proc onchange {w} {
    variable pending
    if {$::Tclme::prompting} return
    set name [buffer-for-widget $w]
    if {$name eq "" || ![should-highlight $name $w]} return
    if {[dict exists $pending $w]} { after cancel [dict get $pending $w] }
    dict set pending $w [after 300 [list [namespace current]::highlight-widget $w]]
}

# ----------------------------------------------------------------------------
#  Commands
# ----------------------------------------------------------------------------

proc cmd-toggle {args} {
    variable forced
    if {![info exists forced]} { set forced [dict create] }

    set name $::Tclme::current_buffer
    set w [widget-for-buffer $name]
    if {$w eq ""} return
    set cur [expr {[dict exists $forced $name] ? [dict get $forced $name]
                                           : [should-highlight $name $w]}]
    dict set forced $name [expr {!$cur}]
    if {!$cur} {
        highlight-widget $w
        Tclme::Message "Highlighting on: $name"
    } else {
        clear-widget $w
        Tclme::Message "Highlighting off: $name"
    }
}

proc cmd-refresh {args} {
    variable forced
    if {![info exists forced]} { set forced [dict create] }
    set name $::Tclme::current_buffer
    dict set forced $name 1
    highlight-current
    Tclme::Message "Re-highlighted $name"
}

proc add-keyword {args} {
    variable keywords
    foreach k $args { dict set keywords $k 1 }
}

# ----------------------------------------------------------------------------
#  Lifecycle
# ----------------------------------------------------------------------------

proc load {} {
    bind TclmeText <KeyRelease> [list [namespace current]::onchange %W]
    bind TclmeText <<Paste>>    [list [namespace current]::onchange %W]
    highlight-current
}

proc unload {} {
    variable pending
    dict for {w id} $pending { after cancel $id }
    bind TclmeText <KeyRelease> {}
    bind TclmeText <<Paste>>    {}
    dict for {name info} $::Tclme::buffers {
        clear-widget ".ws.[dict get $info wid].txt"
    }
}

proc save-state {} {
    variable forced
    variable enabled
    if {![info exists forced]} { set forced [dict create] }
    return [list $enabled $forced]
}

proc restore-state {s} {
    variable forced
    variable enabled
    lassign $s enabled forced
}

# ----------------------------------------------------------------------------
#  Registration
# ----------------------------------------------------------------------------

Tclme::On after-file-read on-file-read
Tclme::On after-save      on-save
Tclme::On buffer-switched on-switch
Tclme::On theme-changed   on-theme-changed
#Tclme::On status-line     on-status

Tclme::DefCommand hl-toggle cmd-toggle "Toggle Tcl highlighting for this buffer"
Tclme::DefCommand hl-refresh cmd-refresh "Force re-highlight of this buffer"