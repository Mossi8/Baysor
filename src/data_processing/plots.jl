using Random
using Colors
using Measures
using DataFrames
using DataFramesMeta
using NearestNeighbors
using Statistics

import MultivariateStats
import Plots

plot_cell_borders_polygons!(args...; kwargs...) =
    plot_cell_borders_polygons(args...; append=true, kwargs...)

plot_cell_borders_polygons(df_spatial::DataFrame, df_centers::DataFrame; kwargs...) =
    plot_cell_borders_polygons(df_spatial, Array{Float64, 2}[], df_centers; kwargs...)

function plot_cell_borders_polygons(df_spatial::DataFrame, polygons::Array{Matrix{Float64}, 1}=Matrix{Float64}[], df_centers=nothing; point_size=2,
                                    color::Union{Vector, Symbol, String}=:gene, center_size::Real=3.0, polygon_line_width=1, polygon_line_color="black", polygon_alpha::Float64=1.0,
                                    size=(800, 800), xlims=nothing, ylims=nothing, append::Bool=false, alpha=0.5, offset=(0, 0), subplot::Int=1,
                                    is_noise::Union{Vector, BitArray, Symbol, Nothing}=nothing, annotation::Union{TA, Nothing} where TA <: AbstractVector = nothing,
                                    ann_colors::Union{Nothing, Dict} = nothing, legend=(annotation !== nothing), legend_bg_alpha::Float64=0.85, fontsize=8,
                                    noise_ann = nothing, format::Symbol=:png, noise_kwargs::Union{Dict, Nothing}=nothing, shuffle_colors::Bool=false, kwargs...)
    noise_args_default = Dict(:markershape => :xcross, :alpha => alpha, :markersize => point_size / 2, :legend => legend, :markerstrokewidth => 0, :color => "black");
    if noise_kwargs === nothing
        noise_kwargs = noise_args_default
    else
        noise_kwargs = Dict{Symbol, Any}(noise_kwargs)
        for k in keys(noise_args_default)
            if !(k in keys(noise_kwargs))
                noise_kwargs[k] = noise_args_default[k]
            end
        end

        for k in keys(kwargs)
            if !(k in keys(noise_kwargs))
                noise_kwargs[k] = kwargs[k]
            end
        end
    end

    if typeof(color) === Symbol
        color = df_spatial[!,color]
    end

    if xlims === nothing
        xlims = (minimum(df_spatial.x), maximum(df_spatial.x))
    end

    if ylims === nothing
        ylims = (minimum(df_spatial.y), maximum(df_spatial.y))
    end

    fig = append ? Plots.plot!(format=format) : Plots.plot(format=format, size=size, xtickfontsize=fontsize, ytickfontsize=fontsize)

    df_noise = nothing

    if typeof(is_noise) === Symbol
        is_noise = df_spatial[!,is_noise]
    end

    if is_noise !== nothing
        df_noise = df_spatial[is_noise,:]
        df_spatial = df_spatial[.!is_noise,:]
        color = color[.!is_noise]
    end

    if is_noise !== nothing
        Plots.scatter!(df_noise.x .+ offset[1], df_noise.y .+ offset[2]; subplot=subplot, noise_kwargs...)
    end

    if annotation === nothing
        fig = Plots.scatter!(df_spatial.x .+ offset[1], df_spatial.y .+ offset[2]; color=color, markerstrokewidth=0, markersize=point_size,
                             alpha=alpha, legend=false, subplot=subplot, kwargs...)
    else
        ann_vals = annotation[annotation .!= noise_ann] |> unique |> sort
        c_map = Colors.distinguishable_colors(length(ann_vals), Colors.colorant"#007a10", lchoices=range(20, stop=70, length=15))
        # c_map = Colors.distinguishable_colors(length(ann_vals), Colors.colorant"#007a10")
        if shuffle_colors
            Random.shuffle!(c_map)
        end

        for (color, ann) in zip(c_map, ann_vals)
            style_dict = (ann_colors === nothing) ? Dict() : Dict(:color => ann_colors[ann])
            c_alpha = (length(alpha) == 1) ? alpha : alpha[annotation .== ann]
            fig = Plots.scatter!(df_spatial.x[annotation .== ann] .+ offset[1], df_spatial.y[annotation .== ann] .+ offset[2];
                                 markerstrokewidth=0, markersize=point_size, alpha=c_alpha, label=ann, legend=legend, color=color,
                                 bg_legend=Colors.RGBA(1.0, 1.0, 1.0, legend_bg_alpha), subplot=subplot, style_dict..., kwargs...)
        end

        if noise_ann in annotation
            fig = Plots.scatter!(df_spatial.x[annotation .== noise_ann] .+ offset[1], df_spatial.y[annotation .== noise_ann] .+ offset[2];
                                 label=noise_ann, subplot=subplot, noise_kwargs...)
        end
    end

    shapes = [Plots.Shape(pg[:,1] .+ offset[1], pg[:,2] .+ offset[2]) for pg in polygons]
    Plots.plot!(shapes, fill=(0, 0.0), linewidth=polygon_line_width, linecolor=polygon_line_color, alpha=polygon_alpha, subplot=subplot, label="")

    if df_centers !== nothing
        Plots.scatter!(df_centers[!,:x] .+ offset[1], df_centers[!,:y] .+ offset[2], color=colorant"#cc1300", markerstrokewidth=1, markersize=center_size,
            subplot=subplot, label="")
    end

    Plots.xlims!(xlims .+ offset[1], subplot=subplot)
    Plots.ylims!(ylims .+ offset[2], subplot=subplot)

    return fig
end

function shuffle_labels(labels::Array{Int})
    new_labs = deepcopy(labels)
    mask = (new_labs .!= 0)
    new_labs[mask] = shuffle(1:maximum(labels))[new_labs[mask]]
    return new_labs
end

function shuffle_colors(colors::Vector)
    uniq_cols = unique(colors);
    col_ord = Dict(Pair.(uniq_cols, shuffle(1:length(uniq_cols))));
    return [uniq_cols[col_ord[tc]] for tc in colors]
end

function plot_expression_vectors(vecs...; gene_names::Vector{String}, min_expr_frac::Float64=0.05, alpha::Float64=0.5, fontsize::Int=5, text_offset::Float64=0.005,
        labels::Vector{String}=["y$i" for i in 1:length(vecs)], xrotation=60, xticks::Bool=false, kwargs...)
    y_vals = maximum(hcat(vecs...), dims=2) |> vec
    scale = sum(y_vals)

    p = Plots.plot(;widen=false, ylims=(0, maximum(y_vals) + text_offset * scale), kwargs...)
    for (v,l) in zip(vecs, labels)
        p = Plots.bar!(v, alpha=alpha, label=l)
    end

    ann_genes = findall(y_vals .>= min_expr_frac * scale)
    p = Plots.annotate!(collect(zip(ann_genes, y_vals[ann_genes] .+ text_offset * scale, Plots.text.(gene_names[ann_genes], fontsize))))
    if xticks
        Plots.xticks!(1:length(gene_names), gene_names, xrotation=xrotation, xgrid=false)
    end
    return p
end

function clustermap(mtx::T where T <: AbstractMatrix{Float64}, gene_names::Vector{String}; gene_ord::Union{<:AbstractVector{<:Integer}, Bool}=true,
        cell_ord::Union{<:AbstractVector{<:Integer},Bool}=true, diag_genes::Bool=false, kwargs...)
    if typeof(cell_ord) === Bool
        if cell_ord
            cell_dists = 1 .- cor(mtx);
            cell_ord = Clustering.hclust(cell_dists, linkage=:ward).order;
        else
            cell_ord = 1:size(mtx, 2)
        end
    end

    if typeof(gene_ord) === Bool
        if gene_ord
            if diag_genes
                gene_ord = sortperm(vec(mapslices(x -> findmax(x)[2], mtx[:, cell_ord], dims=2)), rev=true);
            else
                gene_dists = 1 .- cor(mtx');
                gene_ord = Clustering.hclust(gene_dists, linkage=:ward).order;
            end
        else
            gene_ord = 1:size(mtx, 1)
        end
    end

    Plots.heatmap(mtx[gene_ord, cell_ord]; yticks=(1:length(gene_names), gene_names[gene_ord]), kwargs...), cell_ord, gene_ord
end

### Tracing

function plot_num_of_cells_per_iterarion(tracer::Dict{Symbol, Any}; kwargs...)
    if !(:n_components in keys(tracer)) || length(tracer[:n_components]) == 0
        error("No data about #components per iteration was stored")
    end

    n_components_per_iter = hcat(collect.(values.(tracer[:n_components]))...);
    labels = collect(keys(tracer[:n_components][1]));

    n_components_per_iter = n_components_per_iter[sortperm(labels),:]
    labels = sort(labels)

    p = Plots.plot(; legendtitle="Min #molecules", title="Convergence", xlabel="Iteration", ylabel="#Cells",
                   background_color_legend=Colors.RGBA(1.0, 1.0, 1.0, 0.5), legend=:topleft, kwargs...)
    for i in 1:size(n_components_per_iter, 1)
        p = Plots.plot!(n_components_per_iter[i,:], label="$(labels[i])")
    end

    p = Plots.plot!(xlabel="Iteration", ylabel="#Cells", inset = (1, Plots.bbox(0.05,0.05,0.35,0.35,:top,:right)), subplot=2,
        bg_inside=nothing, legend=nothing, kwargs...)

    subplot_start = ceil(Int, 0.75 * size(n_components_per_iter, 2))
    iter_vals = subplot_start:size(n_components_per_iter, 2)
    for i in 1:size(n_components_per_iter, 1)
        p = Plots.plot!(iter_vals, n_components_per_iter[i, iter_vals], subplot=2, ylims=[0, maximum(n_components_per_iter[:, iter_vals]) * 1.05])
    end

    return p
end

### Colormaps

function map_to_colors(vals::Array{T, 1} where T; lims=nothing, palette=Colors.sequential_palette(0, 11))
    offset = (lims === nothing) ? minimum(vals) : lims[1]
    scale = (lims === nothing) ? maximum(vals) - offset : (lims[2] - lims[1])

    if lims !== nothing
        vals = min.(max.(vals, lims[1]), lims[2])
    end

    color_ticks = collect(range(0.0, 1.0, length=length(palette))) .* scale .+ offset
    colors = palette[floor.(Int, ((vals .- offset) ./ scale) .* (length(palette) - 1) .+ 1)]

    return Dict(:colors=>colors, :ticks=>color_ticks, :palette=>palette)
end

function distinguishable_colors(vals::T where T <: AbstractVector, args...; kwargs...)
    id_per_type = Dict(c => i for (i,c) in enumerate(unique(vals)));
    colors_uniq = Colors.distinguishable_colors(length(id_per_type), args...; kwargs...);
    colors = colors_uniq[get.(Ref(id_per_type), vals, 0)];

    return Dict(:colors=>colors, :ticks=>unique(vals), :palette=>colors_uniq)
end

plot_colorbar(colors; kwargs...) = plot_colorbar(colors[:ticks], colors[:palette]; kwargs...)

function plot_colorbar(color_ticks, palette; size=(500, 60), rotation=0, kwargs...)
    p = Plots.bar(color_ticks, ones(length(palette)); color=palette, size=size, legend=false, yticks=false, kwargs...)
    p.subplots[1][:xaxis][:rotation] = rotation;

    return p
end