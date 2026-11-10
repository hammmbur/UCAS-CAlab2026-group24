set project_file [file normalize [file join [file dirname [info script]] .. soc_verify soc_axi run_vivado project loongson.xpr]]
open_project $project_file
upgrade_ip [get_ips]
generate_target all [get_ips]
launch_simulation
run 20 ms
close_sim
close_project
