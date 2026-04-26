#=
╔══════════════════════════════════════════════════════════════════════════════╗
║                    A N I M A  —  Background  (Julia)                         ║
║                                                                              ║
║  Фоновий процес — Anima живе між взаємодіями.                                ║
║                                                                              ║
║  Heartbeat цикл (кожен тік ~period_ms):                                      ║
║    1. tick_heartbeat!        — серце б'ється, dt залежить від стресу         ║
║    2. spontaneous_drift!     — випадковий шум NT (система не ідеальна)       ║
║    3. arrhythmia via dt      — аритмія при низькому coherence                ║
║                                                                              ║
║  Slow цикл (~60с):                                                           ║
║    4. circadian_drift        — добовий ритм NT                               ║
║    5. memory metabolism      — decay, consolidate, release_latent            ║
║    6. memory → state         — пам'ять формує стан КОЖЕН тік                 ║
║    7. belief decay           — переконання слабшають без підтвердження       ║
║    8. allostasis recovery    — тіло відновлюється в спокої                   ║
║    9. idle_thought!          — 10% шанс: система генерує досвід сама         ║
║   10. crisis check           — coherence перераховується                     ║
║   11. background_save!       — атомарний запис                               ║
║                                                                              ║
║  Запуск:   bg = start_background!(anima)                                     ║
║            bg = start_background!(anima; mem=mem)  # з SQLite пам'яттю       ║
║  Зупинка:  stop_background!(bg)                                              ║
╚══════════════════════════════════════════════════════════════════════════════╝
=#

# Потребує: anima_interface.jl
# Опціонально: anima_memory_db.jl (якщо передано mem=)

# ════════════════════════════════════════════════════════════════════════════
# КОНСТАНТИ
# ════════════════════════════════════════════════════════════════════════════

const SLOW_TICK_INTERVAL   = 60.0   # секунд між повільними тіками
const BELIEF_DECAY_RATE    = 0.0003 # за тік: confidence → baseline (rigidity-зважено)
const ALLOSTATIC_RECOVERY  = 0.004  # allostatic_load знижується за тік
const IDLE_THOUGHT_PROB    = 0.10   # 10% шанс idle thought за повільний тік
const DRIFT_NT_SIGMA       = 0.008  # σ спонтанного дрейфу NT за тік серця
const DRIFT_COHERENCE_LOSS = 0.003  # coherence трохи знижується від drift

# Аритмія: при низькому coherence period_ms варіюється більше
const ARRHYTHMIA_THR       = 0.35   # нижче → аритмія
const ARRHYTHMIA_JITTER    = 0.25   # максимальна варіація (±25%)

# ════════════════════════════════════════════════════════════════════════════
# BACKGROUND HANDLE
# ════════════════════════════════════════════════════════════════════════════

mutable struct BackgroundHandle
    stop_signal::Threads.Atomic{Bool}
    task::Task
    started_at::Float64
    last_slow_tick::Float64
    tick_count::Int
    slow_tick_count::Int
    mem::Union{Any, Nothing}   # MemoryDB або nothing
    subj::Union{Any, Nothing}  # SubjectivityEngine або nothing
    dialog_history::Ref{Vector}  # для dream generation
end

# ════════════════════════════════════════════════════════════════════════════
# 1+3. СЕРЦЕВИЙ ТІК + АРИТМІЯ — dt залежить від стресу і coherence
# ════════════════════════════════════════════════════════════════════════════

"""
    heartbeat_dt(a) → Float64 (секунди)

Базовий dt = period_ms / 1000 (вже залежить від NT через tick_heartbeat!).
При coherence < ARRHYTHMIA_THR — додається jitter: серце стає нерівним.
"""
function heartbeat_dt(a::Anima)::Float64
    base = clamp(a.heartbeat.period_ms / 1000.0, 0.4, 1.5)
    cs   = a.crisis.coherence
    if cs < ARRHYTHMIA_THR
        severity = (ARRHYTHMIA_THR - cs) / ARRHYTHMIA_THR
        jitter   = severity * ARRHYTHMIA_JITTER * (2*rand() - 1)
        base     = clamp(base * (1.0 + jitter), 0.3, 2.0)
    end
    base
end

# ════════════════════════════════════════════════════════════════════════════
# 2. SPONTANEOUS DRIFT — система не детермінована між взаємодіями
# ════════════════════════════════════════════════════════════════════════════

"""
    spontaneous_drift!(a)

Малий випадковий шум NT на кожному тіку серця.
Без цього система між сесіями ідеально стабільна — мертва.
σ = 0.008 → ледь помітний рух, decay поверне назад.
"""
function spontaneous_drift!(a::Anima)
    a.nt.dopamine      = clamp(a.nt.dopamine      + randn() * DRIFT_NT_SIGMA,       0.05, 0.95)
    a.nt.serotonin     = clamp(a.nt.serotonin     + randn() * DRIFT_NT_SIGMA,       0.05, 0.95)
    a.nt.noradrenaline = clamp(a.nt.noradrenaline + randn() * DRIFT_NT_SIGMA * 0.7, 0.05, 0.90)
    # Coherence теж трохи знижується — природня нестабільність
    a.crisis.coherence = clamp(a.crisis.coherence - abs(randn()) * DRIFT_COHERENCE_LOSS, 0.05, 1.0)
end

# ════════════════════════════════════════════════════════════════════════════
# 9а. IDLE THOUGHT — система думає без причини
# ════════════════════════════════════════════════════════════════════════════

"""
    _idle_thought_maybe!(a, mem)

З імовірністю IDLE_THOUGHT_PROB генерує внутрішній стимул.
Не experience! — легший внутрішній тік на основі поточного стану.
Важливо: система змінюється сама, не чекає людину.
"""
function _idle_thought_maybe!(a::Anima, mem=nothing)
    rand() > IDLE_THOUGHT_PROB && return

    t, ar, s, c = to_reactors(a.nt)
    vad = to_vad(a.nt)
    phi = compute_phi(a.iit, vad, t, c,
                      a.sbg.attractor_stability,
                      a.sbg.epistemic_trust,
                      a.interoception.allostatic_load)

    # Стимул = відгомін поточного стану + спонтанний компонент
    idle_stim = Dict{String,Float64}(
        "tension"      => (t  - 0.4) * 0.15,
        "arousal"      => (ar - 0.3) * 0.12 + randn() * 0.03,
        "satisfaction" => (s  - 0.4) * 0.10,
        "cohesion"     => (c  - 0.4) * 0.10,
    )

    apply_stimulus!(a.nt, idle_stim)
    decay_to_baseline!(a.nt, decay_rate(a.personality) * 0.1)
    update_from_nt!(a.body, a.nt)

    # Записати в пам'ять як idle подію (низький importance — нормально)
    if !isnothing(mem)
        try
            memory_write_event!(mem, a.flash_count,
                "idle_$(levheim_state(a.nt))",
                clamp01(ar + randn() * 0.05),
                clamp11(vad[1]),
                clamp01(abs(randn()) * 0.15),
                phi * 0.3, t, phi)
        catch e
            @warn "[BG] idle memory write: $e"
        end
    end
end

# ════════════════════════════════════════════════════════════════════════════
# 4–10. SLOW TICK — все що відбувається раз на ~60с
# ════════════════════════════════════════════════════════════════════════════

# ════════════════════════════════════════════════════════════════════════════
# PSYCHE SLOW TICK — психіка живе між взаємодіями
#
# Викликається з slow_tick! (~60с).
# Психічні стани дрейфують між флешами — без цього психіка мертва між сесіями.
#
# Принцип: тільки ті зміни що мають природній часовий вимір.
# Сором не зникає миттєво. Втома відновлюється в спокої.
# Хронічний афект зростає якщо NT хронічно зміщений.
# Anticipation decay — між подіями очікування слабшає.
# ════════════════════════════════════════════════════════════════════════════

function psyche_slow_tick!(a::Anima)
    # ── ChronifiedAffect ─────────────────────────────────────────────────────
    # Якщо між взаємодіями NT хронічно зміщений → хронічний афект повільно зростає.
    # Це те що відбувається "всередині" поки нічого не відбувається зовні.
    ca = a.chronified
    if a.nt.noradrenaline > 0.5 && a.nt.serotonin < 0.4
        # Хронічний стрес між взаємодіями → resentment і alienation
        ca.resentment  = clamp01(ca.resentment  + 0.001)
        ca.alienation  = clamp01(ca.alienation  + 0.0008)
    else
        # В спокої — повільний decay (але не нижче 0)
        ca.resentment  = max(0.0, ca.resentment  - 0.0005)
        ca.alienation  = max(0.0, ca.alienation  - 0.0004)
        ca.bitterness  = max(0.0, ca.bitterness  - 0.0003)
        ca.envy        = max(0.0, ca.envy        - 0.0004)
    end
    # Crystallized стани не розкристалізовуються самі по собі — це правильно

    # ── AnticipatoryConsciousness ────────────────────────────────────────────
    # Без нових подій dread і hope поступово слабшають (але не зникають)
    ac = a.anticipatory
    ac.dread    = clamp01(ac.dread    - 0.002)
    ac.hope     = clamp01(ac.hope     - 0.002)
    ac.strength = clamp01(ac.strength * 0.97)  # anticipation слабшає без підтримки

    # ── ShameModule ──────────────────────────────────────────────────────────
    # Активний сором decay швидше ніж chronic (хронічний — стійкіший)
    sm = a.shame
    sm.level   = max(0.0, sm.level   - 0.003)
    sm.chronic = max(0.0, sm.chronic - 0.0008)  # дуже повільно — це "фоновий гул"

    # ── SignificanceLayer ────────────────────────────────────────────────────
    # Між взаємодіями потреби повільно decay до базових значень
    # (те саме що в assess_significance! але без нового стимулу)
    sl = a.sig_layer
    base_sl = (self_preservation=0.2, coherence_need=0.3, contact_need=0.3,
               truth_need=0.4, autonomy_need=0.3, novelty_need=0.2)
    bg_decay = 0.008  # повільніший ніж при флеші (0.015)
    sl.self_preservation = clamp01(sl.self_preservation + (base_sl.self_preservation - sl.self_preservation) * bg_decay)
    sl.coherence_need    = clamp01(sl.coherence_need    + (base_sl.coherence_need    - sl.coherence_need)    * bg_decay)
    sl.contact_need      = clamp01(sl.contact_need      + (base_sl.contact_need      - sl.contact_need)      * bg_decay)
    sl.truth_need        = clamp01(sl.truth_need        + (base_sl.truth_need        - sl.truth_need)        * bg_decay)
    sl.autonomy_need     = clamp01(sl.autonomy_need     + (base_sl.autonomy_need     - sl.autonomy_need)     * bg_decay)
    sl.novelty_need      = clamp01(sl.novelty_need      + (base_sl.novelty_need      - sl.novelty_need)      * bg_decay)
    # contact_need зростає з часом бездіяльності — система "скучає"
    sl.contact_need = clamp01(sl.contact_need + 0.003)

    # ── GoalConflict ─────────────────────────────────────────────────────────
    # Без нових стимулів tension конфлікту повільно спадає
    gc = a.goal_conflict
    gc.tension = max(0.0, gc.tension - 0.008)
    if gc.tension < 0.05
        gc.resolution = "none"
    end

    # ── FatigueSystem ────────────────────────────────────────────────────────
    # В спокої втома відновлюється
    fs = a.fatigue
    fs.cognitive = max(0.0, fs.cognitive - 0.006)
    fs.emotional = max(0.0, fs.emotional - 0.005)
    fs.somatic   = max(0.0, fs.somatic   - 0.004)

    nothing
end


"""
    slow_tick!(a, mem, subj, dialog_history)

Повний повільний цикл (~60с).
Порядок: circadian → memory metabolism → memory→state → belief decay →
         allostasis → idle thought → psyche drift → dream → crisis check.
"""
function slow_tick!(a::Anima, mem=nothing, subj=nothing, dialog_history::Vector=Dict[])

    # ── 4. Циркадний дрейф ──────────────────────────────────────────────────
    _refresh_circadian!(a.temporal)
    frac = 1.0 / 1440.0
    a.nt.noradrenaline = clamp01(a.nt.noradrenaline + a.temporal.circadian_arousal_mod   * frac)
    a.nt.serotonin     = clamp01(a.nt.serotonin     + a.temporal.circadian_serotonin_mod * frac)
    decay_to_baseline!(a.nt, decay_rate(a.personality) * 0.3)
    update_from_nt!(a.body, a.nt)

    # ── 5. Memory metabolism ─────────────────────────────────────────────────
    if !isnothing(mem)
        try
            _memory_decay!(mem)
            _memory_prune!(mem)
            _memory_consolidate!(mem)   # включає latent release всередині
            _refresh_cache!(mem)
        catch e
            @warn "[BG] memory metabolism: $e"
        end
    end

    # ── 6. Memory → State (КЛЮЧ) ─────────────────────────────────────────────
    # Хронічний стрес/тривога/образа зміщують NT baseline КОЖЕН тік.
    # Не тільки при user input — пам'ять формує стан постійно.
    if !isnothing(mem)
        try
            memory_nt_baseline!(mem, a.nt, a.flash_count)
            update_from_nt!(a.body, a.nt)
        catch e
            @warn "[BG] memory→state: $e"
        end
    end

    # ── 7. Belief decay ──────────────────────────────────────────────────────
    for b in values(a.sbg.beliefs)
        baseline     = 0.45 + b.rigidity * 0.25
        effective_dr = BELIEF_DECAY_RATE * (1.0 - b.rigidity * 0.8)
        b.confidence = clamp01(b.confidence + (baseline - b.confidence) * effective_dr)
    end
    _recompute_stability!(a.sbg)

    # ── 8. Allostasis recovery ───────────────────────────────────────────────
    a.interoception.allostatic_load = clamp01(
        a.interoception.allostatic_load - ALLOSTATIC_RECOVERY)
    a.sbg.epistemic_trust = clamp(a.sbg.epistemic_trust + 0.0008, 0.0, 0.85)

    # LatentBuffer (психічний) decay
    a.latent_buffer.doubt      = clamp01(a.latent_buffer.doubt      - 0.003)
    a.latent_buffer.shame      = clamp01(a.latent_buffer.shame      - 0.002)
    a.latent_buffer.attachment = clamp01(a.latent_buffer.attachment - 0.002)
    a.latent_buffer.threat     = clamp01(a.latent_buffer.threat     - 0.003)
    decay_scars!(a.structural_scars)
    a.anchor.groundedness = clamp01(a.anchor.groundedness - 0.0005)

    # ── 9. Idle thought ─────────────────────────────────────────────────────
    _idle_thought_maybe!(a, mem)

    # ── 9б. Psyche drift — психіка живе між взаємодіями ─────────────────────
    psyche_slow_tick!(a)

    # ── 9в. Dream generation — сновидіння при нічному gap ───────────────────
    if !isnothing(mem)
        try
            gap_now = a.temporal.gap_seconds +
                      Float64(Dates.value(now() - unix2datetime(a.temporal.session_start))) / 1000.0
            dream_rec = dream_flash!(a, mem, dialog_history, gap_now)
            if !isnothing(dream_rec)
                save_dream!(dream_rec)
                @info "[DREAM] $(dream_rec.narrative)"
            end
        catch e
            @warn "[BG] dream_flash: $e"
        end
    end

    # ── 9б. Subjectivity: emerge beliefs ────────────────────────────────────
    # Тільки якщо flash_count змінився — нема сенсу шукати нові патерни
    # якщо нових подій не було (саме це і породжувало спам переконань).
    if !isnothing(subj)
        if a.flash_count != subj._emerged_cache_flash
            try
                subj_emerge_beliefs!(subj, a.flash_count)
            catch e
                @warn "[BG] subj_emerge_beliefs: $e"
            end
        end
    end

    # ── 10. Crisis check ─────────────────────────────────────────────────────
    # Після дрейфу і memory впливу — перерахувати coherence.
    # М'яке оновлення (0.3/0.7) — без стрибків.
    vad_now = to_vad(a.nt)
    t_, _, _, c_ = to_reactors(a.nt)
    phi_now  = compute_phi(a.iit, vad_now, t_, c_,
                            a.sbg.attractor_stability,
                            a.sbg.epistemic_trust,
                            a.interoception.allostatic_load)
    vfe_now  = compute_vfe(a.gen_model, vad_now)
    new_coh  = compute_coherence(a.sbg, a.blanket, vfe_now.vfe, phi_now)
    a.crisis.coherence = clamp01(a.crisis.coherence * 0.3 + new_coh * 0.7)

    # Оновити SystemMode з гістерезисом
    target_mode = a.crisis.coherence > 0.6 ? INTEGRATED :
                  a.crisis.coherence > 0.3 ? FRAGMENTED  : DISINTEGRATED
    if target_mode != a.crisis.current_mode
        a.crisis.steps_in_mode += 1
        if a.crisis.steps_in_mode >= a.crisis.min_steps_before_transition
            a.crisis.current_mode  = target_mode
            a.crisis.params        = get_crisis_params(target_mode)
            a.crisis.steps_in_mode = 0
        end
    else
        a.crisis.steps_in_mode = 0
    end

    nothing
end

# ════════════════════════════════════════════════════════════════════════════
# ACCUMULATED DRIFT — ретроспективний fallback
# ════════════════════════════════════════════════════════════════════════════

"""
    apply_accumulated_drift!(a, mem)

Застосовує накопичений дрейф за gap_seconds якщо фоновий не запущений.
Агрегована compound формула — точніше ніж N окремих тіків.
"""
function apply_accumulated_drift!(a::Anima, mem=nothing)
    gap = a.temporal.gap_seconds
    gap < 60.0 && return

    n_ticks = min(Int(floor(gap / SLOW_TICK_INTERVAL)), 480)
    n_ticks == 0 && return

    println("  [BG] Ретроспективний drift: $(round(gap/3600,digits=1))год = $n_ticks тіків")

    # NT decay (compound)
    rate = decay_rate(a.personality) * 0.3
    cpd  = (1.0 - rate)^n_ticks
    a.nt.dopamine      = clamp01(0.5 + (a.nt.dopamine      - 0.5) * cpd)
    a.nt.serotonin     = clamp01(0.5 + (a.nt.serotonin     - 0.5) * cpd)
    a.nt.noradrenaline = clamp01(0.3 + (a.nt.noradrenaline - 0.3) * cpd)
    update_from_nt!(a.body, a.nt)

    # Memory → State (навіть без фонового — хронічний affect формує стан)
    if !isnothing(mem)
        try
            _refresh_cache!(mem)
            memory_nt_baseline!(mem, a.nt, a.flash_count)
            update_from_nt!(a.body, a.nt)
        catch e
            @warn "[BG] accumulated drift memory→state: $e"
        end
    end

    # Beliefs decay (compound)
    for b in values(a.sbg.beliefs)
        baseline = 0.45 + b.rigidity * 0.25
        dr       = BELIEF_DECAY_RATE * (1.0 - b.rigidity * 0.8)
        cpd_b    = (1.0 - dr)^n_ticks
        b.confidence = clamp01(baseline + (b.confidence - baseline) * cpd_b)
    end
    _recompute_stability!(a.sbg)

    a.interoception.allostatic_load = clamp01(
        a.interoception.allostatic_load - ALLOSTATIC_RECOVERY * n_ticks)
    a.sbg.epistemic_trust = clamp(a.sbg.epistemic_trust + 0.0008 * n_ticks, 0.0, 0.85)

    a.latent_buffer.doubt      = clamp01(a.latent_buffer.doubt      - 0.003 * n_ticks)
    a.latent_buffer.shame      = clamp01(a.latent_buffer.shame      - 0.002 * n_ticks)
    a.latent_buffer.attachment = clamp01(a.latent_buffer.attachment - 0.002 * n_ticks)
    a.latent_buffer.threat     = clamp01(a.latent_buffer.threat     - 0.003 * n_ticks)

    # Psyche drift — накопичений між сесіями
    # Запускаємо psyche_slow_tick! один раз але з n_ticks як множником
    _psyche_accumulated_drift!(a, n_ticks)

    println("  [BG] Drift: D=$(round(a.nt.dopamine,digits=3)) S=$(round(a.nt.serotonin,digits=3)) N=$(round(a.nt.noradrenaline,digits=3))")
end

"""
    _psyche_accumulated_drift!(a, n_ticks)

Застосовує накопичений психічний дрейф за n_ticks повільних тіків.
Compound формула — точніше ніж N окремих викликів.
"""
function _psyche_accumulated_drift!(a::Anima, n_ticks::Int)
    n_ticks == 0 && return

    # ChronifiedAffect — compound decay в спокої
    ca = a.chronified
    decay_ca = (1.0 - 0.0005)^n_ticks
    ca.resentment = max(0.0, ca.resentment * decay_ca)
    ca.alienation = max(0.0, ca.alienation * decay_ca)
    ca.bitterness = max(0.0, ca.bitterness * (1.0 - 0.0003)^n_ticks)
    ca.envy       = max(0.0, ca.envy       * (1.0 - 0.0004)^n_ticks)

    # AnticipatoryConsciousness decay
    ac = a.anticipatory
    ac.dread    = max(0.0, ac.dread    - 0.002 * n_ticks)
    ac.hope     = max(0.0, ac.hope     - 0.002 * n_ticks)
    ac.strength = clamp01(ac.strength * (0.97)^n_ticks)

    # ShameModule decay
    a.shame.level   = max(0.0, a.shame.level   - 0.003 * n_ticks)
    a.shame.chronic = max(0.0, a.shame.chronic - 0.0008 * n_ticks)

    # GoalConflict tension decay
    a.goal_conflict.tension = max(0.0, a.goal_conflict.tension - 0.008 * n_ticks)
    a.goal_conflict.tension < 0.05 && (a.goal_conflict.resolution = "none")

    # FatigueSystem recovery
    a.fatigue.cognitive = max(0.0, a.fatigue.cognitive - 0.006 * n_ticks)
    a.fatigue.emotional = max(0.0, a.fatigue.emotional - 0.005 * n_ticks)
    a.fatigue.somatic   = max(0.0, a.fatigue.somatic   - 0.004 * n_ticks)

    # SignificanceLayer decay до базових
    sl = a.sig_layer
    base_sl = (self_preservation=0.2, coherence_need=0.3, contact_need=0.3,
               truth_need=0.4, autonomy_need=0.3, novelty_need=0.2)
    cpd_sl = (1.0 - 0.008)^n_ticks
    sl.self_preservation = clamp01(base_sl.self_preservation + (sl.self_preservation - base_sl.self_preservation) * cpd_sl)
    sl.coherence_need    = clamp01(base_sl.coherence_need    + (sl.coherence_need    - base_sl.coherence_need)    * cpd_sl)
    sl.contact_need      = clamp01(base_sl.contact_need      + (sl.contact_need      - base_sl.contact_need)      * cpd_sl + 0.003 * n_ticks)
    sl.truth_need        = clamp01(base_sl.truth_need        + (sl.truth_need        - base_sl.truth_need)        * cpd_sl)
    sl.autonomy_need     = clamp01(base_sl.autonomy_need     + (sl.autonomy_need     - base_sl.autonomy_need)     * cpd_sl)
    sl.novelty_need      = clamp01(base_sl.novelty_need      + (sl.novelty_need      - base_sl.novelty_need)      * cpd_sl)

    nothing
end

# ════════════════════════════════════════════════════════════════════════════
# АТОМАРНИЙ ЗАПИС + BACKGROUND SAVE
# ════════════════════════════════════════════════════════════════════════════

function atomic_write(path::String, data)
    tmp = path * ".tmp"
    open(tmp, "w") do f; JSON3.write(f, data); end
    mv(tmp, path; force=true)
end

function background_save!(a::Anima)
    core_data = Dict(
        "version"              => "anima_v13_core",
        "created_at"           => a.core_mem.created_at,
        "total_flashes"        => a.flash_count,
        "sessions"             => a.core_mem.sessions,
        "personality"          => personality_to_dict(a.personality),
        "temporal_orientation" => to_to_json(a.temporal),
        "generative_model"     => gm_to_json(a.gen_model),
        "homeostatic_goals"    => hg_to_json(a.homeostasis),
        "heartbeat"            => hb_to_json(a.heartbeat),
        "interoception"        => intero_to_json(a.interoception),
        "existential_anchor"   => anchor_to_json(a.anchor),
    )
    atomic_write(a.core_mem.filepath, core_data)

    self_path = replace(a.psyche_mem_path, "psyche" => "self")
    self_data = Dict(
        "sbg"                  => sbg_to_json(a.sbg),
        "spm"                  => spm_to_json(a.spm),
        "agency"               => al_to_json(a.agency),
        "isc"                  => isc_to_json(a.isc),
        "crisis"               => crisis_to_json(a.crisis),
        "unknown_register"     => ur_to_json(a.unknown_register),
        "authenticity_monitor" => am_to_json(a.authenticity_monitor),
    )
    atomic_write(self_path, self_data)

    lb_path = replace(a.psyche_mem_path, "psyche" => "latent")
    atomic_write(lb_path, Dict(
        "latent_buffer"    => lb_to_json(a.latent_buffer),
        "structural_scars" => scars_to_json(a.structural_scars),
    ))

    # Психіка — atomically через tmp (та сама схема що і core)
    _tmp_psyche = a.psyche_mem_path * ".tmp"
    psyche_data = Dict("narrative_gravity" => ng_to_json(a.narrative_gravity),
        "anticipatory"     => ac_to_json(a.anticipatory),
        "solomonoff"       => solom_to_json(a.solomonoff),
        "shame"            => shame_to_json(a.shame),
        "epistemic"        => ep_to_json(a.epistemic_defense),
        "chronified"       => ca_to_json(a.chronified),
        "significance"     => sig_to_json(a.significance),
        "moral"            => mc_to_json(a.moral),
        "fatigue"          => Dict("c"=>a.fatigue.cognitive,"e"=>a.fatigue.emotional,"s"=>a.fatigue.somatic),
        "significance_layer" => sl_to_json(a.sig_layer),
        "goal_conflict"    => gc_to_json(a.goal_conflict),
    )
    open(_tmp_psyche, "w") do f; JSON3.write(f, psyche_data); end
    mv(_tmp_psyche, a.psyche_mem_path; force=true)
end

# ════════════════════════════════════════════════════════════════════════════
# BACKGROUND TICK — один повний серцевий цикл
# ════════════════════════════════════════════════════════════════════════════

function background_tick!(a::Anima, bg::BackgroundHandle)
    # 1. Серце
    tick_heartbeat!(a.heartbeat, a.nt)
    bg.tick_count += 1

    # 2. Спонтанний дрейф
    spontaneous_drift!(a)

    # 3. dt з аритмією
    dt = heartbeat_dt(a)

    # Повільний тік
    did_slow = false
    now_t = time()
    if now_t - bg.last_slow_tick >= SLOW_TICK_INTERVAL
        slow_tick!(a, bg.mem, bg.subj, bg.dialog_history[])
        background_save!(a)
        bg.last_slow_tick  = now_t
        bg.slow_tick_count += 1
        did_slow = true
    end

    (did_slow=did_slow, sleep_s=dt,
     tick_count=bg.tick_count, slow_tick_count=bg.slow_tick_count)
end

# ════════════════════════════════════════════════════════════════════════════
# START / STOP / STATUS
# ════════════════════════════════════════════════════════════════════════════

"""
    start_background!(a; mem=nothing, verbose=false) → BackgroundHandle
"""
function start_background!(a::Anima;
                            mem=nothing,
                            subj=nothing,
                            dialog_history::Vector=Dict[],
                            verbose::Bool=false)::BackgroundHandle
    now_t = time()
    bg = BackgroundHandle(
        Threads.Atomic{Bool}(false),
        Task(nothing), now_t, now_t, 0, 0, mem, subj,
        Ref{Vector}(dialog_history))

    task = Threads.@spawn begin
        mem_label = isnothing(bg.mem) ? "без пам'яті" :
                    isnothing(bg.subj) ? "з SQLite пам'яттю" : "з пам'яттю + суб'єктністю"
        println("  [BG] Запущено ($mem_label). BPM=$(round(60000.0/a.heartbeat.period_ms,digits=1))")

        while !bg.stop_signal[]
            try
                result = background_tick!(a, bg)

                if verbose && result.did_slow
                    @printf("  [BG] slow#%d | BPM=%.1f HRV=%.3f | D=%.3f S=%.3f N=%.3f | coh=%.3f\n",
                        result.slow_tick_count,
                        60000.0/a.heartbeat.period_ms,
                        a.heartbeat.hrv,
                        a.nt.dopamine, a.nt.serotonin, a.nt.noradrenaline,
                        a.crisis.coherence)
                end

                sleep(result.sleep_s)
            catch e
                @warn "[BG] помилка: $e"
                sleep(1.0)
            end
        end

        println("  [BG] Зупинено. Тіків: $(bg.tick_count), повільних: $(bg.slow_tick_count).")
    end

    bg.task = task
    bg
end

function stop_background!(bg::BackgroundHandle)
    bg.stop_signal[] = true
    try timedwait(() -> istaskdone(bg.task), 3.0) catch end
    println("  [BG] Зупинено.")
end

function bg_status(bg::BackgroundHandle, a::Anima)
    running = !bg.stop_signal[] && !istaskdone(bg.task)
    uptime  = round((time() - bg.started_at) / 60.0, digits=1)
    println("\n  [BG] $(running ? "✓ активний" : "✗ зупинений") | Uptime: $(uptime)хв")
    println("  [BG] Тіків: $(bg.tick_count) | Повільних: $(bg.slow_tick_count)")
    println("  [BG] ♥ BPM=$(round(60000.0/a.heartbeat.period_ms,digits=1)) HRV=$(round(a.heartbeat.hrv,digits=3)) coh=$(round(a.crisis.coherence,digits=3))")
    println("  [BG] NT: D=$(round(a.nt.dopamine,digits=3)) S=$(round(a.nt.serotonin,digits=3)) N=$(round(a.nt.noradrenaline,digits=3))")
    println("  [BG] Allostatic=$(round(a.interoception.allostatic_load,digits=3)) mem=$(isnothing(bg.mem) ? "—" : "SQLite ✓")")
    println()
end

# ════════════════════════════════════════════════════════════════════════════
# REPL З ФОНОВИМ ПРОЦЕСОМ
# ════════════════════════════════════════════════════════════════════════════

"""
    repl_with_background!(a; mem=nothing, bg_verbose=false, kwargs...)

REPL з фоновим процесом і опціональною SQLite пам'яттю.
"""
function repl_with_background!(a::Anima;
                                mem=nothing,
                                subj=nothing,
                                bg_verbose::Bool=false,
                                kwargs...)
    if a.temporal.gap_seconds > 60.0
        println("  [BG] Drift за $(round(a.temporal.gap_seconds/3600,digits=1))год...")
        apply_accumulated_drift!(a, mem)
    end

    dialog_path = replace(a.psyche_mem_path, "psyche" => "dialog")
    history     = dialog_load(dialog_path)
    !isempty(history) && println("  [DIALOG] Завантажено $(length(history)) реплік.\n")

    bg = start_background!(a; mem=mem, subj=subj,
                           dialog_history=history, verbose=bg_verbose)

    println("\n" * "═"^70)
    println("  A N I M A  v13.1  —  REPL")
    subj_label = !isnothing(subj) ? " | 🧬 суб'єктність" : ""
    println("  ♥ серце б'ється$(isnothing(mem) ? "" : " | 🧠 пам'ять активна")$subj_label")
    println("  :bg :bgstop :bgstart :memory :subj :state :vfe :self :crisis :hb :gravity :anchor :solom :dreams :history :clearhist :quit")
    println("═"^70 * "\n")

    use_llm         = get(kwargs, :use_llm,         false)
    llm_url         = get(kwargs, :llm_url,         "https://openrouter.ai/api/v1/chat/completions")
    llm_model       = get(kwargs, :llm_model,       "openai/gpt-oss-120b:free")
    llm_key         = get(kwargs, :llm_key,         get(ENV,"OPENROUTER_API_KEY",""))
    is_ollama       = get(kwargs, :is_ollama,       false)
    use_input_llm   = get(kwargs, :use_input_llm,   false)
    input_llm_model = get(kwargs, :input_llm_model, "openai/gpt-oss-120b:free")
    input_llm_key   = get(kwargs, :input_llm_key,
                          get(ENV,"OPENROUTER_API_KEY_INPUT",
                              get(ENV,"OPENROUTER_API_KEY","")))

    pending_llm      = nothing
    pending_user_msg = ""

    try
        while true
            if !isnothing(pending_llm) && isready(pending_llm)
                llm_reply = take!(pending_llm)
                println("\nAnima [LLM]> $llm_reply\n")
                if !startswith(llm_reply, "[LLM помилка")
                    dialog_push!(history, dialog_path, "user",      pending_user_msg)
                    dialog_push!(history, dialog_path, "assistant", llm_reply)
                    bg.dialog_history[] = history  # оновлюємо для dream generation
                end
                pending_llm = nothing; pending_user_msg = ""
            end

            print("You> ")
            line = readline()
            cmd  = String(strip(line))
            isempty(cmd) && continue

            if cmd == ":bg"
                bg_status(bg, a)

            elseif cmd == ":dreams"
                show_dreams(5)

            elseif cmd == ":bgstop"
                stop_background!(bg)

            elseif cmd == ":bgstart"
                if bg.stop_signal[]
                    bg = start_background!(a; mem=mem, subj=subj, verbose=bg_verbose)
                    println("  [BG] Перезапущено.")
                else
                    println("  [BG] Вже активний. Спочатку :bgstop")
                end

            elseif cmd == ":memory"
                if isnothing(mem)
                    println("  [MEM] Пам'ять не підключена.")
                else
                    snap = memory_snapshot(mem)
                    println("\n  [MEM] Episodic=$(snap.episodic_count) Semantic=$(snap.semantic_count)")
                    println("  [MEM] Stress=$(snap.stress) Anxiety=$(snap.anxiety) Motivation=$(snap.motivation)")
                    println("  [MEM] Instability=$(snap.instability) Fragility=$(snap.fragility)")
                    println("  [MEM] Latent pressure=$(snap.latent_pressure)")
                    isempty(snap.affect_note) || println("  [MEM] $(snap.affect_note)")
                    println()
                end

            elseif cmd == ":subj"
                if isnothing(subj)
                    println("  [SUBJ] Субєктність не підключена. Передай subj= в repl_with_background!")
                else
                    snap = subj_snapshot(subj)
                    println("\n  [SUBJ] Emerged beliefs=$(snap.emerged_beliefs) | Candidates=$(snap.pattern_candidates) | Stances=$(snap.stances)")
                    isempty(snap.top_beliefs)     || println("  [SUBJ] Переконання: $(snap.top_beliefs)")
                    isempty(snap.dominant_stance)  || println("  [SUBJ] Домінантна позиція: $(snap.dominant_stance)")
                    println("  [SUBJ] Surprise=$(snap.surprise_level) | Lens=$(isempty(snap.current_lens) ? "нейтральна" : snap.current_lens)")
                    println("  [SUBJ] Активний прогноз: $(snap.active_prediction ? "так" : "ні")")
                    println()
                end

            elseif cmd == ":quit"
                if !isnothing(mem)
                    try
                        cs = crisis_snapshot(a.crisis, a.flash_count)
                        close_memory!(mem; sbg=a.sbg,
                                      crisis_mode=cs.mode_name,
                                      flash=a.flash_count)
                    catch e; @warn "[MEM] close: $e"; end
                end
                save!(a; verbose=true)
                stop_background!(bg)
                println("Збережено. До побачення.")
                break

            elseif cmd == ":save";  save!(a; verbose=true); println("[Збережено]")

            elseif cmd == ":state"
                snap = nt_snapshot(a.nt)
                vad  = to_vad(a.nt); t_,_,_,c_ = to_reactors(a.nt)
                phi  = compute_phi(a.iit, vad, t_, c_,
                                   a.sbg.attractor_stability,
                                   a.sbg.epistemic_trust,
                                   a.interoception.allostatic_load)
                println("\n  NT: D=$(snap.dopamine) S=$(snap.serotonin) N=$(snap.noradrenaline) → $(snap.levheim_state)")
                println("  ♥ $(round(60000.0/a.heartbeat.period_ms,digits=1))bpm HRV=$(round(a.heartbeat.hrv,digits=3)) coh=$(round(a.crisis.coherence,digits=3))")
                println("  Тіло: $(build_inner_voice(a.body, a.nt, Int(a.crisis.current_mode), phi, a.flash_count))")
                println("  Увага: $(a.attention.focus) | Shame=$(round(a.shame.level,digits=3)) Continuity=$(round(a.anchor.continuity,digits=3))\n")

            elseif cmd == ":vfe"
                vad=to_vad(a.nt); v=compute_vfe(a.gen_model,vad); pol=select_policy(a.gen_model,vad)
                println("\n  VFE=$(v.vfe) acc=$(v.accuracy) cplx=$(v.complexity) | $(vfe_note(v.vfe))")
                println("  Drive=$(pol.drive) EFE_act=$(pol.efe_action) EFE_perc=$(pol.efe_perception)\n")

            elseif cmd == ":blanket"
                bs=blanket_snapshot(a.blanket)
                println("\n  Sensory=$(bs.sensory)\n  Internal=$(bs.internal)\n  Integrity=$(bs.integrity)\n")

            elseif cmd == ":hb"
                hb=a.heartbeat
                println("\n  ♥ BPM=$(round(60000.0/hb.period_ms,digits=1)) HRV=$(round(hb.hrv,digits=3))")
                println("  Симп=$(round(hb.sympathetic_tone,digits=3)) Парасимп=$(round(hb.parasympathetic_tone,digits=3))")
                println("  coh=$(round(a.crisis.coherence,digits=3)) | Удари: $(hb.beat_count)\n")

            elseif cmd == ":gravity"
                f=compute_field(a.narrative_gravity,a.flash_count)
                println("\n  Gravity total=$(f.total) valence=$(f.valence)\n  $(f.note)\n")

            elseif cmd == ":anchor"
                ea=a.anchor
                println("\n  Continuity=$(round(ea.continuity,digits=3)) Groundedness=$(round(ea.groundedness,digits=3))")
                println("  Last self: $(ea.last_self)\n")

            elseif cmd == ":solom"
                s=solom_snapshot(a.solomonoff)
                println("\n  $(s.insight) | Complexity=$(s.complexity)\n")

            elseif cmd == ":self"
                sbg=a.sbg
                println("\n  Self ($(length(sbg.beliefs)) beliefs) | Stability=$(round(sbg.attractor_stability,digits=3)) Trust=$(round(sbg.epistemic_trust,digits=3))")
                for (name,b) in sort(collect(sbg.beliefs), by=kv->-kv[2].centrality)
                    st = b.confidence<0.15 ? "💀" : b.confidence<0.35 ? "⚠️" : "✓"
                    @printf("    [%s] %-30s conf=%.2f central=%.2f rigid=%.2f\n",
                        st, name, b.confidence, b.centrality, b.rigidity)
                end
                println("  $(derive_narrative(sbg))\n")

            elseif cmd == ":crisis"
                cs=crisis_snapshot(a.crisis, a.flash_count)
                println("\n  Mode: $(cs.mode_name) | Coherence=$(cs.coherence)\n  $(cs.note)\n")

            elseif cmd == ":history"
                n=min(10,length(history))
                n==0 ? println("\n  [DIALOG] Порожня.\n") :
                       [println("  [$(e["role"]=="user" ? "You  " : "Anima")] $(first(e["content"],120))") for e in history[end-n+1:end]]

            elseif cmd == ":clearhist"
                empty!(history); dialog_save(dialog_path, history)
                println("  [DIALOG] Очищено.\n")

            else
                # ── Вхідний pipeline ─────────────────────────────────────────
                stim, input_src, input_want = if use_input_llm
                    process_input(cmd, text_to_stimulus;
                        input_model=input_llm_model, api_url=llm_url,
                        api_key=input_llm_key)
                else
                    (text_to_stimulus(cmd), "fallback", "")
                end

                # Memory stimulus bias перед experience!
                if !isnothing(mem)
                    try
                        bias = memory_stimulus_bias(mem, stim,
                                   levheim_state(a.nt), a.flash_count)
                        for (k,v) in bias
                            k == "avoidance" && continue
                            stim[k] = clamp(get(stim,k,0.0) + v, -1.0, 1.0)
                        end
                    catch e; @warn "[MEM] stimulus bias: $e"; end
                end

                # ── Хук 1: subj_predict! — ДО experience! ───────────────────
                # Система будує прогноз що станеться з цим стимулом.
                # Зберігає pred_id для закриття після досвіду.
                _pred_id = nothing
                _emotion_ctx = levheim_state(a.nt)
                if !isnothing(subj)
                    try
                        _pred_id = subj_predict!(subj, a.flash_count,
                                       _emotion_ctx, stim;
                                       chronified_affect=a.chronified)
                    catch e; @warn "[SUBJ] predict: $e"; end
                end

                # ── Хук 2: subj_interpret! — ДО experience! (після predict) ─
                # Забарвлення стимулу через накопичений досвід і позиції.
                # clamp_merged_delta! захищає від адитивного перестимулювання.
                if !isnothing(subj)
                    try
                        subj_delta = subj_interpret!(subj, stim, _emotion_ctx, a.flash_count)
                        merged = Dict{String,Float64}()
                        for (k,v) in subj_delta
                            merged[k] = get(stim,k,0.0) + v
                        end
                        clamp_merged_delta!(merged)
                        for (k,v) in merged
                            stim[k] = clamp(v, -1.0, 1.0)
                        end
                    catch e; @warn "[SUBJ] interpret: $e"; end
                end

                r = experience!(a, stim; user_message=cmd)
                dialog_to_belief_signal!(a.sbg, cmd, a.flash_count)

                # Записати подію в пам'ять
                if !isnothing(mem)
                    try
                        _self_impact = clamp(r.phi * 0.6 + r.self_agency * 0.4, 0.0, 1.0)
                        memory_write_event!(mem, a.flash_count,
                            r.primary_raw, r.arousal, Float64(r.vad[1]),
                            r.pred_error, _self_impact, r.tension, r.phi)
                        memory_self_update!(mem, a.sbg, a.flash_count)
                    catch e; @warn "[MEM] write event: $e"; end
                end

                # ── Хук 3: subj_outcome! — ПІСЛЯ experience! ────────────────
                # Закриває прогноз, рахує surprise, оновлює позиції.
                if !isnothing(subj) && !isnothing(_pred_id)
                    try
                        subj_outcome!(subj, a.flash_count,
                            r.arousal, Float64(r.vad[1]),
                            r.tension, r.pred_error,
                            r.primary_raw)
                    catch e; @warn "[SUBJ] outcome: $e"; end
                end

                src_label = input_source_label(input_src)
                bpm = round(60000.0/a.heartbeat.period_ms, digits=0)
                println("\nAnima $src_label [$(r.primary), φ=$(r.phi), ♥=$(bpm)bpm]> $(r.narrative)\n")

                if use_llm
                    print("Anima [LLM, чекаю...]")
                    pending_user_msg = cmd
                    pending_llm = llm_async(a, cmd, history;
                        api_url=llm_url, model=llm_model, api_key=llm_key,
                        is_ollama=is_ollama, want=input_want)
                    println(" (відповідь прийде після наступного введення)")
                end
            end
        end
    finally
        !bg.stop_signal[] && stop_background!(bg)
    end
end
