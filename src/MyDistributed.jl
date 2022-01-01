module MyDistributed

using Reexport
using Distributed
import Pkg
import Sockets


my_addprocs(; host, dir, exename, count, tunnel=true) = addprocs([(host, count)]; tunnel, dir, exename)

function send_file(path::AbstractString, pid::Int)
    remote_dir = remotecall_fetch(mktempdir, pid)
    remote_path = joinpath(remote_dir, basename(path))
    send_file(path => remote_path, pid)
    return remote_path
end

function send_file((local_path, remote_path)::Pair{<:AbstractString, <:AbstractString}, pid::Int)
    content = read(local_path)
    written = remotecall_fetch(write, pid, remote_path, content)
    @assert written == length(content)
end

function send_env_activate_perhost(; env_dir=dirname(Base.active_project()))
    @sync for (host, pids) in pairs(host_to_pids_dict())
        @async begin
            remote_env_dir = send_env_activate(pids[1]; env_dir)
            @sync for pid in pids[2:end]
                @async activate(remote_env_dir, pid; instantiate=false)
            end
        end
    end
end

function host_to_pids_dict()
    hostnames = remotecall_fetch.(gethostname, workers())
    host_to_pid = Dict{String, Vector{Int}}()
    for (w, host) in zip(workers(), hostnames)
        push!(get!(host_to_pid, host, Int[]), w)
    end
    return host_to_pid
end

function send_env_activate(pid::Int; env_dir=dirname(Base.active_project()), instantiate=true)
    remote_env_dir = send_projmanifest(pid; local_env_dir=env_dir)
    activate(remote_env_dir, pid; instantiate)
    return remote_env_dir
end

function send_projmanifest(pid::Int; local_env_dir::String=dirname(Base.active_project()))
    remote_env_dir = remotecall_fetch(mktempdir, pid)
    for f in ["Project.toml", "Manifest.toml"]
        send_file(joinpath(local_env_dir, f) => joinpath(remote_env_dir, f), pid)
    end
    return remote_env_dir
end

function activate(remote_env_dir::String, pid::Int; instantiate::Bool=true)
    Distributed.remotecall_eval(Main, pid, :(import Pkg))
    remotecall_fetch(Pkg.activate, pid, remote_env_dir)
    instantiate && remotecall_fetch(Pkg.instantiate, pid)
end

end
