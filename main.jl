# Run from the project directory: julia --project=. main.jl
include(joinpath(@__DIR__,"src","ShiftScheduling.jl"))
using .ShiftScheduling

function main(args=ARGS)
    input = joinpath(@__DIR__,"data","input.xlsx")
    output = joinpath(@__DIR__,"results")
    solver_log,export_lp = false,false
    i = 1
    while i<=length(args)
        flag = args[i]
        if flag in ("--input","--output")
            i<length(args) || throw(ArgumentError("Missing value after $flag"))
            flag=="--input" ? (input=args[i+1]) : (output=args[i+1])
            i+=2
        elseif flag=="--solver-log"
            solver_log=true; i+=1
        elseif flag=="--export-lp"
            export_lp=true; i+=1
        elseif flag in ("--help","-h")
            println("julia --project=. main.jl [--input data/input.xlsx] [--output results] [--solver-log] [--export-lp]")
            return 0
        else
            throw(ArgumentError("Unknown option: $flag"))
        end
    end
    try
        data = prepare_data(load_input(input))
        @info "Building scheduling model" employees=length(data.A) days=length(data.B) teams=length(data.C) shifts=length(data.S)
        result = solve_schedule(data;solver_log,lp_path=export_lp ? joinpath(output,"model.lp") : nothing)
        result["input_file"] = abspath(input)
        export_result(result,output)
        @info "Solver finished" status=result["status"] seconds=result["seconds"]
        if haskey(result,"metrics")
            m=result["metrics"]
            println("Objective: ",m["objective_recomputed"])
            println("Shortage (person-slots): ",m["shortage_person_slots"])
            println("Preference violations: ",m["preference_violations"])
            println("Absolute hour deviation: ",m["hour_deviation"])
            println("Files written to: ",abspath(output))
            return 0
        end
        @error "No feasible schedule; see result.json" message=result["message"]
        return 3
    catch err
        err isa InterruptException && rethrow()
        @error "Scheduling failed" exception=(err,catch_backtrace())
        export_result(Dict("status"=>"ERROR","message"=>sprint(showerror,err)),output)
        return 2
    end
end

if abspath(PROGRAM_FILE)==@__FILE__
    exit(main())
end
