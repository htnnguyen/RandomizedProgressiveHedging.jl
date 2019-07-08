# ENV["OAR_NODEFILE"] = joinpath(".", "logdir", "config")
using Distributed, OarClusterManager

@assert basename(pwd())=="RPH.jl" "This script should be run from the RPH.jl folder."

GLOBAL_LOG_DIR = joinpath("/", "bettik", "PROJECTS", "pr-cvar", "RPH_num_exps")
# GLOBAL_LOG_DIR = joinpath(".", "logdir")

## Add all available workers
# !(workers() == Vector([1])) && (rmprocs(workers()); println("removing workers"))
# addprocs(get_ncoresmaster()-1)
# length(get_remotehosts())>0 && addprocs_oar(get_remotehosts())

## Load relevant packages in all workers
push!(LOAD_PATH, pwd())
using RPH, JuMP

using GLPK, Ipopt, LinearAlgebra
using DataStructures, DelimitedFiles
using Mosek, MosekTools, Juniper, Cbc

include("exec_algs_on_pbs.jl")

include("../examples/build_simpleexample.jl")
include("../examples/build_hydrothermalscheduling_extended.jl")
include("../examples/build_hydrothermalscheduling_milp.jl")

function get_problems()
    problems = []

    ## Subproblem optimizer parameters
    ipopt_optimizer_params = Dict{Symbol, Any}(:print_level=>0)

    juniper_optimizer_params = Dict{Symbol, Any}()
    juniper_optimizer_params[:nl_solver] = with_optimizer(Ipopt.Optimizer; print_level=0)
    juniper_optimizer_params[:mip_solver] = with_optimizer(Cbc.Optimizer; logLevel=0)
    juniper_optimizer_params[:log_levels] = []

    ## Global solve functions
    ph_globalsolve = pb -> solve_progressivehedging(pb, ϵ_primal=1e-10, ϵ_dual=1e-10, maxtime=4*60*60, maxiter=1e6, printstep=10)
    mosek_globalsolve = pb -> solve_direct(pb, optimizer=Mosek.Optimizer)

    # push!(problems, OrderedDict(
    #     :pbname => "simpleproblem",
    #     :pb => build_simpleexample(),
    #     :optimizer => Ipopt.Optimizer,
    #     :optimizer_params => ipopt_optimizer_params,
    #     :fnglobalsolve => ph_globalsolve
    # ))

    nstages, ndams = 5, 5
    push!(problems, OrderedDict(
        :pbname => "hydrothermal_$(nstages)stages_$(ndams)dams",
        :pb => build_hydrothermalextended_problem(;nstages=nstages, ndams=ndams),
        :optimizer => Ipopt.Optimizer,
        :optimizer_params => ipopt_optimizer_params,
        :fnglobalsolve => ph_globalsolve
    ))

    return problems
end

function get_algorithms()
    algorithms = []

    maxtime = 3*60*60
    maxiter = 1e9
    seeds = 1:3

    push!(algorithms, OrderedDict(
        :algoname => "progressivehedging",
        :fnsolve_symbol => :solve_progressivehedging,
        :fnsolve_params => Dict(
            :maxtime => maxtime,
            :maxiter => maxiter,
            :printstep => 1,
            :ϵ_primal => 1e-10,
            :ϵ_dual => 1e-10,
        ),
        :seeds => [1],
    ))
    push!(algorithms, OrderedDict(
        :algoname => "randomized_sync",
        :fnsolve_symbol => :solve_randomized_sync,
        :fnsolve_params => Dict(
            :maxtime => maxtime,
            :maxiter => maxiter,
            :printstep => 20,
        ),
        :seeds => seeds,
    ))

    return algorithms
end

execute_algs_on_problems(get_problems(), get_algorithms())
