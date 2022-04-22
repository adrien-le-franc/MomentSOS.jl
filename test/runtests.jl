# julia 1.6

using Test
using MomentDecomposition
MD = MomentDecomposition
using DynamicPolynomials
using JuMP

@testset "polynomials" begin
	
	@polyvar x[1:3]
	f = x[1]^4 + x[2]^4 + x[3]^4 + x[1]*x[2]*x[3]
	
	sparse_polynomial = MD.SparsePolynomial(f, x)

	@test sparse_polynomial.coefficients == [1.; 1.; 1.; 1.]
	@test sparse_polynomial.support == [convert.(UInt16, [1; 1; 1; 1]), 
										convert.(UInt16, [2; 2; 2; 2]), 
										convert.(UInt16, [3; 3; 3; 3]), 
										convert.(UInt16, [1; 2; 3])]
	@test MD.degree(sparse_polynomial) == 4

	pop = MD.POP(f, x, g_inequality=[- x[1]^2 - 0.5*x[2]^2, - x[2]^2 - x[3]^2])

	@test pop.n_variables == 3
	@test pop.objective.support == sparse_polynomial.support
	@test pop.inequality_constraints[1].coefficients == [-1. ; -0.5]
	@test pop.equality_constraints == nothing

end

@testset "moments" begin
	
	@polyvar x[1:3]
	f = x[1]^4 + 1
	sparse_f = MD.SparsePolynomial(f, x)
	pop = MD.POP(f, x)

	@test MD.n_moments(3, 2) == 10
	#@test length(collect(MD.moments_columns([1, 3, 5], 2))) == MD.n_moments(3, 2)
	@test length(collect(MD.moment_columns(pop, 2))) == MD.n_moments([1, 3, 5], 2)
	@test length(collect(MD.moment_rows(pop, 2, 5))) == 5
	#@test MD.label(collect(MD.moments([2, 3], 2))[2]) == [0x0002]

	@test MD.localizing_matrix_order(2, sparse_f) == 0

end

@testset "models" begin
	
	@polyvar x[1:6]
	f = x[1]*x[2] + x[2]*x[3] + x[3]*x[4] + x[4]*x[5] + x[5]*x[6]
	g_1 = 1 - x[1]^2 - x[2]^2 
	g_2 = 1 - x[3]^2 - x[4]^2  
	g_3 = 1 - x[5]^2 - x[6]^2 
	pop = MD.POP(f, x, g_inequality=g_1, g_equality=[g_2, g_3])
	
	relaxation_order = 1
	model = Model()
	MD.set_moment_variables!(model, pop, relaxation_order)
	moment_labels = MD.set_moment_matrix!(model, pop, relaxation_order)
	MD.set_objective!(model, pop, moment_labels)

	@test size(model[:moment_matrix])[1] == MD.n_moments(6, 1)
	@test length(model[:y]) == MD.n_moments(6, 2)
	@test objective_function(model) == model[:y][5] + model[:y][9] + 
		model[:y][14] + model[:y][20] + model[:y][27]

	#set_probability_measure_constraint!(model, moment_labels)
	#set_inequality_constraints!(model, pop, relaxation_order)
	#set_equality_constraints!(model, pop, relaxation_order)


	# find new tests !


	#
	#model = MD.dense_relaxation(pop, 1)
	"""
	relaxation_order = 1
	model = Model()
	decomposition_sets = [[1, 2, 3], [2, 3, 4, 5], [4, 5, 6]]
	uint16_sets = [convert.(set) for set in decomposition_sets]
	k = 1
	set = uint16_sets[k]
	MD.set_moment_variables!(model, relaxation_order, set, k)
	moment_labels = MD.set_moment_matrix!(model, relaxation_order, set, k)

	MD.set_objective!(model, pop, moment_labels, uint16_variable_sets)
	
	"""
	

end