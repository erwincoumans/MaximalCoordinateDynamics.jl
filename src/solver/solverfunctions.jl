@inline function setDandΔs!(diagonal::DiagonalEntry, body::Body, mechanism::Mechanism)
    diagonal.D = ∂dyn∂vel(body, mechanism.dt)
    diagonal.Δs = dynamics(body, mechanism)
    return
end

@inline function extendDandΔs!(diagonal::DiagonalEntry, body::Body, ineqc::InequalityConstraint, mechanism::Mechanism)
    diagonal.D += schurD(ineqc, body, mechanism.dt) # + SMatrix{6,6,Float64,36}(1e-5*I)
    diagonal.Δs += schurf(ineqc, body, mechanism)
    return
end

@inline function setDandΔs!(diagonal::DiagonalEntry{T,N}, eqc::EqualityConstraint, mechanism::Mechanism) where {T,N}
    diagonal.D = @SMatrix zeros(T, N, N)
    # μ = 1e-5
    # d.D = SMatrix{N,N,T,N*N}(μ*I) # TODO Positiv because of weird system? fix generally
    diagonal.Δs = g(eqc, mechanism)
    return
end

@inline function setLU!(offdiagonal::OffDiagonalEntry, bodyid::Int64, eqc::EqualityConstraint, mechanism)
    offdiagonal.L = -∂g∂pos(eqc, bodyid, mechanism)'
    offdiagonal.U = ∂g∂vel(eqc, bodyid, mechanism)
    return
end

@inline function setLU!(offdiagonal::OffDiagonalEntry, eqc::EqualityConstraint, bodyid::Int64, mechanism)
    offdiagonal.L = ∂g∂vel(eqc, bodyid, mechanism)
    offdiagonal.U = -∂g∂pos(eqc, bodyid, mechanism)'
    return
end

@inline function setLU!(offdiagonal::OffDiagonalEntry{T,N1,N2}) where {T,N1,N2}
    offdiagonal.L = @SMatrix zeros(T, N2, N1)
    offdiagonal.U = offdiagonal.L'
    return
end

@inline function updateLU1!(offdiagonal::OffDiagonalEntry, diagonal::DiagonalEntry, maintograndchild::OffDiagonalEntry, childtograndchild::OffDiagonalEntry)
    D = diagonal.D
    offdiagonal.L -= maintograndchild.L * D * childtograndchild.U
    offdiagonal.U -= childtograndchild.L * D * maintograndchild.U
    return
end

@inline function updateLU2!(offdiagonal::OffDiagonalEntry, diagonal::DiagonalEntry)
    Dinv = diagonal.Dinv
    offdiagonal.L = offdiagonal.L * Dinv
    offdiagonal.U = Dinv * offdiagonal.U
    return
end

@inline function updateD!(diagonal::DiagonalEntry, childdiagonal::DiagonalEntry, fillin::OffDiagonalEntry)
    diagonal.D -= fillin.L * childdiagonal.D * fillin.U
    return
end

function invertD!(diagonal::DiagonalEntry)
    diagonal.Dinv = inv(diagonal.D)
    return
end

@inline function LSol!(diagonal::DiagonalEntry, child::DiagonalEntry, fillin::OffDiagonalEntry)
    diagonal.Δs -= fillin.L * child.Δs
    return
end

function DSol!(diagonal::DiagonalEntry)
    diagonal.Δs = diagonal.Dinv * diagonal.Δs
    return
end

@inline function USol!(diagonal::DiagonalEntry, parent::DiagonalEntry, fillin::OffDiagonalEntry)
    diagonal.Δs -= fillin.U * parent.Δs
    return
end


function factor!(graph::Graph, ldu::SparseLDU)
    for id in graph.dfslist
        sucs = successors(graph, id)
        for childid in sucs
            offdiagonal = getentry(ldu, (id, childid))
            for grandchildid in sucs
                grandchildid == childid && break
                if hasdirectchild(graph, childid, grandchildid)
                    updateLU1!(offdiagonal, getentry(ldu, grandchildid), getentry(ldu, (id, grandchildid)), getentry(ldu, (childid, grandchildid)))
                end
            end
            updateLU2!(offdiagonal, getentry(ldu, childid))
        end

        diagonal = getentry(ldu, id)

        for childid in successors(graph, id)
            updateD!(diagonal, getentry(ldu, childid), getentry(ldu, (id, childid)))
        end
        invertD!(diagonal)
    end
end

function solve!(mechanism)
    ldu = mechanism.ldu
    graph = mechanism.graph
    dfslist = graph.dfslist

    for id in dfslist
        diagonal = getentry(ldu, id)

        for childid in successors(graph, id)
            LSol!(diagonal, getentry(ldu, childid), getentry(ldu, (id, childid)))
        end
    end

    for id in graph.rdfslist
        diagonal = getentry(ldu, id)

        DSol!(diagonal)

        for parentid in predecessors(graph, id)
            USol!(diagonal, getentry(ldu, parentid), getentry(ldu, (parentid, id)))
        end

        for childid in ineqchildren(graph, id)
            eliminatedSol!(getineqentry(ldu, childid), diagonal, getbody(mechanism, id), getineqconstraint(mechanism, childid), mechanism)
        end
    end
end

@inline function s0tos1!(component::Component)
    component.s1 = component.s0
    return
end

@inline function s1tos0!(component::Component)
    component.s0 = component.s1
    return
end

@inline function s0tos1!(ineqc::InequalityConstraint)
    ineqc.s1 = ineqc.s0
    ineqc.γ1 = ineqc.γ0
    return
end

@inline function s1tos0!(ineqc::InequalityConstraint)
    ineqc.s0 = ineqc.s1
    ineqc.γ0 = ineqc.γ1
    return
end

@inline function normΔs(component::Component)
    d = component.s1 - component.s0
    return dot(d, d)
end

@inline function normΔs(ineqc::InequalityConstraint)
    d1 = ineqc.s1 - ineqc.s0
    d2 = ineqc.γ1 - ineqc.γ0
    return dot(d1, d1) + dot(d2, d2)
end

function eliminatedSol!(ineqentry::InequalityEntry, diagonal::DiagonalEntry, body::Body, ineqc::InequalityConstraint, mechanism::Mechanism)
    dt = mechanism.dt
    μ = mechanism.μ
    No = 2

    φ = g(ineqc, mechanism)

    Nx = ∂g∂pos(ineqc, body, mechanism)
    Nv = ∂g∂vel(ineqc, body, mechanism)

    γ1 = ineqc.γ1
    s1 = ineqc.s1

    Δv = diagonal.Δs
    ineqentry.Δγ = γ1 ./ s1 .* φ - μ ./ s1 - γ1 ./ s1 .* (Nv * Δv)
    ineqentry.Δs = s1 .- μ ./ γ1 - s1 ./ γ1 .* ineqentry.Δγ

    return
end
