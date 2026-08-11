# plugins/budget.tcl

Tclme::Plugin {
    description "Spreadsheet / budget buffer with basic formula support"
    version 0.1.0
    headless ui

    state {
        rows 30
        cols 10
        cells {}
    }

    command budget {args} {
        if {[::Tclme::IsHeadless]} {
            ::Tclme::Message "budget requires the Tclme GUI"
            return
        }
        open_ui
    } "Open the spreadsheet/budget buffer"

    command budget-save {args} {
        save_prompt
    } "Save budget to a file"

    command budget-open {args} {
        open_prompt
    } "Open budget from a file"

    command budget-csv {args} {
        export_csv_buffer
    } "Export current budget to a CSV buffer"

    bind <Control-x><Alt-b> budget

    init {
        variable state

        foreach {k v} {
            rows 30
            cols 10
            cells {}
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
        variable buffer_name "*Budget*"
        variable ui_frame ""
        variable status_path ""

        variable cellvar
        variable value_cache [dict create]
        variable computing [dict create]

        # --------------------------------------------------------------------
        # UI lifecycle
        # --------------------------------------------------------------------

        proc open_ui {} {
            variable buffer_name

            ::Tclme::SwitchToBuffer $buffer_name

            set txt [::Tclme::WidgetForBuffer $buffer_name]
            if {$txt eq ""} {
                ::Tclme::Message "Cannot create budget buffer"
                return
            }

            build_ui $txt

            catch {
                dict set ::Tclme::buffers $buffer_name readonly 1
            }

            status "Budget ready. Formulas start with ="
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
            variable status_path

            if {[winfo exists $ui_frame]} {
                destroy $ui_frame
            }

            set ui_frame ""
            set status_path ""
        }

        proc build_ui {txt} {
            variable ui_frame
            variable status_path
            variable state
            variable cellvar

            destroy_ui

            $txt configure -state normal
            $txt delete 1.0 end

            set f $txt.budget_ui
            frame $f

            set rows [dict get $state rows]
            set cols [dict get $state cols]

            # ----------------------------------------------------------------
            # Toolbar
            # ----------------------------------------------------------------

            frame $f.tools

            button $f.tools.recompute \
                -text "Recompute" \
                -command [namespace code recompute_ui]

            button $f.tools.sample \
                -text "Sample Budget" \
                -command [namespace code load_sample]

            button $f.tools.csv \
                -text "CSV" \
                -command [namespace code export_csv_buffer]

            button $f.tools.save \
                -text "Save" \
                -command [namespace code save_prompt]

            button $f.tools.open \
                -text "Open" \
                -command [namespace code open_prompt]

            button $f.tools.clear \
                -text "Clear" \
                -command [namespace code clear_all]

            button $f.tools.close \
                -text "Close" \
                -command [namespace code close_buffer]

            pack $f.tools.recompute \
                 $f.tools.sample \
                 $f.tools.csv \
                 $f.tools.save \
                 $f.tools.open \
                 $f.tools.clear \
                 $f.tools.close \
                 -side left -padx 4 -pady 2

            pack $f.tools -fill x

            # ----------------------------------------------------------------
            # Spreadsheet grid
            # ----------------------------------------------------------------

            frame $f.grid

            set ns [namespace current]

            label $f.grid.corner -text "" -width 3
            grid $f.grid.corner -row 0 -column 0 -sticky nsew

            for {set c 1} {$c <= $cols} {incr c} {
                set colname [num_to_col $c]

                label $f.grid.col_$colname \
                    -text $colname \
                    -width 12 \
                    -anchor center

                grid $f.grid.col_$colname \
                    -row 0 -column $c -sticky nsew
            }

            for {set r 1} {$r <= $rows} {incr r} {
                label $f.grid.row_$r \
                    -text $r \
                    -width 3 \
                    -anchor e

                grid $f.grid.row_$r -row $r -column 0 -sticky nsew

                for {set c 1} {$c <= $cols} {incr c} {
                    set colname [num_to_col $c]
                    set cell "${colname}${r}"

                    set e $f.grid.e_$cell

                    entry $e \
                        -textvariable ${ns}::cellvar($cell) \
                        -width 12 \
                        -justify right

                    bind $e <FocusIn> [list ${ns}::cell_focus_in $cell $e]
                    bind $e <FocusOut> [list ${ns}::cell_commit $cell]
                    bind $e <Return> [list ${ns}::cell_return $cell $e]
                    bind $e <KP_Enter> [list ${ns}::cell_return $cell $e]

                    grid $e -row $r -column $c -sticky nsew
                }
            }

            pack $f.grid -fill both -expand 1

            # ----------------------------------------------------------------
            # Status
            # ----------------------------------------------------------------

            label $f.status -text "" -anchor w -relief sunken
            pack $f.status -fill x

            # ----------------------------------------------------------------
            # Embed into buffer
            # ----------------------------------------------------------------

            if {[catch {
                $txt window create end -window $f -stretch 1 -padx 4 -pady 4
            }]} {
                $txt window create end -window $f
            }

            catch { $txt edit modified 0 }
            $txt configure -state disabled

            set ui_frame $f
            set status_path $f.status

            recompute_all
            refresh_all
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

        proc recompute_ui {} {
            recompute_all
            refresh_all
            status "Recalculated"
        }

        # --------------------------------------------------------------------
        # Cell editing
        # --------------------------------------------------------------------

        proc cell_focus_in {cell w} {
            variable cellvar

            set raw [cell_raw $cell]
            set cellvar($cell) $raw

            catch {
                $w selection range 0 end
                $w icursor end
            }
        }

        proc cell_commit {cell} {
            variable cellvar
            variable state

            if {![info exists cellvar($cell)]} {
                return
            }

            set raw [string trim $cellvar($cell)]

            if {$raw eq ""} {
                if {[dict exists $state cells $cell]} {
                    dict unset state cells $cell
                }
            } else {
                dict set state cells $cell $raw
            }

            recompute_all
            refresh_all

            status "Cell $cell updated"
        }

        proc cell_return {cell w} {
            cell_commit $cell

            set below [cell_below $cell]
            if {$below eq ""} {
                return
            }

            set parent [winfo parent $w]
            set next $parent.e_$below

            if {[winfo exists $next]} {
                focus $next
            }
        }

        proc cell_below {cell} {
            variable state

            if {![regexp {^([A-Z]+)([0-9]+)$} $cell -> col row]} {
                return ""
            }

            set row [expr {$row + 1}]

            if {$row > [dict get $state rows]} {
                return ""
            }

            return "${col}${row}"
        }

        # --------------------------------------------------------------------
        # Model helpers
        # --------------------------------------------------------------------

        proc cell_raw {cell} {
            variable state

            if {[dict exists $state cells $cell]} {
                return [dict get $state cells $cell]
            }

            return ""
        }

        proc is_number {s} {
            return [string is double -strict $s]
        }

        proc recompute_all {} {
            variable value_cache
            variable computing

            set value_cache [dict create]
            set computing [dict create]
        }

        proc refresh_all {} {
            variable state
            variable cellvar

            set rows [dict get $state rows]
            set cols [dict get $state cols]

            for {set r 1} {$r <= $rows} {incr r} {
                for {set c 1} {$c <= $cols} {incr c} {
                    set cell "[num_to_col $c]$r"
                    set cellvar($cell) [cell_display $cell]
                }
            }
        }

        proc cell_display {cell} {
            set raw [cell_raw $cell]

            if {$raw eq ""} {
                return ""
            }

            if {[string match =* $raw]} {
                if {[catch {eval_formula $raw} result]} {
                    if {[string match *CYCLE* $result]} {
                        return "#CYCLE"
                    }
                    return "#ERR"
                }

                return [format_number $result]
            }

            if {[is_number $raw]} {
                return $raw
            }

            return $raw
        }

        proc cell_numeric {cell} {
            variable value_cache
            variable computing

            if {[dict exists $value_cache $cell]} {
                return [dict get $value_cache $cell]
            }

            if {[dict exists $computing $cell]} {
                error "#CYCLE"
            }

            dict set computing $cell 1

            set raw [cell_raw $cell]

            set rc [catch {
                if {$raw eq ""} {
                    set v 0.0
                } elseif {[string match =* $raw]} {
                    set v [eval_formula $raw]
                } elseif {[is_number $raw]} {
                    set v [expr {double($raw)}]
                } else {
                    set v 0.0
                }
            } err]

            dict unset computing $cell

            if {$rc} {
                error $err
            }

            dict set value_cache $cell $v

            return $v
        }

        proc format_number {n} {
            if {[catch {set num [expr {double($n)}]}]} {
                return $n
            }

            if {$num == int($num)} {
                return [format %d [expr {int($num)}]]
            }

            return [format %.2f $num]
        }

        # --------------------------------------------------------------------
        # Formula evaluation
        # --------------------------------------------------------------------

        proc eval_formula {formula} {
            set expr [string trim $formula]

            if {[string index $expr 0] eq "="} {
                set expr [string range $expr 1 end]
            }

            # Allow $A$1 style references by stripping dollar signs.
            set expr [string map {$ {}} $expr]

            # Normalize to uppercase so cell references and functions match.
            set expr [string toupper $expr]

            set expr [replace_functions $expr]
            set expr [replace_cell_refs $expr]

            if {[string trim $expr] eq ""} {
                error "Empty formula"
            }

            # Basic arithmetic only.
            if {![regexp {^[0-9+*/%(). eE-]+$} $expr]} {
                error "Bad formula"
            }

            return [expr $expr]
        }

        proc replace_functions {expr} {
            while {
                [regexp {
                    (SUM|AVERAGE|AVG|MIN|MAX|COUNT)
                    \s*\(\s*
                    ([A-Z]+[0-9]+)
                    \s*:\s*
                    ([A-Z]+[0-9]+)
                    \s*\)
                } $expr all fn a b]
            } {
                set val [apply_function $fn $a $b]
                set expr [string map [list $all "($val)"] $expr]
            }

            return $expr
        }

        proc replace_cell_refs {expr} {
            set matches [regexp -all -inline -indices {[A-Z]+[0-9]+} $expr]
            set n [llength $matches]

            for {set i [expr {$n - 2}]} {$i >= 0} {incr i -2} {
                set start [lindex $matches $i]
                set end [lindex $matches [expr {$i + 1}]]

                set ref [string range $expr $start [expr {$end - 1}]]
                set val [cell_numeric $ref]

                set expr [string replace $expr $start [expr {$end - 1}] "($val)"]
            }

            return $expr
        }

        proc apply_function {fn a b} {
            set cells [range_cells $a $b]

            set sum 0.0
            set nums {}
            set nonempty 0

            foreach cell $cells {
                set raw [cell_raw $cell]

                if {$raw eq ""} {
                    continue
                }

                incr nonempty

                set numeric_like 0

                if {[is_number $raw] || [string match =* $raw]} {
                    set numeric_like 1
                }

                if {$numeric_like} {
                    if {![catch {cell_numeric $cell} v]} {
                        lappend nums $v
                        set sum [expr {$sum + $v}]
                    }
                }
            }

            if {$fn eq "SUM"} {
                return $sum
            }

            if {$fn eq "AVG" || $fn eq "AVERAGE"} {
                if {[llength $nums] == 0} {
                    return 0.0
                }

                return [expr {double($sum) / [llength $nums]}]
            }

            if {$fn eq "MIN"} {
                if {[llength $nums] == 0} {
                    return 0.0
                }

                set m [lindex $nums 0]

                foreach v [lrange $nums 1 end] {
                    if {$v < $m} {
                        set m $v
                    }
                }

                return $m
            }

            if {$fn eq "MAX"} {
                if {[llength $nums] == 0} {
                    return 0.0
                }

                set m [lindex $nums 0]

                foreach v [lrange $nums 1 end] {
                    if {$v > $m} {
                        set m $v
                    }
                }

                return $m
            }

            if {$fn eq "COUNT"} {
                return $nonempty
            }

            error "Unknown function $fn"
        }

        # --------------------------------------------------------------------
        # Cell / range utilities
        # --------------------------------------------------------------------

        proc parse_cell {cell} {
            if {![regexp {^([A-Z]+)([0-9]+)$} $cell -> col row]} {
                error "Bad cell: $cell"
            }

            return [list [col_to_num $col] [expr {int($row)}]]
        }

        proc range_cells {a b} {
            variable state

            set rows [dict get $state rows]
            set cols [dict get $state cols]

            lassign [parse_cell $a] c1 r1
            lassign [parse_cell $b] c2 r2

            set cmin [expr {min($c1, $c2)}]
            set cmax [expr {max($c1, $c2)}]
            set rmin [expr {min($r1, $r2)}]
            set rmax [expr {max($r1, $r2)}]

            if {$cmin < 1} {
                set cmin 1
            }

            if {$cmax > $cols} {
                set cmax $cols
            }

            if {$rmin < 1} {
                set rmin 1
            }

            if {$rmax > $rows} {
                set rmax $rows
            }

            if {$cmin > $cmax || $rmin > $rmax} {
                return {}
            }

            set out {}

            for {set c $cmin} {$c <= $cmax} {incr c} {
                set colname [num_to_col $c]

                for {set r $rmin} {$r <= $rmax} {incr r} {
                    lappend out "${colname}${r}"
                }
            }

            return $out
        }

        proc col_to_num {col} {
            set n 0

            foreach ch [split $col ""] {
                set n [expr {$n * 26 + [scan $ch %c] - 64}]
            }

            return $n
        }

        proc num_to_col {n} {
            set s ""

            while {$n > 0} {
                incr n -1
                set s [format %c [expr {65 + ($n % 26)}]]$s
                set n [expr {$n / 26}]
            }

            return $s
        }

        # --------------------------------------------------------------------
        # Sample / clear
        # --------------------------------------------------------------------

        proc clear_all {} {
            variable state

            dict set state cells {}

            recompute_all
            refresh_all

            status "Cleared"
        }

        proc load_sample {} {
            variable state

            dict set state cells {}

            dict set state cells A1 "Item"
            dict set state cells B1 "Monthly"
            dict set state cells C1 "Annual"

            dict set state cells A2 "Income"
            dict set state cells B2 3000
            dict set state cells C2 "=B2*12"

            dict set state cells A3 "Rent"
            dict set state cells B3 1200
            dict set state cells C3 "=B3*12"

            dict set state cells A4 "Food"
            dict set state cells B4 450
            dict set state cells C4 "=B4*12"

            dict set state cells A5 "Transport"
            dict set state cells B5 150
            dict set state cells C5 "=B5*12"

            dict set state cells A6 "Utilities"
            dict set state cells B6 120
            dict set state cells C6 "=B6*12"

            dict set state cells A7 "Insurance"
            dict set state cells B7 90
            dict set state cells C7 "=B7*12"

            dict set state cells A8 "Total Expenses"
            dict set state cells B8 "=SUM(B3:B7)"
            dict set state cells C8 "=SUM(C3:C7)"

            dict set state cells A9 "Net"
            dict set state cells B9 "=B2-B8"
            dict set state cells C9 "=C2-C8"

            recompute_all
            refresh_all

            status "Sample budget loaded"
        }

        # --------------------------------------------------------------------
        # CSV export
        # --------------------------------------------------------------------

        proc export_csv_buffer {} {
            variable state

            recompute_all

            set rows [dict get $state rows]
            set cols [dict get $state cols]

            set lines {}

            for {set r 1} {$r <= $rows} {incr r} {
                set vals {}

                for {set c 1} {$c <= $cols} {incr c} {
                    set cell "[num_to_col $c]$r"
                    set v [cell_display $cell]

                    if {
                        [string first , $v] >= 0 ||
                        [string first "\"" $v] >= 0 ||
                        [string first "\n" $v] >= 0
                    } {
                        regsub -all {"} $v {""} v
                        set v "\"$v\""
                    }

                    lappend vals $v
                }

                lappend lines [join $vals ,]
            }

            ::Tclme::ShowInBuffer "*Budget CSV*" [join $lines \n] 1
        }

        # --------------------------------------------------------------------
        # Save / load
        # --------------------------------------------------------------------

        proc save_prompt {} {
            set cb [namespace current]::save_budget_to_file
            ::Tclme::Prompt "Save budget: " $cb ::Tclme::CompleteFile
        }

        proc open_prompt {} {
            set cb [namespace current]::load_budget_from_file
            ::Tclme::Prompt "Open budget: " $cb ::Tclme::CompleteFile
        }

        proc save_budget_to_file {filename} {
            variable state

            set filename [string trim $filename]

            if {$filename eq ""} {
                ::Tclme::Message "Save cancelled"
                return
            }

            set data [dict create \
                version 1 \
                cells [dict get $state cells] \
            ]

            if {[catch {
                set fp [open $filename w]
                fconfigure $fp -encoding utf-8
                puts $fp $data
                close $fp
            } err]} {
                ::Tclme::Log error "budget save: $err"
                return
            }

            ::Tclme::Message "Wrote $filename"
        }

        proc load_budget_from_file {filename} {
            variable state
            variable ui_frame

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
                ::Tclme::Log error "budget open: $err"
                return
            }

            if {[catch {dict size $data}]} {
                ::Tclme::Message "Not a budget file"
                return
            }

            set cells {}

            if {[dict exists $data cells]} {
                set cells [dict get $data cells]
            }

            dict set state cells $cells

            recompute_all

            if {[winfo exists $ui_frame]} {
                refresh_all
            } else {
                catch { open_ui }
            }

            ::Tclme::Message "Loaded $filename"
        }
    }

    do {
        catch { ::Tclme::DefAlias bud budget }
        catch { ::Tclme::DefAlias bsave budget-save }
        catch { ::Tclme::DefAlias bopen budget-open }
        catch { ::Tclme::DefAlias bcsv budget-csv }
    }
}