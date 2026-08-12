      proc build_ui {txt} {
            variable ui_frame
            variable map_widget
            destroy_ui
            $txt configure -state normal
            $txt delete 1.0 end
            set f $txt.gita_ui
            frame $f -bg #060c07

            label $f.hud -text "" -bg #060c07 -fg #33ff66 -font {Consolas 14} -anchor w
            pack $f.hud -fill x -padx 4 -pady 2

            set mw $f.map
            text $mw -font {Consolas 12} -bg #060c07 -fg #33ff66 -state disabled -wrap word -highlightthickness 0 -padx 4 -pady 4 -borderwidth 0 -insertbackground #000000
            bindtags $mw [list $mw [winfo toplevel $mw] all]
            
            $mw tag configure player -foreground white -background #33ff66
            $mw tag configure verse -foreground #ffdd33
            $mw tag configure vread -foreground #33664a
            $mw tag configure frag -foreground #33bbdd
            $mw tag configure fragcol -foreground #225544
            $mw tag configure exit -foreground #ff8833
            $mw tag configure entry -foreground #8833ff
            $mw tag configure dim -foreground #1a2a1a
            $mw tag configure mid -foreground #2a4a2a
            $mw tag configure hot -foreground #44cc44
            $mw tag configure ground -foreground #2a2050
            $mw tag configure dug -foreground #1a1040
            $mw tag configure title -foreground #ffb833 -font {Consolas 16 bold}
            $mw tag configure ref -foreground #ffdd33 -font {Consolas 14 bold}
            $mw tag configure skt -foreground #33bbdd -font {Consolas 12}
            $mw tag configure trans -foreground #33ff66

            pack $mw -fill both -expand 1 -padx 4

            label $f.status -text "" -bg #060c07 -fg #ffb833 -font {Consolas 12} -anchor w
            pack $f.status -fill x -padx 4 -pady 2

            label $f.cmds -text "WASD: Move | Space: Dig | Enter: Read | J/F/Z: Panels | Q: Save+Quit" -bg #060c07 -fg #1a7a33 -font {Consolas 10} -anchor w
            pack $f.cmds -fill x -padx 4 -pady 2

            if {[catch { $txt window create end -window $f -stretch 1 -padx 0 -pady 0 }]} {
                $txt window create end -window $f
            }
            catch { $txt edit modified 0 }
            $txt configure -state disabled

            set ui_frame $f
            set map_widget $mw

            bind $mw <Key> [namespace code {handleKey %K}]
            focus $mw
        }
