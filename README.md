# DistributedAdhoc.jl

Easily use Julia `Distributed` in an ad-hoc way: on computers not dedicated to distributed processing.
Each machine can have different paths, different usernames and home directories, no shared filesystem.
The only requirement is that Julia is installed everywhere, and all machines can be added as `Distributed` workers.

`DistributedAdhoc` can send files, directories, and whole environments from the master process to all workers:

```julia
julia> using DistributedAdhoc  # reexports Distributed, adds no new exports

julia> addprocs(...)

# send a local file and a directory to worker #3
julia> remote_file = DistributedAdhoc.send_file("local_path/to/my_file.txt", 3)
"/tmp/jl_S1vUpx/my_file.txt"  # path of the file on worker #3

julia> remote_dir = DistributedAdhoc.send_dir("local_path/to/my_dir", 3; include=["file.txt", "data/*.csv"])
"/tmp/jl_fKgj4Y"  # path of the dir on worker #3

# send the current Julia environment to all workers, instantiate and activate it
# include source code in `src`, developed packages (in `./dev`), scripts (in `./scripts`), and CSV files (in `./data`)
julia> DistributedAdhoc.send_env_activate_everywhere(include=[
    "*.toml", "src/*.jl", "scripts/*.jl",
    "dev/*/*.toml", "dev/*/src/*.jl", "dev/*/src/*/*.jl",
    "data/*.csv",
])
```

More functions, options, and details: see `src/DistributedAdhoc.jl` or docstrings.
