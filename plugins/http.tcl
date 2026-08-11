# plugins/http-client.tcl
# ============================================================================
# HTTP client for Tclme.
#
# Commands:
#   :http URL
#   :fetch URL
#
# Keybinding:
#   C-x C-h
#
# Behavior:
#   Fetches a URL and renders the response body in a read-only buffer.
#
# Notes:
#   - Plain HTTP works with Tcl's built-in http package.
#   - HTTPS requires either:
#       - Tcl tls package, or
#       - curl in PATH
#   - If curl is available and Tcl tls is not, HTTPS fetches fall back to curl.
# ============================================================================

namespace eval ::HttpFetch {
    variable max_body 5000000

    variable tls_checked 0
    variable tls_ok 0

    variable curl_checked 0
    variable curl_path ""

    variable curl_state

    if {![info exists curl_state]} {
        array set curl_state {}
    }
}

namespace eval ::HttpFetch {

    # ------------------------------------------------------------------------
    # Small helpers
    # ------------------------------------------------------------------------

    proc Message {msg} {
        catch { ::Tclme::Message $msg }
    }

    proc NormalizeUrl {url} {
        set url [string trim $url]

        if {$url eq ""} {
            return ""
        }

        # Basic protection against accidental spaces.
        set url [string map {" " "%20"} $url]

        # Add scheme if missing.
        if {![regexp {^[A-Za-z][A-Za-z0-9+.-]*://} $url]} {
            set url "http://$url"
        }

        return $url
    }

    proc BufferName {url} {
        set name [string map [list "\n" " " "\r" " "] $url]

        if {[string length $name] > 60} {
            set name "[string range $name 0 56]..."
        }

        return "*http: $name*"
    }

    proc SetReadonly {bufname val} {
        catch {
            upvar #0 ::Tclme::buffers buffers

            if {[dict exists $buffers $bufname]} {
                dict set buffers $bufname readonly $val
            }
        }
    }

    # ------------------------------------------------------------------------
    # Command entry point
    # ------------------------------------------------------------------------

    proc cmd-http {args} {
        set url [string trim [join $args " "]]

        if {$url eq ""} {
            if {[info commands ::Tclme::Prompt] ne ""} {
                ::Tclme::Prompt "URL: " [list [namespace current]::PromptFetch]
            } else {
                Message "Usage: :http URL"
            }
            return
        }

        Fetch $url
    }

    proc PromptFetch {url} {
        set url [string trim $url]

        if {$url ne ""} {
            Fetch $url
        }
    }

    # ------------------------------------------------------------------------
    # HTTP / TLS / curl setup
    # ------------------------------------------------------------------------

    proc EnsureHttp {} {
        variable tls_checked
        variable tls_ok

        if {[catch {package require http} err]} {
            error "Tcl http package not available: $err"
        }

        if {!$tls_checked} {
            set tls_checked 1
            set tls_ok 0

            if {![catch {package require tls}]} {
                # Try the best TLS socket registration first.
                if {![catch {
                    ::http::register https 443 \
                        [list ::tls::socket -async -autoservername true]
                }]} {
                    set tls_ok 1
                } elseif {![catch {
                    ::http::register https 443 \
                        [list ::tls::socket -async]
                }]} {
                    set tls_ok 1
                } elseif {![catch {
                    ::http::register https 443 ::tls::socket
                }]} {
                    set tls_ok 1
                }
            }
        }

        return $tls_ok
    }

    proc CurlExecutable {} {
        variable curl_checked
        variable curl_path

        if {!$curl_checked} {
            set curl_checked 1
            set curl_path ""

            if {![catch {auto_execok curl} found] && $found ne ""} {
                set curl_path [lindex $found 0]
            }
        }

        return $curl_path
    }

    # ------------------------------------------------------------------------
    # Fetch dispatch
    # ------------------------------------------------------------------------

    proc Fetch {url} {
        variable tls_ok

        set url [NormalizeUrl $url]

        if {$url eq ""} {
            Message "No URL"
            return
        }

        if {[catch {EnsureHttp} err]} {
            if {[CurlExecutable] ne ""} {
                CurlFetch $url
                return
            }

            Message $err
            return
        }

        # For HTTPS without Tcl TLS, prefer curl if available.
        if {[string match -nocase "https://*" $url] && !$tls_ok} {
            if {[CurlExecutable] ne ""} {
                CurlFetch $url
            } else {
                Message "HTTPS requires Tcl tls package or curl in PATH"
            }
            return
        }

        HttpFetch $url
    }

    # ------------------------------------------------------------------------
    # Tcl http fetch
    # ------------------------------------------------------------------------

    proc HttpFetch {url} {
        Message "Fetching $url ..."

        set headers [list \
            User-Agent "Tclme-HTTP/1.0" \
            Accept "*/*"]

        if {[catch {
            ::http::geturl $url \
                -command [list [namespace current]::HttpDone $url] \
                -redirect 1 \
                -timeout 30000 \
                -headers $headers
        } token err]} {
            if {[CurlExecutable] ne ""} {
                CurlFetch $url
                return
            }

            Message "HTTP fetch failed: $err"
        }
    }

    proc HttpDone {url token} {
        set status [::http::status $token]

        if {$status ne "ok"} {
            set err ""
            catch { set err [::http::error $token] }
            catch { ::http::cleanup $token }

            # Fallback to curl if possible.
            if {[CurlExecutable] ne ""} {
                CurlFetch $url
                return
            }

            Message "Fetch failed: $status $err"
            return
        }

        set code ""
        catch { set code [::http::code $token] }

        set body ""
        catch { set body [::http::data $token] }

        catch { ::http::cleanup $token }

        RenderBody $url $body $code
    }

    # ------------------------------------------------------------------------
    # curl fallback fetch
    # ------------------------------------------------------------------------

    proc CurlFetch {url} {
        variable curl_state

        set curl [CurlExecutable]

        if {$curl eq ""} {
            Message "curl not found"
            return
        }

        Message "Fetching $url ..."

        set pipeline [list | $curl \
            -sSL \
            --compressed \
            --max-time 30 \
            --url $url]

        if {[catch {open $pipeline r} ch err]} {
            Message "curl failed: $err"
            return
        }

        fconfigure $ch -encoding binary -translation binary -blocking 0

        set curl_state($ch) [dict create url $url data ""]

        fileevent $ch readable [list [namespace current]::CurlReadable $ch]
    }

    proc CurlReadable {ch} {
        variable curl_state
        variable max_body

        if {![info exists curl_state($ch)]} {
            fileevent $ch readable {}
            catch { close $ch }
            return
        }

        if {[eof $ch]} {
            fileevent $ch readable {}

            set info $curl_state($ch)
            catch { unset curl_state($ch) }

            set close_err [catch { close $ch } cerr]

            set url  [dict get $info url]
            set body [dict get $info data]

            if {$body eq "" && $close_err} {
                Message "curl failed: $cerr"
                return
            }

            RenderBody $url [MaybeDecodeUtf8 $body]
            return
        }

        if {[catch { read $ch } chunk err]} {
            fileevent $ch readable {}
            catch { unset curl_state($ch) }
            catch { close $ch }
            Message "curl read failed: $err"
            return
        }

        if {$chunk eq ""} {
            return
        }

        set info $curl_state($ch)
        dict append info data $chunk

        if {[string length [dict get $info data]] > $max_body} {
            fileevent $ch readable {}
            catch { unset curl_state($ch) }
            catch { close $ch }
            Message "Response too large"
            return
        }

        set curl_state($ch) $info
    }

    proc MaybeDecodeUtf8 {body} {
        if {[catch {encoding convertfrom utf-8 $body} txt]} {
            return $body
        }

        return $txt
    }

    # ------------------------------------------------------------------------
    # Rendering
    # ------------------------------------------------------------------------

    proc RenderBody {url body {code ""}} {
        variable max_body

        set size [string length $body]

        # Very simple binary detection.
        if {[string first "\x00" $body] >= 0} {
            set body "Binary response not rendered.\n\nURL: $url\nSize: $size bytes"
        } else {
            if {$size > $max_body} {
                set body "[string range $body 0 [expr {$max_body - 1}]]\n\n... response truncated"
            }

            if {$body eq ""} {
                set body "(empty response body)"
            }
        }

        set bufname [BufferName $url]

        if {[catch { ::Tclme::SwitchToBuffer $bufname } err]} {
            Message "Cannot open HTTP buffer: $err"
            return
        }

        set w $::Tclme::active_widget

        if {$w eq "" || ![winfo exists $w]} {
            return
        }

        if {[winfo class $w] ne "Text"} {
            return
        }

        $w configure -state normal
        $w delete 1.0 end
        $w insert end $body
        $w edit modified 0
        $w configure -state disabled

        SetReadonly $bufname 1

        catch { focus $w }

        if {$code ne ""} {
            Message "HTTP $code"
        } else {
            Message "Fetched $url"
        }
    }
}

# ----------------------------------------------------------------------------
# Global command wrapper
# ----------------------------------------------------------------------------

proc ::cmd-http-fetch {args} {
    ::HttpFetch::cmd-http {*}$args
}

# ----------------------------------------------------------------------------
# Registration
# ----------------------------------------------------------------------------
Tclme::DefCommandAndBind http cmd-http-fetch      <Control-x><Control-h>        "Fetch a URL and render the body"
Tclme::DefAlias fetch http 
Tclme::DefAlias http-fetch http 