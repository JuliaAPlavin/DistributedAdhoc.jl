using DistributedAdhoc
using Test


@testset begin
    addprocs(1)
    W = only(workers())

    remote = DistributedAdhoc.send_file("runtests.jl" => "somefile", W)
    @test basename(remote) == "somefile"
    @test (@fetchfrom W read(remote, String)) == read("runtests.jl", String)

    remote = DistributedAdhoc.send_file("runtests.jl", W)
    @test basename(remote) == "runtests.jl"
    @test (@fetchfrom W read(remote, String)) == read("runtests.jl", String)

    @test (@fetchfrom W Base.ACTIVE_PROJECT[]) |> isnothing
    DistributedAdhoc.send_env_activate_everywhere(include=["*.toml"])
    @test occursin(r"^/tmp/\w+/Project.toml$", @fetchfrom W Base.ACTIVE_PROJECT[])
end


import CompatHelperLocal as CHL
CHL.@check()
