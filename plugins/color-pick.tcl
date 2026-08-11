# plugins/colorpicker.tcl

Tclme::Plugin {
    description "Color picker embedded in a Tclme buffer"
    version 0.2.0
    headless ui

    state {
        selected_widget .
        selected_property -background
        custom_color #ff0000
        history {}
        filter ""
    }

    command color-picker {args} {
        if {[::Tclme::IsHeadless]} {
            ::Tclme::Message "color-picker requires the Tclme GUI"
            return
        }
        open_ui
    } "Open the color picker buffer"

    bind <Control-x><Alt-c> color-picker

    init {
        variable state

        foreach {k v} {
            selected_widget .
            selected_property -background
            custom_color #ff0000
            history {}
            filter ""
        } {
            if {![dict exists $state $k]} {
                dict set state $k $v
            }
        }
    }

    cleanup {
        catch { clear_buffer }
        catch { destroy_ui }
        catch { destroy .tclme_colorpicker }
    }

    do {
        variable buffer_name "*Color Picker*"
        variable ui_frame ""
        variable status_path ""
        variable current_path ""

        variable widget_var .
        variable prop_var -background
        variable custom_var #ff0000
        variable filter_var ""
        variable option_seq 0

        proc sget {key default} {
            variable state
            if {[dict exists $state $key]} {
                return [dict get $state $key]
            }
            return $default
        }

        proc open_ui {} {
            variable buffer_name
            variable widget_var
            variable prop_var
            variable custom_var
            variable filter_var
            variable state

            # If the old toplevel version is still open, close it.
            catch { destroy .tclme_colorpicker }

            ::Tclme::SwitchToBuffer $buffer_name

            set txt [::Tclme::WidgetForBuffer $buffer_name]
            if {$txt eq ""} {
                ::Tclme::Message "Cannot create color-picker buffer"
                return
            }

            set widget_var [sget selected_widget .]
            set prop_var   [sget selected_property -background]
            set custom_var [sget custom_color #ff0000]
            set filter_var [sget filter ""]

            build_ui $txt

            catch {
                dict set ::Tclme::buffers $buffer_name readonly 1
            }

            status "Color picker ready"
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
            variable current_path

            if {[winfo exists $ui_frame]} {
                destroy $ui_frame
            }

            set ui_frame ""
            set status_path ""
            set current_path ""
        }

        proc build_ui {txt} {
            variable ui_frame
            variable status_path
            variable current_path
            variable filter_var
            variable custom_var

            destroy_ui

            $txt configure -state normal
            $txt delete 1.0 end

            set f $txt.colorpicker_ui
            frame $f

            # ----------------------------------------------------------------
            # Top controls
            # ----------------------------------------------------------------

            frame $f.top

            label $f.top.title -text "Tclme Color Picker"

            label $f.top.filter_label -text "Filter:"
            entry $f.top.filter -textvariable [namespace current]::filter_var
            bind $f.top.filter <Return> [namespace code populate_widgets]

            button $f.top.refresh -text "Refresh" -command [namespace code refresh_all] -cursor hand2
            button $f.top.close -text "Close" -command [namespace code close_buffer] -cursor hand2

            pack $f.top.title -side left -padx {0 10}
            pack $f.top.filter_label -side left
            pack $f.top.filter -side left -fill x -expand 1 -padx 6
            pack $f.top.refresh -side left -padx 2
            pack $f.top.close -side right

            pack $f.top -fill x -pady {0 6}

            label $f.status -text "" -anchor w -relief sunken
            pack $f.status -fill x -pady {0 8}

            # ----------------------------------------------------------------
            # Widget selector
            # ----------------------------------------------------------------

            labelframe $f.widgets -text "Widget"
            frame $f.widgets.list
            pack $f.widgets.list -fill both -expand 1
            pack $f.widgets -fill both -expand 1 -pady 4

            # ----------------------------------------------------------------
            # Option selector
            # ----------------------------------------------------------------

            labelframe $f.options -text "Color option"
            frame $f.options.list
            pack $f.options.list -fill x
            pack $f.options -fill x -pady 4

            # ----------------------------------------------------------------
            # Color selector
            # ----------------------------------------------------------------

            labelframe $f.colors -text "Colors"

            label $f.colors.current -text " current " -relief sunken -anchor w -padx 6 -pady 4
            frame $f.colors.swatches
            frame $f.colors.custom

            entry $f.colors.custom.entry -textvariable [namespace current]::custom_var
            button $f.colors.custom.apply -text "Apply" -command [namespace code apply_custom] -cursor hand2
            button $f.colors.custom.choose -text "Choose..." -command [namespace code choose_color] -cursor hand2

            pack $f.colors.custom.entry -side left -fill x -expand 1 -padx {0 4}
            pack $f.colors.custom.apply -side left -padx 2
            pack $f.colors.custom.choose -side left -padx 2

            pack $f.colors.current -fill x -pady {0 4}
            pack $f.colors.swatches -fill x
            pack $f.colors.custom -fill x -pady {4 0}
            pack $f.colors -fill x -pady 4

            if {[catch {
                $txt window create end -window $f -stretch 1 -padx 4 -pady 4
            }]} {
                $txt window create end -window $f
            }

            catch { $txt edit modified 0 }
            $txt configure -state disabled

            set ui_frame $f
            set status_path $f.status
            set current_path $f.colors.current

            populate_widgets
            populate_options
            populate_colors
            update_current
        }

        proc close_buffer {} {
            variable buffer_name
            catch { ::Tclme::KillBuffer $buffer_name }
        }

        proc refresh_all {} {
            populate_widgets
            populate_options
            populate_colors
            update_current
        }

        proc is_own {w} {
            variable ui_frame

            if {$ui_frame eq ""} {
                return 0
            }

            if {$w eq $ui_frame || [string match "$ui_frame.*" $w]} {
                return 1
            }

            return 0
        }

        proc all_widgets {root} {
            set out {}

            foreach child [winfo children $root] {
                if {[is_own $child]} {
                    continue
                }

                lappend out $child
                lappend out {*}[all_widgets $child]
            }

            return $out
        }

        proc available_widgets {} {
            variable filter_var

            set raw {}
            if {[winfo exists .]} {
                lappend raw .
            }

            lappend raw {*}[all_widgets .]

            set out {}
            set needle [string tolower [string trim $filter_var]]

            foreach w $raw {
                if {[is_own $w]} {
                    continue
                }

                if {![winfo exists $w]} {
                    continue
                }

                set class ""
                catch { set class [winfo class $w] }

                if {$needle ne ""} {
                    set hay [string tolower "$w $class"]
                    if {[string first $needle $hay] < 0} {
                        continue
                    }
                }

                lappend out $w
            }

            return $out
        }

        proc populate_widgets {} {
            variable ui_frame
            variable widget_var
            variable filter_var
            variable state

            if {![winfo exists $ui_frame]} {
                return
            }

            set f $ui_frame.widgets.list

            foreach child [winfo children $f] {
                destroy $child
            }

            set widgets [available_widgets]

            if {$widget_var ni $widgets} {
                set widget_var [lindex $widgets 0]
            }

            set varname [namespace current]::widget_var
            set i 0

            foreach w $widgets {
                set class ""
                catch { set class [winfo class $w] }

                set text "$w ($class)"
                if {[string length $text] > 110} {
                    set text "[string range $text 0 106]..."
                }

                radiobutton $f.rb$i \
                    -text $text \
                    -value $w \
                    -variable $varname \
                    -command [namespace code widget_selected] \
                    -anchor w \
                    -cursor hand2 \
                    -justify left \
                    -wraplength 520

                pack $f.rb$i -fill x
                incr i
            }

            if {$i == 0} {
                label $f.none -text "No widgets match the filter" -anchor w
                pack $f.none -fill x
            }

            dict set state selected_widget $widget_var
            dict set state filter $filter_var

            widget_selected
        }

        proc widget_selected {} {
            variable ui_frame
            variable widget_var
            variable state

            if {![winfo exists $ui_frame]} {
                return
            }

            if {![winfo exists $widget_var]} {
                set widgets [available_widgets]
                set widget_var [lindex $widgets 0]
            }

            dict set state selected_widget $widget_var

            populate_options
            update_current
            status "Widget: $widget_var"
        }

        proc option_pairs {} {
            return {
                {bg              -background}
                {fg              -foreground}
                {insert/cursor   -insertbackground}
                {select bg       -selectbackground}
                {select fg       -selectforeground}
                {active bg       -activebackground}
                {active fg       -activeforeground}
                {highlight bg    -highlightbackground}
                {highlight       -highlightcolor}
                {disabled fg     -disabledforeground}
                {trough          -troughcolor}
            }
        }

        proc detected_color_options {w} {
            if {[catch {$w configure} specs]} {
                return {}
            }

            set out {}

            foreach spec $specs {
                if {[llength $spec] < 5} {
                    continue
                }

                lassign $spec opt dbname dbclass default current

                set opt_lc [string tolower $opt]
                set name_lc [string tolower $dbname]
                set class_lc [string tolower $dbclass]

                if {
                    $class_lc eq "color" ||
                    [string match *color* $opt_lc] ||
                    [string match *color* $name_lc]
                } {
                    lappend out $opt
                }
            }

            return [lsort -unique $out]
        }

        proc supports_option {w opt} {
            if {![winfo exists $w]} {
                return 0
            }

            if {[catch {$w configure $opt}]} {
                return 0
            }

            return 1
        }

        proc supported_color_options {w} {
            set opts {}

            if {![winfo exists $w]} {
                return {}
            }

            foreach opt [detected_color_options $w] {
                lappend opts $opt
            }

            foreach pair [option_pairs] {
                set opt [lindex $pair 1]
                if {[supports_option $w $opt]} {
                    lappend opts $opt
                }
            }

            return [lsort -unique $opts]
        }

        proc preferred_option {opts} {
            foreach prefer {-background -foreground -insertbackground} {
                if {[lsearch -exact $opts $prefer] >= 0} {
                    return $prefer
                }
            }

            return [lindex $opts 0]
        }

        proc populate_options {} {
            variable ui_frame
            variable widget_var
            variable prop_var
            variable state
            variable option_seq

            if {![winfo exists $ui_frame]} {
                return
            }

            set f $ui_frame.options.list

            foreach child [winfo children $f] {
                catch { destroy $child }
            }

            set supported [supported_color_options $widget_var]

            if {[llength $supported] == 0} {
                set none $f.none_[incr option_seq]

                label $none \
                    -text "No color options available for this widget" \
                    -anchor w

                pack $none -fill x
                return
            }

            if {$prop_var ni $supported} {
                set prop_var [preferred_option $supported]
            }

            set varname [namespace current]::prop_var

            set common_opts {}
            foreach pair [option_pairs] {
                lappend common_opts [lindex $pair 1]
            }

            set seen_opts {}
            set row 0
            set col 0

            # ----------------------------------------------------------------
            # Common named options: bg, fg, etc.
            # ----------------------------------------------------------------

            foreach pair [option_pairs] {
                set label [lindex $pair 0]
                set opt [lindex $pair 1]

                if {[lsearch -exact $seen_opts $opt] >= 0} {
                    continue
                }

                lappend seen_opts $opt

                set st normal
                if {$opt ni $supported} {
                    set st disabled
                }

                set rb $f.opt_[incr option_seq]

                radiobutton $rb \
                    -text $label \
                    -value $opt \
                    -variable $varname \
                    -command [namespace code option_selected] \
                    -state $st \
                    -anchor w -cursor hand2

                grid $rb -row $row -column $col -sticky w -padx 6 -pady 1

                incr col
                if {$col >= 3} {
                    set col 0
                    incr row
                }
            }

            # ----------------------------------------------------------------
            # Extra detected options not already listed above.
            # ----------------------------------------------------------------

            foreach opt $supported {
                if {[lsearch -exact $seen_opts $opt] >= 0} {
                    continue
                }

                lappend seen_opts $opt

                set rb $f.opt_[incr option_seq]

                radiobutton $rb \
                    -text $opt \
                    -value $opt \
                    -variable $varname \
                    -command [namespace code option_selected] \
                    -anchor w -cursor hand2

                grid $rb -row $row -column $col -sticky w -padx 6 -pady 1

                incr col
                if {$col >= 3} {
                    set col 0
                    incr row
                }
            }

            dict set state selected_property $prop_var

            option_selected
        }

        proc option_selected {} {
            variable ui_frame
            variable prop_var
            variable state

            if {![winfo exists $ui_frame]} {
                return
            }

            dict set state selected_property $prop_var
            update_current
            status "Option: $prop_var"
        }

        proc populate_colors {} {
            variable state
            variable ui_frame

            if {![winfo exists $ui_frame]} {
                return
            }

            set f $ui_frame.colors.swatches

            foreach child [winfo children $f] {
                destroy $child
            }

            set palette {
                #000000 #ffffff #7f7f7f #c3c3c3
                #880015 #ed1c24 #ff7f27 #fff200
                #22b14c #00a2e8 #3f48cc #a349a4
                #b97a57 #ffaec9 #ffc90e #efe4b0
                #b5e61d #99d9ea #7092be #c8bfe7
                red orange yellow green blue cyan magenta purple pink brown
                darkred darkgreen darkblue darkcyan darkmagenta darkorange
                gray lightgray darkgray navy teal olive maroon silver gold
            }

            set hist [sget history {}]
            if {[catch {llength $hist}]} {
                set hist {}
            }

            set colors {}

            foreach c [concat $palette $hist] {
                set c [string trim $c]
                if {$c ne ""} {
                    lappend colors $c
                }
            }

            set colors [lsort -unique $colors]

            set row 0
            set col 0

            foreach color $colors {
                set safe [regsub -all {[^A-Za-z0-9_]} $color _]
                set sw $f.sw_$safe

                if {[catch {
                    label $sw \
                        -text "" \
                        -bg $color \
                        -relief raised \
                        -padx 8 \
                        -cursor hand2 \
                        -pady 4
                }]} {
                    continue
                }

                bind $sw <Button-1> [namespace code [list apply_color $color]]

                grid $sw -row $row -column $col -padx 1 -pady 1 -sticky nsew
                grid columnconfigure $f $col -weight 1

                incr col
                if {$col >= 10} {
                    set col 0
                    incr row
                }
            }

            catch { grid rowconfigure $f $row -weight 1 }
        }

        proc apply_custom {} {
            variable custom_var
            apply_color $custom_var
        }

        proc choose_color {} {
            variable custom_var

            set initial $custom_var

            if {[catch {tk_chooseColor -initialcolor $initial -title "Choose color"} color]} {
                set color [tk_chooseColor -title "Choose color"]
            }

            if {$color ne ""} {
                set custom_var $color
                apply_color $color
            }
        }

        proc apply_color {color} {
            variable ui_frame
            variable widget_var
            variable prop_var
            variable custom_var
            variable state

            if {![winfo exists $ui_frame]} {
                return
            }

            if {![winfo exists $widget_var]} {
                status "Widget does not exist: $widget_var"
                return
            }

            if {$prop_var eq ""} {
                status "No color option selected"
                return
            }

            if {[catch {$widget_var configure $prop_var $color} err]} {
                status "Cannot set $prop_var on $widget_var: $err"
                return
            }

            set custom_var $color

            dict set state custom_color $color
            dict set state selected_widget $widget_var
            dict set state selected_property $prop_var

            set hist [sget history {}]
            if {[catch {llength $hist}]} {
                set hist {}
            }

            set hist [lsearch -all -inline -not -exact $hist $color]
            set hist [linsert $hist 0 $color]

            if {[llength $hist] > 16} {
                set hist [lrange $hist 0 15]
            }

            dict set state history $hist

            update_current
            status "$widget_var $prop_var = $color"

            # Refresh swatches later so the clicked swatch is not destroyed
            # in the middle of its own click event.
            catch {
                ::Tclme::After idle [namespace code populate_colors]
            }
        }

        proc update_current {} {
            variable ui_frame
            variable current_path
            variable widget_var
            variable prop_var

            if {![winfo exists $ui_frame] || ![winfo exists $current_path]} {
                return
            }

            if {[winfo exists $widget_var] && ![catch {$widget_var cget $prop_var} color] && $color ne ""} {
                catch { $current_path configure -bg $color }
                $current_path configure -text " $prop_var = $color "
            } else {
                catch { $current_path configure -bg #dddddd }
                $current_path configure -text " no current color "
            }
        }

        proc status {msg} {
            variable ui_frame
            variable status_path

            if {[winfo exists $ui_frame] && [winfo exists $status_path]} {
                $status_path configure -text $msg
            }
        }
    }

    do {
        catch { ::Tclme::DefAlias cp color-picker }
    }
}