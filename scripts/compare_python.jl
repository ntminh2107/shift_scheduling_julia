# Compare objective and feasibility, not cell-by-cell schedules (optima can tie).
using JSON3
root=normpath(joinpath(@__DIR__,".."))
length(ARGS)==2 || error("Pass Julia and Python result files from the SAME input/model. Monthly results must not use the weekly reference.")
julia_result=ARGS[1]
python_result=ARGS[2]
j=JSON3.read(read(julia_result,String))
p=JSON3.read(read(python_result,String))
haskey(j,:metrics) || error("Julia result contains no feasible schedule")
j.status=="OPTIMAL" && p.status=="OPTIMAL" || error("Both results must be optimal for this comparison")
@assert isapprox(j.metrics.objective_recomputed,p.metrics.objective_recomputed;atol=1e-5)
@assert j.metrics.hard_constraint_violations==0
println("PASS: objective and hard constraints agree with the Python reference.")
for key in [:objective_recomputed,:shortage_person_slots,:preference_violations,:hour_deviation,:worked_shifts,:preference_rate]
    println(key," | Julia: ",j.metrics[key]," | Python: ",p.metrics[key])
end
