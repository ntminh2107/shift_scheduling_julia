using Test, JuMP, JSON3
include(joinpath(@__DIR__,"..","src","ShiftScheduling.jl"))
using .ShiftScheduling
const ROOT = normpath(joinpath(@__DIR__,".."))

@testset "Input parity: Excel, JSON, Julia generator" begin
    json = prepare_data(load_input(joinpath(ROOT,"test","fixtures","legacy.json")))
    excel = prepare_data(load_input(joinpath(ROOT,"test","fixtures","legacy.xlsx")))
    generated = prepare_data(sample_input())
    for field in (:A,:B,:C,:S,:K,:h,:q,:v,:allowed,:preferred,:d,:cfg,:dates,:hmin,:hmax,:target)
        @test getproperty(json,field)==getproperty(excel,field)==getproperty(generated,field)
    end
end

@testset "Baseline and Python objective parity" begin
    data=prepare_data(load_input(joinpath(ROOT,"test","fixtures","legacy.xlsx")))
    result=solve_schedule(data)
    reference=JSON3.read(read(joinpath(ROOT,"reference_python","result.json"),String))
    @test result["status"]=="OPTIMAL"
    @test result["metrics"]["objective_recomputed"] ≈ reference.metrics.objective_recomputed atol=1e-5
    @test result["metrics"]["solver_objective"] ≈ result["metrics"]["objective_recomputed"] atol=1e-5
    @test result["metrics"]["hard_constraint_violations"]==0
    @test result["metrics"]["shortage_person_slots"]==0
    @test result["binary_variables"]==420
    @test result["continuous_variables"]==68
    # Multiple optimum schedules may have different shift counts/preferences.
    mktempdir() do out
        export_result(result,out)
        @test all(isfile(joinpath(out,n)) for n in ["result.json","schedule.csv","assignments.csv","coverage.csv","hours.csv"])
        export_result(Dict("status"=>"INFEASIBLE"),out)
        @test isfile(joinpath(out,"result.json"))
        @test !isfile(joinpath(out,"schedule.csv"))
        @test !isfile(joinpath(out,"coverage.csv"))
    end
end

@testset "Exhaustive two-day oracle including late-to-early restriction" begin
    raw=sample_input()
    raw["Employees"]=[Dict{String,Any}("a"=>"E01","name"=>"Test","c"=>"Team_A","min_hours"=>0,"target_hours"=>8,"max_hours"=>16)]
    raw["Days"]=raw["Days"][1:2]
    raw["Availability"]=[Dict{String,Any}("a"=>"E01","b"=>b,"available"=>1) for b in 1:2]
    raw["Preferences"]=[Dict{String,Any}("a"=>"E01","b"=>b,"s"=>s["s"],"allowed"=>1,"preferred"=>Int(s["s"]=="G1")) for b in 1:2 for s in raw["Shifts"]]
    raw["Demand"]=[Dict{String,Any}("b"=>b,"c"=>"Team_A","k"=>k["k"],"required"=>Int((b,k["k"]) in [(1,"K4"),(2,"K1")])) for b in 1:2 for k in raw["Slots"]]
    data=prepare_data(raw)
    costs=Float64[]
    for s1 in vcat(["OFF"],data.S),s2 in vcat(["OFF"],data.S)
        s1 in ["S3","G2"] && s2 in ["S1","G1"] && continue
        h=get(data.h,s1,0)+get(data.h,s2,0)
        h>16 && continue
        shortage=Int(!(s1 in ["S3","G2"]))+Int(!(s2 in ["S1","G1"]))
        violations=count(s->!(s in ["OFF","G1"]),[s1,s2])
        push!(costs,100*shortage+10*violations+abs(h-8))
    end
    result=solve_schedule(data)
    @test result["status"]=="OPTIMAL"
    @test result["metrics"]["solver_objective"] ≈ minimum(costs) atol=1e-5
end

@testset "Demand shortage remains feasible" begin
    raw=sample_input()
    for r in raw["Demand"]
        r["required"]=10
    end
    result=solve_schedule(prepare_data(raw))
    @test haskey(result,"metrics")
    @test result["metrics"]["shortage_person_slots"]>0
    @test result["metrics"]["hard_constraint_violations"]==0
end

@testset "Unavailable employee with positive minimum hours is infeasible" begin
    raw=sample_input()
    for r in raw["Availability"]
        r["a"]=="E01" && (r["available"]=0)
    end
    result=solve_schedule(prepare_data(raw))
    @test result["status"]=="INFEASIBLE"
    @test !haskey(result,"schedule")
end

@testset "R6: six mandatory eight-hour days cannot fit a five-day streak limit" begin
    raw=sample_input()
    raw["Employees"]=[Dict{String,Any}("a"=>"E01","name"=>"Test","c"=>"Team_A","min_hours"=>48,"target_hours"=>48,"max_hours"=>48)]
    raw["Days"]=raw["Days"][1:6]
    raw["Availability"]=[Dict{String,Any}("a"=>"E01","b"=>b,"available"=>1) for b in 1:6]
    raw["Preferences"]=[Dict{String,Any}("a"=>"E01","b"=>b,"s"=>s["s"],"allowed"=>Int(s["s"]=="S2"),"preferred"=>Int(s["s"]=="S2")) for b in 1:6 for s in raw["Shifts"]]
    raw["Demand"]=[Dict{String,Any}("b"=>b,"c"=>"Team_A","k"=>k["k"],"required"=>0) for b in 1:6 for k in raw["Slots"]]
    @test solve_schedule(prepare_data(raw))["status"]=="INFEASIBLE"
end

@testset "Zero denominators and zero work" begin
    raw=sample_input()
    for r in raw["Employees"],f in ["min_hours","target_hours","max_hours"]
        r[f]=0
    end
    for r in raw["Demand"]
        r["required"]=0
    end
    result=solve_schedule(prepare_data(raw))
    @test result["status"]=="OPTIMAL"
    @test result["metrics"]["worked_shifts"]==0
    @test result["metrics"]["coverage_rate"]===nothing
    @test result["metrics"]["preference_rate"]===nothing
end

@testset "Input errors" begin
    raw=sample_input()
    push!(raw["Preferences"],deepcopy(raw["Preferences"][1]))
    @test_throws ArgumentError prepare_data(raw)
    raw=sample_input(); pop!(raw["Demand"])
    @test_throws ArgumentError prepare_data(raw)
    raw=sample_input(); raw["Preferences"][1]["allowed"]=2
    @test_throws ArgumentError prepare_data(raw)
    raw=sample_input(); raw["Shifts"][1]["start"]=7
    @test_throws ArgumentError prepare_data(raw)
end

@testset "Monthly template semantics and validation" begin
    import XLSX, Dates
    grids=XLSX.openxlsx(joinpath(ROOT,"data","input.xlsx")) do xf
        Dict(s=>(collect(XLSX.eachrow(xf[s])); xf[s][:]) for s in ["Nhu cầu nhân sự","Nguyện vọng nhân sự","List ràng buộc"])
    end
    normalize(g)=prepare_data(ShiftScheduling.template_tables(g))
    data=normalize(grids)
    json=prepare_data(load_input(joinpath(ROOT,"data","input.json")))
    for field in (:A,:B,:C,:S,:K,:v,:allowed,:preferred,:d,:cfg,:dates,:hmin,:hmax,:target,:employees)
        @test getproperty(data,field)==getproperty(json,field)
    end
    @test length(data.B)==30
    @test all(==(160),values(data.target))
    @test all(!isempty(e["role"]) for e in values(data.employees))
    g=deepcopy(grids); g["Nguyện vọng nhân sự"][3,10]=missing
    d=normalize(g)
    @test d.v[("E01",1)]==1
    @test all(d.preferred[("E01",1,s)]==d.allowed[("E01",1,s)] for s in d.S)
    g["Nguyện vọng nhân sự"][3,10]="n"
    d=normalize(g); @test d.preferred[("E01",1,"S1")]==d.preferred[("E01",1,"S2")]==1
    g["Nguyện vọng nhân sự"][3,10]="OFF"
    @test normalize(g).v[("E01",1)]==0
    g["Nguyện vọng nhân sự"][3,10]="S3"
    @test_throws ArgumentError normalize(g)
    g["Nguyện vọng nhân sự"][3,10]="S99"
    @test_throws ArgumentError normalize(g)
    g=deepcopy(grids);g["Nguyện vọng nhân sự"][3,5]=1
    d=normalize(g)
    @test d.hmin["E01"]==d.target["E01"]==d.hmax["E01"]==0
    @test all(d.v[("E01",b)]==0 for b in d.B)
    g=deepcopy(grids);g["Nguyện vọng nhân sự"][4,1]="E01"
    @test_throws ArgumentError normalize(g)
    g=deepcopy(grids);g["Nguyện vọng nhân sự"][1,11]=g["Nguyện vọng nhân sự"][1,10]
    @test_throws ArgumentError normalize(g)
    g=deepcopy(grids);g["Nhu cầu nhân sự"][2,5]=-1
    @test_throws ArgumentError normalize(g)
    # February, leap February, and a 31-day month; no fixed 30-column assumption.
    for start in [Dates.Date(2026,2,1),Dates.Date(2028,2,1),Dates.Date(2026,7,1)]
        g=deepcopy(grids);n=Dates.daysinmonth(start)
        p=Matrix{Any}(missing,14,9+n);p[:,1:9]=g["Nguyện vọng nhân sự"][:,1:9]
        for b in 1:n;p[1,9+b]=start+Dates.Day(b-1);end
        g["Nguyện vọng nhân sự"]=p
        @test length(normalize(g).B)==n
    end
    # Check a streak spanning a week boundary (days 5..10), independently of solver.
    selected=Dict((a,b,s)=>0 for a in data.A,b in data.B,s in data.S)
    for b in 5:10;selected[("E01",b,"S2")]=1;end
    @test any(startswith(e,"R6:E01") for e in verify_schedule(data,selected))
end

@testset "R7-R10: independent rules and impossible staffing" begin
    data=prepare_data(load_input(joinpath(ROOT,"data","input.xlsx")))
    @test data.extended
    @test all(length(v)==2 for v in values(data.supervisors))
    zeroschedule()=Dict((a,b,s)=>0 for a in data.A,b in data.B,s in data.S)
    x=zeroschedule()
    for b in [1,2,3,5,6,7];x[("E02",b,"S2")]=1;end
    errors=verify_schedule(data,x)
    @test any(startswith(e,"R7:E02") for e in errors)
    @test !any(startswith(e,"R6:E02") for e in errors)
    x=zeroschedule()
    for b in 1:2:29;x[("E02",b,"S3")]=1;end
    @test "R8:E02" in verify_schedule(data,x)
    x=zeroschedule()
    for b in data.weekends[1:7];x[("E02",b,"G1")]=1;end
    @test "R9:E02" in verify_schedule(data,x)
    @test any(startswith(e,"R10:") for e in verify_schedule(data,zeroschedule()))
    raw=load_input(joinpath(ROOT,"data","input.xlsx"))
    for r in raw["Availability"]
        r["a"] in ["E01","E02"] && r["b"]==1 && (r["available"]=0)
    end
    @test solve_schedule(prepare_data(raw))["status"]=="INFEASIBLE"
    raw=load_input(joinpath(ROOT,"data","input.xlsx"))
    pop!(raw["Config"])
    @test_throws ArgumentError prepare_data(raw)
end
