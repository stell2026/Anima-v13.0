using Pkg
Pkg.activate(@__DIR__)
Pkg.instantiate()

include("anima_interface.jl")
include("anima_memory_db.jl")
include("anima_subjectivity.jl")
include("anima_dream.jl")
include("anima_background.jl")

anima = Anima()
mem   = MemoryDB()
subj  = SubjectivityEngine(mem)

repl_with_background!(
    anima;
    mem = mem,
    subj = subj,
    use_llm = true,
    llm_url = "https://openrouter.ai/api/v1/chat/completions",
    llm_model = "openai/gpt-oss-120b:free",
    llm_key = "YOUR_OPENROUTER_API_KEY",  # https://openrouter.ai/keys
    use_input_llm = true,
    input_llm_model = "openai/gpt-oss-120b:free",
    input_llm_key = "YOUR_OPENROUTER_API_KEY",  # https://openrouter.ai/keys
)
