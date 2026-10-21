"""Build the planning-horizon MILP. R1-R10 correspond to docs/MODEL.md."""
function build_model(data; solver_log=false)
    A,B,C,S,K = data.A,data.B,data.C,data.S,data.K
    model = Model(HiGHS.Optimizer)
    solver_log || set_silent(model)
    set_time_limit_sec(model,data.cfg["time_limit"])
    set_optimizer_attribute(model,"mip_rel_gap",data.cfg["mip_gap"])
    set_optimizer_attribute(model,"threads",1)
    set_optimizer_attribute(model,"random_seed",0)

    @variable(model, x[a in A,b in B,s in S], Bin)
    @variable(model, u[b in B,c in C,k in K]>=0)
    @variable(model, z[a in A]>=0)
    @expression(model, w[a in A,b in B],sum(x[a,b,s] for s in S))
    @expression(model, H[a in A],sum(data.h[s]*x[a,b,s] for b in B,s in S))
    @expression(model, n[b in B,c in C,k in K],
        sum(data.q[(s,k)]*x[a,b,s] for a in data.members[c],s in S))

    # R1: At most one shift; unavailable days are OFF.
    @constraint(model, R1[a in A,b in B],w[a,b]<=data.v[(a,b)])
    # R2: Shift eligibility is a hard upper bound, independent of preferences.
    for a in A,b in B,s in S
        set_upper_bound(x[a,b,s],data.allowed[(a,b,s)])
    end
    # R3: Demand may be unmet, but every missing person-slot incurs a penalty.
    @constraint(model, R3[b in B,c in C,k in K],n[b,c,k]+u[b,c,k]>=data.d[(b,c,k)])
    # R4: Total working-hour bounds over the whole planning horizon.
    @constraint(model, R4[a in A],data.hmin[a]<=H[a]<=data.hmax[a])
    # R5: No end-at-22 shift followed by start-at-06 shift the next day.
    @constraint(model, R5[a in A,b in B[1:end-1]],
        sum(x[a,b,s] for s in data.late)+sum(x[a,b+1,s] for s in data.early)<=1)
    # R6: In each L+1-day window, at least one day off.
    @constraint(model, R6[a in A,b in 1:(length(B)-data.L)],
        sum(w[a,t] for t in b:(b+data.L))<=data.L)
    if data.extended
        # R7: rolling seven-day hour cap, not a calendar-week reset.
        @constraint(model, R7[a in A,b in 1:(length(B)-6)],
            sum(data.h[s]*x[a,t,s] for t in b:(b+6),s in S)<=data.cfg["max_hours_7days"])
        # R8: cap the number of late shifts in the whole month.
        @constraint(model, R8[a in A],sum(x[a,b,s] for b in B,s in data.late)<=data.cfg["max_late_shifts"])
        # R9: cap worked weekend days, regardless of shift duration.
        @constraint(model, R9[a in A],sum(w[a,b] for b in data.weekends)<=data.cfg["max_weekend_days"])
        # R10: at least this many supervisors work in each team/day.
        # This does not require a supervisor in every time slot.
        @constraint(model, R10[b in B,c in C],
            sum(w[a,b] for a in data.supervisors[c])>=data.cfg["min_supervisors_per_day"])
    end
    # Linearization of |H[a]-target[a]|.
    @constraint(model, deviation_above[a in A],z[a]>=H[a]-data.target[a])
    @constraint(model, deviation_below[a in A],z[a]>=data.target[a]-H[a])

    @expression(model, Z1,sum(u[b,c,k] for b in B,c in C,k in K))
    @expression(model, Z2,sum((1-data.preferred[(a,b,s)])*x[a,b,s] for a in A,b in B,s in S))
    @expression(model, Z3,sum(z[a] for a in A))
    @objective(model,Min,data.cfg["lambda_shortage"]*Z1+
        data.cfg["lambda_preference"]*Z2+data.cfg["lambda_hours"]*Z3)
    return (;model,x,u,z,w,H,n,Z1,Z2,Z3)
end
