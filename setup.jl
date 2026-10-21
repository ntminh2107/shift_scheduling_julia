import Pkg
Pkg.activate(@__DIR__)
Pkg.instantiate()
Pkg.precompile()
println("Dependencies installed. Run: julia --project=. main.jl")
