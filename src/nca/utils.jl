const Maybe{T} = Union{Missing, T}

function checkconctime(conc, time=nothing; monotonictime=true)
  # check conc
  conc == nothing && return
  E = eltype(conc)
  isallmissing = all(ismissing, conc)
  if isempty(conc)
    @warn "No concentration data given"
  elseif !(E <: Maybe{Number} && conc isa AbstractArray) || E <: Maybe{Bool} && !isallmissing
    throw(ArgumentError("Concentration data must be numeric and an array"))
  elseif isallmissing
    @warn "All concentration data is missing"
  elseif any(x -> x<0, skipmissing(conc))
    @warn "Negative concentrations found"
  end
  # check time
  time == nothing && return
  T = eltype(time)
  if isempty(time)
    @warn "No time data given"
  elseif any(ismissing, time)
    throw(ArgumentError("Time may not be missing"))
  elseif !(T <: Maybe{Number} && time isa AbstractArray)
    throw(ArgumentError("Time data must be numeric and an array"))
  end
  if monotonictime
    !issorted(time, lt=≤) && throw(ArgumentError("Time must be monotonically increasing"))
  end
  # check both
  # TODO: https://github.com/UMCTM/PuMaS.jl/issues/153
  length(conc) != length(time) && throw(ArgumentError("Concentration and time must be the same length"))
  return
end

function cleanmissingconc(conc, time, args...; missingconc=:drop, check=true)
  check && checkconctime(conc, time)
  E = eltype(conc)
  T = Base.nonmissingtype(E)
  n = count(ismissing, conc)
  # fast path
  n == 0 && return conc, time
  len = length(conc)
  if missingconc === :drop
    newconc = similar(conc, T, len-n)
    newtime = similar(time, len-n)
    ii = 1
    @inbounds for i in eachindex(conc)
      if !ismissing(conc[i])
        newconc[ii] = conc[i]
        newtime[ii] = time[i]
        ii+=1
      end
    end
    return newconc, newtime
  elseif missingconc isa Number
    newconc = similar(conc, T)
    @inbounds for i in eachindex(newconc)
      newconc[i] = ismissing(conc[i]) ? missingconc : conc[i]
    end
    return newconc, time
  else
    throw(ArgumentError("missingconc must be a number or :drop"))
  end
end

"""
  ctlast(conc, time; interval=(0.,Inf), check=true) -> (clast, tlast)

Calculate `clast` and `tlast`.
"""
function ctlast(conc, time; check=true)
  clast, tlast = _ctlast(conc, time, check=check)
  clast == -one(eltype(conc)) && return missing, missing
  return (clast=clast, tlast=tlast)
end

# This function uses ``-1`` to denote missing as after checking `conc` is
# strictly great than ``0``.
function _ctlast(conc, time; check=true)
  if check
    checkconctime(conc, time)
    conc, time = cleanmissingconc(conc, time, check=false)
  end
  # now we assume the data is checked
  all(x->(ismissing(x) || x==0), conc) && return -one(eltype(conc)), -one(eltype(idx))
  @inbounds idx = findlast(x->!(ismissing(x) || x==0), conc)
  return conc[idx], time[idx]
end

"""
  ctmax(conc, time; interval=(0.,Inf), check=true) -> (cmax, tmax)

Calculate ``C_{max}_{t_1}^{t_2}`` and ``T_{max}_{t_1}^{t_2}``
"""
function ctmax(conc, time; interval=(0.,Inf), check=true)
  if interval === (0., Inf)
    idx = 1
    val = conc[idx]
    @inbounds for i in eachindex(conc)
      if !ismissing(conc[i])
        val > conc[i] && (val = conc[i]; idx=1)
      end
    end
    return (cmax=val, tmax=time[idx])
  end
  check && checkconctime(conc, time)
  @assert interval[1] < interval[2] "t0 must be less than t1"
  idx1, idx2 = let lo, hi=interval
    findfirst(t->t>=lo, time),
    findlast( t->t<=hi, time)
  end
  cmax = maximum(skipmissing(@view conc[idx1:idx2]))
  return (cmax=cmax, tmax=time[idx2])
end
