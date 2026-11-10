set project_file [file normalize [file join [file dirname [info script]] .. soc_verify soc_axi run_vivado project loongson.xpr]]
open_project $project_file
reset_run synth_1
foreach ip_run [get_runs *_synth_1] {
    if {[get_property NAME $ip_run] ne "synth_1"} {
        reset_run $ip_run
    }
}
launch_runs synth_1 -jobs 4
wait_on_run synth_1
set status [get_property STATUS [get_runs synth_1]]
puts "Synthesis status: $status"
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} {
    error "Synthesis did not complete"
}
close_project
