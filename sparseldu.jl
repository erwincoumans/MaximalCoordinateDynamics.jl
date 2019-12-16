@inline function setD!(link::Link{T}) where T
    μ = 1e-4
    dynT,dynR = ∂dyn∂vel(link)
    Z = @SMatrix zeros(T,3,3)

    link.data.D = [[dynT Z];[Z dynR]] #+ SMatrix{6,6,Float64,36}(μ*I)
    return nothing
end

@inline setD!(C::Constraint{T,Nc}) where {T,Nc} = (C.data.D = @SMatrix zeros(T,Nc,Nc); nothing)
@inline function updateD!(node::Node,child::Node,fillin::OffDiagonalEntry)
    node.data.D -= fillin.JL*child.data.D*fillin.JU
    return nothing
end
@inline invertD!(node) = (d = node.data; d.Dinv = inv(d.D); nothing)

# TODO pass in the two connected links
@inline function setJ!(L::Link,C::Constraint,F::OffDiagonalEntry)
    # data = F.data

    F.JL = ∂g∂vel(C,L)
    F.JU = -∂g∂pos(C,L)'

    return nothing
end

@inline function setJ!(C::Constraint,L::Link,F::OffDiagonalEntry)
    # data = F.data

    F.JL = -∂g∂pos(C,L)'
    F.JU = ∂g∂vel(C,L)

    return nothing
end

@inline function setJ!(C1::Constraint,C2::Constraint,F::OffDiagonalEntry{T,N1,N2}) where {T,N1,N2}
    # data = F.data

    F.JL = @SMatrix zeros(T,N2,N1)
    F.JU = @SMatrix zeros(T,N1,N2)

    return nothing
end

@inline function updateJ1!(node::Node,gcfillin::OffDiagonalEntry,cgcfillin::OffDiagonalEntry,F::OffDiagonalEntry)
    # d = F.data
    F.JL -= gcfillin.JL*node.data.D*cgcfillin.JU
    F.JU -= cgcfillin.JL*node.data.D*gcfillin.JU
    return nothing
end

@inline function updateJ2!(node::Node,F::OffDiagonalEntry)
    # d = F.data
    F.JL = F.JL*node.data.Dinv
    F.JU = node.data.Dinv*F.JU
    return nothing
end

@inline setSol!(link::Link) = (link.data.ŝ = dynamics(link); nothing)
@inline function setSol!(C::Constraint{T,Nc,Nc²,Nl}) where {T,Nc,Nc²,Nl}
    C.data.ŝ = g(C)
    # for i=1:Nl
    #     gŝ(C.constr[i],C.link1,C.link2,C.datavec[i])
    # end
    return nothing
end

# (A) For extended equations
# @inline addGtλ!(L::Link,C::Constraint) = (L.data.ŝ -= Gtλ(L,C); nothing)
@inline addλ0!(C::Constraint) = (C.data.ŝ += C.data.s0; nothing)

@inline function LSol!(node::Node,child::Node,fillin::OffDiagonalEntry)
    node.data.ŝ -= fillin.JL*child.data.ŝ
    return nothing
end
@inline DSol!(node) = (d = node.data; d.ŝ = d.Dinv*d.ŝ; nothing)
@inline function USol!(node::Node,parent::Node,fillin::OffDiagonalEntry)
    node.data.ŝ -= fillin.JU*parent.data.ŝ
    return nothing
end


@inline function setNormf!(link::Link,robot::Robot)
    data = link.data
    graph = robot.graph
    data.f = dynamics(link)
    for (cind,isconnected) in enumerate(graph.adjacency[graph.dict[link.id]])
        isconnected && GtλTof!(robot.nodes[robot.dict[graph.rdict[cind]]],link)
    end
    data.normf = data.f'*data.f
    return nothing
end

@inline function setNormf!(C::Constraint{T,Nc,Nc²,Nl},robot::Robot) where {T,Nc,Nc²,Nl}
    data = C.data
    data.f = g(C)
    # for i=1:Nl
    #     gf(C.constr[i],C.link1,C.link2,C.datavec[i])
    # end
    data.normf = data.f'*data.f
    return nothing
end

@inline GtλTof!(C::Constraint,L::Link) = (L.data.f -= ∂g∂pos(C,L)'*C.data.s1; nothing)
