# julia 1.6.5

## oracle ##

#call_f!(y::Vector{Float64}, phi::Phi_scalar) = phi.f(y)

call_f(y::Vector{Float64}, phi::Phi_scalar) = phi.f(y)
call_f_and_g!(y::Vector{Float64}, grad::Vector{Float64}, phi::Phi_scalar) = phi.f_and_g!(y, grad)

@views function evaluate_matrix(y::Vector{Float64}, phi::Phi_matrix) 
	return Symmetric(Matrix(sum(phi.A_j[i]*y[phi.address][i] for i in 1:length(phi.A_j)))) # keep sparse matrix for equality constraints ?
end

function projection(M::Symmetric{Float64, Matrix{Float64}}) # keep it sparse untill here ? Symmetric after Matrix ?

	sigmas, P = eigen(M, sortby=x->-x) # allocations !? is sorting necessary ?

	return Symmetric(P*spdiagm(max.(sigmas, 0.))*P')

end

function call_f!(y::Vector{Float64}, phi::Phi_matrix; project::Bool=false)

	if project
		phi.M = projection(evaluate_matrix(y, phi)) # avoid using Matrix ?
	else
		phi.M = evaluate_matrix(y, phi) 
	end

	return -0.5*norm(phi.M)^2

end

function call_f_and_g!(y::Vector{Float64}, grad::Vector{Float64}, phi::Phi_matrix; project::Bool=false)

	if project
		phi.M = projection(evaluate_matrix(y, phi))
	else
		phi.M = evaluate_matrix(y, phi) 
	end

	grad[phi.address] = -[dot(phi.A_j[i], phi.M) for i in 1:length(phi.A_j)]
	
	return -0.5*norm(phi.M)^2 

end


function call_dual_obj!() end

function call_dual_obj_and_grad!(y::Vector{Float64}, grad::Vector{Float64}, dual_model::DualModel)

	obj, grad[:] = call_f_and_g!(y, grad, dual_model.phi_moment)

	for phi in dual_model.phi_inequality
		obj += call_f_and_g!(y, grad, phi)
	end

	for phi in dual_model.phi_equality
		obj += call_f_and_g!(y, grad, phi)
	end

	obj += call_f_and_g!(y, grad, dual_model.phi_0)
	obj += call_f_and_g!(y, grad, dual_model.linear_term)

end