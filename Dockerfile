FROM julia:1.10-bookworm

ENV JULIA_CPU_TARGET=generic
ENV JULIA_DEPOT_PATH=/app/.julia

WORKDIR /app

RUN useradd -m -s /bin/bash anima

COPY Anima/ Anima/

# Manifest.toml may target a different Julia version — regenerate for this image
RUN rm -f Anima/Manifest.toml && \
    julia --project=Anima -e 'using Pkg; Pkg.Registry.add("General"); Pkg.resolve(); Pkg.instantiate(); Pkg.precompile()'

RUN mkdir -p /app/Anima/memory /app/Anima/state && \
    chown -R anima:anima /app/Anima /app/.julia

USER anima
WORKDIR /app/Anima

VOLUME ["/app/Anima/memory", "/app/Anima/state"]

CMD ["julia", "--project=.", "run_anima_telegram.jl"]
