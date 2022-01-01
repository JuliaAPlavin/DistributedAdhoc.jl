module MyDistributed

using Reexport
@reexport using Distributed
import Pkg
import Sockets

using DocStringExtensions
@template (FUNCTIONS, METHODS, MACROS) = """$(TYPEDSIGNATURES)\n$(DOCSTRING)"""



""" Send local file `path` to the worker `pid`.

Creates a temporary file at the worker, with the same `basename` as `path`.
"""
function send_file(path::AbstractString, pid::Int)
    remote_dir = remotecall_fetch(mktempdir, pid)
    remote_path = joinpath(remote_dir, basename(path))
    return send_file(path => remote_path, pid)
end

""" Send local file `local_path` to `remote_path` at the worker `pid`. """
function send_file((local_path, remote_path)::Pair{<:AbstractString, <:AbstractString}, pid::Int)
    content = read(local_path)
    written = remotecall_fetch(write, pid, remote_path, content)
    @assert written == length(content)
    return remotecall_fetch(abspath, pid, remote_path)
end

""" Send the local Julia environment to all active workers and activate it there.

Instantiates the environment using a single worker at each host, other workers just `activate` the created env. """
function send_env_activate_perhost(; env_dir=dirname(Base.active_project()))
    @sync for (host, pids) in pairs(host_to_pids_dict())
        @async begin
            @info "Sending and activating" host pid=pids[1]
            remote_env_dir = send_env_activate(pids[1]; env_dir)
            @sync for pid in pids[2:end]
                @info "Activating" host pid
                @async activate(remote_env_dir, pid; instantiate=false)
            end
        end
    end
end

" Determine the host-worker mapping and return it as a `Dict`: `hostname => [pids...]`. "
function host_to_pids_dict()
    hostnames = remotecall_fetch.(gethostname, workers())
    host_to_pid = Dict{String, Vector{Int}}()
    for (w, host) in zip(workers(), hostnames)
        push!(get!(host_to_pid, host, Int[]), w)
    end
    return host_to_pid
end

" Send the local Julia environment to the worker `pid`, and activate it. "
function send_env_activate(pid::Int; env_dir=dirname(Base.active_project()), instantiate=true)
    remote_env_dir = send_projmanifest(pid; local_env_dir=env_dir)
    activate(remote_env_dir, pid; instantiate)
    return remote_env_dir
end

" Send `Project.toml` and `Manifest.toml` files from the local environment to a new temporary directory at the worker `pid`. "
function send_projmanifest(pid::Int; local_env_dir::String=dirname(Base.active_project()))
    remote_env_dir = remotecall_fetch(mktempdir, pid)
    for f in ["Project.toml", "Manifest.toml"]
        send_file(joinpath(local_env_dir, f) => joinpath(remote_env_dir, f), pid)
    end
    return remote_env_dir
end

" Activate the Julia environment at `remote_env_dir` at worker `pid`. "
function activate(remote_env_dir::String, pid::Int; instantiate::Bool=true)
    Distributed.remotecall_eval(Main, pid, :(import Pkg))
    remotecall_fetch(Pkg.activate, pid, remote_env_dir)
    instantiate && remotecall_fetch(Pkg.instantiate, pid)
end

end
