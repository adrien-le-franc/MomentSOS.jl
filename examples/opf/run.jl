# julia 1.6

ENV["MOSEKLM_LICENSE_FILE"] = "/home/OPF/mosek/mosek.lic"
DATA_FOLDER = "/home/OPF/data/pglib-opf/"
max_set_size = 12
relaxation_order = 2
case = "pglib_opf_case5_pjm.m"


using MomentSOS
MSOS = MomentSOS

using MosekTools

using Ipopt
using JuMP

using FileIO
using Dates

include("scaling.jl")
include("parse.jl")

# AC-OPF to POP

data = parse_file(joinpath(DATA_FOLDER, case))

pop, x0, minimal_sets, bounds = parse_opf_to_pop(data, AngleCons=true, LineLimit=true, nlp=true, n_max=max_set_size)

objective_scaling = maximum(abs.(pop.objective.coefficients))
objective = normalize_polynomial(pop.objective)
inequalities = [normalize_polynomial(g) for g in pop.inequality_constraints]
equalities = [normalize_polynomial(g) for g in pop.equality_constraints]
pop = MSOS.POP(objective, pop.n_variables, inequalities, equalities)

# NLP

model = MSOS.non_linear_model(pop)
set_optimizer(model, Ipopt.Optimizer)
set_start_value.(model[:x], x0)
optimize!(model)

nlp = Dict("primal_status" => primal_status(model),
		   "dual_status" => dual_status(model),
		   "termination_status" => termination_status(model),
		   "upper_bound" => objective_value(model)*objective_scaling)

# Relaxation 

t_build = @elapsed model = MSOS.sos_relaxation_model(pop, relaxation_order, minimal_sets)

set_optimizer(model, Mosek.Optimizer)
optimize!(model)
t_solve = solve_time(model)

relaxation = Dict("t_build" => t_build, "t_solve" => t_solve,
				  "primal_status" => primal_status(model),
				  "dual_status" => dual_status(model),
				  "termination_status" => termination_status(model),
				  "lower_bound" => objective_value(model)*objective_scaling)

# Results

println("NLP")
display(nlp)
println("Relaxation")
display(relaxation)