module DistributedAdhoc

using Reexport
@reexport using Distributed
import Pkg
import Sockets
using Glob



"""
    send_file(local::String, pid::Int)
    send_file(local => remote, pid::Int)

Send the file `local` from the current machine to the `pid` worker, saving as the `remote` path.
The parent directory of `remote` should already exist.

If the `remote` path isn't specified, creates a temporary file at the target worker with the same `basename` as `local`.
Returns the full path to the created file.
"""
function send_file(path::AbstractString, pid::Int)
    remote_dir = remotecall_fetch(mktempdir, pid)
    remote_path = joinpath(remote_dir, basename(path))
    return send_file(path => remote_path, pid)
end

function send_file((local_path, remote_path)::Pair{<:AbstractString, <:AbstractString}, pid::Int)
    content = read(local_path)
    written = remotecall_fetch(write, pid, remote_path, content)
    @assert written == length(content)
    return remotecall_fetch(abspath, pid, remote_path)
end

"""
    send_dir(local::String, pid::Int; include::Vector{String})
    send_dir(local => remote, pid::Int; include::Vector{String})

Send the directory `local` from the current machine to the `pid` worker, saving as the `remote` path.

If the `remote` path isn't specified, creates a temporary directory at the target worker.
Returns the full path to the created directory.

`include` is a list of file patterns to send, as accepted by `Glob.jl`.
"""
function send_dir(local_dir::AbstractString, pid::Int; include::Vector)
    remote_dir = remotecall_fetch(mktempdir, pid)
    return send_dir(local_dir => remote_dir, pid; include)
end

function send_dir((local_dir, remote_dir)::Pair{<:AbstractString, <:AbstractString}, pid::Int; include::Vector)
    localfiles = mapreduce(vcat, include) do pat
        glob(pat, local_dir)
    end |> unique
    remotefiles = map(f -> joinpath(remote_dir, relpath(f, local_dir)), localfiles)
    remotedirs = dirname.(remotefiles) |> unique
    remotecall_fetch.(mkpath, pid, remotedirs)
    for (l, r) in zip(localfiles, remotefiles)
        send_file(l => r, pid)
    end
    return remote_dir
end

"""    send_env_activate_everywhere([local_dir]; include)

Send the local Julia environment to all available workers, activate and instantiate it there.

Instantiates the environment using a single worker at each host, other workers just activate the created env.

Uses the current active project environment `dirname(Base.active_project())` if `local_dir` is omitted.

`include` is a list of file patterns to send, as accepted by `Glob.jl`.

# Example

Send the current Julia environment, including source code in `src`, developed packages (in `./dev`), scripts (in `./scripts`), and CSV files (in `./data`):
```
DistributedAdhoc.send_env_activate_everywhere(include=[
    "*.toml", "src/*.jl", "scripts/*.jl",
    "dev/*/*.toml", "dev/*/src/*.jl", "dev/*/src/*/*.jl",
    "data/*.csv",
])
```
"""
function send_env_activate_everywhere(env_dir=dirname(Base.active_project()); include::Vector)
    dir_by_pid = Dict{Int, String}()
    @sync for (host, pids) in pairs(host_to_pids_dict())
        @async begin
            @info "Sending and activating" host pid=pids[1]
            remote_env_dir = send_env_activate(env_dir, pids[1]; include)
            @sync for pid in pids
                dir_by_pid[pid] = remote_env_dir
                @async begin
                    remotecall_fetch(cd, pid, remote_env_dir)
                    activate(remote_env_dir, pid; instantiate=false)
                end
            end
        end
    end
    return dir_by_pid
end

"    host_to_pids_dict()

Determine the host-worker mapping and return it as a `Dict` of `hostname => [pids...]`. "
function host_to_pids_dict()
    hostnames = remotecall_fetch.(gethostname, workers())
    host_to_pid = Dict{String, Vector{Int}}()
    for (w, host) in zip(workers(), hostnames)
        push!(get!(host_to_pid, host, Int[]), w)
    end
    return host_to_pid
end

"    send_env_activate([local_dir], pid; [instantiate=true], include)

Send the local Julia environment to the worker `pid`, activate and optionally `instantiate` it.

Uses the current active project environment `dirname(Base.active_project())` if `local_dir` is omitted.

`include` is a list of file patterns to send, as accepted by `Glob.jl`.
"
send_env_activate(pid::Int; kwargs...) = send_env_activate(dirname(Base.active_project()), pid; kwargs...)

function send_env_activate(env_dir, pid::Int; instantiate=true, include::Vector)
    remote_env_dir = send_dir(env_dir, pid; include)
    activate(remote_env_dir, pid; instantiate)
    return remote_env_dir
end

"    activate(remote_dir, pid; [instantiate=false])

Activate the Julia environment at `remote_dir` at worker `pid`. Optionally, `instantiate` the environment afterwards. "
function activate(remote_env_dir::String, pid::Int; instantiate=false)
    Distributed.remotecall_eval(Main, pid, :(import Pkg))
    remotecall_fetch(Pkg.activate, pid, remote_env_dir)
    instantiate && remotecall_fetch(Pkg.instantiate, pid)
end

end
