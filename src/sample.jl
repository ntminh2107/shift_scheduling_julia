"""Same deterministic synthetic data as generate_input.py in the Python project."""
function sample_input()
    raw = Dict{String,Any}()
    raw["Employees"] = [Dict{String,Any}("a"=>"E"*lpad(string(i+1),2,'0'),"name"=>"Nhan vien "*lpad(string(i+1),2,'0'),
        "c"=>i<6 ? "Team_A" : "Team_B","min_hours"=>24,"target_hours"=>32,"max_hours"=>40) for i in 0:11]
    raw["Days"] = [Dict{String,Any}("b"=>b,"date"=>string(Date(2026,10,26)+Day(b-1))) for b in 1:7]
    raw["Shifts"] = [Dict{String,Any}("s"=>s,"label"=>label,"start"=>st,"end"=>en) for (s,label,st,en) in
        [("S1","Sang",6,14),("S2","Chieu",10,18),("S3","Toi",14,22),("G1","Gay sang",6,10),("G2","Gay toi",18,22)]]
    raw["Slots"] = [Dict{String,Any}("k"=>"K$(i+1)","start"=>6+4i,"end"=>10+4i) for i in 0:3]
    raw["Availability"],raw["Preferences"] = Dict{String,Any}[],Dict{String,Any}[]
    for (j,employee) in enumerate(raw["Employees"])
        i = j-1
        for b in 1:7
            push!(raw["Availability"],Dict("a"=>employee["a"],"b"=>b,"available"=>Int(b!=mod(i,7)+1)))
            preference = ["S1","S2","S3"][mod(i+b,3)+1]
            for shift in raw["Shifts"]
                s = shift["s"]
                allowed = !startswith(s,"G") || mod(i,3)!=0
                i in (0,6) && s in ("S3","G2") && (allowed=false)
                preferred = allowed && (s==preference || s==get(Dict("S1"=>"G1","S3"=>"G2"),preference,""))
                push!(raw["Preferences"],Dict("a"=>employee["a"],"b"=>b,"s"=>s,"allowed"=>Int(allowed),"preferred"=>Int(preferred)))
            end
        end
    end
    # Use comprehensions with `for` to keep these as a vector of records.
    raw["Demand"] = [Dict{String,Any}("b"=>b,"c"=>c,"k"=>"K$k","required"=>[2,1,1,2][k]) for b in 1:7 for c in ["Team_A","Team_B"] for k in 1:4]
    raw["Config"] = [Dict{String,Any}("key"=>key,"value"=>value) for (key,value) in
        [("lambda_shortage",100),("lambda_preference",10),("lambda_hours",1),("max_consecutive",5),("time_limit",60),("mip_gap",0)]]
    return raw
end
