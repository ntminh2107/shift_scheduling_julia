# Export the current monthly workbook to the canonical JSON schema.
include(joinpath(@__DIR__,"src","ShiftScheduling.jl"))
using .ShiftScheduling
input=length(ARGS)>=1 ? ARGS[1] : joinpath(@__DIR__,"data","input.xlsx")
output=length(ARGS)>=2 ? ARGS[2] : joinpath(@__DIR__,"data","input.json")
length(ARGS)<=2 || error("Usage: generate_input.jl [input.xlsx] [output.json]")
raw=load_input(input)
prepare_data(raw)
save_json(output,raw)
println("Validated JSON saved to: ",abspath(output))
