"""Check the decoded schedule without using JuMP's constraint matrix."""
function verify_schedule(data, selected; tolerance=1e-6)
    errors = String[]
    A,B,S = data.A,data.B,data.S
    for a in A
        working = Dict(b=>sum(selected[(a,b,s)] for s in S) for b in B)
        for b in B
            working[b] <= data.v[(a,b)] || push!(errors,"R1:$a:$b")
            for s in S
                val = selected[(a,b,s)]
                (val in (0,1) && val <= data.allowed[(a,b,s)]) || push!(errors,"R2:$a:$b:$s")
            end
        end
        hours = sum(data.h[s]*selected[(a,b,s)] for b in B,s in S)
        data.hmin[a]-tolerance <= hours <= data.hmax[a]+tolerance || push!(errors,"R4:$a")
        for b in B[1:end-1]
            late = sum(selected[(a,b,s)] for s in data.late; init=0)
            early = sum(selected[(a,b+1,s)] for s in data.early; init=0)
            late+early <= 1 || push!(errors,"R5:$a:$b")
        end
        for b in 1:(length(B)-data.L)
            sum(working[t] for t in b:(b+data.L)) <= data.L || push!(errors,"R6:$a:$b")
        end
    end
    if data.extended
        for a in A
            for b in 1:(length(B)-6)
                sum(data.h[s]*selected[(a,t,s)] for t in b:b+6,s in S)<=data.cfg["max_hours_7days"]+tolerance || push!(errors,"R7:$a:$b")
            end
            sum(selected[(a,b,s)] for b in B,s in data.late;init=0)<=data.cfg["max_late_shifts"] || push!(errors,"R8:$a")
            sum(selected[(a,b,s)] for b in data.weekends,s in S;init=0)<=data.cfg["max_weekend_days"] || push!(errors,"R9:$a")
        end
        for b in B,c in data.C
            sum(selected[(a,b,s)] for a in data.supervisors[c],s in S;init=0)>=data.cfg["min_supervisors_per_day"] || push!(errors,"R10:$b:$c")
        end
    end
    return errors
end

finite_or_null(x) = x isa Real && isfinite(x) ? x : nothing

function solve_schedule(data; solver_log=false, lp_path=nothing)
    bundle = build_model(data;solver_log)
    model,x,u,z = bundle.model,bundle.x,bundle.u,bundle.z
    if lp_path !== nothing
        mkpath(dirname(abspath(lp_path)))
        write_to_file(model,lp_path)
    end
    started = time_ns()
    optimize!(model)
    elapsed = (time_ns()-started)/1e9
    termination = termination_status(model)
    result = Dict{String,Any}(
        "termination_status"=>string(termination),"primal_status"=>string(primal_status(model)),
        "message"=>raw_status(model),"seconds"=>elapsed,
        "julia_version"=>string(VERSION),"jump_version"=>string(pkgversion(JuMP)),
        "highs_package_version"=>string(pkgversion(HiGHS)),"solver"=>solver_name(model),
        "period_start"=>string(data.dates[first(data.B)]),
        "period_end"=>string(data.dates[last(data.B)]),"days"=>length(data.B),
        "binary_variables"=>length(data.A)*length(data.B)*length(data.S),
        "continuous_variables"=>length(u)+length(z),
        "constraints"=>num_constraints(model; count_variable_in_set_constraints=false),
    )
    if primal_status(model) != MOI.FEASIBLE_POINT || !has_values(model)
        result["status"] = termination == MOI.INFEASIBLE ? "INFEASIBLE" :
            termination == MOI.TIME_LIMIT ? "LIMIT_NO_SOLUTION" : "NO_FEASIBLE_SOLUTION"
        return result
    end
    # A feasible incumbent at a time limit is useful, but never called optimal.
    result["status"] = termination == MOI.OPTIMAL ? "OPTIMAL" : "FEASIBLE_NOT_PROVEN_OPTIMAL"
    A,B,C,S,K = data.A,data.B,data.C,data.S,data.K
    selected = Dict((a,b,s)=>round(Int,value(x[a,b,s])) for a in A,b in B,s in S)
    all(abs(value(x[a,b,s])-selected[(a,b,s)])<=1e-5 for a in A,b in B,s in S) || error("Nonintegral incumbent")
    errors = verify_schedule(data,selected)
    coverage = Dict{String,Any}[]
    for b in B,c in C,k in K
        actual = sum(data.q[(s,k)]*selected[(a,b,s)] for a in data.members[c],s in S)
        required = data.d[(b,c,k)]
        shortage,surplus = max(0,required-actual),max(0,actual-required)
        value(u[b,c,k]) >= shortage-1e-5 || push!(errors,"R3:$b:$c:$k")
        push!(coverage,Dict("b"=>b,"c"=>c,"k"=>k,"required"=>required,"actual"=>actual,
                            "shortage"=>shortage,"surplus"=>surplus))
    end
    assignments,schedule,hours_rows = Dict{String,Any}[],Dict{String,Any}[],Dict{String,Any}[]
    for a in A
        employee = data.employees[(a,)]
        wide = Dict{String,Any}("a"=>a,"name"=>employee["name"],"role"=>get(employee,"role",""),"c"=>data.team[a])
        for b in B
            assigned = [s for s in S if selected[(a,b,s)]==1]
            s = isempty(assigned) ? "OFF" : only(assigned)
            wide[string(data.dates[b])] = s
            violation = s=="OFF" ? 0 : 1-data.preferred[(a,b,s)]
            push!(assignments,Dict("a"=>a,"name"=>employee["name"],"role"=>get(employee,"role",""),"c"=>data.team[a],"b"=>b,
                "date"=>string(data.dates[b]),"shift"=>s,"hours"=>get(data.h,s,0.0),"preference_violation"=>violation))
        end
        push!(schedule,wide)
        total = sum(data.h[s]*selected[(a,b,s)] for b in B,s in S)
        deviation = abs(total-data.target[a])
        value(z[a]) >= deviation-1e-5 || push!(errors,"Deviation:$a")
        push!(hours_rows,Dict("a"=>a,"name"=>employee["name"],"role"=>get(employee,"role",""),"c"=>data.team[a],"min_hours"=>data.hmin[a],"target_hours"=>data.target[a],
            "max_hours"=>data.hmax[a],"actual_hours"=>total,"deviation"=>deviation))
    end
    isempty(errors) || error("Independent validation failed: $(join(errors,", "))")
    z1 = sum(r["shortage"] for r in coverage)
    z2 = sum(r["preference_violation"] for r in assignments)
    z3 = sum(r["deviation"] for r in hours_rows)
    total_demand = sum(r["required"] for r in coverage)
    worked = count(r->r["shift"]!="OFF",assignments)
    recomputed = data.cfg["lambda_shortage"]*z1+data.cfg["lambda_preference"]*z2+data.cfg["lambda_hours"]*z3
    metrics = Dict{String,Any}(
        "shortage_person_slots"=>z1,"preference_violations"=>z2,"hour_deviation"=>z3,
        "total_demand_person_slots"=>total_demand,
        "coverage_rate"=>total_demand==0 ? nothing : 1-z1/total_demand,
        "preference_rate"=>worked==0 ? nothing : 1-z2/worked,
        "worked_shifts"=>worked,"broken_shifts"=>count(r->startswith(r["shift"],"G"),assignments),
        "surplus_person_slots"=>sum(r["surplus"] for r in coverage),
        "actual_hours"=>sum(r["actual_hours"] for r in hours_rows),
        "objective_recomputed"=>recomputed,"solver_objective"=>objective_value(model),
        "objective_auxiliary_slack"=>objective_value(model)-recomputed,
        "hard_constraint_violations"=>length(errors),
    )
    result["mip_gap"] = finite_or_null(relative_gap(model))
    result["mip_dual_bound"] = finite_or_null(objective_bound(model))
    result["metrics"] = metrics
    result["schedule"],result["assignments"] = schedule,assignments
    result["hours"],result["coverage"] = hours_rows,coverage
    return result
end

function save_json(path,object)
    mkpath(dirname(abspath(path)))
    open(path,"w") do io
        JSON3.pretty(io,object)
        println(io)
    end
end

function export_result(result,output_dir)
    mkpath(output_dir)
    save_json(joinpath(output_dir,"result.json"),result)
    fields = Dict(
        "assignments"=>["a","name","role","c","b","date","shift","hours","preference_violation"],
        "coverage"=>["b","c","k","required","actual","shortage","surplus"],
        "hours"=>["a","name","role","c","min_hours","target_hours","max_hours","actual_hours","deviation"],
    )
    for name in ["schedule","assignments","coverage","hours"]
        path = joinpath(output_dir,name*".csv")
        if !haskey(result,name)
            isfile(path) && rm(path) # Remove only this program's stale schedule files.
            continue
        end
        rows = result[name]
        columns = name=="schedule" ? vcat(["a","name","role","c"],sort([k for k in keys(first(rows)) if tryparse(Date,k)!==nothing])) : fields[name]
        df = DataFrame([Symbol(k)=>[r[k] for r in rows] for k in columns])
        CSV.write(path,df;bom=true)
    end
end
