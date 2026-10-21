# Compact Vietnamese workbook -> canonical tables consumed by the unchanged MILP.
blankcell(x) = ismissing(x) || x === nothing || (x isa AbstractString && isempty(strip(x)))
celltext(x) = blankcell(x) ? "" : strip(string(x))

function shift_list(value, valid, label)
    txt=uppercase(celltext(value))
    isempty(txt) && return copy(valid)
    parts=String.(strip.(split(replace(txt,r"(?i)\s+or\s+"=>","),r"[,;/]")))
    all(s->!isempty(s) && s in valid,parts) || throw(ArgumentError("$label: mã ca không hợp lệ '$value'; chọn $(join(valid,", "))"))
    length(unique(parts))==length(parts) || throw(ArgumentError("$label: mã ca bị lặp"))
    return parts
end

function preference_cell(value, allowed, shifts, label)
    txt=uppercase(celltext(value))
    txt in ("0","0.0","OFF") && return (0,String[])
    isempty(txt) && return (1,copy(allowed))
    wanted = txt=="N" ? [r["s"] for r in shifts if r["end"]-r["start"]>=8 && r["start"]<14 && r["s"] in allowed] :
        shift_list(value,[r["s"] for r in shifts],label)
    isempty(wanted) && throw(ArgumentError("$label: không có ca phù hợp với đăng ký n"))
    all(s->s in allowed,wanted) || throw(ArgumentError("$label: đăng ký ca ngoài danh sách Ca được phép"))
    return (1,wanted)
end

function template_date(v,label)
    v isa Date && return v
    v isa DateTime && return Date(v)
    for fmt in (dateformat"yyyy-mm-dd",dateformat"dd/mm/yyyy")
        d=tryparse(Date,celltext(v),fmt)
        d !== nothing && return d
    end
    throw(ArgumentError("$label: cần ngày Excel hoặc yyyy-mm-dd / dd/mm/yyyy"))
end

function interval_text(v,label)
    m=match(r"^(\d{1,2}):(\d{2})\s*[-–]\s*(\d{1,2}):(\d{2})$",celltext(v))
    m===nothing && throw(ArgumentError("$label: nhập khung giờ HH:MM-HH:MM"))
    h1,m1,h2,m2=parse.(Int,m.captures)
    0<=m1<60 && 0<=m2<60 || throw(ArgumentError("$label: phút không hợp lệ"))
    return h1+m1/60,h2+m2/60
end

function template_tables(grids)
    needed=["Nhu cầu nhân sự","Nguyện vọng nhân sự","List ràng buộc"]
    all(haskey(grids,s) for s in needed) || throw(ArgumentError("Cần 3 sheet: $(join(needed,", "))"))
    raw=Dict{String,Any}(k=>Dict{String,Any}[] for k in keys(TABLE_FIELDS))
    cfg=grids["List ràng buộc"]
    size(cfg,2)>=8 || throw(ArgumentError("List ràng buộc: thiếu bảng ca hoặc cấu hình"))
    celltext.(cfg[1,1:4])==["Mã ca","Tên ca","Bắt đầu","Kết thúc"] || throw(ArgumentError("Sai tiêu đề bảng ca A1:D1"))
    celltext.(cfg[1,7:8])==["Tham số","Giá trị"] || throw(ArgumentError("Sai tiêu đề cấu hình G1:H1"))
    for i in 2:size(cfg,1)
        if !all(blankcell,cfg[i,1:4])
            push!(raw["Shifts"],Dict("s"=>identifier(cfg[i,1],"Mã ca dòng $i"),"label"=>cfg[i,2],"start"=>cfg[i,3],"end"=>cfg[i,4]))
        end
        if !all(blankcell,cfg[i,7:8])
            push!(raw["Config"],Dict("key"=>cfg[i,7],"value"=>cfg[i,8]))
        end
    end
    # Validate time values before using them to expand 'n'.
    for r in raw["Shifts"]
        r["start"]=numeric(r["start"],"Bắt đầu"); r["end"]=numeric(r["end"],"Kết thúc")
    end
    shifts=String[r["s"] for r in raw["Shifts"]]
    p=grids["Nguyện vọng nhân sự"]
    headers=["Mã NV","Tên","Team","Role","Không xếp","Ca được phép","Giờ tối thiểu","Giờ mục tiêu","Giờ tối đa"]
    size(p,2)>9 && size(p,1)>=3 || throw(ArgumentError("Nguyện vọng: thiếu nhân viên hoặc cột ngày"))
    celltext.(p[1,1:9])==headers || throw(ArgumentError("Nguyện vọng: sai tiêu đề A1:I1; hãy dùng mẫu v2"))
    cols=[j for j in 10:size(p,2) if !blankcell(p[1,j])]
    cols==collect(10:maximum(cols;init=9)) && !isempty(cols) || throw(ArgumentError("Cột ngày phải liên tục từ J1"))
    for (b,j) in enumerate(cols)
        push!(raw["Days"],Dict("b"=>b,"date"=>string(template_date(p[1,j],"Nguyện vọng cột $j"))))
    end
    dates=[Date(r["date"]) for r in raw["Days"]]
    dates==collect(firstdayofmonth(first(dates)):Day(1):lastdayofmonth(first(dates))) ||
        throw(ArgumentError("Mẫu tháng phải có đủ ngày liên tiếp từ đầu đến cuối một tháng"))
    for j in setdiff(10:size(p,2),cols)
        all(blankcell,p[3:end,j]) || throw(ArgumentError("Có đăng ký dưới cột thiếu ngày $j"))
    end
    for i in 3:size(p,1)
        all(blankcell,p[i,:]) && continue
        a=identifier(p[i,1],"Mã NV dòng $i")
        excluded=binary(p[i,5],"Không xếp dòng $i")
        allowed=shift_list(p[i,6],shifts,"Ca được phép dòng $i")
        emp=Dict{String,Any}("a"=>a,"name"=>identifier(p[i,2],"Tên dòng $i"),"c"=>identifier(p[i,3],"Team dòng $i"),"role"=>identifier(p[i,4],"Role dòng $i"))
        for (j,k) in [(7,"min_hours"),(8,"target_hours"),(9,"max_hours")]
            val=numeric(p[i,j],"$k dòng $i")
            emp[k]=excluded==1 ? 0.0 : val
        end
        push!(raw["Employees"],emp)
        for (b,j) in enumerate(cols)
            available,wanted=preference_cell(p[i,j],allowed,raw["Shifts"],"Nguyện vọng dòng $i cột $j")
            excluded==1 && (available=0; wanted=String[])
            push!(raw["Availability"],Dict("a"=>a,"b"=>b,"available"=>available))
            for s in shifts
                push!(raw["Preferences"],Dict("a"=>a,"b"=>b,"s"=>s,"allowed"=>Int(s in allowed),"preferred"=>Int(s in wanted)))
            end
        end
    end
    demand=grids["Nhu cầu nhân sự"]
    celltext.(demand[1,1:5])==["STT","Team","Nội dung","Kí hiệu","Nhu cầu nhân sự"] || throw(ArgumentError("Nhu cầu: sai tiêu đề A1:E1"))
    seen=Dict{String,Tuple{Float64,Float64}}()
    team=""
    for i in 2:size(demand,1)
        all(blankcell,demand[i,1:5]) && continue
        !blankcell(demand[i,2]) && (team=identifier(demand[i,2],"Team nhu cầu dòng $i"))
        isempty(team) && throw(ArgumentError("Thiếu team tại dòng nhu cầu $i"))
        k=identifier(demand[i,4],"Kí hiệu khung dòng $i")
        st,en=interval_text(demand[i,3],"Nội dung dòng $i")
        if haskey(seen,k)
            seen[k]==(st,en) || throw(ArgumentError("Khung $k có giờ không thống nhất giữa các team"))
        else
            seen[k]=(st,en)
            push!(raw["Slots"],Dict("k"=>k,"start"=>st,"end"=>en))
        end
        required=numeric(demand[i,5],"Nhu cầu dòng $i";integer=true)
        for day in raw["Days"]
            push!(raw["Demand"],Dict("b"=>day["b"],"c"=>team,"k"=>k,"required"=>required))
        end
    end
    return raw
end

function load_template(path)
    grids=XLSX.openxlsx(path) do xf
        Dict(s=>(collect(XLSX.eachrow(xf[s])); xf[s][:]) for s in ["Nhu cầu nhân sự","Nguyện vọng nhân sự","List ràng buộc"])
    end
    return template_tables(grids)
end
