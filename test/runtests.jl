# julia 1.6

using Test
using MomentHierarchy
MH = MomentHierarchy
using DynamicPolynomials
using JuMP
using LinearAlgebra

@testset "basics" begin

	@testset "polynomials" begin
		
		@polyvar x[1:3]
		f = x[1]^4 + x[2]^4 + x[3]^4 + x[1]*x[2]*x[3]
		
		sparse_polynomial = MH.SparsePolynomial(f, x)

		@test sparse_polynomial.coefficients == [1., 1., 1., 1.]
		@test sparse_polynomial.support == [[0x0001, 0x0001, 0x0001, 0x0001], 
											[0x0002, 0x0002, 0x0002, 0x0002], 
											[0x0003, 0x0003, 0x0003, 0x0003], 
											[0x0001, 0x0002, 0x0003]]
		@test MH.degree(sparse_polynomial) == 4

		pop = MH.POP(f, x, g_inequality=[- x[1]^2 - 0.5*x[2]^2, - x[2]^2 - x[3]^2])

		@test pop.n_variables == 3
		@test pop.objective.support == sparse_polynomial.support
		@test pop.inequality_constraints[1].coefficients == [-1. ; -0.5]
		@test pop.equality_constraints == nothing
		@test collect(MH.terms(sparse_polynomial)) == [([0x0001, 0x0001, 0x0001, 0x0001], 1.),
													   ([0x0002, 0x0002, 0x0002, 0x0002], 1.),
													   ([0x0003, 0x0003, 0x0003, 0x0003], 1.),
													   ([0x0001, 0x0002, 0x0003], 1.)]

	end

	@testset "moments" begin
		
		@polyvar x[1:3]
		f = x[1]^4 + 1
		sparse_f = MH.SparsePolynomial(f, x)
		pop = MH.POP(f, x)

		@test MH.n_moments(3, 1) == 4
		@test MH.n_moments(collect(1:3), 1) == 4
		@test MH.n_moments(pop, 2) == 10
		@test MH.localizing_matrix_order(sparse_f, 2) == 0

		@test collect(MH.moment_columns([0x0001], 2)) == [(1, [0x0000, 0x0000]),
														  (2, [0x0000, 0x0001]),
														  (3, [0x0001, 0x0001])]

		@test collect(MH.moment_rows([0x0001], 1, 2)) == [(1, [0x0000]),
	 													  (2, [0x0001])]

	 	@test collect(MH.coupling_moments([0x0001, 0x0003], 2)) == [[0x0000, 0x0000],
																	[0x0000, 0x0001],
																	[0x0000, 0x0003],
																	[0x0001, 0x0001],
																	[0x0001, 0x0003],
																	[0x0003, 0x0003]]

		@test MH.monomial([0x0002, 0x0000, 0x0001]) == [0x0001, 0x0002]
		@test MH.monomial_product([0x0001], [0x0001, 0x0000]) == [0x0001, 0x0001]
		@test MH.monomial_product([0x0001], [0x0001, 0x0000], [0x0000]) == [0x0001, 0x0001]

	end

end

@testset "models" begin
	
	@polyvar x[1:6]
	f = x[1]*x[2] + x[2]*x[3] + x[3]*x[4] + x[4]*x[5] + x[5]*x[6]
	g_1 = 1 - x[1]^2 - x[2]^2 
	g_2 = 1 - x[3]^2 - x[4]^2  
	g_3 = 1 - x[5]^2 - x[6]^2 
	pop = MH.POP(f, x, g_inequality=g_1, g_equality=[g_2, g_3])
	
	relaxation_order = 1

	@testset "moment" begin
		
		model = Model()
		variable_sets = [collect(1:6)]
		
		moment_labels = MH.set_moment_matrices!(model, pop, relaxation_order, variable_sets)
		@test length(keys(moment_labels)) == 28
		
		@test MH.linear_expression(model, pop.objective, moment_labels) == model[:y][5] + 
		model[:y][9] + model[:y][14] + model[:y][20] + model[:y][27]
		
		MH.set_objective!(model, pop, moment_labels)
		@test objective_function(model) == model[:y][5] + model[:y][9] + 
			model[:y][14] + model[:y][20] + model[:y][27]

		MH.set_probability_measure_constraint!(model, moment_labels)
		MH.set_polynomial_constraints!(model, pop, relaxation_order, moment_labels, variable_sets)

		@test num_constraints(model, AffExpr, MOI.EqualTo{Float64}) == 3
		@test num_constraints(model, AffExpr, MOI.GreaterThan{Float64}) == 1
		@test num_constraints(model, Vector{AffExpr}, MOI.PositiveSemidefiniteConeTriangle) == 1

		model = Model()
		moment_labels = MH.set_moment_matrices!(model, pop, 2, variable_sets)
		MH.set_polynomial_constraints!(model, pop, 2, moment_labels, variable_sets)

		@test num_constraints(model, Vector{AffExpr}, MOI.PositiveSemidefiniteConeTriangle) == 2	

	end

	@testset "sos" begin
		
		model = Model()
		@variable(model, t)
		variable_sets = [collect(1:6)]
		
		monomial_index = MH.set_X_0!(model, variable_sets, relaxation_order)
		@test length(keys(monomial_index)) == 28
		@test length(model[:X_0]) == 1

		MH.set_X_j!(model, pop, monomial_index, variable_sets, relaxation_order)
		@test length(model[:X_ineq]) == 1
		@test length(model[:X_eq]) == 2

		MH.set_SOS_constraints!(model, pop, monomial_index)
		@test num_constraints(model, AffExpr, MOI.EqualTo{Float64}) == 28
		@test num_constraints(model, AffExpr, MOI.GreaterThan{Float64}) == 1
		@test num_constraints(model, Vector{VariableRef}, MOI.PositiveSemidefiniteConeTriangle) == 1

	end	

	variable_sets = [[1, 2, 3], [3, 4, 5, 6]]
	
	@testset "sparsity" begin

		model = Model()
		variable_sets = [[1, 2, 3], [3, 4, 5, 6]]

		moment_labels = MH.set_moment_matrices!(model, pop, relaxation_order, variable_sets)
		
		@test length(keys(moment_labels)) == 22
		@test num_constraints(model, Vector{AffExpr}, MOI.PositiveSemidefiniteConeTriangle) == 2

		@test MH.assign_constraint_to_set(pop.inequality_constraints[1], variable_sets) == 1

	end

	@testset "nlp" begin
		
		model = MH.non_linear_model(pop)
		@test num_constraints(model; count_variable_in_set_constraints=false) == 3
		
	end

end