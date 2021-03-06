using Rotations
using Plots: RGBA
using StaticArrays

!(@isdefined MaximalCoordinateDynamics) && include(joinpath("..", "src", "MaximalCoordinateDynamics.jl"))
using Main.MaximalCoordinateDynamics

# Parameters
joint_axis = [1.0;0.0;0.0]

length1 = 0.5
width,depth = 0.5, 0.5
box1 = Box(width,depth,length1,1.,color=RGBA(1.,1.,0.))

# Links
origin = Origin{Float64}()

link1 = Body(box1)

# Constraints

joint1 = InequalityConstraint(Impact(link1,[0;-0.1;1.0]),Impact(link1,[0;0.1;1.0]))
joint2 = InequalityConstraint(Impact(link1,[0.1;0;1.0]))
joint3 = InequalityConstraint(Impact(link1,[-0.1;0;1.0]))

links = [link1]
ineqs = [joint1;joint2;joint3]
shapes = [box1]


mech = Mechanism(origin, links,ineqs)

for link in links
    link.x[2] += [0.01;0.005;0.05]
end

simulate!(mech,save=true)
MaximalCoordinateDynamics.visualize(mech,shapes)
