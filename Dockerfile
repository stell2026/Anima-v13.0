FROM julia:1.10-bookworm

ENV JULIA_CPU_TARGET=generic

WORKDIR /app

COPY Anima/ Anima/

RUN julia --project=Anima -e 'using Pkg; Pkg.Registry.add("General"); Pkg.resolve(); Pkg.instantiate(); Pkg.precompile()'

RUN mkdir -p /app/Anima/memory

VOLUME ["/app/Anima/memory"]

CMD ["julia", "--project=Anima", "Anima/run_anima_telegram.jl"]
