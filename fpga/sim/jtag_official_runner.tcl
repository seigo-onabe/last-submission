# ADC 2026 official-board runner over USB-Blaster Virtual JTAG.
# Usage via quartus_stp -t:
#   jtag_official_runner.tcl BOARD_FILE RESULT_CSV ?MAX_BOARDS? ?INSTANCE? ?MODE?

if {$argc < 2 || $argc > 5} {
    error "usage: jtag_official_runner.tcl BOARD_FILE RESULT_CSV ?MAX_BOARDS? ?INSTANCE? ?normal|fast?"
}
set board_file [lindex $argv 0]
set result_file [lindex $argv 1]
set max_boards [expr {$argc >= 3 ? [lindex $argv 2] : 2147483647}]
set instance_index [expr {$argc >= 4 ? [lindex $argv 3] : 0}]
set run_mode [expr {$argc >= 5 ? [string tolower [lindex $argv 4]] : "normal"}]
if {$run_mode ne "normal" && $run_mode ne "fast"} {
    error "mode must be normal or fast"
}
set fast_mode [expr {$run_mode eq "fast"}]
set scan_count 0

proc crc16_byte {crc data} {
    set value [expr {($crc ^ (($data & 0xff) << 8)) & 0xffff}]
    for {set i 0} {$i < 8} {incr i} {
        if {$value & 0x8000} {
            set value [expr {(($value << 1) ^ 0x1021) & 0xffff}]
        } else {
            set value [expr {($value << 1) & 0xffff}]
        }
    }
    return $value
}

proc u64hex {value} {
    return [format %016llX [expr {$value & 0xffffffffffffffff}]]
}

proc shift_word {instance word} {
    global scan_count
    set captured [device_virtual_dr_shift -instance_index $instance -length 64 \
        -dr_value [u64hex $word] -value_in_hex]
    incr scan_count
    return [expr 0x$captured]
}

proc send_word {instance word} {
    global scan_count
    device_virtual_dr_shift -instance_index $instance -length 64 \
        -dr_value [u64hex $word] -value_in_hex -no_captured_dr_value
    incr scan_count
}

proc exchange_word {instance word} {
    global fast_mode
    shift_word $instance $word
    if {!$fast_mode} { after 2 }
    set captured [shift_word $instance 0]
    if {!$fast_mode} { after 2 }
    return $captured
}

proc verify_ping {instance payload} {
    set payload [expr {$payload & 0xfffffffffffffff}]
    set response [exchange_word $instance [expr {(9 << 60) | $payload}]]
    set expected [expr {(13 << 60) | ($payload ^ 0x5a5a5a5a5a5a5a5)}]
    if {$response != $expected} {
        error [format "PING mismatch: tx=%015llX expected=%016llX actual=%016llX" \
            $payload $expected $response]
    }
}

proc read_status {instance} {
    set status [exchange_word $instance [expr {4 << 60}]]
    if {[expr {($status >> 60) & 0xf}] != 0xa} {
        error [format "invalid status marker: %016llX" $status]
    }
    return $status
}

proc wait_engine_idle {instance timeout_ms} {
    global fast_mode
    set deadline [expr {[clock milliseconds] + $timeout_ms}]
    while 1 {
        set status [read_status $instance]
        set exec_busy [expr {($status >> 29) & 1}]
        if {!$exec_busy} { return $status }
        if {[clock milliseconds] >= $deadline} { error "JTAG command timeout" }
        if {!$fast_mode} { after 2 }
    }
}

proc post_command {instance word} {
    global fast_mode
    if {$fast_mode} {
        send_word $instance $word
    } else {
        shift_word $instance $word
        after 2
        wait_engine_idle $instance 5000
    }
}

proc csv_quote {text} {
    if {[string first "," $text] >= 0 || [string first "\"" $text] >= 0} {
        return "\"[string map {\" \"\"} $text]\""
    }
    return $text
}

set input [open $board_file r]
fconfigure $input -encoding utf-8 -translation auto
set boards {}
while {[gets $input line] >= 0} {
    set line [string trim $line]
    if {$line eq ""} { continue }
    if {![regexp {^([0-9]+) +([0-9]+) +([0-9]+) +(\S+)$} $line -> w h mines name]} {
        error "invalid board header: $line"
    }
    if {$w < 1 || $w > 19 || $h < 1 || $h > 19 || $mines < 1 || $mines >= $w*$h} {
        error "illegal board header: $line"
    }
    set cells {}
    for {set y 0} {$y < $h} {incr y} {
        if {[gets $input row] < 0} { error "unexpected EOF in board $name" }
        set row [string trim $row]
        if {[string length $row] != $w || ![regexp {^[0-9]+$} $row]} {
            error "invalid row $y in board $name"
        }
        foreach digit [split $row ""] { lappend cells [scan $digit %d] }
    }
    lappend boards [list $w $h $mines $name $cells]
    if {[llength $boards] >= $max_boards} { break }
}
close $input
puts "Parsed [llength $boards] board(s)"

set hardware_name ""
foreach candidate [get_hardware_names] {
    if {[string match "*USB-Blaster*" $candidate]} {
        set hardware_name $candidate
        break
    }
}
if {$hardware_name eq ""} { error "USB-Blaster was not found" }
puts "Hardware: $hardware_name"
set devices [get_device_names -hardware_name $hardware_name]
if {[llength $devices] == 0} { error "no JTAG device found on $hardware_name" }
set device_name [lindex $devices 0]
puts "Device: $device_name"

open_device -hardware_name $hardware_name -device_name $device_name
puts "Device opened"
device_lock -timeout 10000
puts "Device locked"
puts "Mode: $run_mode"
set transport_start_ms [clock milliseconds]
set output ""
set completed 0
set total_cycles 0
set total_score_scaled 0
set header "board_index,board_name,width,height,total_mines,selections,opened_safe,opened_mines,cycles,cfg_cycles,load_cycles,solver_cycles,score_cycles,total_board_cycles,score_numerator,score_denominator,score_scaled,score,board_crc,jtag_retries,transport_error,protocol_version,build_id,solver_stalled"
lappend output $header

set rc [catch {
    device_virtual_ir_shift -instance_index $instance_index -ir_value 1 \
        -no_captured_ir_value
    foreach pattern {
        0x0123456789abcde 0x800000000000000 0x000000000000001
        0xaaaaaaaaaaaaaaa 0x555555555555555
    } {
        verify_ping $instance_index $pattern
    }
    puts "PING: 5/5 patterns passed"
    set version [exchange_word $instance_index [expr {8 << 60}]]
    if {[expr {($version >> 60) & 0xf}] != 0xb} {
        error [format "Virtual JTAG protocol not detected: %016llX" $version]
    }
    set build_id [expr {($version >> 44) & 0xffff}]
    set protocol_version [expr {($version >> 36) & 0xff}]

    foreach board $boards {
        lassign $board w h mines name cells
        set board_id [expr {$completed + 1}]
        set status [read_status $instance_index]
        if {[expr {($status >> 34) & 1}] || [expr {($status >> 33) & 1}]} {
            error [format "transport/CRC error before board %d: %016llX" $board_id $status]
        }
        if {[expr {($status >> 31) & 1}]} {
            error "unacknowledged result before board $board_id"
        }

        set crc 0xffff
        foreach value [list $w $h [expr {$mines & 0xff}] [expr {($mines >> 8) & 1}]] {
            set crc [crc16_byte $crc $value]
        }
        foreach value $cells { set crc [crc16_byte $crc $value] }

        set begin [expr {(1 << 60) | ($board_id << 44) | ($w << 39) |
                         ($h << 34) | ($mines << 25)}]
        post_command $instance_index $begin

        set ordinal 0
        set cell_count [llength $cells]
        while {$ordinal < $cell_count} {
            set count [expr {min(11, $cell_count - $ordinal)}]
            set data [expr {(2 << 60) | ($ordinal << 51) | (($count - 1) << 47)}]
            for {set i 0} {$i < $count} {incr i} {
                set data [expr {$data | ([lindex $cells [expr {$ordinal+$i}]] << (4*$i))}]
            }
            post_command $instance_index $data
            incr ordinal $count
        }

        post_command $instance_index [expr {(3 << 60) | $crc}]
        set deadline [expr {[clock milliseconds] + 30000}]
        while 1 {
            set status [read_status $instance_index]
            if {[expr {($status >> 34) & 1}] || [expr {($status >> 33) & 1}] ||
                [expr {($status >> 32) & 1}]} {
                error [format "FPGA error on board %d: %016llX" $board_id $status]
            }
            if {[expr {($status >> 31) & 1}]} { break }
            if {[clock milliseconds] >= $deadline} { error "solver timeout on board $board_id" }
            if {!$fast_mode} { after 2 }
        }

        set result_a [exchange_word $instance_index [expr {5 << 60}]]
        set result_b [exchange_word $instance_index [expr {6 << 60}]]
        if {[expr {($result_a >> 60) & 0xf}] != 0xc} {
            error [format "bad result marker on board %d: %016llX" $board_id $result_a]
        }
        set returned_id [expr {($result_a >> 44) & 0xffff}]
        set returned_w [expr {($result_a >> 39) & 0x1f}]
        set returned_h [expr {($result_a >> 34) & 0x1f}]
        set returned_mines [expr {($result_a >> 25) & 0x1ff}]
        set selections [expr {($result_a >> 22) & 7}]
        set solver_stalled 0
        if {$protocol_version >= 2} {
            set result_c [exchange_word $instance_index [expr {10 << 60}]]
            if {[expr {($result_c >> 60) & 0xf}] != 0xe} {
                error [format "bad extended result marker on board %d: %016llX" \
                    $board_id $result_c]
            }
            set selections [expr {($result_c >> 51) & 0x1ff}]
            set solver_stalled [expr {($result_c >> 50) & 1}]
        }
        set opened_safe [expr {($result_a >> 13) & 0x1ff}]
        set opened_mines [expr {($result_a >> 4) & 0x1ff}]
        set cycles [expr {($result_b >> 32) & 0xffffffff}]
        set score_scaled [expr {$result_b & 0xffffffff}]
        if {$score_scaled >= 0x80000000} { set score_scaled [expr {$score_scaled-0x100000000}] }
        if {$returned_id != $board_id || $returned_w != $w ||
            $returned_h != $h || $returned_mines != $mines} {
            error "result identity mismatch on board $board_id"
        }
        set numerator [expr {$opened_safe*$mines - $opened_mines*($w*$h-$mines)}]
        set denominator [expr {($w*$h-$mines)*$mines}]
        # Match Verilog signed division: truncate toward zero.  Tcl integer
        # division floors a negative quotient, which differs by one when a
        # remainder is present.
        if {$numerator < 0} {
            set expected_scaled [expr {-((-$numerator*10000)/$denominator)}]
        } else {
            set expected_scaled [expr {($numerator*10000)/$denominator}]
        }
        if {$expected_scaled != $score_scaled} {
            error "score mismatch on board $board_id: FPGA=$score_scaled PC=$expected_scaled"
        }
        set score [format %.4f [expr {$score_scaled/10000.0}]]
        lappend output [join [list $board_id [csv_quote $name] $w $h $mines \
            $selections $opened_safe $opened_mines $cycles 0 0 $cycles 0 $cycles \
            $numerator $denominator $score_scaled $score [format %04X $crc] 0 0 \
            $protocol_version [format %04X $build_id] $solver_stalled] ,]
        incr completed
        incr total_cycles $cycles
        incr total_score_scaled $score_scaled

        post_command $instance_index [expr {7 << 60}]
        if {$completed % 25 == 0} {
            puts "JTAG progress: $completed/[llength $boards] boards"
        }
    }
} message options]

device_unlock
close_device

if {$rc} {
    return -options $options $message
}
file mkdir [file dirname $result_file]
set out [open $result_file w]
fconfigure $out -encoding utf-8 -translation lf
puts $out [join $output "\n"]
close $out
set transport_elapsed_ms [expr {[clock milliseconds] - $transport_start_ms}]
puts "JTAG RUN COMPLETE: $completed boards, cycles=$total_cycles, score_scaled=$total_score_scaled"
puts "JTAG TRANSPORT: mode=$run_mode scans=$scan_count elapsed_ms=$transport_elapsed_ms"
puts "CSV: $result_file"
