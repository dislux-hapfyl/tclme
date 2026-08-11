# plugins/circuit.tcl

Tclme::Plugin {
    description "Circuit designer in a Tclme buffer"
    version 0.1.0
    headless ui

    state {
        components {}
        wires {}
        seq 1
    }

    command circuit {args} {
        if {[::Tclme::IsHeadless]} {
            ::Tclme::Message "circuit requires the Tclme GUI"
            return
        }
        open_ui
    } "Open the circuit designer buffer"

    command circuit-netlist {args} {
        export_netlist_buffer
    } "Generate a netlist for the current circuit"

    command circuit-save {args} {
        save_prompt
    } "Save circuit to a file"

    command circuit-open {args} {
        open_prompt
    } "Open circuit from a file"

    bind <Control-x><Alt-d> circuit

    init {
        variable state

        foreach {k v} {
            components {}
            wires {}
            seq 1
        } {
            if {![dict exists $state $k]} {
                dict set state $k $v
            }
        }
    }

    cleanup {
        catch { clear_buffer }
        catch { destroy_ui }
    }

    do {
        variable buffer_name "*Circuit*"
        variable ui_frame ""
        variable canvas ""
        variable status_path ""

        variable mode select
        variable selected_id ""
        variable drag_orig {}

        variable press_x 0
        variable press_y 0
        variable last_x 0
        variable last_y 0

        variable wire_start_x 0
        variable wire_start_y 0
        variable temp_line ""

        # --------------------------------------------------------------------
        # UI lifecycle
        # --------------------------------------------------------------------

        proc open_ui {} {
            variable buffer_name

            ::Tclme::SwitchToBuffer $buffer_name

            set txt [::Tclme::WidgetForBuffer $buffer_name]
            if {$txt eq ""} {
                ::Tclme::Message "Cannot create circuit buffer"
                return
            }

            build_ui $txt

            catch {
                dict set ::Tclme::buffers $buffer_name readonly 1
            }

            status "Circuit designer ready"
        }

        proc clear_buffer {} {
            variable buffer_name

            set txt [::Tclme::WidgetForBuffer $buffer_name]
            if {$txt eq ""} {
                return
            }

            catch {
                set old [$txt cget -state]
                $txt configure -state normal
                $txt delete 1.0 end
                $txt configure -state $old
            }
        }

        proc destroy_ui {} {
            variable ui_frame
            variable canvas
            variable status_path

            if {[winfo exists $ui_frame]} {
                destroy $ui_frame
            }

            set ui_frame ""
            set canvas ""
            set status_path ""
        }

        proc build_ui {txt} {
            variable ui_frame
            variable canvas
            variable status_path
            variable mode

            destroy_ui

            $txt configure -state normal
            $txt delete 1.0 end

            set f $txt.circuit_ui
            frame $f

            # ----------------------------------------------------------------
            # Toolbar
            # ----------------------------------------------------------------

            frame $f.tools

            set mode_var [namespace current]::mode

            radiobutton $f.tools.select \
                -text "Select" \
                -variable $mode_var \
                -value select \
                -command [namespace code mode_changed]

            radiobutton $f.tools.wire \
                -text "Wire" \
                -variable $mode_var \
                -value wire \
                -command [namespace code mode_changed]

            radiobutton $f.tools.node \
                -text "Node" \
                -variable $mode_var \
                -value node \
                -command [namespace code mode_changed]

            radiobutton $f.tools.resistor \
                -text "Resistor" \
                -variable $mode_var \
                -value resistor \
                -command [namespace code mode_changed]

            radiobutton $f.tools.battery \
                -text "Battery" \
                -variable $mode_var \
                -value battery \
                -command [namespace code mode_changed]

            radiobutton $f.tools.led \
                -text "LED" \
                -variable $mode_var \
                -value led \
                -command [namespace code mode_changed]

            button $f.tools.delete \
                -text "Delete" \
                -command [namespace code delete_selected]

            button $f.tools.clear \
                -text "Clear" \
                -command [namespace code clear_all]

            button $f.tools.netlist \
                -text "Netlist" \
                -command [namespace code export_netlist_buffer]

            button $f.tools.save \
                -text "Save" \
                -command [namespace code save_prompt]

            button $f.tools.open \
                -text "Open" \
                -command [namespace code open_prompt]

            button $f.tools.close \
                -text "Close" \
                -command [namespace code close_buffer]

            grid $f.tools.select \
                 $f.tools.wire \
                 $f.tools.node \
                 $f.tools.resistor \
                 $f.tools.battery \
                 $f.tools.led \
                 -sticky w -padx 4 -pady 2

            grid $f.tools.delete \
                 $f.tools.clear \
                 $f.tools.netlist \
                 $f.tools.save \
                 $f.tools.open \
                 $f.tools.close \
                 -sticky w -padx 4 -pady 2

            pack $f.tools -fill x

            # ----------------------------------------------------------------
            # Canvas
            # ----------------------------------------------------------------

            frame $f.canvas_frame

            set c $f.canvas_frame.canvas

            canvas $c \
                -width 900 \
                -height 560 \
                -bg white \
                -highlightthickness 0 \
                -scrollregion {0 0 1600 1200}

            scrollbar $f.canvas_frame.vs \
                -orient vertical \
                -command [list $c yview]

            scrollbar $f.canvas_frame.hs \
                -orient horizontal \
                -command [list $c xview]

            $c configure -xscrollcommand [list $f.canvas_frame.hs set]
            $c configure -yscrollcommand [list $f.canvas_frame.vs set]

            grid $c -row 0 -column 0 -sticky nsew
            grid $f.canvas_frame.vs -row 0 -column 1 -sticky ns
            grid $f.canvas_frame.hs -row 1 -column 0 -sticky ew

            grid columnconfigure $f.canvas_frame 0 -weight 1
            grid rowconfigure $f.canvas_frame 0 -weight 1

            pack $f.canvas_frame -fill both -expand 1

            # ----------------------------------------------------------------
            # Status line
            # ----------------------------------------------------------------

            label $f.status -text "" -anchor w -relief sunken
            pack $f.status -fill x

            # ----------------------------------------------------------------
            # Embed into the Tclme buffer
            # ----------------------------------------------------------------

            if {[catch {
                $txt window create end -window $f -stretch 1 -padx 4 -pady 4
            }]} {
                $txt window create end -window $f
            }

            catch { $txt edit modified 0 }
            $txt configure -state disabled

            set ui_frame $f
            set canvas $c
            set status_path $f.status

            set ns [namespace current]

            bind $c <Button-1> [list ${ns}::canvas_press $c %x %y]
            bind $c <B1-Motion> [list ${ns}::canvas_drag $c %x %y]
            bind $c <ButtonRelease-1> [list ${ns}::canvas_release $c %x %y]

            draw_all
            mode_changed
        }

        proc close_buffer {} {
            variable buffer_name
            catch { ::Tclme::KillBuffer $buffer_name }
        }

        proc status {msg} {
            variable status_path

            if {[winfo exists $status_path]} {
                $status_path configure -text $msg
            }
        }

        proc mode_changed {} {
            variable mode
            status "Mode: $mode"
        }

        # --------------------------------------------------------------------
        # Canvas interaction
        # --------------------------------------------------------------------

        proc snap {v} {
            return [expr {int(round(double($v) / 10.0) * 10)}]
        }

        proc canvas_press {c x y} {
            variable mode
            variable press_x
            variable press_y
            variable last_x
            variable last_y
            variable selected_id
            variable drag_orig
            variable temp_line
            variable wire_start_x
            variable wire_start_y
            variable state

            set x [$c canvasx $x]
            set y [$c canvasy $y]

            set x [snap $x]
            set y [snap $y]

            set press_x $x
            set press_y $y
            set last_x $x
            set last_y $y

            switch -exact -- $mode {
                select {
                    set id [find_item_at $c $x $y]
                    select_item $id

                    set drag_orig {}

                    if {$id ne ""} {
                        if {[dict exists $state components $id]} {
                            set drag_orig [dict get $state components $id]
                        } elseif {[dict exists $state wires $id]} {
                            set drag_orig [dict get $state wires $id]
                        }
                    }
                }

                wire {
                    set wire_start_x $x
                    set wire_start_y $y

                    set temp_line [$c create line \
                        $x $y $x $y \
                        -fill #268bd2 \
                        -width 2 \
                        -dash {4 2} \
                    ]
                }

                node -
                resistor -
                battery -
                led {
                    place_component $mode $x $y
                }
            }
        }

        proc canvas_drag {c x y} {
            variable mode
            variable last_x
            variable last_y
            variable selected_id
            variable temp_line
            variable wire_start_x
            variable wire_start_y

            set x [$c canvasx $x]
            set y [$c canvasy $y]

            if {$mode eq "select" && $selected_id ne ""} {
                set dx [expr {$x - $last_x}]
                set dy [expr {$y - $last_y}]

                if {$dx != 0 || $dy != 0} {
                    $c move item_$selected_id $dx $dy
                }
            } elseif {$mode eq "wire" && $temp_line ne ""} {
                $c coords $temp_line $wire_start_x $wire_start_y $x $y
            }

            set last_x $x
            set last_y $y
        }

        proc canvas_release {c x y} {
            variable mode
            variable press_x
            variable press_y
            variable selected_id
            variable drag_orig
            variable temp_line
            variable wire_start_x
            variable wire_start_y
            variable state

            set x [$c canvasx $x]
            set y [$c canvasy $y]

            set x [snap $x]
            set y [snap $y]

            if {$mode eq "select" && $selected_id ne ""} {
                set dx [expr {$x - $press_x}]
                set dy [expr {$y - $press_y}]

                if {[dict exists $state components $selected_id]} {
                    if {[dict size $drag_orig] > 0} {
                        set nx [snap [expr {[dict get $drag_orig x] + $dx}]]
                        set ny [snap [expr {[dict get $drag_orig y] + $dy}]]

                        dict set state components $selected_id x $nx
                        dict set state components $selected_id y $ny
                    }

                    $c delete item_$selected_id
                    draw_component $selected_id
                } elseif {[dict exists $state wires $selected_id]} {
                    if {[dict size $drag_orig] > 0} {
                        set nx1 [snap [expr {[dict get $drag_orig x1] + $dx}]]
                        set ny1 [snap [expr {[dict get $drag_orig y1] + $dy}]]
                        set nx2 [snap [expr {[dict get $drag_orig x2] + $dx}]]
                        set ny2 [snap [expr {[dict get $drag_orig y2] + $dy}]]

                        dict set state wires $selected_id x1 $nx1
                        dict set state wires $selected_id y1 $ny1
                        dict set state wires $selected_id x2 $nx2
                        dict set state wires $selected_id y2 $ny2
                    }

                    $c delete item_$selected_id
                    draw_wire $selected_id
                }
            } elseif {$mode eq "wire" && $temp_line ne ""} {
                $c delete $temp_line
                set temp_line ""

                set dist [expr {
                    abs($x - $wire_start_x) + abs($y - $wire_start_y)
                }]

                if {$dist >= 10} {
                    create_wire $wire_start_x $wire_start_y $x $y
                }
            }

            set drag_orig {}
        }

        proc find_item_at {c x y} {
            set ids [$c find overlapping \
                [expr {$x - 5}] [expr {$y - 5}] \
                [expr {$x + 5}] [expr {$y + 5}] \
            ]

            foreach id $ids {
                foreach tag [$c gettags $id] {
                    if {[regexp {^item_(.+)$} $tag -> logical_id]} {
                        return $logical_id
                    }
                }
            }

            return ""
        }

        proc select_item {id} {
            variable selected_id

            set selected_id $id

            if {$id eq ""} {
                status "No selection"
            } else {
                status "Selected: $id"
            }
        }

        proc delete_selected {} {
            variable selected_id

            if {$selected_id eq ""} {
                status "Nothing selected"
                return
            }

            delete_item $selected_id
        }

        proc delete_item {id} {
            variable state
            variable canvas
            variable selected_id

            if {[dict exists $state components $id]} {
                dict unset state components $id
            }

            if {[dict exists $state wires $id]} {
                dict unset state wires $id
            }

            if {[winfo exists $canvas]} {
                $canvas delete item_$id
            }

            if {$selected_id eq $id} {
                set selected_id ""
            }

            status "Deleted $id"
        }

        proc clear_all {} {
            variable state
            variable canvas
            variable selected_id

            dict set state components {}
            dict set state wires {}

            set selected_id ""

            if {[winfo exists $canvas]} {
                $canvas delete circuit_item
            }

            status "Circuit cleared"
        }

        # --------------------------------------------------------------------
        # Circuit model
        # --------------------------------------------------------------------

        proc new_id {prefix} {
            variable state

            set n [dict get $state seq]
            dict set state seq [expr {$n + 1}]

            return "$prefix$n"
        }

        proc place_component {type x y} {
            variable state

            set x [snap $x]
            set y [snap $y]

            switch -exact -- $type {
                resistor {
                    set prefix R
                    set value 1k
                }

                battery {
                    set prefix V
                    set value 5V
                }

                led {
                    set prefix D
                    set value LED
                }

                node {
                    set prefix N
                    set value ""
                }

                default {
                    return
                }
            }

            set id [new_id $prefix]

            dict set state components $id [dict create \
                type $type \
                x $x \
                y $y \
                label $id \
                value $value \
            ]

            draw_component $id
            select_item $id

            status "Placed $id at $x,$y"
        }

        proc create_wire {x1 y1 x2 y2} {
            variable state

            set x1 [snap $x1]
            set y1 [snap $y1]
            set x2 [snap $x2]
            set y2 [snap $y2]

            if {$x1 == $x2 && $y1 == $y2} {
                return
            }

            set id [new_id W]

            dict set state wires $id [dict create \
                x1 $x1 \
                y1 $y1 \
                x2 $x2 \
                y2 $y2 \
            ]

            draw_wire $id

            status "Added wire $id"
        }

        # --------------------------------------------------------------------
        # Drawing
        # --------------------------------------------------------------------

        proc draw_all {} {
            variable canvas
            variable state

            if {![winfo exists $canvas]} {
                return
            }

            $canvas delete circuit_item

            dict for {id w} [dict get $state wires] {
                draw_wire $id
            }

            dict for {id comp} [dict get $state components] {
                draw_component $id
            }
        }

        proc draw_wire {id} {
            variable canvas
            variable state

            if {![winfo exists $canvas]} {
                return
            }

            if {![dict exists $state wires $id]} {
                return
            }

            set w [dict get $state wires $id]

            $canvas create line \
                [dict get $w x1] [dict get $w y1] \
                [dict get $w x2] [dict get $w y2] \
                -fill #0055aa \
                -width 2 \
                -tags [list circuit_item item_$id wire]
        }

        proc draw_component {id} {
            variable canvas
            variable state

            if {![winfo exists $canvas]} {
                return
            }

            if {![dict exists $state components $id]} {
                return
            }

            set comp [dict get $state components $id]

            set type [dict get $comp type]
            set x [dict get $comp x]
            set y [dict get $comp y]
            set label [dict get $comp label]
            set value [dict get $comp value]

            set tag [list circuit_item item_$id component $type]

            switch -exact -- $type {
                resistor {
                    $canvas create line \
                        [expr {$x - 30}] $y \
                        [expr {$x - 20}] $y \
                        -fill black -width 2 -tags $tag

                    $canvas create rectangle \
                        [expr {$x - 20}] [expr {$y - 8}] \
                        [expr {$x + 20}] [expr {$y + 8}] \
                        -fill white -outline black -tags $tag

                    $canvas create line \
                        [expr {$x + 20}] $y \
                        [expr {$x + 30}] $y \
                        -fill black -width 2 -tags $tag

                    $canvas create text \
                        $x [expr {$y - 16}] \
                        -text "$label $value" \
                        -anchor s \
                        -tags $tag
                }

                battery {
                    $canvas create line \
                        [expr {$x - 20}] $y \
                        [expr {$x - 6}] $y \
                        -fill black -width 2 -tags $tag

                    $canvas create line \
                        [expr {$x - 6}] [expr {$y - 14}] \
                        [expr {$x - 6}] [expr {$y + 14}] \
                        -fill black -width 4 -tags $tag

                    $canvas create line \
                        [expr {$x + 6}] [expr {$y - 7}] \
                        [expr {$x + 6}] [expr {$y + 7}] \
                        -fill black -width 4 -tags $tag

                    $canvas create line \
                        [expr {$x + 6}] $y \
                        [expr {$x + 20}] $y \
                        -fill black -width 2 -tags $tag

                    $canvas create text \
                        $x [expr {$y - 22}] \
                        -text "$label $value" \
                        -anchor s \
                        -tags $tag
                }

                led {
                    $canvas create line \
                        [expr {$x - 20}] $y \
                        [expr {$x - 10}] $y \
                        -fill black -width 2 -tags $tag

                    $canvas create polygon \
                        [list \
                            [expr {$x - 10}] [expr {$y - 10}] \
                            [expr {$x - 10}] [expr {$y + 10}] \
                            [expr {$x + 10}] $y \
                        ] \
                        -outline black -fill white -tags $tag

                    $canvas create line \
                        [expr {$x + 10}] [expr {$y - 10}] \
                        [expr {$x + 10}] [expr {$y + 10}] \
                        -fill black -width 3 -tags $tag

                    $canvas create line \
                        [expr {$x + 10}] $y \
                        [expr {$x + 20}] $y \
                        -fill black -width 2 -tags $tag

                    $canvas create line \
                        $x [expr {$y - 14}] \
                        [expr {$x + 8}] [expr {$y - 22}] \
                        -arrow last -fill black -tags $tag

                    $canvas create line \
                        [expr {$x + 8}] [expr {$y - 10}] \
                        [expr {$x + 16}] [expr {$y - 18}] \
                        -arrow last -fill black -tags $tag

                    $canvas create text \
                        $x [expr {$y - 28}] \
                        -text "$label $value" \
                        -anchor s \
                        -tags $tag
                }

                node {
                    $canvas create oval \
                        [expr {$x - 4}] [expr {$y - 4}] \
                        [expr {$x + 4}] [expr {$y + 4}] \
                        -fill black -outline black -tags $tag
                }
            }
        }

        # --------------------------------------------------------------------
        # Netlist generation
        # --------------------------------------------------------------------

        proc point {x y} {
            return "$x,$y"
        }

        proc comp_pins {comp} {
            set type [dict get $comp type]
            set x [dict get $comp x]
            set y [dict get $comp y]

            switch -exact -- $type {
                resistor {
                    return [list \
                        [point [expr {$x - 30}] $y] \
                        [point [expr {$x + 30}] $y] \
                    ]
                }

                battery {
                    return [list \
                        [point [expr {$x - 20}] $y] \
                        [point [expr {$x + 20}] $y] \
                    ]
                }

                led {
                    return [list \
                        [point [expr {$x - 20}] $y] \
                        [point [expr {$x + 20}] $y] \
                    ]
                }

                node {
                    return [list [point $x $y]]
                }
            }

            return {}
        }

        proc uf_find {parentvar x} {
            upvar 1 $parentvar parent

            if {![info exists parent($x)]} {
                set parent($x) $x
                return $x
            }

            set root $x

            while {$parent($root) ne $root} {
                set root $parent($root)
            }

            while {$parent($x) ne $root} {
                set next $parent($x)
                set parent($x) $root
                set x $next
            }

            return $root
        }

        proc uf_union {parentvar a b} {
            upvar 1 $parentvar parent

            set ra [uf_find $parentvar $a]
            set rb [uf_find $parentvar $b]

            if {$ra ne $rb} {
                set parent($ra) $rb
            }
        }

        proc generate_netlist {} {
            variable state

            array set parent {}

            # Wires connect their endpoints.
            dict for {id w} [dict get $state wires] {
                set p1 [point [dict get $w x1] [dict get $w y1]]
                set p2 [point [dict get $w x2] [dict get $w y2]]

                if {![info exists parent($p1)]} {
                    set parent($p1) $p1
                }

                if {![info exists parent($p2)]} {
                    set parent($p2) $p2
                }

                uf_union parent $p1 $p2
            }

            # Component pins become points.
            dict for {id comp} [dict get $state components] {
                foreach p [comp_pins $comp] {
                    if {![info exists parent($p)]} {
                        set parent($p) $p
                    }
                }
            }

            # Assign net names to union-find roots.
            set netnames [dict create]
            set counter 1

            foreach p [array names parent] {
                set r [uf_find parent $p]

                if {![dict exists $netnames $r]} {
                    dict set netnames $r "N$counter"
                    incr counter
                }
            }

            set lines [list "; Tclme circuit netlist" ""]

            dict for {id comp} [dict get $state components] {
                set type [dict get $comp type]

                if {$type eq "node"} {
                    continue
                }

                set label [dict get $comp label]
                set value [dict get $comp value]

                set nets {}

                foreach p [comp_pins $comp] {
                    set r [uf_find parent $p]
                    lappend nets [dict get $netnames $r]
                }

                if {[llength $nets] == 2} {
                    lappend lines [format "%s %s %s %s" \
                        $label \
                        [lindex $nets 0] \
                        [lindex $nets 1] \
                        $value \
                    ]
                } elseif {[llength $nets] == 1} {
                    lappend lines [format "%s %s %s" \
                        $label \
                        [lindex $nets 0] \
                        $value \
                    ]
                } else {
                    lappend lines "; $label has no pins"
                }
            }

            return [join $lines \n]
        }

        proc export_netlist_buffer {} {
            set text [generate_netlist]
            ::Tclme::ShowInBuffer "*Circuit Netlist*" $text 1
        }

        # --------------------------------------------------------------------
        # Save / load
        # --------------------------------------------------------------------

        proc save_prompt {} {
            set cb [namespace current]::save_circuit_to_file
            ::Tclme::Prompt "Save circuit: " $cb ::Tclme::CompleteFile
        }

        proc open_prompt {} {
            set cb [namespace current]::load_circuit_from_file
            ::Tclme::Prompt "Open circuit: " $cb ::Tclme::CompleteFile
        }

        proc save_circuit_to_file {filename} {
            variable state

            set filename [string trim $filename]

            if {$filename eq ""} {
                ::Tclme::Message "Save cancelled"
                return
            }

            set data [dict create \
                version 1 \
                components [dict get $state components] \
                wires [dict get $state wires] \
                seq [dict get $state seq] \
            ]

            if {[catch {
                set fp [open $filename w]
                fconfigure $fp -encoding utf-8
                puts $fp $data
                close $fp
            } err]} {
                ::Tclme::Log error "circuit save: $err"
                return
            }

            ::Tclme::Message "Wrote $filename"
        }

        proc load_circuit_from_file {filename} {
            variable state
            variable canvas

            set filename [string trim $filename]

            if {$filename eq ""} {
                ::Tclme::Message "Open cancelled"
                return
            }

            if {[catch {
                set fp [open $filename r]
                fconfigure $fp -encoding utf-8
                set data [read $fp]
                close $fp
            } err]} {
                ::Tclme::Log error "circuit open: $err"
                return
            }

            if {[catch {dict size $data}]} {
                ::Tclme::Message "Not a circuit file"
                return
            }

            set components {}
            set wires {}
            set seq 1

            if {[dict exists $data components]} {
                set components [dict get $data components]
            }

            if {[dict exists $data wires]} {
                set wires [dict get $data wires]
            }

            if {[dict exists $data seq]} {
                set seq [dict get $data seq]
            }

            dict set state components $components
            dict set state wires $wires
            dict set state seq $seq

            if {[winfo exists $canvas]} {
                draw_all
            } else {
                catch { open_ui }
            }

            ::Tclme::Message "Loaded $filename"
        }
    }

    do {
        catch { ::Tclme::DefAlias cir circuit }
        catch { ::Tclme::DefAlias cnet circuit-netlist }
        catch { ::Tclme::DefAlias csave circuit-save }
        catch { ::Tclme::DefAlias copen circuit-open }
    }
}
