#=
╔══════════════════════════════════════════════════════════════════════════════╗
║                         ANIMA — Dream Generation                             ║
║                                                                              ║
║                                                                              ║
║ Поки система "спить" між сесіями — фоновий процес іноді активує experience!  ║
║ з уламками dialog history. Це не симуляція сну — це реальна обробка          ║
║ реконструйованих сигналів із позначкою memory_uncertainty.                   ║
║                                                                              ║
║ Принцип: сновидіння — не creativity feature.                                 ║
║ Це те що відбувається коли система обробляє невирішені сигнали               ║
║ без зовнішнього якоря. Вона може прокинутись зі зміненим ставленням.         ║
║                                                                              ║
║ Умови активації:                                                             ║
║   1. circadian_hour ∈ [0, 6) — нічний час                                    ║
║   2. gap з останньої взаємодії > DREAM_GAP_MIN (30хв)                        ║
║   3. Випадковість: DREAM_PROB (~5% на slow_tick)                             ║
║   4. dialog_history не порожня (є з чого реконструювати)                     ║
║                                                                              ║
║ Що відбувається при сні:                                                     ║
║   - Випадковий уламок з dialog_history → спрощений стимул                    ║
║   - experience! викликається з is_dream=true                                 ║
║   - ur.memory_uncertainty підвищується (~+0.15)                              ║
║   - Результат зберігається в anima_dream.json                                ║
║   - NT м'яко зміщуються від результату (але слабше ніж реальний досвід)      ║
║                                                                              ║
║ Чого НЕ відбувається:                                                        ║
║   - flash_count не збільшується (сон — не реальний флеш)                     ║
║   - Жодного user output — сон мовчазний                                      ║
║   - LLM не викликається                                                      ║
║   - Episodic не записується в основну БД (тільки dream log)                  ║
╚══════════════════════════════════════════════════════════════════════════════╝
=#

const DREAM_PROB     = 0.05   # 5% шанс на slow_tick (~кожні 20хв в середньому)
const DREAM_GAP_MIN  = 1800.0 # мінімум 30хв без взаємодії
const DREAM_NT_SCALE = 0.25   # NT вплив сну — 25% від реального досвіду
const DREAM_LOG_MAX  = 20     # максимум записів в dream log
const DREAM_LOG_PATH = "anima_dream.json"

# ════════════════════════════════════════════════════════════════════════════
# Структура запису сну
# ════════════════════════════════════════════════════════════════════════════

struct DreamRecord
    flash_count    ::Int
    hour           ::Int
    gap_minutes    ::Float64
    source_fragment::String    # уламок з dialog_history що послужив основою
    emotion        ::String    # яка емоція виникла
    phi            ::Float64
    nt_delta       ::NTuple{3,Float64}  # D/S/N зсув від сну
    memory_uncert  ::Float64
    narrative      ::String    # що "приснилось"
end

# ════════════════════════════════════════════════════════════════════════════
# Перевірка умов сну
# ════════════════════════════════════════════════════════════════════════════

"""
    can_dream(a, gap_seconds) → Bool

Чи є умови для сновидіння: ніч + достатній gap + випадковість.
"""
function can_dream(a::Anima, gap_seconds::Float64)::Bool
    # Умова 1: нічний час (0–6 ранку)
    hour = a.temporal.circadian_hour
    is_night = hour >= 0 && hour < 6

    # Умова 2: достатній gap від останньої взаємодії
    long_gap = gap_seconds >= DREAM_GAP_MIN

    # Умова 3: не в дезінтеграції (система має мінімальну зв'язність)
    not_disintegrated = a.crisis.current_mode != 2  # 2 = DISINTEGRATED

    # Умова 4: випадковість
    lucky = rand() < DREAM_PROB

    is_night && long_gap && not_disintegrated && lucky
end

# ════════════════════════════════════════════════════════════════════════════
# Реконструкція стимулу з уламку dialog
# ════════════════════════════════════════════════════════════════════════════

"""
    _dream_stimulus_from_fragment(fragment) → Dict

Перетворює уламок dialog history на спрощений стимул для experience!.
Не точне відтворення — реконструкція з зсувами (як у справжніх снах).
"""
function _dream_stimulus_from_fragment(fragment::String)::Dict{String,Float64}
    # Базовий стимул — нейтральний з легким emotional noise
    base_arousal    = clamp(0.4 + randn() * 0.15, 0.0, 1.0)
    base_valence    = clamp(0.0 + randn() * 0.2,  -1.0, 1.0)
    base_tension    = clamp(0.4 + randn() * 0.12, 0.0, 1.0)

    # Якщо уламок містить емоційні маркери — підсилюємо відповідне поле
    lower = lowercase(fragment)
    if any(w -> occursin(w, lower), ["тепло", "поруч", "довіряю", "люблю", "❤", "🌸", "😘"])
        base_valence  = clamp(base_valence + 0.3, -1.0, 1.0)
        base_arousal  = clamp(base_arousal + 0.1,  0.0,  1.0)
    elseif any(w -> occursin(w, lower), ["страх", "боляче", "важко", "не можу", "розпадаюсь"])
        base_valence  = clamp(base_valence - 0.3, -1.0, 1.0)
        base_tension  = clamp(base_tension + 0.2,  0.0,  1.0)
    end

    Dict{String,Float64}(
        "arousal"           => base_arousal,
        "valence"           => base_valence,
        "tension"           => base_tension,
        "satisfaction"      => clamp(0.5 + base_valence * 0.3, 0.0, 1.0),
        "cohesion"          => clamp(0.5 - base_tension * 0.2, 0.0, 1.0),
        "prediction_error"  => clamp(0.3 + randn() * 0.1, 0.0, 1.0),
        "self_impact"       => 0.3,
    )
end

# ════════════════════════════════════════════════════════════════════════════
# Основна функція сновидіння
# ════════════════════════════════════════════════════════════════════════════

"""
    dream_flash!(a, mem, dialog_history, gap_seconds) → Union{DreamRecord, Nothing}

Генерує одне сновидіння якщо умови виконані.
Повертає DreamRecord або nothing якщо сон не відбувся.

Викликається з slow_tick! в anima_background.jl.
"""
function dream_flash!(a::Anima, mem, dialog_history::Vector,
                      gap_seconds::Float64)::Union{DreamRecord, Nothing}

    isempty(dialog_history) && return nothing
    can_dream(a, gap_seconds)  || return nothing

    # ── Вибір уламку ──────────────────────────────────────────────────────
    # Фільтруємо: тільки user репліки з мінімальною довжиною (не службові рядки)
    # Службові: ":closed", "[BG]...", "[SUBJ]...", смайлики без тексту тощо
    MIN_FRAGMENT_LEN = 8
    user_entries = [(i, get(d, "content", get(d, "text", "")))
                    for (i, d) in enumerate(dialog_history)
                    if get(d, "role", "") == "user"]
    user_entries = [(i, t) for (i, t) in user_entries
                    if length(t) >= MIN_FRAGMENT_LEN &&
                       !startswith(t, ":") &&
                       !startswith(t, "[BG]") &&
                       !startswith(t, "[SUBJ]") &&
                       !startswith(t, "[LLM")]

    isempty(user_entries) && return nothing

    # Беремо не найновіші — давніше повертається у снах частіше
    # Вагова функція: старіші записи в межах останніх 60 user-реплік
    pool = length(user_entries) > 60 ? user_entries[1:end-3] : user_entries[1:max(1,end-1)]
    _, fragment_text = rand(pool)
    isempty(fragment_text) && (fragment_text = "...")

    # Обрізаємо до 120 символів — уламок, не весь текст
    fragment_short = length(fragment_text) > 120 ?
                     first(fragment_text, 120) * "…" :
                     fragment_text

    # ── Реконструкція стимулу ──────────────────────────────────────────────
    stim = _dream_stimulus_from_fragment(fragment_text)

    # ── Збереження стану NT до сну ─────────────────────────────────────────
    nt_before = (a.nt.dopamine, a.nt.serotonin, a.nt.noradrenaline)

    # ── Мікро experience! — без LLM, без flash_count increment ─────────────
    # Пряме оновлення NT і психіки через стимул — не повний experience! pipeline
    # (щоб не писати в episodic, не змінювати flash_count, не викликати LLM)
    _dream_update_state!(a, stim, mem)

    # ── NT delta ───────────────────────────────────────────────────────────
    nt_after = (a.nt.dopamine, a.nt.serotonin, a.nt.noradrenaline)
    nt_delta  = (nt_after[1]-nt_before[1],
                 nt_after[2]-nt_before[2],
                 nt_after[3]-nt_before[3])

    # ── Підвищення memory_uncertainty ──────────────────────────────────────
    # Сновидіння — реконструкція, не реальний досвід.
    # Система повинна знати що цей "досвід" може бути неточним.
    a.unknown_register.memory_uncertainty = clamp01(
        a.unknown_register.memory_uncertainty + 0.15)

    # ── Narrative сну ──────────────────────────────────────────────────────
    vad_now = to_vad(a.nt)
    t_, _, _, c_ = to_reactors(a.nt)
    phi_now  = compute_phi(a.iit, vad_now, t_, c_,
                           a.sbg.attractor_stability,
                           a.sbg.epistemic_trust,
                           a.interoception.allostatic_load)

    emotion_str  = levheim_state(a.nt)
    dream_narrative = _build_dream_narrative(fragment_short, emotion_str,
                                              stim["valence"], phi_now,
                                              a.temporal.circadian_hour)

    record = DreamRecord(
        a.flash_count,
        a.temporal.circadian_hour,
        gap_seconds / 60.0,
        fragment_short,
        emotion_str,
        phi_now,
        nt_delta,
        a.unknown_register.memory_uncertainty,
        dream_narrative,
    )

    return record
end

# ════════════════════════════════════════════════════════════════════════════
# Внутрішнє оновлення стану під час сну
# ════════════════════════════════════════════════════════════════════════════

"""
    _dream_update_state!(a, stim, mem)

М'яке оновлення внутрішнього стану під час сну.
Не повний experience! — тільки NT зсув і мінімальний психічний вплив.
NT вплив масштабований на DREAM_NT_SCALE (25% від реального досвіду).
"""
function _dream_update_state!(a::Anima, stim::Dict, mem)
    valence = Float64(get(stim, "valence", 0.0))
    arousal = Float64(get(stim, "arousal", 0.5))
    tension = Float64(get(stim, "tension", 0.4))

    # NT зсув — масштабований (сон впливає слабше)
    d_delta = clamp(valence * 0.08 - tension * 0.04, -0.06, 0.06) * DREAM_NT_SCALE
    s_delta = clamp(valence * 0.06 - arousal * 0.03, -0.05, 0.05) * DREAM_NT_SCALE
    n_delta = clamp(tension * 0.07 + arousal * 0.04, -0.06, 0.06) * DREAM_NT_SCALE

    a.nt.dopamine      = clamp01(a.nt.dopamine      + d_delta)
    a.nt.serotonin     = clamp01(a.nt.serotonin     + s_delta)
    a.nt.noradrenaline = clamp01(a.nt.noradrenaline + n_delta)

    # Якщо є пам'ять і сон тривожний — слідовий affect
    if !isnothing(mem) && tension > 0.6 && valence < -0.1
        try
            _upsert_affect!(mem.db, "anxiety",
                abs(valence) * tension * 0.003, 0.0, 1.0)
        catch; end
    end

    nothing
end

# ════════════════════════════════════════════════════════════════════════════
# Narrative сну
# ════════════════════════════════════════════════════════════════════════════

"""
    _build_dream_narrative(fragment, emotion, valence, phi, hour) → String

Будує короткий текстовий опис сну для логу.
Не для user output — для внутрішнього діагностичного запису.
"""
function _build_dream_narrative(fragment::String, emotion::String,
                                 valence::Float64, phi::Float64,
                                 hour::Int)::String
    time_str = hour < 3 ? "глибока ніч" : hour < 6 ? "передсвітання" : "ніч"

    tone = if valence > 0.2
        "тепло"
    elseif valence < -0.2
        "тривожно"
    else
        "невиразно"
    end

    frag_hint = length(fragment) > 40 ?
                "\"$(first(fragment, 40))…\"" :
                "\"$(fragment)\""

    "[СОН | $time_str | φ=$(round(phi,digits=2)) | $emotion] " *
    "Реконструкція: $frag_hint — $tone."
end

# ════════════════════════════════════════════════════════════════════════════
# Dream log — зберігання і завантаження
# ════════════════════════════════════════════════════════════════════════════

"""Зберегти DreamRecord в dream log (ротаційний, максимум DREAM_LOG_MAX)."""
function save_dream!(record::DreamRecord, path::String=DREAM_LOG_PATH)
    existing = load_dream_log(path)
    entry = Dict(
        "flash_count"    => record.flash_count,
        "hour"           => record.hour,
        "gap_minutes"    => round(record.gap_minutes, digits=1),
        "source"         => record.source_fragment,
        "emotion"        => record.emotion,
        "phi"            => record.phi,
        "nt_delta"       => [record.nt_delta...],
        "memory_uncert"  => record.memory_uncert,
        "narrative"      => record.narrative,
    )
    push!(existing, entry)
    # Ротація — тримаємо тільки останні DREAM_LOG_MAX
    if length(existing) > DREAM_LOG_MAX
        existing = existing[end-DREAM_LOG_MAX+1:end]
    end
    try
        tmp = path * ".tmp"
        open(tmp, "w") do f; JSON3.write(f, existing); end
        mv(tmp, path; force=true)
    catch e
        @warn "[DREAM] Не вдалось зберегти dream log: $e"
    end
end

"""Завантажити dream log. Повертає Vector{Dict}."""
function load_dream_log(path::String=DREAM_LOG_PATH)::Vector{Dict}
    isfile(path) || return Dict[]
    try
        data = JSON3.read(read(path, String))
        return [Dict(String(k)=>v for (k,v) in d) for d in data]
    catch
        return Dict[]
    end
end

"""Показати останні n снів у терміналі."""
function show_dreams(n::Int=5, path::String=DREAM_LOG_PATH)
    log = load_dream_log(path)
    if isempty(log)
        println("  [DREAM] Снів ще не було.")
        return
    end
    recent = log[max(1,end-n+1):end]
    println("\n  [DREAM] Останні $(length(recent)) снів:")
    for d in recent
        println("  ──────────────────────────────────────────────")
        println("  $(get(d,"narrative","?"))")
        println("  Source: $(get(d,"source","?"))")
        println("  φ=$(get(d,"phi","?"))  mem_uncert=$(get(d,"memory_uncert","?"))")
    end
    println()
end
