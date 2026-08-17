# tcled.tcl 
# Something of an editor

namespace eval Tclme {
    variable prompting        0
    variable prompt_callback  ""
    variable prompt_completer ""
    variable prompt_history  {}
    variable history_index   0
    variable buffer_seq      0
    variable buffer_order    {}
    variable buffers         [dict create]  ;# name -> dict(path wid readonly)
    variable path_to_buffer  [dict create]

    variable current_buffer  ""
    variable active_widget   ""
    variable status_job  ""
    variable theme [dict create \
        bg          "#F5F5F5"  fg          "#2C2C2C" \
        editor_bg   "#FFFFFF"  editor_fg   "#1A1A1A" \
        status_bg   "#2C2C2C"  status_fg   "#DDDDDD" \
        minibuf_bg  "#FFFFFF"  minibuf_fg  "#1A1A1A" \
        accent      "#4A7CFE"  separator   "#D8D8D8" \
        scrollbar   "#D8D8D8"  cursor      "#1A1A1A" \
        font        {Consolas 12} \
        status_font {Consolas 10} \
    ]
}

proc Tclme::BuildUI {} {
    wm title . "Tcled"
    wm minsize . 560 360
    . configure -bg [Tclme::GetTheme bg]

    frame .ws -bg [Tclme::GetTheme bg]
    pack .ws -fill both -expand 1

    frame .sep1 -bg [Tclme::GetTheme separator] -height 1
    pack .sep1 -fill x

    label .status \
        -anchor w \
        -bg [Tclme::GetTheme status_bg] \
        -fg [Tclme::GetTheme status_fg] \
        -font [Tclme::GetTheme status_font] \
        -padx 6 \
        -pady 2
    pack .status -fill x

    frame .sep2 -bg [Tclme::GetTheme separator] -height 1
    pack .sep2 -fill x

    frame .minibar -bg [Tclme::GetTheme minibuf_bg]

    label .minibar.prompt \
        -text "" \
        -bg [Tclme::GetTheme minibuf_bg] \
        -fg [Tclme::GetTheme accent] \
        -font [Tclme::GetTheme status_font]

    entry .minibar.entry \
        -bg [Tclme::GetTheme minibuf_bg] \
        -fg [Tclme::GetTheme minibuf_fg] \
        -insertbackground [Tclme::GetTheme cursor] \
        -bd 0 \
        -highlightthickness 0 \
        -relief flat \
        -font [Tclme::GetTheme font]

    pack .minibar.prompt -side left -padx {6 0}
    pack .minibar.entry -side left -fill x -expand 1 -padx 6 -pady 2
    pack .minibar -fill x

    bind .minibar.entry <Return>     { Tclme::MinibarReturn }
    bind .minibar.entry <Escape>     { Tclme::MinibarCancel }
    bind .minibar.entry <Control-g>  { Tclme::MinibarCancel }
    bind .minibar.entry <Tab>        { Tclme::MinibarComplete; break }
    bind .minibar.entry <Up>         { Tclme::HistoryPrev; break }
    bind .minibar.entry <Down>       { Tclme::HistoryNext; break }
    bind .minibar.entry <Control-p>  { Tclme::HistoryPrev; break }
    bind .minibar.entry <Control-n>  { Tclme::HistoryNext; break }

    Tclme::ApplyTheme
}


# ----------------------------------------------------------------------------
# Medium Solarized
# ----------------------------------------------------------------------------

proc Tclme::SolarizedMedium {} {
    # Solarized palette used:
    #
    # base03   #002b36
    # base02   #073642
    # base01   #586e75
    # base00   #657b83
    # base0    #839496
    # base1    #93a1a1
    # base2    #eee8d5
    # base3    #fdf6e3
    # yellow   #b58900
    # orange   #cb4b16
    # red      #dc322f
    # magenta  #d33682
    # violet   #6c71c4
    # blue     #268bd2
    # cyan     #2aa198
    # green    #859900

    return [dict create \
        bg          "#eee8d5" \
        fg          "#657b83" \
        editor_bg   "#eee8d5" \
        editor_fg   "#586e75" \
        status_bg   "#073642" \
        status_fg   "#93a1a1" \
        minibuf_bg  "#eee8d5" \
        minibuf_fg  "#586e75" \
        accent      "#268bd2" \
        separator   "#d8d1be" \
        scrollbar   "#cfc7b2" \
        cursor      "#cb4b16" \
        font        {Consolas 12} \
        status_font {Consolas 10} \
    ]

}


proc Tclme::SolarizedMediumDark {} {
    return [dict create \
        bg          "#002b36" \
        fg          "#839496" \
        editor_bg   "#073642" \
        editor_fg   "#93a1a1" \
        status_bg   "#002b36" \
        status_fg   "#93a1a1" \
        minibuf_bg  "#073642" \
        minibuf_fg  "#93a1a1" \
        accent      "#268bd2" \
        separator   "#0e4c58" \
        scrollbar   "#0e4c58" \
        cursor      "#cb4b16" \
        font        {Consolas 12} \
        status_font {Consolas 10} \
    ]

}

proc Tclme::LightPalette {} {
    return [dict create \
        bg          "#F5F5F5" \
        fg          "#2C2C2C" \
        editor_bg   "#FFFFFF" \
        editor_fg   "#1A1A1A" \
        status_bg   "#2C2C2C" \
        status_fg   "#DDDDDD" \
        minibuf_bg  "#FFFFFF" \
        minibuf_fg  "#1A1A1A" \
        accent      "#4A7CFE" \
        separator   "#D8D8D8" \
        scrollbar   "#D8D8D8" \
        cursor      "#1A1A1A" \
        font        {Consolas 12} \
        status_font {Consolas 10} \
    ]
}

proc Tclme::DarkPalette {} {
    return [dict create \
        bg          "#222222" \
        fg          "#DADADA" \
        editor_bg   "#1E1E1E" \
        editor_fg   "#D4D4D4" \
        status_bg   "#252526" \
        status_fg   "#DDDDDD" \
        minibuf_bg  "#252526" \
        minibuf_fg  "#D4D4D4" \
        accent      "#4A9EFF" \
        separator   "#3C3C3C" \
        scrollbar   "#3E3E3E" \
        cursor      "#D4D4D4" \
        font        {Consolas 12} \
        status_font {Consolas 10} \
    ]
}

proc Tclme::GetTheme {key} {
    variable theme 
    return [dict get $theme $key]
}

proc Tclme::UseTheme {name} {
    variable theme

    if {$name eq "dark"} {
        set theme [dict merge $theme [Tclme::DarkPalette]]
    } elseif {$name eq "light"} {
        set theme [dict merge $theme [Tclme::LightPalette]]
    } elseif {$name eq "sol"} {
        set theme [dict merge $theme [Tclme::SolarizedMedium]]
    } elseif {$name eq "sold"} {
        set theme [dict merge $theme [Tclme::SolarizedMediumDark]]
    } else {
        Tclme::Message "Unknown theme: $name"
        return
    }

    Tclme::ApplyTheme
}

proc Tclme::ApplyTheme {} {
    variable theme
    variable buffers

    . configure -bg [dict get $theme bg]

    if {[winfo exists .status]} {
        .status configure \
            -bg [dict get $theme status_bg] \
            -fg [dict get $theme status_fg] \
            -font [dict get $theme status_font]
    }

    if {[winfo exists .minibar.entry]} {
        .minibar configure -bg [dict get $theme minibuf_bg]

        .minibar.prompt configure \
            -bg [dict get $theme minibuf_bg] \
            -fg [dict get $theme accent]

        .minibar.entry configure \
            -bg [dict get $theme minibuf_bg] \
            -fg [dict get $theme minibuf_fg] \
            -insertbackground [dict get $theme cursor]
    }

    foreach sep {.sep1 .sep2} {
        if {[winfo exists $sep]} {
            $sep configure -bg [dict get $theme separator]
        }
    }

    dict for {name info} $buffers {
        set c ".ws.[dict get $info wid]"
        set txt "$c.txt"

        if {[winfo exists $c]} {
            $c configure -bg [dict get $theme bg]
        }

        if {[winfo exists $txt]} {
            $txt configure \
                -bg [dict get $theme editor_bg] \
                -fg [dict get $theme editor_fg] \
                -insertbackground [dict get $theme cursor] \
                -font [dict get $theme font]
        }

        if {[winfo exists "$c.vs"]} {
            "$c.vs" configure -bg [dict get $theme scrollbar]
        }
    }

    Tclme::Emit theme-changed
}

proc Tclme::Message {msg {tag message}} {
    variable prompting

    if {![winfo exists .minibar.entry]} {
        return
    }

    if {$prompting} {
        Tclme::UpdateStatus $msg
        return
    }

    .minibar.prompt configure -text ""
    .minibar.entry delete 0 end
    .minibar.entry insert 0 $msg
    .minibar.entry xview end
}

proc Tclme::UpdateStatus {msg} {
    if {[winfo exists .status]} {
        .status configure -text " $msg "
    }
}

proc Tclme::OpenTranscript {args} {
    variable transcript_buffer "*repl*"
    variable transcript
    variable buffers

    Tclme::SwitchToBuffer $transcript_buffer

 
    dict set buffers $transcript_buffer readonly 1

    set w $Tclme::active_widget

    if {![winfo exists $w]} {
        return
    }

    $w configure -state normal
    $w delete 1.0 end

    $w tag configure repl_input   -foreground [Tclme::GetTheme accent]
    $w tag configure repl_result  -foreground [Tclme::GetTheme fg]
    $w tag configure repl_error   -foreground "#D9534F"
    $w tag configure repl_message -foreground [Tclme::GetTheme fg]

    foreach entry $transcript {
        lassign $entry tag text

        if {$tag eq ""} {
            $w insert end "$text\n"
        } else {
            $w insert end "$text\n" [list $tag]
        }
    }

    $w edit modified 0
    $w see end
    $w configure -state disabled

    Tclme::RefreshStatus
}

proc Tclme::BindKey {name keys {tag TclmeText}} {
    variable commands
    variable _owner
    variable plugin_meta

    set owner $_owner

    if {$owner eq ""} {
        set owner [Tclme::NamespaceOwner [uplevel 1 {namespace current}]]
    }

    catch { bind $tag $keys {} }

    if {$keys ne ""} {
        set script [list Tclme::Invoke $name]
        bind $tag $keys "$script; break"

        # This is the important part for :help.
        if {[dict exists $commands $name]} {
            dict set commands $name keys $keys
        }

        if {$owner ne "" && [dict exists $plugin_meta $owner]} {
            dict lappend plugin_meta $owner binds [list $tag $keys]
        }
    } else {
        if {[dict exists $commands $name]} {
            dict set commands $name keys ""
        }
    }
}

proc Tclme::Prompt {label callback {completer ""}} {
    variable prompting
    variable prompt_callback
    variable prompt_completer
    variable prompt_history
    variable history_index
    variable _owner

    set owner $_owner
    if {$owner eq ""} {
        set owner [Tclme::NamespaceOwner [uplevel 1 {namespace current}]]
    }
    set callback [Tclme::QualifyScript $callback $owner]
    set completer [Tclme::QualifyScript $completer $owner]

    set prompting 1
    set prompt_callback $callback
    set prompt_completer $completer
    set history_index [llength $prompt_history]

    .minibar.prompt configure -text $label
    .minibar.entry delete 0 end
    focus .minibar.entry

    Tclme::Emit minibuffer-prompted $label
}

proc Tclme::SwitchToTranscript {} {
    variable transcript_buffer

    if {![info exists transcript_buffer]} {
        set transcript_buffer "*repl*"
    }

    if {[Tclme::WidgetForBuffer $transcript_buffer] eq ""} {
        Tclme::OpenTranscript
    } else {
        Tclme::SwitchToBuffer $transcript_buffer
    }
}

proc Tclme::EvalInput {code} {

    set code [string trim $code]

    if {$code eq ""} {
        return
    }

    if {[catch {uplevel #0 $code} result]} {
        Tclme::Print "Error: $result" repl_error
        Tclme::SwitchToTranscript

    } else {
        if {$result ne "" } {
            Tclme::Print "=> $result" repl_result
        }
    }
}

proc Tclme::DispatchLine {line} {

    set line [string trim $line]

    if {$line eq ""} {
        return
    }

    if {[string match ::* $line]} {
        Tclme::EvalInput $line
    } elseif {[string index $line 0] eq ";"} {
        Tclme::RunExCommand [string range $line 1 end]
    } else {
        Tclme::EvalInput $line
    }
}

proc Tclme::MinibarReturn {} {
    variable prompting
    variable prompt_callback
    variable prompt_completer
    variable active_widget

    set input [.minibar.entry get]

    if {$prompting} {
        set cb $prompt_callback

        set prompting 0
        set prompt_callback ""
        set prompt_completer ""

        .minibar.prompt configure -text ""
        .minibar.entry delete 0 end

        Tclme::HistoryAdd $input

        if {[catch {uplevel #0 [list {*}$cb $input]} err]} {
            Tclme::Log error "prompt callback: $err"
        }

        if {!$prompting && [winfo exists $active_widget]} {
            focus $active_widget
        }

        return
    }

    # Normal minibuffer input.

    set t [string trim $input]

    if {$t eq ""} {
        return
    }

    Tclme::HistoryAdd $t
    .minibar.entry delete 0 end

    set looks_like_command [expr {
        [string index $t 0] eq ";" &&
        ![string match ::* $t]
    }]

    Tclme::DispatchLine $t

    if {!$prompting} {
        if {$looks_like_command && [winfo exists $active_widget]} {
            focus $active_widget
        } else {
             focus .minibar.entry
        }
    }
}

proc Tclme::MinibarCancel {} {
    variable prompting
    variable prompt_callback
    variable prompt_completer
    variable active_widget

    set prompting 0
    set prompt_callback ""
    set prompt_completer ""

    .minibar.prompt configure -text ""
    .minibar.entry delete 0 end

    Tclme::Emit minibuffer-cancelled

    if {[winfo exists $active_widget]} {
        focus $active_widget
    }
}

# Ex-command parsing choice:

proc Tclme::RunExCommand {line} {
    set line [string trim $line]
    if {$line eq ""} {
        return
    }

    if {![regexp {^\s*(\S+)\s*(.*)$} $line -> name rest]} {
        return
    }

    Tclme::Invoke $name $rest
}

proc Tclme::HistoryAdd {s} {
    variable prompt_history
    variable history_index

    set s [string trim $s]
    if {$s eq ""} {
        return
    }

    if {[llength $prompt_history] == 0 || [lindex $prompt_history end] ne $s} {
        lappend prompt_history $s
    }

    if {[llength $prompt_history] > 200} {
        set prompt_history [lrange $prompt_history end-199 end]
    }

    set history_index [llength $prompt_history]
}

proc Tclme::HistoryPrev {} {
    variable prompt_history
    variable history_index

    set len [llength $prompt_history]
    if {$len == 0} {
        return
    }

    if {$history_index > $len} {
        set history_index $len
    }

    if {$history_index > 0} {
        incr history_index -1
    }

    .minibar.entry delete 0 end
    .minibar.entry insert 0 [lindex $prompt_history $history_index]
    .minibar.entry icursor end
}

proc Tclme::HistoryNext {} {
    variable prompt_history
    variable history_index

    set len [llength $prompt_history]
    if {$len == 0 || $history_index >= $len} {
        return
    }

    incr history_index

    if {$history_index >= $len} {
        set history_index $len
        .minibar.entry delete 0 end
    } else {
        .minibar.entry delete 0 end
        .minibar.entry insert 0 [lindex $prompt_history $history_index]
    }

    .minibar.entry icursor end
}

proc Tclme::CommonPrefix {items} {
    if {[llength $items] == 0} {
        return ""
    }

    set prefix [lindex $items 0]
    foreach s [lrange $items 1 end] {
        set i 0
        set max [expr {min([string length $prefix], [string length $s])}]

        while {$i < $max && [string index $prefix $i] eq [string index $s $i]} {
            incr i
        }

        if {$i == 0} {
            set prefix ""
            break
        }

        set prefix [string range $prefix 0 [expr {$i - 1}]]
    }

    return $prefix
}

proc Tclme::MinibarComplete {} {
    variable prompting
    variable prompt_completer
    variable commands
    variable aliases

    if {![winfo exists .minibar.entry]} {
        return
    }

    set txt [.minibar.entry get]
    set cands {}

    if {$prompting} {
        if {$prompt_completer eq ""} {
            return
        }

        if {[catch {set cands [uplevel #0 [list {*}$prompt_completer $txt]]} err]} {
            Tclme::Log error "completer: $err"
            return
        }
    } else {
        set t [string trim $txt]

        # Complete :command only while it is still a single token.
        if {![regexp {^;(\S*)$} $t -> prefix]} {
            return
        }

        set plen [string length $prefix]
        set names {}

        foreach n [dict keys $commands] {
            lappend names $n
        }

        foreach n [dict keys $aliases] {
            lappend names $n
        }

        foreach n [lsort -unique $names] {
            if {[string equal -length $plen $prefix $n]} {
                lappend cands ";$n"
            }
        }
    }

    set n [llength $cands]

    if {$n == 0} {
        Tclme::UpdateStatus "No completions"
        return
    }

    if {$n == 1} {
        .minibar.entry delete 0 end
        .minibar.entry insert 0 [lindex $cands 0]
        .minibar.entry icursor end
        return
    }

    set common [Tclme::CommonPrefix $cands]

    if {$common ne $txt} {
        .minibar.entry delete 0 end
        .minibar.entry insert 0 $common
        .minibar.entry icursor end
    }

    Tclme::UpdateStatus [join [lrange $cands 0 12] "  "]
}

proc Tclme::CompleteBuffer {txt} {
    variable buffer_order

    set out {}
    set plen [string length $txt]

    foreach b $buffer_order {
        if {[string equal -length $plen $txt $b]} {
            lappend out $b
        }
    }

    return $out
}

proc Tclme::CompleteFile {txt} {
    if {$txt eq ""} {
        set dir [pwd]
        set base ""
    } elseif {[file isdirectory $txt]} {
        set dir $txt
        set base ""
    } else {
        set dir [file dirname $txt]
        set base [file tail $txt]
    }

    set out {}
    set plen [string length $base]
    set matches [glob -nocomplain -directory $dir -- *]

    foreach m [lsort $matches] {
        set tail [file tail $m]

        if {$base eq "" || [string equal -length $plen $base $tail]} {
            if {[file isdirectory $m]} {
                append m "/"
            }
            lappend out $m
        }
    }

    return $out
}

proc Tclme::WidgetForBuffer {name} {
    variable buffers

    if {![dict exists $buffers $name]} {
        return ""
    }

    set info [dict get $buffers $name]

    if {![dict exists $info wid]} {
        return ""
    }

    set w ".ws.[dict get $info wid].txt"

    if {[winfo exists $w]} {
        return $w
    }

    return ""
}

proc Tclme::GetBufferContent {name} {
    variable buffers

    set w [Tclme::WidgetForBuffer $name]

    if {$w ne ""} {
        return [$w get 1.0 end-1c]
    }

    if {[dict exists $buffers $name model text]} {
        return [dict get $buffers $name model text]
    }

    return ""
}

proc Tclme::SetBufferContent {name text} {
    variable buffers

    if {![dict exists $buffers $name]} {
        error "No such buffer: $name"
    }

    set w [Tclme::WidgetForBuffer $name]

    if {$w ne ""} {
        set old_state [$w cget -state]

        catch { $w edit separator }

        $w configure -state normal
        $w delete 1.0 end
        $w insert end $text
        $w edit modified 0

        catch { $w edit separator }

        $w configure -state $old_state

        return
    }

    dict set buffers $name model text $text
}

proc Tclme::UniqueBufferName {base} {
    variable buffers

    set base [string trim $base]

    if {$base eq ""} {
        set base "scratch"
    }

    if {![dict exists $buffers $base]} {
        return $base
    }

    set n 2

    while {[dict exists $buffers "$base<$n>"]} {
        incr n
    }

    return "$base<$n>"
}

proc Tclme::SwitchToBuffer {name} {
    variable current_buffer
    variable buffers
    variable buffer_order
    variable buffer_seq
    variable active_widget

    Tclme::Emit before-buffer-switch $name

    if {![dict exists $buffers $name]} {
        set wid "b[incr buffer_seq]"

        dict set buffers $name [dict create \
            path "" \
            wid $wid \
            readonly 0 \
        ]

        lappend buffer_order $name
        Tclme::CreateBufferWidget $name $wid
        Tclme::Emit buffer-created $name
    }

    set wid [dict get [dict get $buffers $name] wid]
    set container ".ws.$wid"

    foreach child [winfo children .ws] {
        pack forget $child
    }

    pack $container -fill both -expand 1

    set current_buffer $name
    set active_widget "$container.txt"

    focus $active_widget

    Tclme::RefreshStatus
    Tclme::Emit buffer-switched $name
    Tclme::Emit cursor-moved
}

proc Tclme::CreateBufferWidget {name wid} {
    set container ".ws.$wid"
    set txt "$container.txt"

    frame $container -bg [Tclme::GetTheme bg]

    text $txt \
        -undo 1 \
        -wrap word \
        -padx 6 \
        -pady 4 \
        -bg [Tclme::GetTheme editor_bg] \
        -fg [Tclme::GetTheme editor_fg] \
        -insertbackground [Tclme::GetTheme cursor] \
        -font [Tclme::GetTheme font] \
        -highlightthickness 0 \
        -yscrollcommand [list "$container.vs" set]

    scrollbar "$container.vs" \
        -orient vertical \
        -command [list $txt yview] \
        -bg [Tclme::GetTheme scrollbar]

    pack "$container.vs" -side right -fill y
    pack $txt -side left -fill both -expand 1
    Tclme::ApplyTheme
    bindtags $txt [list $txt TclmeText Text [winfo toplevel $container] all]

    bind $txt <<Modified>>      { Tclme::RefreshStatus }
    bind $txt <KeyRelease>      { after idle { Tclme::CursorMoved } }
    bind $txt <ButtonRelease-1> { after idle { Tclme::CursorMoved } }
}

proc Tclme::CursorMoved {} {
    variable active_widget

    if {$active_widget ne "" && [winfo exists $active_widget]} {
        Tclme::Emit cursor-moved
        Tclme::RefreshStatus
    }
}

proc Tclme::KillBuffer {name} {
    variable buffers
    variable buffer_order
    variable path_to_buffer
    variable current_buffer

    if {![dict exists $buffers $name]} {
        Tclme::Message "No such buffer: $name"
        return
    }

    set reason [Tclme::EmitCancelable before-kill-buffer $name]
    if {$reason ne ""} {
        Tclme::Message "Kill cancelled: $reason"
        return
    }

    set info [dict get $buffers $name]
    set txt ".ws.[dict get $info wid].txt"

    if {[winfo exists $txt] && [$txt edit modified]} {
        set ans [tk_messageBox \
            -type yesno \
            -icon warning \
            -title "Unsaved changes" \
            -message "Buffer \"$name\" has unsaved changes. Kill anyway?"]

        if {$ans ne "yes"} {
            return
        }
    }

    set path [dict get $info path]
    if {$path ne ""} {
        catch { dict unset path_to_buffer $path }
    }

    set buffer_order [lsearch -all -inline -not -exact $buffer_order $name]
    dict unset buffers $name

    Tclme::Emit buffer-killed $name
    after idle [list destroy ".ws.[dict get $info wid]"]

    if {$current_buffer eq $name} {
        if {[llength $buffer_order] > 0} {
            Tclme::SwitchToBuffer [lindex $buffer_order end]
        } else {
            Tclme::SwitchToBuffer "scratch"
        }
    }
}

proc Tclme::ListBuffers {} {
    variable buffer_order
    variable current_buffer

    if {[llength $buffer_order] == 0} {
        Tclme::Message "No buffers"
        return
    }

    set i 0
    set out {}

    foreach b $buffer_order {
        incr i
        set mark [expr {$b eq $current_buffer ? "%" : " "}]
        lappend out "$i$mark:$b"
    }

    Tclme::Message [join $out "  "]
}

proc Tclme::ShowInBuffer {name content {readonly 0}} {
    variable active_widget
    variable buffers

    Tclme::SwitchToBuffer $name

    if {[dict exists $buffers $name]} {
        dict set buffers $name readonly $readonly
    }

    set w $active_widget
    if {![winfo exists $w]} {
        return
    }

    $w configure -state normal
    $w delete 1.0 end
    $w insert end $content
    $w edit modified 0

    if {$readonly} {
        $w configure -state disabled
    }

    Tclme::RefreshStatus
}

proc Tclme::FindBufferForPath {full} {
    variable path_to_buffer

    if {[dict exists $path_to_buffer $full]} {
        return [dict get $path_to_buffer $full]
    }

    return ""
}

proc Tclme::OpenFile {filename} {
    variable buffers
    variable path_to_buffer
    variable active_widget

    set filename [string trim $filename]
    if {$filename eq ""} {
        Tclme::Message "No filename given"
        return
    }

    set full [file normalize $filename]

    if {[file isdirectory $full]} {
        Tclme::Message "Cannot open directory: $full"
        return
    }

    set existing [Tclme::FindBufferForPath $full]
    if {$existing ne ""} {
        Tclme::SwitchToBuffer $existing
        return
    }

    set bname [file tail $full]
    if {$bname eq ""} {
        set bname $full
    }

    set bname [Tclme::UniqueBufferName $bname]
    Tclme::Emit before-file-read $full
    Tclme::SwitchToBuffer $bname

    dict set buffers $bname [dict merge \
        [dict get $buffers $bname] \
        [dict create path $full] \
    ]

    dict set path_to_buffer $full $bname

    if {![file exists $full]} {
        Tclme::Message "(New file)"
    } else {
        if {[catch {
            set fp [open $full r]
            fconfigure $fp -encoding utf-8 -translation auto
            set data [read $fp]
            close $fp

            $active_widget configure -state normal
            $active_widget insert end $data
        } err]} {
            Tclme::Log error "open '$full': $err"
        }
    }

    catch { $active_widget edit modified 0 }

    Tclme::RefreshStatus
    Tclme::Emit after-file-read $full
}

proc Tclme::SaveCurrentBuffer {} {
    variable current_buffer
    variable buffers

    if {$current_buffer eq ""} {
        return
    }

    set info [dict get $buffers $current_buffer]

    if {[dict get $info readonly]} {
        Tclme::Message "Read-only buffer"
        return
    }

    set path [dict get $info path]

    if {$path eq ""} {
        Tclme::Prompt "Save as: " Tclme::SaveBufferToFile Tclme::CompleteFile
    } else {
        Tclme::SaveBufferToFile $path
    }
}

proc Tclme::SaveBufferToFile {filename} {
    variable current_buffer
    variable active_widget
    variable buffers
    variable path_to_buffer

    set filename [string trim $filename]
    if {$filename eq ""} {
        Tclme::Message "Save cancelled"
        return
    }

    if {$current_buffer eq "" || ![winfo exists $active_widget]} {
        return
    }

    set info [dict get $buffers $current_buffer]

    if {[dict get $info readonly]} {
        Tclme::Message "Read-only buffer"
        return
    }

    set norm [file normalize $filename]

    if {[file isdirectory $norm]} {
        Tclme::Message "Cannot save to directory: $norm"
        return
    }

    set reason [Tclme::EmitCancelable before-save $norm]
    if {$reason ne ""} {
        Tclme::Message "Save cancelled: $reason"
        return
    }

    Tclme::Emit before-file-write $norm

    set rc [catch {
        set fp [open $norm w]
        fconfigure $fp -encoding utf-8

        puts -nonewline $fp [$active_widget get 1.0 end-1c]
        close $fp

        $active_widget edit modified 0

        set old [dict get $info path]
        if {$old ne "" && $old ne $norm} {
            catch { dict unset path_to_buffer $old }
        }

        dict set buffers $current_buffer [dict merge \
            [dict get $buffers $current_buffer] \
            [dict create path $norm] \
        ]

        dict set path_to_buffer $norm $current_buffer
    } err]

    if {$rc} {
        Tclme::Log error "save '$norm': $err"
        return
    }

    Tclme::RefreshStatus
    Tclme::Emit after-save $norm
    Tclme::Emit after-file-write $norm
    Tclme::Message "Wrote $norm"
}

proc Tclme::Quit {} {
    variable buffers

    set reason [Tclme::EmitCancelable before-quit]
    if {$reason ne ""} {
        Tclme::Message "Quit cancelled: $reason"
        return
    }

    set dirty {}

    dict for {name info} $buffers {
        if {[dict exists $info readonly] && [dict get $info readonly]} {
            continue
        }

        set txt ".ws.[dict get $info wid].txt"
        if {[winfo exists $txt] && [$txt edit modified]} {
            lappend dirty $name
        }
    }

    if {[llength $dirty] > 0} {
        set ans [tk_messageBox \
            -type yesno \
            -icon warning \
            -title "Unsaved changes" \
            -message "Unsaved changes in: [join $dirty {, }]\n\nQuit anyway?"]

        if {$ans ne "yes"} {
            return
        }
    }

    Tclme::Emit editor-quit
    exit 0
}

proc Tclme::RefreshStatus {} {
    variable status_job

    if {$status_job ne ""} {
        catch { after cancel $status_job }
    }

    set status_job [after 50 Tclme::DoRefreshStatus]
}

proc Tclme::DoRefreshStatus {} {
    variable status_job ""
    variable current_buffer
    variable active_widget
    variable buffers

    if {$active_widget eq "" || ![winfo exists $active_widget]} {
        return
    }

    set dirty [expr {[$active_widget edit modified] ? "*" : " "}]
    set pos [$active_widget index insert]
    set line [lindex [split $pos .] 0]
    set col  [expr {[lindex [split $pos .] 1] + 1}]

    set path ""
    if {[dict exists $buffers $current_buffer]} {
        set path [dict get [dict get $buffers $current_buffer] path]
    }

    set loc [expr {$path ne "" ? "   $path" : ""}]
    set base " ${current_buffer}${dirty}  Ln $line, Col $col${loc} "

    set extra [Tclme::Collect status-line $current_buffer]
    if {$extra ne ""} {
        append base "  |  $extra"
    }

    Tclme::UpdateStatus $base
}

proc Tclme::GotoLine {n} {
    variable active_widget

    set n [string trim $n]
    if {$n eq ""} {
        return
    }

    if {![string is integer -strict $n]} {
        Tclme::Message "Line number must be an integer"
        return
    }

    if {$active_widget eq "" || ![winfo exists $active_widget]} {
        return
    }

    if {[catch {$active_widget mark set insert $n.0} err]} {
        Tclme::Message "Cannot goto line $n"
        return
    }

    $active_widget see insert
    Tclme::Emit cursor-moved
    Tclme::RefreshStatus
}

proc Tclme::ShowLogBuffer {} {
    variable log

    set lines {}

    foreach e $log {
        lassign $e t lvl msg
        lappend lines "$t \[$lvl\] $msg"
    }

    if {[llength $lines] == 0} {
        set lines [list "Log empty."]
    }

    Tclme::ShowInBuffer "*Log*" [join $lines \n] 1
}

proc Tclme::ShowHelpBuffer {} {
    variable commands
    variable aliases

    set lines [list "Tclme commands" ""]

    foreach name [lsort [dict keys $commands]] {
        set entry [dict get $commands $name]
        set keys [dict get $entry keys]
        set doc [dict get $entry doc]

        lappend lines [format "%-14s %-26s %s" $name $keys $doc]
    }

    lappend lines "" "Aliases:"

    foreach a [lsort [dict keys $aliases]] {
        lappend lines [format "  %-8s -> %s" $a [dict get $aliases $a]]
    }

    lappend lines "" \
        "Type :command in the minibuffer. Tab completes. Up/Down history." \
        "C-l goes to line, C-x b switches buffers."

    Tclme::ShowInBuffer "*Help*" [join $lines \n] 1
}

proc Tclme::CmdNew {args} {
    set name [string trim [join $args " "]]

    if {$name eq ""} {
        set name "untitled"
    }

    set target [Tclme::UniqueBufferName $name]

    Tclme::SwitchToBuffer $target
    Tclme::Message "New buffer: $target"
}

proc Tclme::CmdScratch {args} {
    Tclme::SwitchToBuffer "scratch"
}

proc Tclme::CmdWrite {args} {
    Tclme::SaveCurrentBuffer
}

proc Tclme::CmdCancel {args} {
    Tclme::MinibarCancel
}

proc Tclme::CmdList {args} {
    Tclme::ListBuffers
}

proc Tclme::CmdLog {args} {
    Tclme::ShowLogBuffer
}

proc Tclme::CmdHelp {args} {
    Tclme::ShowHelpBuffer
}

proc Tclme::CmdReloadInit {args} {
    Tclme::ReloadUserInit
}

proc Tclme::CmdEdit {args} {
    set arg [string trim [join $args " "]]

    if {$arg eq ""} {
        Tclme::Prompt "Open: " Tclme::OpenFile Tclme::CompleteFile
    } else {
        Tclme::OpenFile $arg
    }
}

proc Tclme::CmdEval {args} {
    set arg [string trim [join $args " "]]

    if {$arg eq ""} {
        Tclme::Prompt "% " Tclme::EvalInput
    } else {
        Tclme::EvalInput $arg
    }
}

proc Tclme::CmdSwitch {args} {
    set arg [string trim [join $args " "]]

    if {$arg eq ""} {
        Tclme::Prompt "Buffer: " Tclme::SwitchByNameOrIndex Tclme::CompleteBuffer
    } else {
        Tclme::SwitchByNameOrIndex $arg
    }
}

proc Tclme::CmdSaveAs {args} {
    set arg [string trim [join $args " "]]

    if {$arg eq ""} {
        Tclme::Prompt "Save as: " Tclme::SaveBufferToFile Tclme::CompleteFile
    } else {
        Tclme::SaveBufferToFile $arg
    }
}

proc Tclme::CmdKill {args} {
    variable current_buffer

    set arg [string trim [join $args " "]]

    if {$arg eq ""} {
        Tclme::KillBuffer $current_buffer
    } else {
        Tclme::KillBuffer $arg
    }
}

proc Tclme::CmdReloadPlugins {args} {
    set arg [string trim [join $args " "]]
    Tclme::ReloadPlugins $arg
}

proc Tclme::CmdGoto {args} {
    set arg [string trim [join $args " "]]

    if {$arg eq ""} {
        Tclme::Prompt "Goto line: " Tclme::GotoLine
    } else {
        Tclme::GotoLine $arg
    }
}

proc Tclme::CmdTheme {args} {
    set name [string trim [join $args " "]]

    Tclme::UseTheme $name
}

proc Tclme::SwitchByNameOrIndex {target} {
    variable buffer_order

    set target [string trim $target]

    if {$target eq ""} {
        Tclme::ListBuffers
        return
    }

    if {[string is integer -strict $target]} {
        set max [llength $buffer_order]

        if {$target >= 1 && $target <= $max} {
            Tclme::SwitchToBuffer [lindex $buffer_order [expr {$target - 1}]]
        } else {
            Tclme::Message "Index out of range (1-$max)"
        }

        return
    }

    if {[lsearch -exact $buffer_order $target] >= 0} {
        Tclme::SwitchToBuffer $target
    } else {
        Tclme::Message "No such buffer: $target"
    }
}

proc Tclme::SetOutputSink {cmd} {
    variable output_sink
    set output_sink $cmd
}

proc Tclme::TkTranscriptSink {text tag} {
    variable transcript_buffer

    set w [Tclme::WidgetForBuffer $transcript_buffer]

    if {$w eq ""} {
        catch { Tclme::OpenTranscript }
        set w [Tclme::WidgetForBuffer $transcript_buffer]

        if {$w eq ""} {
            return
        }
    }

    catch {
        $w configure -state normal

        if {$tag eq ""} {
            $w insert end "$text\n"
        } else {
            $w insert end "$text\n" [list $tag]
        }

        $w see end
        $w edit modified 0
        $w configure -state disabled
    }
}

proc Tclme::InitGUI {} {
    variable headless 0
    Tclme::InitKernel

    Tclme::DefCommandAndBind write   Tclme::CmdWrite         <Control-s>            "Save current buffer"
    Tclme::DefCommandAndBind edit    Tclme::CmdEdit          <Control-o>            "Open a file"
    Tclme::DefCommandAndBind eval    Tclme::CmdEval          <Control-Return>       "Evaluate Tcl"
    Tclme::DefCommandAndBind kill    Tclme::CmdKill          <Control-r>k           "Kill buffer"
    Tclme::DefCommandAndBind reload  Tclme::CmdReloadPlugins <Control-r><Control-r> "Reload plugins"
    Tclme::DefCommandAndBind cancel  Tclme::CmdCancel        <Control-g>            "Cancel prompt"
    Tclme::DefCommandAndBind goto    Tclme::CmdGoto          <Control-l>            "Goto line"
    Tclme::DefCommandAndBind new     Tclme::CmdNew           <Control-n>            "Create an untitled buffer"

    Tclme::DefCommand repl        Tclme::OpenTranscript "Open repl"
    Tclme::DefCommand save-as     Tclme::CmdSaveAs      "Save current buffer"
    Tclme::DefCommand list        Tclme::CmdList        "List open buffers"
    Tclme::DefCommand buffers     Tclme::CmdList        "List open buffers"
    Tclme::DefCommand log         Tclme::CmdLog         "Open log buffer"
    Tclme::DefCommand help        Tclme::CmdHelp        "Open help buffer"
    Tclme::DefCommand reload-init Tclme::CmdReloadInit  "Reload init file"
    Tclme::DefCommand theme       Tclme::CmdTheme       "Switch theme: light/dark/sol/sold"
    Tclme::DefCommand scratch     Tclme::CmdScratch     "Switch to scratch or create new"

    Tclme::DefAlias rp  repl
    Tclme::DefAlias n   new
    Tclme::DefAlias sc  scratch
    Tclme::DefAlias w   write
    Tclme::DefAlias q   quit
    Tclme::DefAlias ed   edit
    Tclme::DefAlias b   switch
    Tclme::DefAlias bd  kill
    Tclme::DefAlias ls  list
    Tclme::DefAlias h   help
    Tclme::DefAlias l   log
    Tclme::DefAlias g   goto
    Tclme::DefAlias th  theme

    Tclme::BuildUI
    Tclme::SwitchToBuffer "scratch"
    Tclme::SetOutputSink Tclme::TkTranscriptSink
    Tclme::LoadAllPlugins
    Tclme::LoadUserInit
    Tclme::Emit editor-started
}

