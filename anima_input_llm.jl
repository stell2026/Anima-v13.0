#=
╔══════════════════════════════════════════════════════════════════════════════╗
║                A N I M A  —  Input LLM                                      ║
║                                                                              ║
║  Вхідна LLM — перекладач сигналу.                                           ║
║  Отримує текст користувача, повертає JSON-стимул для ядра.                   ║
║  НЕ відповідає користувачу. НЕ має голосу в діалозі.                        ║
║                                                                              ║
║  Потік:                                                                      ║
║    user_text                                                                 ║
║      → input_llm_async (сильна модель, async)                               ║
║      → validate_input_signal! (Julia, синхронно)                            ║
║      → experience! (ядро)                                                   ║
║      → output_llm (слабша модель, async)                                    ║
║      → відповідь користувачу                                                ║
║                                                                              ║
║  Якщо вхідна LLM недоступна або confidence < threshold:                     ║
║    → fallback на text_to_stimulus (поточна логіка)                          ║
╚══════════════════════════════════════════════════════════════════════════════╝
=#

# Потребує: HTTP, JSON3 (вже є в anima_interface.jl)

# ════════════════════════════════════════════════════════════════════════════
# КОНСТАНТИ
# ════════════════════════════════════════════════════════════════════════════

# Мінімальний confidence щоб прийняти сигнал від вхідної LLM.
# Нижче — fallback на text_to_stimulus.
const INPUT_LLM_CONFIDENCE_THRESHOLD = 0.60

# Максимальне значення будь-якого поля стимулу від вхідної LLM.
# Захист від перебільшень (LLM може повернути tension=0.99 на звичайне питання).
const INPUT_LLM_MAX_DELTA = 0.7

# Таймаут для вхідної LLM (секунди). Має бути коротший ніж вихідний LLM.
const INPUT_LLM_TIMEOUT = 15

# ════════════════════════════════════════════════════════════════════════════
# ASYNC ВИКЛИК
# ════════════════════════════════════════════════════════════════════════════

"""
    input_llm_async(user_msg; api_url, model, api_key) → Channel{Dict}

Асинхронний виклик вхідної LLM.
Повертає Channel — результат приходить коли готовий.
При помилці або невалідному JSON → повертає порожній Dict (буде fallback).

Модель: сильна (claude-3-5-sonnet, gpt-4o, тощо).
Завдання: перекласти текст у JSON-стимул.
"""
function input_llm_async(user_msg::String;
                          api_url::String="https://openrouter.ai/api/v1/chat/completions",
                          model::String="anthropic/claude-3-5-sonnet",
                          api_key::String="",
                          prompt_path::String=joinpath(@__DIR__,"llm","input_prompt.txt")
                          )::Channel{Dict{String,Any}}

    ch = Channel{Dict{String,Any}}(1)

    # Читаємо системний промпт до spawn — не захоплюємо IO у thread
    sys_text = try
        read(prompt_path, String)
    catch
        # Мінімальний fallback якщо файл не знайдено
        "Return ONLY a JSON with keys: tension, arousal, satisfaction, cohesion, valence, subtext, confidence. Values -1.0 to 1.0."
    end

    messages = [
        Dict("role"=>"system", "content"=>sys_text),
        Dict("role"=>"user",   "content"=>user_msg)
    ]

    Threads.@spawn begin
        result = Dict{String,Any}()
        try
            is_ollama = contains(api_url,"11434") || contains(api_url,"ollama")
            headers   = ["Content-Type"=>"application/json"]
            !isempty(api_key) && push!(headers, "Authorization"=>"Bearer $api_key")

            body = is_ollama ?
                JSON3.write(Dict("model"=>model, "messages"=>messages,
                                 "stream"=>false, "format"=>"json")) :
                JSON3.write(Dict("model"=>model, "messages"=>messages,
                                 "max_tokens"=>200,
                                 "response_format"=>Dict("type"=>"json_object")))

            resp  = HTTP.post(api_url, headers, body; readtimeout=INPUT_LLM_TIMEOUT)
            text  = is_ollama ? String(resp.body |> JSON3.read |> x->x["message"]["content"]) :
                                String(resp.body |> JSON3.read |> x->x["choices"][1]["message"]["content"])
            clean = replace(text, r"```json|```" => "")
            parsed = JSON3.read(clean)
            result = Dict{String,Any}(String(k)=>v for (k,v) in parsed)
        catch e
            @debug "input_llm error: $e"
            # result залишається порожнім → fallback
        finally
            # FIX 7: гарантований put! — канал ніколи не залишається порожнім
            put!(ch, result)
        end
    end

    ch
end

# ════════════════════════════════════════════════════════════════════════════
# ВАЛІДАЦІЯ І НОРМАЛІЗАЦІЯ
# ════════════════════════════════════════════════════════════════════════════

"""
    validate_input_signal(raw) → Dict{String,Float64}

Перевірити і нормалізувати відповідь вхідної LLM.

Повертає:
- Dict зі стимулом якщо confidence >= threshold і поля валідні
- порожній Dict якщо треба fallback

Захисти:
- confidence < threshold → fallback
- будь-яке поле > INPUT_LLM_MAX_DELTA → clamped (не відхиляємо, але обрізаємо)
- відсутні обов'язкові поля → fallback
- NaN або Inf → fallback
"""
function validate_input_signal(raw::Dict{String,Any})::Dict{String,Float64}
    isempty(raw) && return Dict{String,Float64}()

    # Перевірка confidence
    conf = get(raw, "confidence", 0.0)
    try conf = Float64(conf) catch; return Dict{String,Float64}() end
    conf < INPUT_LLM_CONFIDENCE_THRESHOLD && return Dict{String,Float64}()

    result = Dict{String,Float64}()
    signal_keys = ("tension", "arousal", "satisfaction", "cohesion")

    for k in signal_keys
        !haskey(raw, k) && return Dict{String,Float64}()  # обов'язкові поля
        v = try Float64(raw[k]) catch; return Dict{String,Float64}() end
        (isnan(v) || isinf(v)) && return Dict{String,Float64}()
        # Clamp до INPUT_LLM_MAX_DELTA — захист від перебільшень
        result[k] = clamp(v, -INPUT_LLM_MAX_DELTA, INPUT_LLM_MAX_DELTA)
    end

    result
end

# ════════════════════════════════════════════════════════════════════════════
# ГОЛОВНА ФУНКЦІЯ — повний цикл з fallback
# ════════════════════════════════════════════════════════════════════════════

"""
    process_input(user_msg, text_to_stimulus_fn; kwargs...) → (stim, source)

Повний вхідний pipeline:
1. Запускає вхідну LLM асинхронно
2. Паралельно обчислює text_to_stimulus як fallback
3. Чекає результат вхідної LLM (з таймаутом)
4. Валідує — якщо ок, повертає LLM-стимул; інакше — fallback

Повертає (stimulus::Dict{String,Float64}, source::String)
де source = "llm" або "fallback"

ВАЖЛИВО: ця функція синхронна (чекає вхідну LLM).
Якщо треба не блокувати — використовувати input_llm_async напряму.
"""
function process_input(user_msg::String,
                       text_to_stimulus_fn;
                       input_model::String="anthropic/claude-3-5-sonnet",
                       api_url::String="https://openrouter.ai/api/v1/chat/completions",
                       api_key::String="",
                       prompt_path::String=joinpath(@__DIR__,"llm","input_prompt.txt")
                       )::Tuple{Dict{String,Float64}, String, String}

    # Fallback завжди готовий
    fallback_stim = text_to_stimulus_fn(user_msg)

    # Якщо немає API ключа або порожнє повідомлення → одразу fallback
    (isempty(api_key) || isempty(strip(user_msg))) &&
        return (fallback_stim, "fallback", "")

    # Запустити вхідну LLM
    ch = input_llm_async(user_msg;
        api_url=api_url, model=input_model,
        api_key=api_key, prompt_path=prompt_path)

    # Чекати результат. Таймаут забезпечується readtimeout=INPUT_LLM_TIMEOUT
    # всередині input_llm_async через HTTP.post — Timer тут не потрібен
    # і не перериває take! (Julia channels не мають timeout на take!).
    raw = Dict{String,Any}()
    try
        raw = take!(ch)
    catch
        # канал закритий або spawn впав — fallback
    end

    validated = validate_input_signal(raw)
    isempty(validated) && return (fallback_stim, "fallback", "")

    want = String(get(raw, "want", ""))
    (validated, "llm", want)
end

# ════════════════════════════════════════════════════════════════════════════
# SNAPSHOT для логу
# ════════════════════════════════════════════════════════════════════════════

"""Коротке позначення джерела стимулу для рядка логу."""
input_source_label(source::String) = source == "llm" ? "🧠" : "📝"
