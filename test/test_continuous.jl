using ModelingToolkit, ModelingToolkitStandardLibrary, OrdinaryDiffEq
using ModelingToolkitStandardLibrary.Blocks
using ModelingToolkitStandardLibrary.Blocks: Dₜ, t

#=
Testing strategy:
The general strategy is to test systems using simple intputs where the solution
is known on closed form. For algebraic systems (without differential variables),
an integrator with a constant input is often used together with the system under test. 
=#

@testset "Constant" begin
    @info "Testing Constant"
    @named c = Constant(42)
    sys = structural_simplify(c)
    prob = ODEProblem(sys, Pair[], (0.0, 1.0))
    @test_broken begin # StackOverflowError:
        sol = solve(prob, Rosenbrock23())
        @test all(==(42), sol[c.y])
    end
    @named int = Integrator(; k=1)
    @named iosys = ODESystem([int.u~c.y], t, systems=[c, int])
    sys = structural_simplify(iosys)
    prob = ODEProblem(sys, Pair[], (0.0, 1.0))
    sol = solve(prob, Rosenbrock23(), saveat=0:0.1:1)
    @test sol[int.y] ≈ 42 .* (0:0.1:1)
end

@testset "Integrator" begin
    @info "Testing Integrator"
    for k = [0.1, 1, 10]
        @named int = Integrator(; k)
        @test count(ModelingToolkit.isinput, states(int)) == 1
        @test count(ModelingToolkit.isoutput, states(int)) == 1
        @named iosys = ODESystem([int.u~1], t, systems=[int])
        sys = structural_simplify(iosys)
        stateind(sym) = findfirst(isequal(sym),states(sys))
        prob = ODEProblem(sys, Pair[int.u=>1.], (0.0, 1.0))
        sol = solve(prob, Rosenbrock23(), saveat=0:0.1:1)
        @test sol[int.y] ≈ k .* (0:0.1:1)
    end
end

@testset "Derivative" begin
    @info "Testing Derivative"

    #= Derivative
    The test output below is generated by
    using ControlSystems
    sys = ss(-1/T, 1/T, -k/T, k/T)
    tv = 0:0.5:10
    u = (x,t)->[sin(t)]
    y = vec(lsim(sys, u, tv, alg=Rosenbrock23())[1])
    =#
    k = 1
    T = 0.1

    y01 = [0.0, 0.9096604391560481, 0.6179369162956885, 0.16723968919320775, -0.3239425882305049, -0.7344654437585882, -0.9662915429884467, -0.9619031643363591, -0.7219189996926385, -0.3046471954239838, 0.18896274787342904, 0.6325612488150467, 0.923147635361496, 0.9882186461533009, 0.8113758856575801, 0.4355269842556595, -0.05054266121798534, -0.5180957852231662, -0.8615644854197235, -0.994752654263345, -0.8845724777509947]

    y1 = [0.0, 0.37523930001382705, 0.5069379343173124, 0.422447016206449, 0.17842742193310424, -0.14287580928455357, -0.44972307981519677, -0.6589741190943343, -0.7145299845867902, -0.5997749247850142, -0.34070236779586216, -5.95731929625698e-5, 0.33950710748637825, 0.595360048429, 0.7051403889991136, 0.6421181090255983, 0.4214753349401378, 0.09771852881756515, -0.24995564964733635, -0.5364893060362096, -0.6917461951831227]

    y10 = [0.0, 0.04673868865158038, 0.07970450452536708, 0.09093906605247397, 0.07779607227750623, 0.04360203242101193, -0.0031749143460660587, -0.050989771426848074, -0.08804727520541561, -0.10519046453331109, -0.09814083278784949, -0.06855209962041757, -0.023592611490189652, 0.025798926487949535, 0.0675952553752348, 0.0916256775597053, 0.09206230764744555, 0.06885879535935949, 0.027748930190142837, -0.021151336671582116, -0.06582115823326284]

    for k = [0.1, 1, 10], (T,y) = zip([0.1, 1, 10], [y01, y1, y10])
        @named der = Derivative(; k, T)
        @test count(ModelingToolkit.isinput, states(der)) == 1
        @test count(ModelingToolkit.isoutput, states(der)) == 1
        @named iosys = ODESystem([der.u~sin(t)], t, systems=[der])
        sys = structural_simplify(iosys)
        stateind(sym) = findfirst(isequal(sym),states(sys))
        prob = ODEProblem(sys, Pair[der.u=>0., der.x=>0], (0.0, 10.0))
        sol = solve(prob, Rosenbrock23(), saveat=0:0.5:10)
        # plot([sol[der.y] k.*y]) |> display
        @test sol[der.y] ≈ k .* y rtol=1e-2
    end
end

@testset "FirstOrder" begin
    @info "Testing FirstOrder"

    for k = [0.1, 1, 10], T = [0.1, 1, 10]
        @named fo = FirstOrder(; k, T)
        @test count(ModelingToolkit.isinput, states(fo)) == 1
        @test count(ModelingToolkit.isoutput, states(fo)) == 1
        @named iosys = ODESystem([fo.u~1], t, systems=[fo])
        sys = structural_simplify(iosys)
        prob = ODEProblem(sys, Pair[fo.u=>1., fo.x=>0], (0.0, 10.0))
        sol = solve(prob, Rosenbrock23(), saveat=0:0.1:10)
        y = k .* (1 .- exp.(.-sol.t ./ T)) # Known solution to first-order system
        # plot([sol[fo.y] y]) |> display
        @test sol[fo.y] ≈ y rtol=1e-3
    end

end

@testset "SecondOrder" begin
    @info "Testing SecondOrder"
    
    # The impulse response of a second-order system with damping d follows the equations below
    function so(t,w,d)
        val = if d == 0
            1/w * sin(w*t)
        elseif d < 1
            1/(w*sqrt(1-d^2)) * exp(-d*w*t) * sin(w*sqrt(1-d^2)*t)
        elseif d == 1
            t*exp(-w*t)
        else
            1/(w*sqrt(d^2-1)) * exp(-d*w*t) * sinh(w*sqrt(d^2-1)*t)
        end
        val
    end

    w = 1
    d = 0.5
    for k = [0.1, 1, 10], w = [0.1, 1, 10], d = [0, 0.01, 0.1, 1, 1.1]
        @named sos = SecondOrder(; k, w, d)
        @test count(ModelingToolkit.isinput, states(sos)) == 1
        @test count(ModelingToolkit.isoutput, states(sos)) == 1
        @named iosys = ODESystem([sos.u~0], t, systems=[sos])
        sys = structural_simplify(iosys)
        prob = ODEProblem(sys, Pair[sos.u=>0.0, sos.xd=>1.0], (0.0, 10.0)) # set initial derivative state to 1 to simulate an impulse response
        sol = solve(prob, Rosenbrock23(), saveat=0:0.1:10, reltol=1e-6)
        y =  so.(sol.t,w,d)# Known solution to second-order system
        # plot([sol[sos.y] y]) |> display
        @test sum(abs2, sol[sos.y] - y) < 1e-4
    end
end
