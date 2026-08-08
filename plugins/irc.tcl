# plugins/irc.tcl
# ============================================================================
#  IRC chat plugin for Tclme.
#
#  Tclme commands:
#    :irc                      toggle IRC panel
#    :irc-connect host ?port? ?nick? ?channel?
#    :irc-join #channel
#    :irc-say message
#    :irc-msg target message
#    :irc-nick newnick
#    :irc-names ?channel?
#    :irc-part ?channel? ?message?
#    :irc-target target
#    :irc-quit ?message?
#    :irc-close                disconnect and hide panel
#
#  Panel input commands:
#    /join #channel
#    /part ?message?
#    /me action
#    /msg target message
#    /nick newnick
#    /names ?channel?
#    /target target
#    /raw IRC LINE
#    /quit ?message?
#    /close
#    /help
#
#  Notes:
#    - Plain TCP IRC only. TLS requires the Tcl tls package and extra work.
#    - Reloading this plugin disconnects the active IRC session.
# ============================================================================

# ----------------------------------------------------------------------------
# State
# ----------------------------------------------------------------------------

variable fd             ""
variable connected      0
variable registered     0
variable connecting     0

variable host           ""
variable port           0
variable nick           ""
variable mynick         ""

variable current_target ""
variable targets        {}
variable pending_joins  {}
variable names          [dict create]
variable show_names     0

variable backlog        {}
variable history        {}
variable hist_index     0

variable ping_after     ""
variable load_after     ""
variable panel_visible  0

# ----------------------------------------------------------------------------
# Theme helper
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

# ----------------------------------------------------------------------------
# Output / UI
# ----------------------------------------------------------------------------

proc Output {text {tag ""}} {
    variable backlog

    set stamp [clock format [clock seconds] -format {%H:%M:%S}]
    set line "\[$stamp\] $text"

    lappend backlog [list $line $tag]

    if {[llength $backlog] > 500} {
        set backlog [lrange $backlog end-499 end]
    }

    if {[winfo exists .irc.out]} {
        InsertLine $line $tag
    }
}

proc InsertLine {line tag} {
    set out .irc.out

    if {![winfo exists $out]} {
        return
    }

    set near_end 1
    catch {
        set near_end [expr {[lindex [$out yview] 1] >= 0.98}]
    }

    $out configure -state normal

    if {$tag eq ""} {
        $out insert end "$line\n"
    } else {
        $out insert end "$line\n" [list $tag]
    }

    if {$near_end} {
        $out see end
    }

    $out configure -state disabled
}

proc RenderBacklog {} {
    variable backlog

    set out .irc.out

    if {![winfo exists $out]} {
        return
    }

    $out configure -state normal
    $out delete 1.0 end
    $out configure -state disabled

    foreach item $backlog {
        lassign $item line tag
        InsertLine $line $tag
    }

    catch { $out see end }
}

proc Show {} {
    variable panel_visible 1

    if {![winfo exists .irc]} {
        BuildUI
    }

    if {[winfo exists .sep1]} {
        pack .irc -fill x -before .sep1
    } elseif {[winfo exists .status]} {
        pack .irc -fill x -before .status
    } else {
        pack .irc -side bottom -fill x
    }

    ConfigureColors
    RenderBacklog
    UpdateStatus
}

proc Hide {} {
    variable panel_visible 0

    if {[winfo exists .irc]} {
        destroy .irc
    }
}

proc BuildUI {} {
    set ns [namespace current]

    frame .irc
    frame .irc.bar

    label .irc.bar.status -text "IRC" -anchor w

    button .irc.bar.disconnect \
        -text Disconnect \
        -command [list ${ns}::Disconnect "Closed"]

    button .irc.bar.hide \
        -text Hide \
        -command [list ${ns}::Hide]

    pack .irc.bar.hide .irc.bar.disconnect -side right -padx 2
    pack .irc.bar.status -side left -fill x -expand 1 -padx 4

    text .irc.out \
        -height 10 \
        -wrap word \
        -state disabled \
        -borderwidth 0 \
        -highlightthickness 0

    frame .irc.inbar

    label .irc.inbar.target -text "(no target)"
    entry .irc.inbar.entry \
        -borderwidth 0 \
        -highlightthickness 0

    pack .irc.inbar.target -side left -padx 4
    pack .irc.inbar.entry -side left -fill x -expand 1 -padx 4 -pady 2

    pack .irc.bar -fill x
    pack .irc.out -fill both -expand 1
    pack .irc.inbar -fill x

    bind .irc.inbar.entry <Return> [list ${ns}::Submit]
    bind .irc.inbar.entry <Up>     "[list ${ns}::HistoryPrev]; break"
    bind .irc.inbar.entry <Down>   "[list ${ns}::HistoryNext]; break"
}

proc ConfigureColors {} {
    if {![winfo exists .irc]} {
        return
    }

    set bg      [Theme bg          "#F5F5F5"]
    set fg      [Theme fg          "#222222"]
    set editor  [Theme editor_bg   "#FFFFFF"]
    set accent  [Theme accent      "#4A7CFE"]
    set font    [Theme font        {Consolas 11}]

    set italic_font $font
    if {[llength $font] >= 2} {
        set italic_font [list [lindex $font 0] [lindex $font 1] italic]
    }

    .irc configure -bg $bg
    .irc.bar configure -bg $bg
    .irc.inbar configure -bg $bg

    .irc.bar.status configure -bg $bg -fg $fg

    foreach child [winfo children .irc.bar] {
        catch {
            $child configure \
                -bg $bg \
                -fg $fg \
                -activebackground $bg \
                -activeforeground $fg
        }
    }

    .irc.out configure \
        -bg $editor \
        -fg $fg \
        -insertbackground $fg \
        -font $font

    .irc.inbar.target configure \
        -bg $bg \
        -fg $accent

    .irc.inbar.entry configure \
        -bg $editor \
        -fg $fg \
        -insertbackground $fg

    .irc.out tag configure server  -foreground $accent
    .irc.out tag configure error   -foreground "#D9534F"
    .irc.out tag configure join    -foreground "#5CB85C"
    .irc.out tag configure part    -foreground "#F0AD4E"
    .irc.out tag configure msg     -foreground $fg
    .irc.out tag configure self    -foreground $accent
    .irc.out tag configure private -foreground "#5A9BD5"
    .irc.out tag configure action  -foreground $accent -font $italic_font
}

proc UpdateStatus {} {
    variable connected
    variable host
    variable port
    variable mynick
    variable current_target

    if {[winfo exists .irc.bar.status]} {
        if {$connected} {
            set text "IRC: $mynick @ $host:$port"

            if {$current_target ne ""} {
                append text "  \[$current_target\]"
            }
        } else {
            set text "IRC: disconnected"
        }

        .irc.bar.status configure -text $text
    }

    if {[winfo exists .irc.inbar.target]} {
        if {$current_target eq ""} {
            .irc.inbar.target configure -text "(no target)"
        } else {
            .irc.inbar.target configure -text $current_target
        }
    }
}

proc OnTheme {args} {
    ConfigureColors
}

# ----------------------------------------------------------------------------
# Panel input history
# ----------------------------------------------------------------------------

proc HistoryAdd {line} {
    variable history
    variable hist_index

    if {[llength $history] == 0 || [lindex $history end] ne $line} {
        lappend history $line
    }

    if {[llength $history] > 200} {
        set history [lrange $history end-199 end]
    }

    set hist_index [llength $history]
}

proc HistoryPrev {} {
    variable history
    variable hist_index

    set in .irc.inbar.entry

    if {![winfo exists $in]} {
        return
    }

    set len [llength $history]

    if {$len == 0} {
        return
    }

    if {$hist_index > $len} {
        set hist_index $len
    }

    if {$hist_index > 0} {
        incr hist_index -1
    }

    $in delete 0 end
    $in insert 0 [lindex $history $hist_index]
    $in icursor end
}

proc HistoryNext {} {
    variable history
    variable hist_index

    set in .irc.inbar.entry

    if {![winfo exists $in]} {
        return
    }

    set len [llength $history]

    if {$len == 0 || $hist_index >= $len} {
        return
    }

    incr hist_index

    if {$hist_index >= $len} {
        set hist_index $len
        $in delete 0 end
    } else {
        $in delete 0 end
        $in insert 0 [lindex $history $hist_index]
        $in icursor end
    }
}

# ----------------------------------------------------------------------------
# Input submission
# ----------------------------------------------------------------------------

proc Submit {} {
    variable current_target

    set in .irc.inbar.entry

    if {![winfo exists $in]} {
        return
    }

    set line [$in get]
    $in delete 0 end

    set line [string trim $line]

    if {$line eq ""} {
        return
    }

    HistoryAdd $line

    if {[regexp {^\s*/(\S+)\s*(.*)$} $line -> cmd arg]} {
        HandleInputCommand $cmd $arg
    } else {
        SendMessage $current_target $line
    }
}

proc HandleInputCommand {cmd arg} {
    variable current_target
    variable show_names
    variable mynick

    switch -- $cmd {
        join {
            Join $arg
        }

        part {
            set parts [split $arg]
            set chan  [lindex $parts 0]
            set msg   [join [lrange $parts 1 end]]

            Part $chan $msg
        }

        me {
            SendAction $current_target $arg
        }

        msg {
            if {![regexp {^(\S+)\s+(.*)$} $arg -> target text]} {
                Output "usage: /msg target text" error
                return
            }

            SendMessage $target $text
        }

        nick {
            set newnick [string trim $arg]

            if {$newnick eq ""} {
                Output "usage: /nick newnick" error
                return
            }

            Send "NICK $newnick"
        }

        names {
            set chan [string trim $arg]

            if {$chan eq ""} {
                set chan $current_target
            }

            if {![IsChannel $chan]} {
                Output "Not a channel: $chan" error
                return
            }

            set show_names 1
            Send "NAMES $chan"
        }

        target {
            set target [string trim $arg]

            if {$target eq ""} {
                Output "Current target: $current_target" server
                return
            }

            SetTarget $target
        }

        raw {
            Send $arg
        }

        quit {
            Disconnect $arg
        }

        close {
            Disconnect "Closed"
            Hide
        }

        help {
            Output "Panel commands:" server
            Output "  /join #channel" server
            Output "  /part ?message?" server
            Output "  /me action" server
            Output "  /msg target message" server
            Output "  /nick newnick" server
            Output "  /names ?channel?" server
            Output "  /target target" server
            Output "  /raw IRC LINE" server
            Output "  /quit ?message?" server
            Output "  /close" server
        }

        default {
            Output "Unknown command: /$cmd" error
        }
    }
}

# ----------------------------------------------------------------------------
# IRC helpers
# ----------------------------------------------------------------------------

proc DefaultNick {} {
    set n ""

    catch { set n $::env(USER) }

    if {$n eq ""} {
        catch { set n [file tail $::env(USERPROFILE)] }
    }

    if {$n eq ""} {
        set n "tclmer"
    }

    regsub -all {[^A-Za-z0-9_]} $n _ n

    if {$n eq ""} {
        set n "tclmer"
    }

    return [string range $n 0 20]
}

proc NormalizeChannel {chan} {
    set chan [string trim $chan]

    if {$chan eq ""} {
        return ""
    }

    if {![string match {#*} $chan] && ![string match {&*} $chan]} {
        set chan "#$chan"
    }

    return $chan
}

proc IsChannel {target} {
    return [expr {[string match {#*} $target] || [string match {&*} $target]}]
}

proc NickFromPrefix {prefix} {
    set nick $prefix

    set bang [string first "!" $nick]

    if {$bang >= 0} {
        set nick [string range $nick 0 [expr {$bang - 1}]]
    }

    return $nick
}

proc AddTarget {target} {
    variable targets
    variable current_target

    set target [string trim $target]

    if {$target eq ""} {
        return
    }

    if {[lsearch -exact $targets $target] < 0} {
        lappend targets $target
    }

    if {$current_target eq ""} {
        set current_target $target
        UpdateStatus
    }
}

proc RemoveTarget {target} {
    variable targets
    variable current_target

    set i [lsearch -exact $targets $target]

    if {$i >= 0} {
        set targets [lreplace $targets $i $i]
    }

    if {$current_target eq $target} {
        set current_target [lindex $targets end]
        UpdateStatus
    }
}

proc SetTarget {target} {
    variable current_target

    set target [string trim $target]

    if {$target eq ""} {
        return
    }

    AddTarget $target

    set current_target $target

    Output "Target: $target" server
    UpdateStatus
}

# ----------------------------------------------------------------------------
# Connection lifecycle
# ----------------------------------------------------------------------------

proc Connect {hostname port_arg nick_arg {channel ""}} {
    variable fd
    variable connected
    variable connecting
    variable registered
    variable host
    variable port
    variable nick
    variable mynick
    variable targets
    variable current_target
    variable pending_joins

    if {$fd ne ""} {
        Disconnect "New connection"
    }

    set hostname [string trim $hostname]

    if {$hostname eq ""} {
        Output "No IRC host given" error
        return
    }

    # Allow host:port syntax.
    if {[regexp {^(.+):(\d+)$} $hostname -> h p]} {
        set hostname $h

        if {$port_arg eq "" || ![string is integer -strict $port_arg]} {
            set port_arg $p
        }
    }

    if {$port_arg eq "" || ![string is integer -strict $port_arg]} {
        set port_arg 6667
    }

    if {$nick_arg eq ""} {
        set nick_arg [DefaultNick]
    }

    regsub -all {[^A-Za-z0-9_]} $nick_arg _ nick_arg
    set nick_arg [string range $nick_arg 0 20]

    if {$nick_arg eq ""} {
        set nick_arg "tclmer"
    }

    set host           $hostname
    set port           $port_arg
    set nick           $nick_arg
    set mynick         $nick_arg
    set connected      0
    set registered     0
    set connecting     1
    set targets        {}
    set current_target ""
    set pending_joins  {}

    if {$channel ne ""} {
        lappend pending_joins [NormalizeChannel $channel]
    }

    set ns [namespace current]

    if {[catch { set fd [socket -async $host $port] } err]} {
        Output "Cannot create socket: $err" error
        set fd ""
        set connecting 0
        return
    }

    fconfigure $fd \
        -translation auto \
        -encoding utf-8 \
        -buffering line \
        -blocking 0

    fileevent $fd writable [list ${ns}::OnWritable $fd]

    Output "Connecting to $host:$port as $nick..." server
    UpdateStatus
}

proc Disconnect {{reason ""}} {
    variable fd
    variable connected
    variable registered
    variable targets
    variable current_target

    StopPing

    if {$fd ne "" && $connected} {
        catch {
            puts $fd "QUIT :$reason"
            flush $fd
        }
    }

    CloseSocket

    set connected      0
    set registered     0
    set targets        {}
    set current_target ""

    Output "Disconnected" server
    UpdateStatus
}

proc CloseSocket {} {
    variable fd

    if {$fd ne ""} {
        catch { fileevent $fd readable {} }
        catch { fileevent $fd writable {} }
        catch { close $fd }
    }

    set fd ""
}

proc OnWritable {sock} {
    variable fd
    variable connected
    variable connecting
    variable host
    variable port
    variable nick

    if {$sock ne $fd} {
        return
    }

    fileevent $sock writable {}

    set err [fconfigure $sock -error]

    if {$err ne ""} {
        Output "Connection failed: $err" error
        CloseSocket
        set connecting 0
        UpdateStatus
        return
    }

    set connecting 0
    set connected  1

    set user [string tolower $nick]

    Send "NICK $nick"
    Send "USER $user 0 * :Tclme IRC"

    Output "Connected to $host:$port" server

    fileevent $sock readable [list [namespace current]::OnReadable $sock]

    StartPing
    UpdateStatus
}

proc OnReadable {sock} {
    variable fd

    if {$sock ne $fd} {
        return
    }

    if {[eof $sock]} {
        Disconnect "Connection closed"
        return
    }

    if {[catch { gets $sock line } n]} {
        Disconnect "Read error"
        return
    }

    if {$n < 0} {
        return
    }

    ProcessLine $line
}

proc Send {line} {
    variable fd
    variable connected

    if {$fd eq "" || !$connected} {
        Output "Not connected" error
        return 0
    }

    if {[catch {
        puts $fd $line
        flush $fd
    } err]} {
        Output "Send failed: $err" error
        Disconnect "Send failed"
        return 0
    }

    return 1
}

# ----------------------------------------------------------------------------
# IRC protocol handling
# ----------------------------------------------------------------------------

proc ProcessLine {raw} {
    variable mynick
    variable registered
    variable show_names
    variable names

    set line [string trimright $raw "\r\n"]

    if {$line eq ""} {
        return
    }

    set prefix ""
    set rest $line

    if {[string index $rest 0] eq ":"} {
        set sp [string first " " $rest]

        if {$sp == -1} {
            return
        }

        set prefix [string range $rest 1 [expr {$sp - 1}]]
        set rest   [string range $rest [expr {$sp + 1}] end]
    }

    set pos [string first " :" $rest]

    set has_trailing 0
    set trailing     ""
    set before       $rest

    if {$pos >= 0} {
        set before       [string range $rest 0 [expr {$pos - 1}]]
        set trailing     [string range $rest [expr {$pos + 2}] end]
        set has_trailing 1
    }

    set parts [split $before]

    if {[llength $parts] == 0} {
        return
    }

    set cmd    [lindex $parts 0]
    set params [lrange $parts 1 end]

    if {$has_trailing} {
        lappend params $trailing
    }

    set from [NickFromPrefix $prefix]

    switch -- $cmd {
        PING {
            set payload [lindex $params 0]
            Send "PONG :$payload"
        }

        ERROR {
            Output "Server error: [join $params { }]" error
            Disconnect "Server error"
        }

        PRIVMSG {
            if {[llength $params] < 2} {
                return
            }

            set target [lindex $params 0]
            set text   [lindex $params end]

            HandlePrivmsg $from $target $text
        }

        NOTICE {
            if {[llength $params] < 2} {
                return
            }

            set text [lindex $params end]
            Output "-$from- $text" server
        }

        JOIN {
            set chan [lindex $params 0]

            if {$chan eq ""} {
                return
            }

            if {[string equal -nocase $from $mynick]} {
                AddTarget $chan
                Output "You joined $chan" join
            } else {
                Output "$from joined $chan" join
            }
        }

        PART {
            set chan [lindex $params 0]

            set msg ""
            if {[llength $params] > 1} {
                set msg [lindex $params end]
            }

            if {[string equal -nocase $from $mynick]} {
                RemoveTarget $chan
                Output "You left $chan ($msg)" part
            } else {
                Output "$from left $chan ($msg)" part
            }
        }

        QUIT {
            set msg ""
            if {[llength $params] > 0} {
                set msg [lindex $params 0]
            }

            Output "$from quit ($msg)" part
        }

        KICK {
            if {[llength $params] < 2} {
                return
            }

            set chan    [lindex $params 0]
            set kicked  [lindex $params 1]

            set reason ""
            if {[llength $params] > 2} {
                set reason [lindex $params end]
            }

            if {[string equal -nocase $kicked $mynick]} {
                RemoveTarget $chan
                Output "You were kicked from $chan by $from ($reason)" error
            } else {
                Output "$kicked was kicked from $chan by $from ($reason)" part
            }
        }

        NICK {
            set new [lindex $params 0]

            if {[string equal -nocase $from $mynick]} {
                set mynick $new
                UpdateStatus
            }

            Output "$from is now known as $new" server
        }

        TOPIC {
            set chan  [lindex $params 0]
            set topic [lindex $params end]

            Output "$from set topic on $chan: $topic" server
        }

        default {
            if {[regexp {^\d{3}$} $cmd]} {
                switch -- $cmd {
                    001 {
                        set mynick    [lindex $params 0]
                        set registered 1

                        Output [lindex $params end] server

                        JoinPending
                        UpdateStatus
                    }

                    353 {
                        if {[llength $params] < 4} {
                            return
                        }

                        set chan [lindex $params 2]
                        set n    [lindex $params end]

                        dict set names $chan $n

                        if {$show_names} {
                            Output "Names $chan: $n" server
                        }
                    }

                    366 {
                        if {$show_names} {
                            Output [lindex $params end] server
                            set show_names 0
                        }
                    }

                    433 {
                        Output "Nick in use, trying ${mynick}_" error
                        set mynick "${mynick}_"
                        Send "NICK $mynick"
                        UpdateStatus
                    }

                    default {
                        if {[string index $cmd 0] eq "4" || [string index $cmd 0] eq "5"} {
                            Output [join $params { }] error
                        }
                    }
                }
            }
        }
    }
}

proc JoinPending {} {
    variable pending_joins

    set joins $pending_joins
    set pending_joins {}

    foreach chan $joins {
        Send "JOIN $chan"
        AddTarget $chan
    }
}

proc HandlePrivmsg {from target text} {
    variable mynick
    variable current_target

    # CTCP ACTION: /me
    if {[string match "\x01ACTION *\x01" $text]} {
        set action [string range $text 8 end-1]

        if {[string equal -nocase $target $mynick]} {
            AddTarget $from
        }

        Output "* $from $action" action
        return
    }

    # Other CTCP
    if {[string match "\x01*\x01" $text]} {
        HandleCtcp $from $text
        return
    }

    if {[string equal -nocase $target $mynick]} {
        AddTarget $from

        if {$current_target eq ""} {
            set current_target $from
            UpdateStatus
        }

        Output "<$from> $text" private
    } else {
        Output "\[$target\] <$from> $text" msg
    }
}

proc HandleCtcp {from text} {
    if {[string match "\x01VERSION*\x01" $text]} {
        Send "NOTICE $from :\x01VERSION Tclme IRC plugin\x01"
    } else {
        Output "CTCP from $from: $text" server
    }
}

proc Join {chan} {
    variable connected
    variable registered
    variable pending_joins
    variable fd

    set chan [NormalizeChannel $chan]

    if {$chan eq ""} {
        return
    }

    if {!$connected} {
        if {$fd ne ""} {
            lappend pending_joins $chan
            Output "Queued join $chan" server
        } else {
            Output "Not connected" error
        }
        return
    }

    if {!$registered} {
        lappend pending_joins $chan
        return
    }

    Send "JOIN $chan"
    AddTarget $chan
}

proc Part {{chan ""} {msg ""}} {
    variable current_target

    if {$chan eq ""} {
        set chan $current_target
    }

    set chan [NormalizeChannel $chan]

    if {![IsChannel $chan]} {
        Output "Not a channel: $chan" error
        return
    }

    if {$msg eq ""} {
        set msg "Leaving"
    }

    Send "PART $chan :$msg"
}

proc SendMessage {target text} {
    variable mynick

    set target [string trim $target]
    set text   [string trim $text]

    if {$target eq ""} {
        Output "No current target. Use /join or /target first." error
        return
    }

    if {$text eq ""} {
        return
    }

    if {![Send "PRIVMSG $target :$text"]} {
        return
    }

    Output "\[$target\] <$mynick> $text" self
}

proc SendAction {target text} {
    variable mynick

    set target [string trim $target]
    set text   [string trim $text]

    if {$target eq ""} {
        Output "No current target. Use /join or /target first." error
        return
    }

    if {$text eq ""} {
        return
    }

    if {![Send "PRIVMSG $target :\x01ACTION $text\x01"]} {
        return
    }

    Output "* $mynick $text" action
}

# ----------------------------------------------------------------------------
# Keepalive ping
# ----------------------------------------------------------------------------

proc StartPing {} {
    variable ping_after

    StopPing

    set ns [namespace current]
    set ping_after [after 60000 [list ${ns}::PingTick]]
}

proc StopPing {} {
    variable ping_after

    if {$ping_after ne ""} {
        catch { after cancel $ping_after }
        set ping_after ""
    }
}

proc PingTick {} {
    variable connected

    if {$connected} {
        Send "PING :Tclme"
        StartPing
    }
}

# ----------------------------------------------------------------------------
# Tclme commands
# ----------------------------------------------------------------------------

proc PromptMaybe {label cb {completer ""}} {
    if {$completer eq ""} {
        catch { ::Tclme::Prompt $label $cb }
        return
    }

    if {[catch { ::Tclme::Prompt $label $cb $completer }]} {
        catch { ::Tclme::Prompt $label $cb }
    }
}

proc cmd-toggle {args} {
    if {[winfo exists .irc]} {
        Hide
    } else {
        Show
    }
}

proc cmd-connect {args} {
    set arg [string trim [join $args " "]]

    if {$arg eq ""} {
        Show
        PromptMaybe "IRC host: " [namespace current]::ConnectFromPrompt
        return
    }

    set parts [split $arg]

    set host    [lindex $parts 0]
    set port    [lindex $parts 1]
    set nick    [lindex $parts 2]
    set channel [lindex $parts 3]

    Connect $host $port $nick $channel
    Show
}

proc ConnectFromPrompt {host} {
    Connect $host 6667 [DefaultNick] ""
    Show
}

proc cmd-join {args} {
    set arg [string trim [join $args " "]]

    Show

    if {$arg eq ""} {
        PromptMaybe "Join channel: " [namespace current]::JoinFromPrompt
    } else {
        Join $arg
    }
}

proc JoinFromPrompt {chan} {
    Join $chan
}

proc cmd-say {args} {
    variable current_target

    set text [string trim [join $args " "]]

    if {$text eq ""} {
        return
    }

    SendMessage $current_target $text
}

proc cmd-msg {args} {
    set arg [string trim [join $args " "]]

    if {![regexp {^(\S+)\s+(.*)$} $arg -> target text]} {
        Output "usage: :irc-msg target message" error
        return
    }

    SendMessage $target $text
}

proc cmd-nick {args} {
    set newnick [string trim [join $args " "]]

    if {$newnick eq ""} {
        Output "usage: :irc-nick newnick" error
        return
    }

    Send "NICK $newnick"
}

proc cmd-names {args} {
    variable current_target
    variable show_names

    set chan [string trim [join $args " "]]

    if {$chan eq ""} {
        set chan $current_target
    }

    if {![IsChannel $chan]} {
        Output "Not a channel: $chan" error
        return
    }

    set show_names 1
    Send "NAMES $chan"
}

proc cmd-part {args} {
    set arg [string trim [join $args " "]]

    set chan ""
    set msg  ""

    if {$arg ne ""} {
        set parts [split $arg]
        set chan  [lindex $parts 0]
        set msg   [join [lrange $parts 1 end]]
    }

    Part $chan $msg
}

proc cmd-target {args} {
    variable current_target

    set target [string trim [join $args " "]]

    if {$target eq ""} {
        Output "Current target: $current_target" server
        return
    }

    SetTarget $target
}

proc cmd-quit {args} {
    set msg [string trim [join $args " "]]

    Disconnect $msg
}

proc cmd-close {args} {
    Disconnect "Closed"
    Hide
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
    variable panel_visible

    if {$panel_visible} {
        Show
    }
}

proc unload {} {
    variable load_after

    if {$load_after ne ""} {
        catch { after cancel $load_after }
        set load_after ""
    }

    Disconnect "Plugin unloaded"
    Hide
}

proc save-state {} {
    variable panel_visible

    return [dict create panel_visible $panel_visible]
}

proc restore-state {s} {
    variable panel_visible

    if {[catch { dict size $s }]} {
        return
    }

    if {[dict exists $s panel_visible]} {
        set panel_visible [dict get $s panel_visible]
    }
}

# ----------------------------------------------------------------------------
# Registration
# ----------------------------------------------------------------------------

Tclme::On theme-changed OnTheme

Tclme::DefCommand irc           cmd-toggle  "Toggle IRC panel"
Tclme::DefCommand irc-connect   cmd-connect "Connect to an IRC server"
Tclme::DefCommand irc-join      cmd-join    "Join an IRC channel"
Tclme::DefCommand irc-say       cmd-say     "Send message to current target"
Tclme::DefCommand irc-msg       cmd-msg     "Send message to a target"
Tclme::DefCommand irc-nick      cmd-nick    "Change IRC nick"
Tclme::DefCommand irc-names     cmd-names   "List names in a channel"
Tclme::DefCommand irc-part      cmd-part    "Leave a channel"
Tclme::DefCommand irc-target    cmd-target  "Set current IRC target"
Tclme::DefCommand irc-quit      cmd-quit    "Quit IRC"
Tclme::DefCommand irc-close     cmd-close   "Disconnect and hide IRC panel"