# Read the existing Python-project schema, then validate and normalize all keys.
const TABLE_FIELDS = Dict(
    "Employees" => ["a", "name", "c", "min_hours", "target_hours", "max_hours"],
    "Days" => ["b", "date"],
    "Shifts" => ["s", "label", "start", "end"],
    "Slots" => ["k", "start", "end"],
    "Availability" => ["a", "b", "available"],
    "Preferences" => ["a", "b", "s", "allowed", "preferred"],
    "Demand" => ["b", "c", "k", "required"],
    "Config" => ["key", "value"],
)

mutable_json(x::AbstractDict) = Dict{String,Any}(string(k) => mutable_json(v) for (k,v) in pairs(x))
mutable_json(x::AbstractVector) = Any[mutable_json(v) for v in x]
mutable_json(x) = x

function load_input(path::AbstractString)
    isfile(path) || throw(ArgumentError("Input does not exist: $path"))
    ext = lowercase(splitext(path)[2])
    if ext == ".json"
        return mutable_json(JSON3.read(read(path, String)))
    elseif ext == ".xlsx"
        sheets = XLSX.openxlsx(path) do xf
            XLSX.sheetnames(xf)
        end
        "Nguyện vọng nhân sự" in sheets && return load_template(path)
        raw = Dict{String,Any}()
        for table in keys(TABLE_FIELDS)
            frame = DataFrame(XLSX.readtable(path, table; infer_eltypes=true))
            raw[table] = [Dict{String,Any}(name => r[Symbol(name)] for name in names(frame)) for r in eachrow(frame)]
        end
        return raw
    end
    throw(ArgumentError("Input must be .xlsx or .json"))
end

function numeric(v, label; lower=0.0, integer=false)
    v isa Real && !(v isa Bool) || throw(ArgumentError("$label must be numeric"))
    f = Float64(v)
    isfinite(f) && f >= lower || throw(ArgumentError("$label must be finite and >= $lower"))
    integer && !isinteger(f) && throw(ArgumentError("$label must be an integer"))
    return integer ? Int(f) : f
end

function identifier(v, label)
    v isa AbstractString && !isempty(strip(v)) || throw(ArgumentError("$label must be nonblank text"))
    return strip(String(v))
end

function binary(v, label)
    n = numeric(v, label; integer=true)
    n in (0,1) || throw(ArgumentError("$label must be 0 or 1"))
    return n
end

function unique_table(rows, fields, table)
    out = Dict{Tuple,Dict{String,Any}}()
    for row in rows
        key = Tuple(row[f] for f in fields)
        haskey(out,key) && throw(ArgumentError("Duplicate key in $table: $key"))
        out[key] = row
    end
    return out
end

function prepare_data(raw)
    raw = deepcopy(raw)
    # Do not silently drop blank rows or fill missing input flags with zero.
    for (table, fields) in TABLE_FIELDS
        haskey(raw,table) && !isempty(raw[table]) || throw(ArgumentError("Missing/empty table: $table"))
        for (i,row) in enumerate(raw[table])
            all(haskey(row,f) && !ismissing(row[f]) && row[f] !== nothing for f in fields) ||
                throw(ArgumentError("Missing field in $table, data row $i"))
            for f in intersect(fields,["a","c","s","k","key","name","label"])
                row[f] = identifier(row[f],"$table.$f")
            end
            if "b" in fields
                row["b"] = numeric(row["b"],"$table.b"; lower=1,integer=true)
            end
        end
    end
    employees = unique_table(raw["Employees"],["a"],"Employees")
    days = unique_table(raw["Days"],["b"],"Days")
    shifts = unique_table(raw["Shifts"],["s"],"Shifts")
    slots = unique_table(raw["Slots"],["k"],"Slots")
    availability = unique_table(raw["Availability"],["a","b"],"Availability")
    preferences = unique_table(raw["Preferences"],["a","b","s"],"Preferences")
    demand = unique_table(raw["Demand"],["b","c","k"],"Demand")
    config = unique_table(raw["Config"],["key"],"Config")

    A = String[r["a"] for r in raw["Employees"]]
    B = sort(Int[r["b"] for r in raw["Days"]])
    C = sort(unique(String[r["c"] for r in raw["Employees"]]))
    S = String[r["s"] for r in raw["Shifts"]]
    K = String[r["k"] for r in raw["Slots"]]
    "OFF" in S && throw(ArgumentError("OFF is reserved for days off; do not define it as a shift"))
    B == collect(1:length(B)) || throw(ArgumentError("Days.b must be 1..N without gaps"))
    dates = Dict{Int,Date}()
    for b in B
        value = days[(b,)]["date"]
        dates[b] = value isa Date ? value : value isa DateTime ? Date(value) : Date(string(value))
    end
    all(dates[b+1]-dates[b] == Day(1) for b in B[1:end-1]) || throw(ArgumentError("Calendar dates must be consecutive"))
    for r in values(employees)
        for f in ["min_hours","target_hours","max_hours"]
            r[f] = numeric(r[f],"Employees.$f")
        end
        r["min_hours"] <= r["target_hours"] <= r["max_hours"] || throw(ArgumentError("Require min_hours <= target_hours <= max_hours"))
    end
    for (table,rows) in [("Shifts",shifts),("Slots",slots)]
        for r in values(rows)
            r["start"] = numeric(r["start"],"$table.start")
            r["end"] = numeric(r["end"],"$table.end")
            0 <= r["start"] < r["end"] <= 24 || throw(ArgumentError("$table only supports same-day intervals 0 <= start < end <= 24"))
        end
    end
    sorted_slots = sort(collect(values(slots)); by=r->r["start"])
    all(sorted_slots[i]["end"] <= sorted_slots[i+1]["start"] for i in 1:length(K)-1) || throw(ArgumentError("Slots must not overlap"))
    h = Dict(s => shifts[(s,)]["end"]-shifts[(s,)]["start"] for s in S)
    q = Dict{Tuple{String,String},Int}()
    for s in S, k in K
        sr, kr = shifts[(s,)], slots[(k,)]
        full = sr["start"] <= kr["start"] && sr["end"] >= kr["end"]
        overlap = max(0,min(sr["end"],kr["end"])-max(sr["start"],kr["start"]))
        overlap > 0 && !full && throw(ArgumentError("Shift $s only partly covers $k; split slot boundaries"))
        q[(s,k)] = Int(full)
    end
    all(any(q[(s,k)]==1 for k in K) for s in S) || throw(ArgumentError("Every shift must cover a slot"))
    for (table,rows,expected) in [
        ("Availability",availability,Set((a,b) for a in A for b in B)),
        ("Preferences",preferences,Set((a,b,s) for a in A for b in B for s in S)),
        ("Demand",demand,Set((b,c,k) for b in B for c in C for k in K)),
    ]
        Set(keys(rows)) == expected || throw(ArgumentError("$table has missing or unexpected keys; provide every combination"))
    end
    v = Dict((a,b)=>binary(availability[(a,b)]["available"],"available") for a in A for b in B)
    allowed = Dict((a,b,s)=>binary(preferences[(a,b,s)]["allowed"],"allowed") for a in A for b in B for s in S)
    preferred = Dict((a,b,s)=>binary(preferences[(a,b,s)]["preferred"],"preferred") for a in A for b in B for s in S)
    all(preferred[key]<=allowed[key] for key in keys(allowed)) || throw(ArgumentError("Preferred shifts must also be allowed"))
    d = Dict((b,c,k)=>numeric(demand[(b,c,k)]["required"],"required";integer=true) for b in B for c in C for k in K)
    cfg_names = ["lambda_shortage","lambda_preference","lambda_hours","max_consecutive","time_limit","mip_gap"]
    extra_names=["max_hours_7days","max_late_shifts","max_weekend_days","min_supervisors_per_day"]
    actual_names=Set(k[1] for k in keys(config))
    extended=actual_names==Set(vcat(cfg_names,extra_names))
    (extended || actual_names==Set(cfg_names)) || throw(ArgumentError("Config must contain the six base keys, and either all four extended rule keys or none"))
    cfg = Dict(key=>numeric(config[(key,)]["value"],key) for key in actual_names)
    if extended
        cfg["max_hours_7days"]>0 || throw(ArgumentError("max_hours_7days must be positive"))
        for key in extra_names[2:end]
            numeric(cfg[key],key;integer=true)
        end
    end
    all(cfg[key]>0 for key in ["lambda_shortage","lambda_preference","lambda_hours","time_limit"]) || throw(ArgumentError("Weights and time_limit must be positive"))
    L = numeric(cfg["max_consecutive"],"max_consecutive";lower=1,integer=true)
    cfg["mip_gap"]<=1 || throw(ArgumentError("mip_gap must be between 0 and 1"))
    team = Dict(a=>employees[(a,)]["c"] for a in A)
    members = Dict(c=>[a for a in A if team[a]==c] for c in C)
    supervisors=Dict(c=>[a for a in members[c] if get(employees[(a,)],"role","")=="Shift Supervisor"] for c in C)
    weekends=[b for b in B if dayofweek(dates[b]) in (6,7)]
    return (; extended,supervisors,weekends,A,B,C,S,K,employees,dates,shifts,slots,h,q,v,allowed,preferred,d,cfg,L,team,members,
            hmin=Dict(a=>employees[(a,)]["min_hours"] for a in A),
            hmax=Dict(a=>employees[(a,)]["max_hours"] for a in A),
            target=Dict(a=>employees[(a,)]["target_hours"] for a in A),
            late=[s for s in S if shifts[(s,)]["end"]==22],
            early=[s for s in S if shifts[(s,)]["start"]==6])
end
