using Pkg
Pkg.activate(@__DIR__)
isfile(joinpath(@__DIR__, "Manifest.toml")) || Pkg.instantiate()

# Load .env file if present
function load_dotenv!(path::String)
    isfile(path) || return
    for line in eachline(path)
        stripped = strip(line)
        isempty(stripped) && continue
        startswith(stripped, '#') && continue
        startswith(stripped, "export ") && (stripped = strip(stripped[8:end]))
        m = match(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$", stripped)
        isnothing(m) && continue
        key = m.captures[1]
        val = strip(m.captures[2])
        if length(val) >= 2 && ((startswith(val, '"') && endswith(val, '"')) ||
                                (startswith(val, '\'') && endswith(val, '\'')))
            val = val[2:end-1]
        end
        haskey(ENV, key) || (ENV[key] = val)
    end
end

load_dotenv!(joinpath(@__DIR__, ".env"))

include("anima_memory_db.jl")
include("anima_narrative.jl")
include("anima_interface.jl")
include("anima_subjectivity.jl")
include("anima_dream.jl")
include("anima_background.jl")
include("anima_telegram.jl")

anima = Anima()
mem   = MemoryDB()
subj  = SubjectivityEngine(mem)

telegram_loop!(
    anima;
    mem = mem,
    subj = subj,
    use_llm = true,
    llm_url = get(ENV, "ANIMA_LLM_URL", "https://openrouter.ai/api/v1/chat/completions"),
    llm_model = get(ENV, "ANIMA_LLM_MODEL", "openai/gpt-oss-120b:free"),
    llm_key = get(ENV, "OPENROUTER_API_KEY", ""),
    use_input_llm = true,
    input_llm_model = get(ENV, "ANIMA_INPUT_LLM_MODEL", "openai/gpt-oss-120b:free"),
    input_llm_key = get(ENV, "OPENROUTER_API_KEY_INPUT", get(ENV, "OPENROUTER_API_KEY", "")),
    telegram_token = get(ENV, "ANIMA_TELEGRAM_TOKEN", ""),
    telegram_chat_id = get(ENV, "ANIMA_TELEGRAM_CHAT_ID", ""),
)
