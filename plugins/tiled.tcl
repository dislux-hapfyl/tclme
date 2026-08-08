# plugins/tiled.tcl
# ============================================================================
#  Tiled buffers for Tclme.
#
#  This plugin lets you keep multiple buffers visible at once.
#
#  Commands:
#    :tile-mode          toggle tiled mode
#    :tile-split-right   split right with another buffer
#    :tile-split-below   split below with another buffer
#    :tile-open          open a file in a new pane
#    :tile-close         hide current pane, without killing the buffer
#    :tile-kill          kill current buffer
#    :tile-single        show only the current pane
#    :tile-other         focus next visible pane
#    :tile-layout        toggle left/right vs top/bottom layout
#
#  Default keybindings:
#    C-x t               toggle tiled mode
#    C-x 3               split right
#    C-x 2               split below
#    C-x 0               close/hide current pane
#    C-x 1               single pane
#    C-x o               focus next pane
#
#  Notes:
#    - This plugin wraps Tclme::SwitchToBuffer.
#    - It uses a simple one-row or one-column tiling model.
#    - Clicking in a visible tiled buffer focuses that buffer.
# ============================================================================

variable enabled       0
variable visible       {}
variable layout        "v"        ;# v = left/right, h = top/bottom
variable pending_layout ""

variable orig_switch   ""
variable installed     0

variable bindtag       "TclmeText"
variable prev_click    ""
variable bound_keys    {}
variable load_after    ""

# ----------------------------------------------------------------------------
#  Install / uninstall the SwitchToBuffer wrapper
# ----------------------------------------------------------------------------

proc Install {} {
    variable orig_switch
    variable installed

    set orig_name ::Tclme::__tiled_orig_SwitchToBuffer

    if {[info commands $orig_name] ne ""} {
        set orig_switch $orig_name
    } elseif {[info commands ::Tclme::SwitchToBuffer] ne ""} {
        rename ::Tclme::SwitchToBuffer $orig_name
        set orig_switch $orig_name
    } else {
        set orig_switch ""
        return
    }

    set ns [namespace current]

    proc ::Tclme::SwitchToBuffer {name} "${ns}::Wrapper \$name"

    set installed 1
}

proc Uninstall {} {
    variable orig_switch
    variable installed

    if {!$installed} {
        return
    }

    catch { rename ::Tclme::SwitchToBuffer {} }

    if {$orig_switch ne ""} {
        catch { rename $orig_switch ::Tclme::SwitchToBuffer }
    }

    set installed 0
}

proc Wrapper {name} {
    variable enabled
    variable orig_switch

    if {$orig_switch eq ""} {
        return
    }

    set old $::Tclme::current_buffer

    if {[catch { $orig_switch $name } err]} {
        catch { ::Tclme::Log error "tiled: switch failed: $err" }
        return
    }

    if {$enabled} {
        UpdateVisibleAfterSwitch $old $name
        Relayout
    }
}

# ----------------------------------------------------------------------------
#  Visible-buffer state
# ----------------------------------------------------------------------------

proc CleanVisible {} {
    variable visible

    set kept {}

    foreach b $visible {
        if {[dict exists $::Tclme::buffers $b] && [lsearch -exact $kept $b] < 0} {
            lappend kept $b
        }
    }

    set visible $kept
}

proc UpdateVisibleAfterSwitch {old new} {
    variable visible

    # If the target is already visible, just focus it.
    if {[lsearch -exact $visible $new] >= 0} {
        return
    }

    # Otherwise replace the old current buffer in its pane.
    set i [lsearch -exact $visible $old]

    if {$i >= 0} {
        set visible [lreplace $visible $i $i $new]
    } else {
        lappend visible $new
    }
}

# ----------------------------------------------------------------------------
#  Layout
# ----------------------------------------------------------------------------

proc Relayout {} {
    variable enabled
    variable visible
    variable layout

    if {!$enabled} {
        return
    }

    set ws .ws

    if {![winfo exists $ws]} {
        return
    }

    if {[llength $visible] == 0} {
        set visible [list $::Tclme::current_buffer]
    }

    foreach child [winfo children $ws] {
        catch { pack forget $child }
    }

    if {$layout eq "h"} {
        set side top
    } else {
        set side left
    }

    foreach name $visible {
        if {![dict exists $::Tclme::buffers $name]} {
            continue
        }

        set info [dict get $::Tclme::buffers $name]
        set c ".ws.[dict get $info wid]"

        if {[winfo exists $c]} {
            catch { pack forget $c }
            pack $c -side $side -fill both -expand 1
        }
    }

    if {[winfo exists $::Tclme::active_widget]} {
        focus $::Tclme::active_widget
    }

    catch { ::Tclme::RefreshStatus }
}

proc EnableTile {} {
    variable enabled
    variable visible

    set enabled 1

    CleanVisible

    set cur $::Tclme::current_buffer

    if {[llength $visible] == 0} {
        set visible [list $cur]
    } elseif {[lsearch -exact $visible $cur] < 0} {
        lappend visible $cur
    }

    Relayout
}

proc DisableTile {} {
    variable enabled
    variable orig_switch

    set enabled 0

    set cur $::Tclme::current_buffer

    if {$orig_switch ne ""} {
        catch { $orig_switch $cur }
    }

    catch { ::Tclme::RefreshStatus }
}

# ----------------------------------------------------------------------------
#  Commands
# ----------------------------------------------------------------------------

proc cmd-toggle {args} {
    variable enabled

    if {$enabled} {
        DisableTile
        ::Tclme::Message "Tiled mode off"
    } else {
        EnableTile
        ::Tclme::Message "Tiled mode on"
    }
}

proc cmd-layout {args} {
    variable layout
    variable enabled

    if {$layout eq "v"} {
        set layout "h"
    } else {
        set layout "v"
    }

    if {$enabled} {
        Relayout
    }

    if {$layout eq "v"} {
        ::Tclme::Message "Tiled layout: left/right"
    } else {
        ::Tclme::Message "Tiled layout: top/bottom"
    }
}

proc cmd-split-right {args} {
    variable pending_layout

    set pending_layout "v"

    set ns [namespace current]

    PromptMaybe \
        "Buffer for right pane: " \
        ${ns}::AddPaneFromPrompt \
        ${ns}::CompleteBuffer
}

proc cmd-split-below {args} {
    variable pending_layout

    set pending_layout "h"

    set ns [namespace current]

    PromptMaybe \
        "Buffer for lower pane: " \
        ${ns}::AddPaneFromPrompt \
        ${ns}::CompleteBuffer
}

proc cmd-open {args} {
    set arg [string trim [join $args " "]]

    set ns [namespace current]

    if {$arg eq ""} {
        set completer ""

        if {[info commands ::Tclme::CompleteFile] ne ""} {
            set completer ::Tclme::CompleteFile
        }

        PromptMaybe "Open in pane: " ${ns}::OpenFilePane $completer
    } else {
        OpenFilePane $arg
    }
}

proc cmd-close {args} {
    variable enabled
    variable visible
    variable orig_switch

    if {!$enabled} {
        return
    }

    set cur $::Tclme::current_buffer

    set i [lsearch -exact $visible $cur]

    if {$i >= 0} {
        set visible [lreplace $visible $i $i]
    }

    if {[llength $visible] == 0} {
        DisableTile
        ::Tclme::Message "Tiled mode off"
        return
    }

    set next [lindex $visible end]

    set saved_enabled $enabled
    set enabled 0

    if {$orig_switch ne ""} {
        catch { $orig_switch $next }
    }

    set enabled $saved_enabled

    Relayout
}

proc cmd-single {args} {
    variable enabled
    variable visible

    if {!$enabled} {
        return
    }

    set visible [list $::Tclme::current_buffer]

    Relayout
}

proc cmd-other {args} {
    variable enabled
    variable visible

    if {!$enabled || [llength $visible] < 2} {
        return
    }

    set cur $::Tclme::current_buffer
    set i [lsearch -exact $visible $cur]

    if {$i < 0} {
        set i 0
    }

    set next [lindex $visible [expr {($i + 1) % [llength $visible]}]]

    ::Tclme::SwitchToBuffer $next
}

proc cmd-kill {args} {
    ::Tclme::KillBuffer $::Tclme::current_buffer
}

# ----------------------------------------------------------------------------
#  Pane creation helpers
# ----------------------------------------------------------------------------

proc AddPaneFromPrompt {name} {
    variable pending_layout
    variable layout

    if {$pending_layout ne ""} {
        set layout $pending_layout
        set pending_layout ""
    }

    AddPane $name
}

proc AddPane {name} {
    variable enabled
    variable visible
    variable orig_switch

    set name [string trim $name]

    if {$name eq ""} {
        set name "scratch"
    }

    set cur $::Tclme::current_buffer

    if {!$enabled} {
        set enabled 1
        set visible [list $cur]
    } else {
        CleanVisible

        if {[lsearch -exact $visible $cur] < 0} {
            lappend visible $cur
        }
    }

    if {$name eq $cur} {
        Relayout
        return
    }

    if {[lsearch -exact $visible $name] >= 0} {
        ::Tclme::SwitchToBuffer $name
        Relayout
        return
    }

    if {$orig_switch eq ""} {
        return
    }

    # Bypass the wrapper so this becomes an additional pane instead of
    # replacing the current pane.
    if {[catch { $orig_switch $name } err]} {
        ::Tclme::Message "Cannot open buffer: $err"
        return
    }

    if {[lsearch -exact $visible $name] < 0} {
        lappend visible $name
    }

    Relayout
}

proc OpenFilePane {filename} {
    variable enabled
    variable visible

    set filename [string trim $filename]

    if {$filename eq ""} {
        return
    }

    set cur $::Tclme::current_buffer

    if {!$enabled} {
        set enabled 1
        set visible [list $cur]
    } else {
        CleanVisible

        if {[lsearch -exact $visible $cur] < 0} {
            lappend visible $cur
        }
    }

    set saved_enabled $enabled
    set enabled 0

    if {[catch { ::Tclme::OpenFile $filename } err]} {
        set enabled $saved_enabled
        ::Tclme::Message "Open failed: $err"
        return
    }

    set enabled $saved_enabled

    set new $::Tclme::current_buffer

    if {[lsearch -exact $visible $new] < 0} {
        lappend visible $new
    }

    Relayout
}

# ----------------------------------------------------------------------------
#  Click-to-focus
# ----------------------------------------------------------------------------

proc OnClickFocus {w} {
    variable enabled
    variable visible

    if {!$enabled} {
        return
    }

    set name [BufferForWidget $w]

    if {$name eq "" || $name eq $::Tclme::current_buffer} {
        return
    }

    if {[lsearch -exact $visible $name] >= 0} {
        ::Tclme::SwitchToBuffer $name
    }
}

proc BufferForWidget {w} {
    dict for {name info} $::Tclme::buffers {
        set txt ".ws.[dict get $info wid].txt"

        if {$txt eq $w} {
            return $name
        }
    }

    return ""
}

# ----------------------------------------------------------------------------
#  Completion / prompt helpers
# ----------------------------------------------------------------------------

proc CompleteBuffer {txt} {
    set out {}
    set plen [string length $txt]

    foreach b $::Tclme::buffer_order {
        if {[string equal -length $plen $txt $b]} {
            lappend out $b
        }
    }

    return $out
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

# ----------------------------------------------------------------------------
#  Events
# ----------------------------------------------------------------------------

proc OnBufferKilled {args} {
    variable enabled
    variable visible

    set name [lindex $args 0]

    set i [lsearch -exact $visible $name]

    if {$i >= 0} {
        set visible [lreplace $visible $i $i]

        if {$enabled} {
            Relayout
        }
    }
}


proc BindCommand {cmd keys} {
    variable bindtag
    variable bound_keys

    if {[catch { ::Tclme::BindKey $cmd $keys $bindtag }]} {
        catch { ::Tclme::BindKey $cmd $keys }
    }

    if {[lsearch -exact $bound_keys $keys] < 0} {
        lappend bound_keys $keys
    }
}

# ----------------------------------------------------------------------------
#  Lifecycle
# ----------------------------------------------------------------------------

proc load {} {
    variable bindtag
    variable prev_click
    variable load_after

    Install

    set bindtag "TclmeText"

    BindCommand tile-mode        <Control-x>t
    BindCommand tile-split-right <Control-x>3
    BindCommand tile-split-below <Control-x>2
    BindCommand tile-close       <Control-x>0
    BindCommand tile-single      <Control-x>1
    BindCommand tile-other       <Control-x>o

    # Click-to-focus binding.
    set ns  [namespace current]
    set old [bind $bindtag <ButtonRelease-1>]

    if {[string first $ns $old] >= 0} {
        set old ""
    }

    set prev_click $old

    set script [list ${ns}::OnClickFocus %W]

    if {$old ne ""} {
        append script "; $old"
    }

    bind $bindtag <ButtonRelease-1> $script

    set load_after [after idle [list ${ns}::ApplyState]]
}

proc unload {} {
    variable bound_keys
    variable bindtag
    variable prev_click
    variable load_after
    variable enabled
    variable orig_switch

    if {$load_after ne ""} {
        catch { after cancel $load_after }
        set load_after ""
    }

    catch { bind $bindtag <ButtonRelease-1> $prev_click }

    foreach tag [list $bindtag TclmeText CoreText] {
        foreach keys $bound_keys {
            catch { bind $tag $keys {} }
        }
    }

    set bound_keys {}

    if {$enabled} {
        set cur $::Tclme::current_buffer
        set enabled 0

        if {$orig_switch ne ""} {
            catch { $orig_switch $cur }
        }
    }

    Uninstall
}

proc ApplyState {} {
    variable load_after ""
    variable enabled
    variable visible

    if {!$enabled} {
        return
    }

    CleanVisible

    set cur $::Tclme::current_buffer

    if {[llength $visible] == 0} {
        set visible [list $cur]
    } elseif {[lsearch -exact $visible $cur] < 0} {
        lappend visible $cur
    }

    Relayout
}

proc save-state {} {
    variable enabled
    variable visible
    variable layout

    return [dict create \
        enabled $enabled \
        visible $visible \
        layout $layout \
    ]
}

proc restore-state {s} {
    variable enabled
    variable visible
    variable layout

    if {[catch { dict size $s }]} {
        return
    }

    if {[dict exists $s enabled]} {
        set enabled [dict get $s enabled]
    }

    if {[dict exists $s visible]} {
        set visible [dict get $s visible]
    }

    if {[dict exists $s layout]} {
        set layout [dict get $s layout]
    }
}

# ----------------------------------------------------------------------------
#  Registration
# ----------------------------------------------------------------------------

Tclme::On buffer-killed OnBufferKilled

Tclme::DefCommand tile-mode        cmd-toggle      "Toggle tiled buffer mode"
Tclme::DefCommand tile-split-right cmd-split-right "Split right with another buffer"
Tclme::DefCommand tile-split-below cmd-split-below "Split below with another buffer"
Tclme::DefCommand tile-open        cmd-open        "Open a file in a new tiled pane"
Tclme::DefCommand tile-close       cmd-close       "Hide current tiled pane"
Tclme::DefCommand tile-kill        cmd-kill        "Kill current tiled buffer"
Tclme::DefCommand tile-single      cmd-single      "Show only current tiled pane"
Tclme::DefCommand tile-other       cmd-other       "Focus next tiled pane"
Tclme::DefCommand tile-layout      cmd-layout      "Toggle tiled layout direction"

if {[info commands ::Tclme::DefAlias] ne ""} {
    catch { ::Tclme::DefAlias tile tile-mode }
}