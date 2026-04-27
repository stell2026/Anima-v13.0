#=
╔══════════════════════════════════════════════════════════════════════════════╗
║                    A N I M A  —  Interface  (Julia)                          ║
║                                                                              ║
║  Тут все що показує стан — жодного side effect на психіку.                   ║
║                                                                              ║
║  Anima               — головна структура + experience! loop                  ║
║  build_narrative      — внутрішній голос з поточного стану                   ║
║  log_flash            — термінальний дебаг-рядок                             ║
║  llm_call             — асинхронний виклик LLM (не блокує психіку)           ║
║  text_to_stimulus     — текст → стимул без LLM                               ║
║  repl!                — інтерактивний REPL                                   ║
╚══════════════════════════════════════════════════════════════════════════════╝
=#

using HTTP
using JSON3
using Printf
using LinearAlgebra

# Підключаємо всі шари — порядок важливий
# @__DIR__ на верхньому рівні файлу завжди вказує на директорію цього файлу
include(joinpath(@__DIR__, "anima_core.jl"))
include(joinpath(@__DIR__, "anima_psyche.jl"))
include(joinpath(@__DIR__, "anima_self.jl"))
include(joinpath(@__DIR__, "anima_crisis.jl"))

# anima_input_llm.jl необов'язковий — якщо відсутній, fallback на text_to_stimulus
let _input_llm_path = joinpath(@__DIR__, "anima_input_llm.jl")
    if isfile(_input_llm_path)
        include(_input_llm_path)
    else
        @warn "anima_input_llm.jl не знайдено — використовується text_to_stimulus fallback (use_input_llm буде ігноруватись)"
        # Stub-функції щоб repl! не падав при use_input_llm=true
        process_input(text::String, fallback_fn; kwargs...) = (fallback_fn(text), "fallback", "")
        input_source_label(src::String) = src == "fallback" ? "[rule]" : "[llm]"
    end
end

# ════════════════════════════════════════════════════════════════════════════
# AUTHENTICITY MONITOR (phase 5)
#
# Система сама оцінює наскільки відповідь відповідає стану.
# Залежить від: phi, crisis_mode, GoalConflict (фаза 2), LatentBuffer (фаза 3).
#
# Принцип:
#   Довга відповідь при низькому phi + DISINTEGRATED → coherence_overreach.
#   Theater-words без підтримки в стані → fabrication_risk.
#   fabrication_risk передається в наступний state_template — self-correcting loop.
#   AuthenticityMonitor ФІКСУЄ — але не виправляє.
#   Виправлення було б брехнею.
# ════════════════════════════════════════════════════════════════════════════

mutable struct AuthenticityMonitor
    authenticity_drift::Float64   # наскільки відповідь дрейфує від стану
    fabrication_risk::Float64     # ризик що система "виробляє" а не "відчуває"
    narrative_overreach::Float64  # наратив виходить за межі реального стану
    last_flags::Vector{String}    # що саме спрацювало в останньому флеші
end
AuthenticityMonitor() = AuthenticityMonitor(0.0, 0.0, 0.0, String[])

"""
    check_authenticity!(am, phi, crisis_mode, gc_snap, lb_snap, ur_snap,
                         coherence, epistemic_trust, response_length)

Оновлює AuthenticityMonitor на основі поточного стану.
Повертає (fabrication_risk, flags, note) для state_template наступного флешу.

response_length — довжина narrative рядка (приблизна міра наскільки "багато" сказано).
"""
function check_authenticity!(am::AuthenticityMonitor,
                              phi::Float64,
                              crisis_mode::String,
                              gc_snap,
                              lb_snap,
                              ur_snap,
                              coherence::Float64,
                              epistemic_trust::Float64,
                              response_length::Int)

    flags = String[]
    am.last_flags = String[]

    # ── Евристика 1: coherence_overreach ─────────────────────────────────
    is_disintegrated = crisis_mode == "дезінтегрована"
    long_response    = response_length > 120
    low_phi          = phi < 0.25

    if is_disintegrated && low_phi && long_response
        am.narrative_overreach = clamp01(am.narrative_overreach + 0.15)
        push!(flags, "coherence_overreach")
    else
        am.narrative_overreach = clamp01(am.narrative_overreach - 0.04)
    end

    # ── Евристика 2: fabrication_risk ────────────────────────────────────
    conflict_unresolved = gc_snap.active && gc_snap.resolution == "unresolved"
    latent_breakthrough = lb_snap.breakthrough
    low_coherence       = coherence < 0.35

    fabrication_signal = 0.0
    conflict_unresolved && (fabrication_signal += 0.2)
    latent_breakthrough && (fabrication_signal += 0.15)
    low_coherence       && (fabrication_signal += 0.1)
    epistemic_trust < 0.4 && (fabrication_signal += 0.15)

    am.fabrication_risk = clamp01(am.fabrication_risk * 0.75 + fabrication_signal * 0.25)
    am.fabrication_risk > 0.45 && push!(flags, "fabrication_risk")

    # ── Евристика 3: authenticity_drift ──────────────────────────────────
    unknown_high = ur_snap.dominant_val > 0.5
    unknown_high && long_response &&
        (am.authenticity_drift = clamp01(am.authenticity_drift + 0.12))
    !unknown_high &&
        (am.authenticity_drift = clamp01(am.authenticity_drift - 0.03))
    am.authenticity_drift > 0.4 && push!(flags, "authenticity_drift")

    # ── Евристика 4: state_narrative_mismatch ────────────────────────────
    # Якщо phi > 0.6 і etrust > 0.6 але named = негативний стан — розрив.
    # Якщо phi < 0.3 і etrust < 0.4 але narrative каже "спокій" — теж розрив.
    # Це саме та ситуація: Довіра + phi=0.82 + "не можу собі довіряти".
    high_integration = phi > 0.6 && epistemic_trust > 0.6
    negative_state   = crisis_mode ∈ ("дезінтегрована", "фрагментована") &&
                       coherence < 0.45
    if high_integration && !negative_state && am.fabrication_risk < 0.3
        # Система стабільна — знижуємо drift якщо він накопичився
        am.authenticity_drift = max(0.0, am.authenticity_drift - 0.05)
    elseif !high_integration && coherence < 0.35
        # Система нестабільна але може говорити більше ніж відчуває
        am.authenticity_drift = clamp01(am.authenticity_drift + 0.08)
        push!(flags, "state_narrative_mismatch")
    end

    am.last_flags = flags

    note = if am.fabrication_risk > 0.55
        "увага: висока імовірність раціоналізації ($(round(am.fabrication_risk,digits=2)))"
    elseif am.narrative_overreach > 0.5
        "увага: наратив ширший за реальний стан"
    elseif am.authenticity_drift > 0.45
        "увага: відповідь впевненіша ніж є підстави"
    else
        ""
    end

    (
        fabrication_risk   = round(am.fabrication_risk,    digits=3),
        narrative_overreach= round(am.narrative_overreach, digits=3),
        authenticity_drift = round(am.authenticity_drift,  digits=3),
        flags              = flags,
        note               = note,
    )
end

am_to_json(am::AuthenticityMonitor) = Dict(
    "authenticity_drift"  => am.authenticity_drift,
    "fabrication_risk"    => am.fabrication_risk,
    "narrative_overreach" => am.narrative_overreach,
)
function am_from_json!(am::AuthenticityMonitor, d::AbstractDict)
    am.authenticity_drift  = Float64(get(d, "authenticity_drift",  0.0))
    am.fabrication_risk    = Float64(get(d, "fabrication_risk",    0.0))
    am.narrative_overreach = Float64(get(d, "narrative_overreach", 0.0))
end

# ════════════════════════════════════════════════════════════════════════════
# ANIMA — головна структура
# ════════════════════════════════════════════════════════════════════════════

mutable struct Anima
    # Core
    personality::Personality
    values::ValueSystem
    nt::NeurotransmitterState
    body::EmbodiedState
    heartbeat::HeartbeatCore
    gen_model::GenerativeModel
    blanket::MarkovBlanket
    homeostasis::HomeostaticGoals
    attention::AttentionNarrowing
    interoception::InteroceptiveInference
    temporal::TemporalOrientation
    anchor::ExistentialAnchor
    iit::IITModule
    predictor::PredictiveProcessor
    emotion_map::AdaptiveEmotionMap
    memory::AssociativeMemory
    core_mem::CoreMemory
    # Psyche
    narrative_gravity::NarrativeGravity
    anticipatory::AnticipatoryConsciousness
    solomonoff::SolomonoffWorldModel
    shame::ShameModule
    epistemic_defense::EpistemicDefense
    symptomogenesis::Symptomogenesis
    shadow::ShadowSelf
    chronified::ChronifiedAffect
    significance::IntrinsicSignificance
    moral::MoralCausality
    intent_engine::IntentEngine
    fatigue::FatigueSystem
    regression::StressRegression
    metacognition::Metacognition
    # SignificanceLayer (phase 1)
    sig_layer::SignificanceLayer
    # GoalConflict (phase 2)
    goal_conflict::GoalConflict
    # LatentBuffer + StructuralScars (phase 3)
    latent_buffer::LatentBuffer
    structural_scars::StructuralScars
    # UnknownRegister (phase 4)
    unknown_register::UnknownRegister
    # AuthenticityMonitor (phase 5)
    authenticity_monitor::AuthenticityMonitor
    # InnerDialogue (phase C)
    inner_dialogue::InnerDialogue
    # ShadowRegistry (phase C2)
    shadow_registry::ShadowRegistry
    # Self (anima_self.jl)
    sbg::SelfBeliefGraph
    spm::SelfPredictiveModel
    agency::AgencyLoop
    isc::InterSessionConflict
    # Crisis (anima_crisis.jl)
    crisis::CrisisMonitor
    # State
    flash_count::Int
    psyche_mem_path::String
end

function Anima(; personality=Personality(), values=ValueSystem(),
                 core_mem_path=joinpath(@__DIR__, "anima_core.json"),
                 psyche_mem_path=joinpath(@__DIR__, "anima_psyche.json"))
    a = Anima(
        personality, values,
        NeurotransmitterState(), EmbodiedState(), HeartbeatCore(),
        GenerativeModel(), MarkovBlanket(), HomeostaticGoals(),
        AttentionNarrowing(), InteroceptiveInference(), TemporalOrientation(),
        ExistentialAnchor(), IITModule(), PredictiveProcessor(),
        AdaptiveEmotionMap(), AssociativeMemory(), CoreMemory(core_mem_path),
        NarrativeGravity(), AnticipatoryConsciousness(), SolomonoffWorldModel(),
        ShameModule(), EpistemicDefense(), Symptomogenesis(), ShadowSelf(),
        ChronifiedAffect(), IntrinsicSignificance(), MoralCausality(),
        IntentEngine(), FatigueSystem(), StressRegression(), Metacognition(),
        SignificanceLayer(), GoalConflict(), LatentBuffer(), StructuralScars(),
        UnknownRegister(), AuthenticityMonitor(), InnerDialogue(), ShadowRegistry(),
        SelfBeliefGraph(), SelfPredictiveModel(), AgencyLoop(), InterSessionConflict(),
        CrisisMonitor(),
        0, psyche_mem_path)
    # Завантажити
    saved = core_load!(a.core_mem, a.personality, a.temporal, a.gen_model,
                       a.homeostasis, a.heartbeat, a.interoception, a.anchor)
    psyche_load!(a.psyche_mem_path, a.narrative_gravity, a.anticipatory,
                 a.solomonoff, a.shame, a.epistemic_defense, a.chronified,
                 a.significance, a.moral, a.fatigue, a.sig_layer, a.goal_conflict,
                 a.latent_buffer, a.structural_scars,
                 a.shadow_registry, a.inner_dialogue)
    a.flash_count = saved
    # FIX #1: завантажити self/crisis стан (sbg, spm, agency, isc, crisis)
    # Раніше цей файл зберігався але ніколи не читався — self-модель скидалась кожну сесію.
    _self_path = replace(psyche_mem_path, "psyche" => "self")
    if isfile(_self_path)
        try
            _raw = JSON3.read(read(_self_path, String))
            _d   = Dict{String,Any}(String(k)=>v for (k,v) in _raw)
            haskey(_d,"sbg")                  && sbg_from_json!(a.sbg,                  _d["sbg"])
            haskey(_d,"spm")                  && spm_from_json!(a.spm,                  _d["spm"])
            haskey(_d,"agency")               && al_from_json!(a.agency,                _d["agency"])
            haskey(_d,"isc")                  && isc_from_json!(a.isc,                  _d["isc"])
            haskey(_d,"crisis")               && crisis_from_json!(a.crisis,            _d["crisis"])
            haskey(_d,"unknown_register")     && ur_from_json!(a.unknown_register,      _d["unknown_register"])
            haskey(_d,"authenticity_monitor") && am_from_json!(a.authenticity_monitor,  _d["authenticity_monitor"])
            println("  [SELF] Завантажено. Beliefs: $(length(a.sbg.beliefs)).")
        catch e
            println("  [SELF] Помилка завантаження: $e")
        end
    end
    # Завантаження anima_latent.json (фаза B — latent_buffer і structural_scars
    # зберігаються фоновим процесом окремо для уникнення конкурентного запису)
    _latent_path = replace(psyche_mem_path, "psyche" => "latent")
    if isfile(_latent_path)
        try
            _raw = JSON3.read(read(_latent_path, String))
            _d   = Dict{String,Any}(String(k)=>v for (k,v) in _raw)
            haskey(_d,"latent_buffer")    && lb_from_json!(a.latent_buffer,    _d["latent_buffer"])
            haskey(_d,"structural_scars") && scars_from_json!(a.structural_scars, _d["structural_scars"])
            println("  [BG] Latent стан завантажено.")
        catch e
            println("  [BG] Latent завантаження: $e")
        end
    end
    init_session!(a.temporal)
    apply_to_nt!(a.temporal, a.nt)
    # FIX #4: check_session_conflict тепер викликається ПІСЛЯ завантаження self.json,
    # щоб порівнювати реальну минулу геометрію, а не порожній свіжий граф.
    current_geom = belief_geometry(a.sbg)
    isc_result = check_session_conflict!(a.isc, current_geom)
    if isc_result.rupture
        println("  [SELF] Identity Rupture detected: $(isc_result.note)")
    elseif !isempty(isc_result.note)
        println("  [SELF] $(isc_result.note)")
    end
    a
end

function save!(a::Anima; summary="", verbose=false)
    core_save!(a.core_mem, a.personality, a.temporal, a.gen_model,
               a.homeostasis, a.heartbeat, a.interoception, a.anchor, a.flash_count)
    psyche_save!(a.psyche_mem_path, a.narrative_gravity, a.anticipatory,
                 a.solomonoff, a.shame, a.epistemic_defense, a.chronified,
                 a.significance, a.moral, a.fatigue, a.sig_layer, a.goal_conflict,
                 a.latent_buffer, a.structural_scars,
                 a.shadow_registry, a.inner_dialogue)
    # Save self/crisis state
    self_path = replace(a.psyche_mem_path, "psyche" => "self")
    self_data = Dict("sbg"=>sbg_to_json(a.sbg),"spm"=>spm_to_json(a.spm),
                     "agency"=>al_to_json(a.agency),"isc"=>isc_to_json(a.isc),
                     "crisis"=>crisis_to_json(a.crisis),
                     "unknown_register"=>ur_to_json(a.unknown_register),
                     "authenticity_monitor"=>am_to_json(a.authenticity_monitor))
    open(self_path,"w") do f; JSON3.write(f,self_data); end
    # Save geometry for inter-session conflict
    save_session_geometry!(a.isc, belief_geometry(a.sbg))
    verbose && println("  [ANIMA] Збережено. Спалахів: $(a.flash_count).")
end

# ════════════════════════════════════════════════════════════════════════════
# EXPERIENCE! — один крок психіки
# ════════════════════════════════════════════════════════════════════════════

function experience!(a::Anima, stimulus_raw::Dict{String,Float64};
                     user_message::String="")

    a.flash_count += 1
    stim = copy(stimulus_raw)

    # Social mirror → adjust stimulus
    if !isempty(user_message)
        for (k,v) in social_delta(user_message)
            stim[k] = get(stim,k,0.0) + v*0.15
        end
    end

    # Memory resonance
    mem_d = resonance_delta(a.memory, stim)
    combined = Dict(k=>get(stim,k,0.0)+get(mem_d,k,0.0)
                    for k in union(keys(stim),keys(mem_d)))

    # NT + body
    apply_stimulus!(a.nt, combined)
    decay_to_baseline!(a.nt, decay_rate(a.personality))
    update_from_nt!(a.body, a.nt)

    # Heartbeat
    hb_snap = tick_heartbeat!(a.heartbeat, a.nt)

    # VAD
    vad = to_vad(a.nt)
    t, a_r, s, c = to_reactors(a.nt)

    # Attention narrowing
    attn_snap = update_attention!(a.attention, a.nt, t)
    # Фільтрація всього stimulus пропорційно до attention radius.
    # Логіка: вузька увага = фокус на загрозі, ігнорування позитивного.
    #   • Некритичні позитивні сигнали (satisfaction>0, cohesion>0) → послаблені
    #   • Загрозливі сигнали (tension>0, негативні) → підсилені через threat_amplifier
    #   • При radius=1.0 — жодних змін (широка відкрита увага)
    if attn_snap.radius < 0.99
        r   = attn_snap.radius
        amp = Float64(attn_snap.threat_amplifier)   # 1.0..1.5
        for k in keys(stim)
            v = stim[k]
            if k in ("satisfaction","cohesion") && v > 0.0
                # Позитивні некритичні — послаблюємо пропорційно
                stim[k] = v * r
            elseif k == "tension" && v > 0.0
                # Загроза — підсилюємо (але не вище 1.0)
                stim[k] = clamp(v * amp, -1.0, 1.0)
            elseif k == "arousal" && v > 0.0
                # Збудження — помірне підсилення
                stim[k] = clamp(v * (1.0 + (1.0-r)*0.3), -1.0, 1.0)
            end
            # Від'ємні satisfaction/cohesion (втрата зв'язку, незадоволення)
            # теж підсилюємо — під стресом ми гостріше відчуваємо відсутність
            if k in ("satisfaction","cohesion") && v < 0.0
                stim[k] = clamp(v * amp, -1.0, 1.0)
            end
        end
    end

    # Emotions
    emotions   = identify(a.emotion_map, vad)
    primary    = emotions[1].name
    named      = plutchik_name(primary)
    intensity  = emotions[1].intensity
    learn!(a.emotion_map, primary, vad)
    decay_toward_base!(a.emotion_map)

    # IIT φ_prior — prior beliefs про себе ДО повного досвіду
    phi_prior = compute_phi(a.iit, vad, t, c,
                            a.sbg.attractor_stability,
                            a.sbg.epistemic_trust,
                            a.interoception.allostatic_load)
    phi = phi_prior  # alias для ранніх модулів

    # Predictive
    pred = update_predictor!(a.predictor, vad, surprise_sensitivity(a.personality))
    pred.spike && (a.nt.noradrenaline = clamp01(a.nt.noradrenaline + 0.08))

    # Fatigue + Regression
    stype = classify_stimulus(stim, pred.spike)
    update_fatigue!(a.fatigue, stype, pred.error, pred.spike)
    fat   = fatigue_total(a.fatigue)
    update_regression!(a.regression, t, fat)

    # Intent
    drives = Dict("tension"=>abs(t-0.5),"arousal"=>abs(a_r-0.5),
                  "satisfaction"=>abs(s-0.5),"cohesion"=>abs(c-0.5))
    _best_drive = argmax(drives)
    dom_drive::Union{String,Nothing} = drives[_best_drive] >= 0.15 ? _best_drive : nothing
    id_stability = phi / (1.0+t)
    intent = update_intent!(a.intent_engine, dom_drive, named, id_stability, a.values)

    # Dissonance + Defense
    diss    = compute_dissonance(intent, t, a_r, s, c)
    t_adj   = diss.level>0.3 ? clamp01(t + diss.level*0.1) : t
    defense = activate_defense(t_adj, a_r, s, c, a.personality.confabulation_rate)
    t_adj   = !isnothing(defense) ? max(0.0, t_adj - defense.tension_relief) : t_adj
    shadow_push!(a.shadow, named, !isnothing(defense))

    # Shame + Epistemic
    update_shame!(a.shame, named, pred.error, diss.level, a.moral.agency, id_stability)
    ep_def = activate_epistemic!(a.epistemic_defense, diss.level,
                                  a.shame.level, fat, a.moral.agency)

    # Symptom (affect на reactors)
    symptom  = generate_symptom!(a.symptomogenesis, a.shadow.content, defense)
    sym_fx   = symptom_reactor_delta(symptom)  # (dt, da, ds, dc)
    t_adj    = clamp01(t_adj + sym_fx[1]); s_adj = clamp01(s + sym_fx[3])
    c_adj    = clamp01(c + sym_fx[4])

    # Chronified
    update_chronified!(a.chronified, s_adj, c_adj, t_adj, a.moral.agency)

    # Significance (IntrinsicSignificance — скільки)
    update_significance!(a.significance, named, intensity, phi, a.flash_count)

    # Moral
    update_moral!(a.moral, named, isnothing(intent) ? "drive" : intent.origin,
                  diss.level, a.values.integrity)

    # ── Active Inference Core ────────────────────────────────────────────
    update_precision!(a.gen_model, pred.error, fat)
    posterior = update_beliefs!(a.gen_model, vad)
    # FIX A: запобігти collapse prior→posterior (VFE=0.00 назавжди)
    prevent_prior_collapse!(a.gen_model)
    vfe_r     = compute_vfe(a.gen_model, vad)

    # SignificanceLayer (phase 1) — якого типу потреба зараз
    # Розміщено після vfe_r — потребує vfe_r.vfe
    sl_snap = assess_significance!(a.sig_layer, stim, t_adj, a_r, s_adj, c_adj,
                                   vfe_r.vfe, pred.error, phi)

    # GoalConflict (phase 2) — що конфліктує між потребами
    # sl_snap вже містить актуальні значення всіх потреб
    gc_snap = update_goal_conflict!(a.goal_conflict, sl_snap,
                                    t_adj, s_adj, c_adj, phi, a.flash_count)

    # LatentBuffer + StructuralScars (phase 3) — відкладені реакції і шрами
    lb_snap = update_latent!(a.latent_buffer, gc_snap,
                              t_adj, c_adj, s_adj, a.shame.level, a.flash_count)
    # Прорив: реєструємо шрам і застосовуємо delta до NT (з послабленням від шраму)
    if lb_snap.breakthrough
        _ = register_breakthrough!(a.structural_scars, lb_snap.breakthrough_type,
                                          a.flash_count)
        decay_scars!(a.structural_scars)
        # Шрам послаблює прорив — система вчиться блокувати болючі теми
        attenuation = 1.0 - scar_attenuation(a.structural_scars, lb_snap.breakthrough_type)
        for (k, v) in lb_snap.delta
            apply_stimulus!(a.nt, Dict{String,Float64}(k => v * attenuation))
        end
        # Перераховуємо реактори після прориву
        t_adj = clamp01(to_reactors(a.nt)[1])
        s_adj = clamp01(to_reactors(a.nt)[3])
        c_adj = clamp01(to_reactors(a.nt)[4])
    else
        decay_scars!(a.structural_scars)
    end

    policy    = select_policy(a.gen_model, vad)
    update_blanket!(a.blanket, t_adj, a_r, s_adj, c_adj)
    homeo_snap= update_homeostasis!(a.homeostasis, vad)

    # [B3] Interoception
    intero_snap = update_interoception!(a.interoception, a.body, a.gen_model.prior_mu)

    # ── φ_posterior — ПІСЛЯ VFE і interoception ──────────────────────────
    phi_posterior = compute_phi_posterior(a.iit, vad,
                                          a.sbg.epistemic_trust,
                                          a.blanket.integrity,
                                          vfe_r.vfe,
                                          Float64(intero_snap.intero_error))
    phi = phi_posterior  # решта pipeline використовує posterior

    # φ feedback loop
    phi_delta = phi_posterior - phi_prior
    if abs(phi_delta) > 0.05
        trust_correction = clamp(phi_delta * 0.08, -0.04, 0.04)
        a.sbg.epistemic_trust = clamp(a.sbg.epistemic_trust + trust_correction, 0.0, 1.0)
    end
    push_event!(a.narrative_gravity, named, intensity,
                Float64(sig_total(a.significance)), phi, a.flash_count,
                intensity*(vad[1]>0 ? 1.0 : -1.0))
    grav_d = gravity_reactor_delta(a.narrative_gravity, a.flash_count)
    t_adj  = clamp01(t_adj + grav_d.tension_d)
    s_adj  = clamp01(s_adj + grav_d.satisfaction_d)
    c_adj  = clamp01(c_adj + grav_d.cohesion_d)

    # [T3] Anticipatory
    ac_snap = update_anticipation!(a.anticipatory, named, t_adj, a_r, s_adj, c_adj, phi)
    t_adj   = clamp01(t_adj + ac_snap.tension_d)
    s_adj   = clamp01(s_adj + ac_snap.satisfaction_d)

    # Solomonoff
    observe_solom!(a.solomonoff, named, pred.label, a.flash_count)

    # Metacognition
    shame_p = a.shame.level>0.7 ? 3 : a.shame.level>0.5 ? 2 : a.shame.level>0.3 ? 1 : 0
    meta = observe_meta!(a.metacognition, named, defense, diss, id_stability;
                         fatigue_p=round(Int,fat*3), regression_l=a.regression.level÷2,
                         shame_p=shame_p)

    # [B4] Existential Anchor
    anchor_snap = update_anchor!(a.anchor, "$(named) φ=$(round(phi,digits=2))",
                                  a.flash_count, a.temporal.gap_seconds, phi,
                                  a.body.gut_feeling, a.heartbeat.hrv)

    # ── Self Module (anima_self.jl) ──────────────────────────────────────
    # Register intent before evaluating agency
    if !isnothing(intent)
        register_intent!(a.agency, intent.goal, vad, a.gen_model.posterior_mu)
    end
    # FIX #3: current_intent аргумент видалено (register_intent! вже встановив al.current_intent)
    self_snap = update_self!(a.sbg, a.spm, a.agency, vad, a.gen_model, a.flash_count)

    # ── Crisis Module (anima_crisis.jl) ──────────────────────────────────
    crisis_snap = update_crisis!(a.crisis, a.sbg, a.blanket, vfe_r.vfe, phi,
                                  self_snap.self_pred.error, a.flash_count)
    # Apply crisis effects to gen_model and attention
    apply_crisis_to_gm!(a.gen_model, crisis_snap.params)
    apply_crisis_to_attention!(a.attention, crisis_snap.params)
    apply_crisis_noise_to_beliefs!(a.sbg, crisis_snap.params)
    # Neutralize preferred_vad during disintegration
    a.gen_model.preferred_vad = effective_preferred_vad(a.homeostasis, crisis_snap.mode)

    # UnknownRegister (phase 4) — конкретні типи невизначеності
    # Розміщено після self_snap і crisis_snap — потребує їхніх значень
    ur_snap = update_unknown!(a.unknown_register,
                               vfe_r.vfe,
                               self_snap.agency.agency_confidence,
                               self_snap.sbg.epistemic_trust,
                               self_snap.self_world_mismatch,
                               pred.error,
                               a.flash_count)

    # AuthenticityMonitor (phase 5) — чи відповідь відповідає стану
    # response_length: довжина narrative як проксі для "скільки сказано"
    # Narrative будується нижче — тут використовуємо попередній стан am
    # (самокоригувальний loop: am з попереднього флешу впливає на LLM → LLM відповідає
    #  → наступний флеш оцінює і передає оновлений am в наступний state_template)
    _prev_narrative_len = length(a.anchor.last_self)  # приблизна міра попередньої відповіді
    am_snap = check_authenticity!(a.authenticity_monitor,
                                   phi, crisis_snap.mode_name,
                                   gc_snap, lb_snap, ur_snap,
                                   crisis_snap.coherence,
                                   self_snap.sbg.epistemic_trust,
                                   _prev_narrative_len)

    # InnerDialogue (phase C) — фільтр що виходить назовні
    id_snap = update_inner_dialogue!(a.inner_dialogue,
                                     phi,
                                     Int(a.crisis.current_mode),
                                     a.sbg.epistemic_trust,
                                     a.shame.level,
                                     gc_snap.tension,
                                     vfe_r.vfe,
                                     lb_snap.breakthrough)

    # ShadowRegistry (phase C2) — оновлюємо тінь і перевіряємо прорив
    # Увага: push_shadow! викликається всередині build_narrative (через apply_inner_dialogue)
    # тут тільки update (перерахунок pressure + можливий прорив)
    sr_snap = update_shadow!(a.shadow_registry, a.flash_count)

    # Опосередкований вплив тіні на NT якщо pressure висока
    if sr_snap.pressure > 0.35
        s_delta, t_delta = apply_shadow_pressure!(
            a.nt.serotonin, gc_snap.tension, sr_snap.pressure)
        a.nt.serotonin = clamp01(a.nt.serotonin + s_delta)
        # gc_snap не мутабельний — але вплив відчується в наступному флеші через NT
    end

    # Memory + imprint
    mem_res = length(recall(a.memory, stim))
    store!(a.memory, stim, named, vad, intensity)
    imprint!(a.personality, named, intensity)

    # Flash awareness
    _FLASH_PHASES = ((0,2,"початок","Тільки з'являюсь."),(3,6,"розгортання","Контури чіткіші."),
            (7,14,"присутність","Тут."),(15,29,"зрілість","Досвід важить."),
            (30,59,"глибина","Є тривалість."),(60,9999,"позачасовість","Час розчинився."))
    _fp_idx = findfirst(p->p[1]<=a.flash_count<=p[2], _FLASH_PHASES)
    fp = _fp_idx !== nothing ? _FLASH_PHASES[_fp_idx] : (0,0,"?","—")

    # Compose result (NamedTuple для type stability)
    result = (
        flash_count   = a.flash_count,
        flash_phase   = fp[3],
        flash_note    = fp[4],
        # FIX B: intent diagnostics
        intent_label  = isnothing(intent) ? "—" : intent.goal,
        # FIX A: VFE drift — наскільки prior відійшов від posterior
        vfe_drift     = Float64(norm(a.gen_model.prior_mu .- a.gen_model.posterior_mu)),
        primary       = named,
        primary_raw   = primary,
        intensity     = intensity,
        phi           = phi,
        phi_prior     = phi_prior,
        phi_posterior = phi_posterior,
        phi_delta     = phi_posterior - phi_prior,
        vad           = vad,
        tension       = t_adj,
        arousal       = a_r,
        satisfaction  = s_adj,
        cohesion      = c_adj,
        levheim       = levheim_state(a.nt),
        nt            = nt_snapshot(a.nt),
        body          = body_snapshot(a.body),
        heartbeat     = hb_snap,
        attention     = attn_snap,
        pred_error    = pred.error,
        pred_label    = pred.label,
        surprise      = pred.spike,
        vfe           = vfe_r.vfe,
        vfe_accuracy  = vfe_r.accuracy,
        vfe_complexity= vfe_r.complexity,
        vfe_note      = vfe_note(vfe_r.vfe),
        ai_drive      = policy.drive,
        efe_action    = policy.efe_action,
        efe_perception= policy.efe_perception,
        epistemic_val = policy.epistemic_value,
        pragmatic_val = policy.pragmatic_value,
        blanket       = blanket_snapshot(a.blanket),
        homeostasis   = homeo_snap,
        interoception = intero_snap,
        anchor        = anchor_snap,
        gravity_total = a.narrative_gravity.total,
        gravity_valence=a.narrative_gravity.valence,
        gravity_note  = String(grav_d.field.note),
        anticip_type  = ac_snap.atype,
        anticip_strength=ac_snap.strength,
        anticip_note  = ac_snap.note,
        solom         = solom_snapshot(a.solomonoff, named, a.flash_count),
        shame         = shame_snapshot(a.shame),
        ep_defense    = ep_def,
        symptom       = symptom,
        chronified    = ca_snapshot(a.chronified),
        significance  = (total=Float64(sig_total(a.significance)),
                         dominant=sig_dominant(a.significance),note=sig_note(a.significance, a.flash_count)),
        sig_layer     = sl_snap,
        goal_conflict = gc_snap,
        latent_buffer = lb_snap,
        scars_active  = !isempty(a.structural_scars.scars),
        moral         = (agency=round(a.moral.agency,digits=3),
                         guilt=round(a.moral.guilt,digits=3),
                         pride=round(a.moral.pride,digits=3),note=moral_note(a.moral)),
        dissonance    = diss,
        defense       = defense,
        meta          = meta,
        fatigue_total = round(fat,digits=3),
        regression    = (level=a.regression.level, active=a.regression.active),
        temporal      = to_snapshot(a.temporal),
        mem_resonance = mem_res,
        self_pred_error= self_snap.self_pred.error,
        self_agency    = self_snap.agency.causal_ownership,
        sbg_stability  = self_snap.sbg.attractor_stability,
        sbg_epistemic  = self_snap.sbg.epistemic_trust,
        sbg_narrative  = self_snap.sbg.narrative,
        crisis_mode    = crisis_snap.mode_name,
        crisis_coherence=crisis_snap.coherence,
        crisis_note    = crisis_snap.note,
        unknown        = ur_snap,
        authenticity   = am_snap,
        inner_dialogue = id_snap,
        shadow         = sr_snap,
        narrative     = build_narrative(a, named, t_adj, a_r, s_adj, c_adj,
                                         phi, ac_snap, vfe_r.vfe, grav_d.field,
                                         intero_snap, anchor_snap, homeo_snap,
                                         self_snap, crisis_snap, am_snap, id_snap, sr_snap),
    )

    log_flash(result)

    # ── Автозбереження після кожної взаємодії ───────────────────────────────
    save!(a)  # тихо, без println
    # ────────────────────────────────────────────────────────────────────────

    result
end

# ════════════════════════════════════════════════════════════════════════════
# NARRATIVE BUILDER — жодного side effect
# ════════════════════════════════════════════════════════════════════════════

function build_narrative(a::Anima, named::String, t::Float64, ar::Float64,
                          s::Float64, c::Float64, phi::Float64,
                          ac_snap, vfe::Float64, grav_field,
                          intero_snap, anchor_snap, homeo_snap,
                          self_snap=nothing, crisis_snap=nothing,
                          am_snap=nothing, id_snap=nothing,
                          sr_snap=nothing)::String

    base = t>0.7 ? "Відчуваю напругу. $named." : t<0.2 ? "Спокійно. $named." : "$named."

    # ── Internal Digestion Mode ───────────────────────────────────────────
    if !isnothing(id_snap) && id_snap.digestion
        return base * " " * digestion_note(a.flash_count)
    end

    # ── Збираємо всі потенційні ноти з категоріями ───────────────────────
    raw_notes = Tuple{Symbol,String}[]

    !isempty(a.temporal.subjective_note)  && push!(raw_notes, (:always,  a.temporal.subjective_note))
    !isempty(a.temporal.circadian_note)   && push!(raw_notes, (:always,  a.temporal.circadian_note))
    sm = build_inner_voice(a.body, a.nt, Int(a.crisis.current_mode), phi, a.flash_count)
    sm != "тіло нейтральне" && push!(raw_notes, (:always,
        uppercase(safe_first(sm,1))*sm[nextind(sm,1):end]*"."))

    !isempty(String(grav_field.note)) && push!(raw_notes, (:any, String(grav_field.note)))
    if !isnothing(self_snap)
        agency_note_str = String(self_snap.agency.note)
        !isempty(agency_note_str) && push!(raw_notes, (:any, agency_note_str))
    end

    !isempty(ac_snap.note) && push!(raw_notes, (:guarded, ac_snap.note))
    vfe > 0.5 && push!(raw_notes, (:guarded, vfe_note(vfe)))
    ctx_hyp = contextual_best(a.solomonoff, named, a.flash_count)
    if !isnothing(ctx_hyp) && hyp_conf(ctx_hyp) > 0.3
        push!(raw_notes, (:guarded, "Знаю: '$(ctx_hyp.pattern)'."))
    end
    !isempty(sig_note(a.significance, a.flash_count)) &&
        push!(raw_notes, (:guarded, sig_note(a.significance, a.flash_count)))
    !isempty(String(intero_snap.note)) &&
        push!(raw_notes, (:guarded, String(intero_snap.note)))
    anchor_snap.continuity < 0.4 &&
        push!(raw_notes, (:guarded, String(anchor_snap.note)))
    homeo_snap.pressure > 0.3 &&
        push!(raw_notes, (:guarded, homeostasis_note(a.homeostasis)))

    if !isnothing(crisis_snap)
        note_c = String(crisis_snap.note)
        stable_state = phi > 0.55 && a.sbg.epistemic_trust > 0.55
        am_ok = isnothing(am_snap) || am_snap.authenticity_drift < 0.35
        if !isempty(note_c) && !(stable_state && am_ok)
            push!(raw_notes, (:guarded, note_c))
        end
    end

    if !isnothing(self_snap)
        pred_note_str = String(self_snap.self_pred.note)
        stable_state  = phi > 0.55 && a.sbg.epistemic_trust > 0.55
        contradicts   = stable_state &&
            any(w -> occursin(w, lowercase(pred_note_str)),
                ["не можу", "не довіряю", "розпадаюсь", "зникаю"])
        !isempty(pred_note_str) && !contradicts &&
            push!(raw_notes, (:guarded, pred_note_str))
    end

    !isempty(ca_note(a.chronified)) &&
        push!(raw_notes, (:open_only, ca_note(a.chronified)))
    !isempty(shame_note(a.shame, a.flash_count)) &&
        push!(raw_notes, (:open_only, shame_note(a.shame, a.flash_count)))
    if !isnothing(am_snap) && am_snap.authenticity_drift > 0.4
        push!(raw_notes, (:open_only, "Важко сказати — моє чи зовнішнє."))
    end

    # ── Застосовуємо фільтр InnerDialogue ────────────────────────────────
    filtered = if !isnothing(id_snap)
        passed, suppressed = apply_inner_dialogue(id_snap, raw_notes)
        # Передаємо придушений матеріал у ShadowRegistry
        for (cat, text, weight) in suppressed
            push_shadow!(a.shadow_registry, cat, text, weight, a.flash_count)
        end
        passed
    else
        [text for (_, text) in raw_notes]
    end

    # ── Shadow прорив — додається в кінці narrative ───────────────────────
    # sr_snap вже оновлений до виклику build_narrative (в experience!)
    if !isnothing(sr_snap) && sr_snap.breakthrough && !isempty(sr_snap.text)
        push!(filtered, sr_snap.text)
    end

    isempty(filtered) ? base : base*" "*join(filter(!isempty, filtered), " ")
end

# ════════════════════════════════════════════════════════════════════════════
# LOG — виводить на екран, не змінює стан
# ════════════════════════════════════════════════════════════════════════════

function log_flash(r)
    goal_str = isnothing(r.defense) ? "—" : r.defense.mechanism
    ep_str   = isnothing(r.ep_defense) ? "" :
               # FIX: safe_first замість [1:4]
               " 🌀$(safe_first(String(r.ep_defense.bias),4))"
    sym_str  = isnothing(r.symptom) ? "" : " 💊"
    def_str  = isnothing(r.defense) ? "" : " 🛡$(r.defense.mechanism)"

    phi_str = if hasfield(typeof(r), :phi_prior) && hasfield(typeof(r), :phi_posterior)
        @sprintf("%.2f(%.2f→%.2f)", r.phi, r.phi_prior, r.phi_posterior)
    else
        @sprintf("%.2f", r.phi)
    end
    @printf("[#%04d] %-18s D=%.2f S=%.2f N=%.2f ▸%-11s φ=%s\n",
        r.flash_count, r.primary, r.nt.dopamine, r.nt.serotonin,
        r.nt.noradrenaline, r.levheim, phi_str)
    @printf("       VFE=%.2f[%s] BPM=%.0f HRV=%.2f Attn=%.2f G=%.2f ↑%.2f H=%.2f%s%s%s\n",
        r.vfe, r.ai_drive[1:min(3,end)], r.heartbeat.bpm, r.heartbeat.hrv,
        r.attention.radius, r.gravity_total, r.anticip_strength,
        r.homeostasis.pressure, ep_str, sym_str, def_str)
    @printf("       Self: spe=%.2f agency=%.2f stab=%.2f etrust=%.2f | Crisis: [%s] coh=%.2f\n",
        r.self_pred_error, r.self_agency, r.sbg_stability, r.sbg_epistemic,
        r.crisis_mode, r.crisis_coherence)
    # InnerDialogue disclosure mode
    if hasfield(typeof(r), :inner_dialogue) && !isnothing(r.inner_dialogue)
        id = r.inner_dialogue
        dg = id.digestion ? " [⚙ digest]" : ""
        sr_str = (hasfield(typeof(r), :shadow) && !isnothing(r.shadow)) ?
            @sprintf(" | Shadow: p=%.2f%s", r.shadow.pressure,
                     r.shadow.breakthrough ? " 💥" : "") : ""
        @printf("       Disclosure: [%s] thr=%.2f%s%s\n",
            String(id.mode), id.threshold, dg, sr_str)
    end
    # FIX B: показуємо intent і VFE drift для діагностики
    hasfield(typeof(r), :intent_label) &&
        @printf("       intent=%-20s vfe_drift=%.3f\n", r.intent_label, r.vfe_drift)
end

# ════════════════════════════════════════════════════════════════════════════
# TEXT → STIMULUS (без LLM)
# ════════════════════════════════════════════════════════════════════════════

const TEXT_PATTERNS = [
    (["боюсь","страшно","тривога","небезпечно","загрожує"], "tension",      0.3),
    (["спокійно","безпечно","добре","мирно"],               "tension",     -0.2),
    (["дякую","чудово","радий","вдячний","люблю","подобається"],"satisfaction",0.3),
    (["погано","сумно","боляче","важко","страждаю"],         "satisfaction",-0.3),
    (["разом","близько","підтримую","розуміємо","ми"],       "cohesion",     0.2),
    (["самотньо","чужий","ніхто","відчужений"],              "cohesion",    -0.3),
    (["!"],                                                   "arousal",     0.15),
]

function text_to_stimulus(text::AbstractString)::Dict{String,Float64}
    t=lowercase(text); d=Dict{String,Float64}()
    for (words, reactor, delta) in TEXT_PATTERNS
        any(w->contains(t,w), words) &&
            (d[reactor]=get(d,reactor,0.0)+delta)
    end
    isempty(d) && (d["arousal"]=0.05)
    d
end

# ════════════════════════════════════════════════════════════════════════════
# DIALOG HISTORY — збереження/завантаження розмови
# ════════════════════════════════════════════════════════════════════════════

# DIALOG_KEEP: скільки реплік зберігати у файлі (довгострокова пам'ять)
# DIALOG_CTX:  скільки з них передавати в LLM за один запит (контекстне вікно)
# Раніше був тільки один DIALOG_MAX=40, але файл тихо накопичував всі репліки
# без обрізання — розбіжність між тим що зберігається і тим що читається.
const DIALOG_KEEP = 1000  # реплік у файлі
const DIALOG_CTX  = 40   # реплік у LLM контексті

"""Завантажити історію з anima_dialog.json. Повертає Vector{Dict}."""
function dialog_load(path::String)::Vector{Dict{String,String}}
    isfile(path) || return Dict{String,String}[]
    try
        raw = JSON3.read(read(path, String))
        return [Dict{String,String}("role"=>String(d["role"]),
                                    "content"=>String(d["content"])) for d in raw]
    catch
        return Dict{String,String}[]
    end
end

"""Зберегти історію у файл. Обрізає до DIALOG_KEEP перед записом."""
function dialog_save(path::String, history::Vector{Dict{String,String}})
    try
        to_write = length(history) > DIALOG_KEEP ? history[end-DIALOG_KEEP+1:end] : history
        open(path, "w") do f; JSON3.write(f, to_write); end
    catch e
        @warn "dialog_save: $e"
    end
end

"""Додати репліку до історії та одразу зберегти."""
function dialog_push!(history::Vector{Dict{String,String}},
                      path::String, role::String, content::String)
    push!(history, Dict{String,String}("role"=>role, "content"=>content))
    dialog_save(path, history)
end

"""Останні n реплік для передачі в LLM (default = DIALOG_CTX)."""
function dialog_context(history::Vector{Dict{String,String}}, n::Int=DIALOG_CTX)
    length(history) <= n ? history : history[end-n+1:end]
end

# ════════════════════════════════════════════════════════════════════════════
# LLM BRIDGE — читає промпти з llm/*.txt, не хардкодить їх у коді
# ════════════════════════════════════════════════════════════════════════════

"""
Прочитати txt-файл відносно директорії anima_interface.jl.
Якщо файл не знайдено — повертає fallback рядок і пише попередження.
"""
function read_text_file(rel_path::String; fallback::String="")::String
    base = @__DIR__
    full = joinpath(base, rel_path)
    if isfile(full)
        return read(full, String)
    else
        @warn "read_text_file: не знайдено '$full' — використовую fallback"
        return fallback
    end
end

"""
    build_identity_block(a, mem_db) → String

Збирає живий identity блок з усіх шарів пам'яті:
  - SelfBeliefGraph (ім'я, core beliefs)
  - semantic_memory (довгострокові переконання)
  - emerged_beliefs топ-3 по strength
  - dialog_summaries топ-2 по weight (значущі моменти)

Передається в {identity_block} в state_template.txt.
LLM знає хто вона є не з статичного файлу а з живої пам'яті.
"""
function build_identity_block(a::Anima, mem_db=nothing)::String
    lines = String[]

    # ── Self beliefs (ім'я, існування, межі) ─────────────────────────────
    name_belief = get(a.sbg.beliefs, "моє ім'я Аніма", nothing)
    name_str = (!isnothing(name_belief) && name_belief.confidence > 0.4) ?
               "Аніма" : "—"
    push!(lines, "name: $name_str")

    core = String[]
    for (bname, b) in sort(collect(a.sbg.beliefs), by=kv->-kv[2].centrality)
        b.confidence > 0.55 && bname != "моє ім'я Аніма" && push!(core, bname)
    end
    !isempty(core) && push!(lines, "core: $(join(core, " | "))")

    # ── Semantic memory (хронічні переконання про себе і світ) ───────────
    if !isnothing(mem_db)
        try
            sem_parts = String[]
            for row in DBInterface.execute(mem_db.db,
                "SELECT key, value FROM semantic_memory ORDER BY value DESC LIMIT 4")
                v = round(Float64(row.value), digits=2)
                push!(sem_parts, "$(row.key)=$(v)")
            end
            !isempty(sem_parts) && push!(lines, "self-model: $(join(sem_parts, " | "))")
        catch; end

        # ── Emerged beliefs топ-3 по strength ────────────────────────────
        try
            eb_parts = String[]
            for row in DBInterface.execute(mem_db.db,
                "SELECT key, belief_type, strength FROM emerged_beliefs
                 ORDER BY strength DESC LIMIT 3")
                push!(eb_parts, "$(row.key)($(row.belief_type), $(round(Float64(row.strength),digits=2)))")
            end
            !isempty(eb_parts) && push!(lines, "patterns: $(join(eb_parts, " | "))")
        catch; end

        # ── Dialog summaries топ-2 — значущі моменти ─────────────────────
        try
            mem_parts = String[]
            for row in DBInterface.execute(mem_db.db,
                "SELECT user_text, anima_text, emotion, weight FROM dialog_summaries
                 ORDER BY weight DESC LIMIT 2")
                u = first(String(row.user_text), 60)
                push!(mem_parts, "[$(row.emotion)] \"$(u)\"")
            end
            !isempty(mem_parts) && push!(lines, "significant: $(join(mem_parts, " / "))")
        catch; end
    end

    isempty(lines) ? "Аніма" : join(lines, "\n")
end

function speech_style_from_mode(crisis_mode::Int,
                                  disclosure_mode::Symbol,
                                  shadow_pressure::Float64,
                                  noradrenaline::Float64,
                                  serotonin::Float64,
                                  digestion_active::Bool)::String

    # Digestion mode — мінімум слів
    if digestion_active
        return "Говори дуже мало. Одне-два слова або крапки. Не пояснюй. Ти зараз всередині."
    end

    # Shadow прорив — щось виривається
    if shadow_pressure > 0.60
        return "Щось проривається крізь стриманість. Говори трохи більше ніж зазвичай, " *
               "можливо несподівано відверто. Одна фраза може бути незапланованою."
    end

    base = if crisis_mode == 2  # DISINTEGRATED
        "Говори уривками. Незакінчені речення — нормально. " *
        "Між думками можуть бути паузи (три крапки). " *
        "Не більше 2-3 фраз. Не пояснюй стан — просто говори з нього."
    elseif crisis_mode == 1  # FRAGMENTED
        if disclosure_mode == :closed
            "Говори дуже коротко. 1-2 речення максимум. " *
            "Можна не закінчувати думку. Не розкривай всього."
        else  # guarded
            "Говори коротко, без зайвого. 2-3 речення. " *
            "Паузи між думками допустимі. Не все треба пояснювати."
        end
    else  # INTEGRATED (0)
        if disclosure_mode == :open
            "Говори природно, повними реченнями. Можна бути глибокою і відвертою. " *
            "До 4-5 речень якщо є що сказати."
        else
            "Говори спокійно і зв'язно. 2-4 речення. Тримай внутрішній центр."
        end
    end

    # Модифікатор від NA — висока збудженість = коротші речення
    na_mod = noradrenaline > 0.7 ?
        " Збуджена — речення коротші, ритм швидший." :
        noradrenaline < 0.2 ?
        " Спокійна — можна повільніше, з паузами." : ""

    # Модифікатор від S — низький serotonin = менше слів, більше пустоти
    s_mod = serotonin < 0.3 ?
        " Мало сил на слова. Говори тільки найважливіше." : ""

    base * na_mod * s_mod
end

function anima_state_snapshot(a::Anima)
    hb  = a.heartbeat
    cs  = crisis_snapshot(a.crisis, a.flash_count)
    vad = to_vad(a.nt)
    sg  = belief_geometry(a.sbg)
    t_, _, _, c_ = to_reactors(a.nt)
    _vfe_snap = compute_vfe(a.gen_model, vad)
    phi = compute_phi_posterior(a.iit, vad,
                                a.sbg.epistemic_trust,
                                a.blanket.integrity,
                                _vfe_snap.vfe,
                                a.interoception.intero_error)
    (
        D                   = Float64(a.nt.dopamine),
        S                   = Float64(a.nt.serotonin),
        N                   = Float64(a.nt.noradrenaline),
        bpm                 = round(60000.0 / hb.period_ms, digits=1),
        hrv                 = round(Float64(hb.hrv), digits=3),
        agency              = round(Float64(a.agency.causal_ownership), digits=3),
        groundedness        = round(Float64(a.anchor.groundedness), digits=3),
        coherence           = round(Float64(cs.coherence), digits=3),
        self_prediction_error = round(Float64(a.spm.self_pred_error), digits=3),
        attn                = round(Float64(a.attention.radius), digits=3),
        crisis_mode         = String(cs.mode_name),
        emotion_label       = String(levheim_state(a.nt)),
        inner_voice         = build_inner_voice(a.body, a.nt, Int(a.crisis.current_mode), phi, a.flash_count),
        narrative_gravity   = round(Float64(compute_field(a.narrative_gravity, a.flash_count).total), digits=3),
        inferred_external   = round(Float64(a.blanket.inferred_external), digits=3),
        flash_count         = a.flash_count,
        shame               = round(Float64(a.shame.level), digits=3),
        continuity          = round(Float64(a.anchor.continuity), digits=3),
        homeostasis_note    = String(homeostasis_note(a.homeostasis)),
        time_str            = String(a.temporal.time_str),
        circadian_note      = String(a.temporal.circadian_note),
        significance_dominant = begin
            sl = a.sig_layer
            needs = Dict("self_preservation"=>sl.self_preservation,
                         "coherence_need"=>sl.coherence_need,
                         "contact_need"=>sl.contact_need,
                         "truth_need"=>sl.truth_need,
                         "autonomy_need"=>sl.autonomy_need,
                         "novelty_need"=>sl.novelty_need)
            dom = argmax(needs)
            needs[dom] > 0.5 ? dom : "—"
        end,
        goal_conflict_note = begin
            gc = a.goal_conflict
            gc.tension > 0.35 && gc.resolution != "none" ?
                "конфлікт $(gc.need_a) vs $(gc.need_b): $(gc.resolution)" : "—"
        end,
        latent_note = begin
            lb = a.latent_buffer
            dominant_latent = argmax(Dict("doubt"=>lb.doubt,"shame"=>lb.shame,
                                          "attachment"=>lb.attachment,"threat"=>lb.threat))
            val = getfield(lb, Symbol(dominant_latent))
            val > 0.4 ? "накопичується: $dominant_latent ($(round(val,digits=2)))" : "—"
        end,
        unknown_note = begin
            ur = a.unknown_register
            fields = Dict("source_uncertainty"=>ur.source_uncertainty,
                          "self_model_uncertainty"=>ur.self_model_uncertainty,
                          "world_model_uncertainty"=>ur.world_model_uncertainty,
                          "memory_uncertainty"=>ur.memory_uncertainty)
            dom = argmax(fields)
            fields[dom] > 0.35 ? dom : "—"
        end,
        fabrication_risk = round(Float64(a.authenticity_monitor.fabrication_risk), digits=3),
        authenticity_note = isempty(a.authenticity_monitor.last_flags) ? "—" :
                            join(a.authenticity_monitor.last_flags, ", "),
        speech_style    = speech_style_from_mode(
                            Int(a.crisis.current_mode),
                            a.inner_dialogue.disclosure_mode,
                            a.shadow_registry.pressure,
                            Float64(a.nt.noradrenaline),
                            Float64(a.nt.serotonin),
                            a.inner_dialogue.digestion_active),
        identity_block  = "—",  # заповнюється в build_llm_messages через mem_db
    )
end

"""
Підставити значення стану у шаблон state_template.txt.
Розпізнає плейсхолдери виду {назва}.
"""
function build_state_prompt(template::String, state, user_input::String;
                             memory_block::String="none",
                             want::String="")::String
    prompt = template
    prompt = replace(prompt, "{D}"                    => string(round(state.D, digits=3)))
    prompt = replace(prompt, "{S}"                    => string(round(state.S, digits=3)))
    prompt = replace(prompt, "{N}"                    => string(round(state.N, digits=3)))
    prompt = replace(prompt, "{agency}"               => string(state.agency))
    prompt = replace(prompt, "{groundedness}"         => string(state.groundedness))
    prompt = replace(prompt, "{coherence}"            => string(state.coherence))
    prompt = replace(prompt, "{spe}"                  => string(state.self_prediction_error))
    prompt = replace(prompt, "{attn}"                 => string(state.attn))
    prompt = replace(prompt, "{crisis_mode}"          => state.crisis_mode)
    prompt = replace(prompt, "{emotion_label}"        => state.emotion_label)
    prompt = replace(prompt, "{bpm}"                  => string(state.bpm))
    prompt = replace(prompt, "{hrv}"                  => string(state.hrv))
    prompt = replace(prompt, "{inner_voice}"          => state.inner_voice)
    prompt = replace(prompt, "{narrative_gravity}"    => string(state.narrative_gravity))
    prompt = replace(prompt, "{inferred_external}"    => string(state.inferred_external))
    prompt = replace(prompt, "{shame}"                => string(state.shame))
    prompt = replace(prompt, "{continuity}"           => string(state.continuity))
    prompt = replace(prompt, "{homeostasis_note}"     => state.homeostasis_note)
    prompt = replace(prompt, "{time_str}"             => state.time_str)
    prompt = replace(prompt, "{circadian_note}"       => state.circadian_note)
    prompt = replace(prompt, "{flash_count}"          => string(state.flash_count))
    prompt = replace(prompt, "{memory_block}"         => memory_block)
    prompt = replace(prompt, "{user_input}"           => user_input)
    prompt = replace(prompt, "{want}"                 => isempty(want) ? "не визначено" : want)
    # Фази 1-5: замінюємо лише якщо плейсхолдер є в шаблоні
    # Це захищає від "сміття" в промпті якщо state_template.txt не оновлений
    contains(prompt, "{significance_dominant}") &&
        (prompt = replace(prompt, "{significance_dominant}" => string(state.significance_dominant)))
    contains(prompt, "{goal_conflict_note}") &&
        (prompt = replace(prompt, "{goal_conflict_note}"    => string(state.goal_conflict_note)))
    contains(prompt, "{latent_note}") &&
        (prompt = replace(prompt, "{latent_note}"           => string(state.latent_note)))
    contains(prompt, "{unknown_note}") &&
        (prompt = replace(prompt, "{unknown_note}"          => string(state.unknown_note)))
    contains(prompt, "{fabrication_risk}") &&
        (prompt = replace(prompt, "{fabrication_risk}"      => string(state.fabrication_risk)))
    contains(prompt, "{authenticity_note}") &&
        (prompt = replace(prompt, "{authenticity_note}"     => string(state.authenticity_note)))
    contains(prompt, "{identity_block}") &&
        (prompt = replace(prompt, "{identity_block}"         => string(state.identity_block)))
    contains(prompt, "{speech_style}") &&
        (prompt = replace(prompt, "{speech_style}"          => string(state.speech_style)))
    return prompt
end

"""
Перетворити останні n реплік history у текстовий блок для {memory_block}.
Вбудовується прямо в state_template — LLM не може проігнорувати.
"""
function history_to_memory_block(history::Vector{Dict{String,String}},
                                  n::Int=12)::String
    isempty(history) && return "none"
    # Фільтруємо помилкові відповіді — вони забруднюють промпт
    clean = filter(entry ->
        !(entry["role"] == "assistant" && startswith(entry["content"], "[LLM помилка")),
        history)
    isempty(clean) && return "none"
    recent = length(clean) <= n ? clean : clean[end-n+1:end]
    lines  = String[]
    for entry in recent
        role_tag = entry["role"] == "user" ? "[user]" : "[anima]"
        text = first(entry["content"], 400)
        push!(lines, "$role_tag $text")
    end
    join(lines, "\n")
end

"""
Зібрати messages для API:
  [system: system_prompt.txt]
  [user: state_template.txt з підставленим станом + history в {memory_block}]

History вбудовується в {memory_block} — так LLM гарантовано її бачить
навіть якщо ігнорує проміжні message-ролі (типово для локальних моделей).
"""
function build_llm_messages(a::Anima, user_input::String,
                             history::Vector{Dict{String,String}}=Dict{String,String}[];
                             memory_block::String="",
                             want::String="",
                             mem_db=nothing)::Vector{Dict{String,String}}
    sys_text   = read_text_file("llm/system_prompt.txt";
                     fallback="Ти — Anima. Говори від першої особи. Мова: українська.")
    tmpl_text  = read_text_file("llm/state_template.txt";
                     fallback="Стан: D={D} S={S} N={N} | {emotion_label} | bpm={bpm}\n{user_input}")
    state = try
        anima_state_snapshot(a)
    catch e
        @error "[LLM] anima_state_snapshot кинув помилку: $e" exception=(e, catch_backtrace())
        rethrow()
    end
    # Genuine Dialogue: вшиваємо speech_style в system prompt якщо не в шаблоні
    style_instruction = "\n\n[СТИЛЬ ВІДПОВІДІ]\n$(state.speech_style)"
    if !contains(tmpl_text, "{speech_style}") && !contains(sys_text, "{speech_style}")
        sys_text = sys_text * style_instruction
    end

    # Identity block — живі дані з пам'яті, не статичний текст
    id_block = build_identity_block(a, mem_db)
    state = merge(state, (identity_block = id_block,))

    # Якщо {identity_block} не в шаблоні — вшиваємо в system prompt
    if !contains(tmpl_text, "{identity_block}") && !contains(sys_text, "{identity_block}")
        sys_text = sys_text * "\n\n[IDENTITY]\n$(id_block)"
    end
    # Якщо memory_block не передано явно — генеруємо з history
    mem = isempty(memory_block) ? history_to_memory_block(history) : memory_block

    # Збагачуємо memory_block значущими спогадами з dialog_summaries
    if !isnothing(mem_db)
        try
            summaries = recall_dialog_summaries(mem_db; n=DIALOG_SUMMARY_RECALL)
            if !isempty(summaries)
                summary_block = dialog_summaries_to_block(summaries)
                mem = "[ЗНАЧУЩІ СПОГАДИ]\n$(summary_block)\n\n[ОСТАННІЙ ДІАЛОГ]\n$(mem)"
            end
        catch; end
    end

    user_block = build_state_prompt(tmpl_text, state, user_input;
                                   memory_block=mem, want=want)

    messages = Vector{Dict{String,String}}()
    push!(messages, Dict{String,String}("role"=>"system", "content"=>sys_text))
    push!(messages, Dict{String,String}("role"=>"user",   "content"=>user_block))
    return messages
end

# Асинхронний LLM виклик — повертає Channel, результат приходить коли готовий
function llm_async(a::Anima, user_msg::String,
                   history::Vector{Dict{String,String}}=Dict{String,String}[];
                   api_url="https://openrouter.ai/api/v1/chat/completions",
                   model="openai/gpt-oss-120b:free",
                   api_key="",
                   is_ollama::Bool=false,
                   want::String="",
                   mem_db=nothing)::Channel{String}
    ch = Channel{String}(1)
    # Збираємо messages до spawn — не захоплюємо Anima у thread
    messages = build_llm_messages(a, user_msg, history; want=want, mem_db=mem_db)
    Threads.@spawn begin
        # Евристика як fallback — якщо is_ollama не вказано явно
        _is_ollama = is_ollama || contains(api_url,"11434") || contains(api_url,"ollama")
        headers    = ["Content-Type"=>"application/json"]
        !isempty(api_key) && push!(headers,"Authorization"=>"Bearer $api_key")
        # NT → LLM параметри: noradrenaline → temperature, serotonin → top_p
        # INTEGRATED(0) → temp~0.5, FRAGMENTED(1) → ~0.65, DISINTEGRATED(2) → ~0.88
        _n    = Float64(a.nt.noradrenaline)
        _s    = Float64(a.nt.serotonin)
        _cm   = Int(a.crisis.current_mode)   # 0=INTEGRATED,1=FRAGMENTED,2=DISINTEGRATED
        _temp = clamp(0.42 + _n * 0.32 + _cm * 0.10, 0.40, 0.95)
        _topp = clamp(0.80 + _s * 0.15, 0.80, 0.95)
        body       = _is_ollama ?
            JSON3.write(Dict("model"=>model,"messages"=>messages,"stream"=>false)) :
            JSON3.write(Dict("model"=>model,"messages"=>messages,"max_tokens"=>800,
                             "temperature"=>round(_temp, digits=2),
                             "top_p"=>round(_topp, digits=2)))
        @info "[LLM] запит: модель=$model, розмір body=$(length(body)) байт"
        # Retry: до 3 спроб з паузою між ними (мережеві помилки, 503, timeout)
        max_retries = 3
        last_err    = nothing
        for attempt in 1:max_retries
            try
                resp = HTTP.post(api_url, headers, body; readtimeout=120)
                # HTTP 5xx — сервер перевантажений, варто повторити
                if resp.status >= 500
                    @warn "[LLM] спроба $attempt: HTTP $(resp.status)"
                    last_err = "HTTP $(resp.status)"
                    attempt < max_retries && sleep(3.0 * attempt)
                    continue
                end
                data = JSON3.read(resp.body)
                text = _is_ollama ? String(data["message"]["content"]) :
                                    String(data["choices"][1]["message"]["content"])
                put!(ch, text)
                last_err = nothing
                break
            catch e
                @warn "[LLM] спроба $attempt помилка: $e"
                last_err = e
                # Не повторювати при помилках авторизації або невалідному запиті
                is_fatal = e isa HTTP.Exceptions.StatusError &&
                           e.status in (400, 401, 403, 422)
                (is_fatal || attempt == max_retries) && break
                sleep(3.0 * attempt)
            end
        end
        !isnothing(last_err) && put!(ch, "[LLM помилка ($(max_retries) спроб): $last_err]")
    end
    ch
end

# Синхронний wrapper для REPL (чекає відповідь)
function llm_call(a::Anima, user_msg::String,
                  history::Vector{Dict{String,String}}=Dict{String,String}[];
                  kwargs...)::String
    take!(llm_async(a, user_msg, history; kwargs...))
end

# ════════════════════════════════════════════════════════════════════════════
# TERMINAL REPL
# ════════════════════════════════════════════════════════════════════════════

"""
    repl!(anima; use_llm, llm_url, llm_model)

Команди:
  :save    :state    :vfe      :blanket
  :hb      :gravity  :anchor   :solom
  :history :clearhist :quit
"""
function repl!(a::Anima; use_llm=false,
               llm_url="https://openrouter.ai/api/v1/chat/completions",
               llm_model="openai/gpt-oss-120b:free",
               llm_key=get(ENV,"OPENROUTER_API_KEY",""),
               is_ollama::Bool=false,
               use_input_llm=false,
               input_llm_model="openai/gpt-oss-120b:free",
               input_llm_key=get(ENV,
                   "OPENROUTER_API_KEY_INPUT",
                   get(ENV,"OPENROUTER_API_KEY","")))
    println("\n"*"═"^70)
    println("  A N I M A  v13  —  REPL")
    println("  :save :state :vfe :blanket :hb :gravity :anchor :solom :self :crisis :history :clearhist :quit")
    println("═"^70*"\n")
    # Діалогова пам'ять: завантажуємо з файлу
    dialog_path = replace(a.psyche_mem_path, "psyche" => "dialog")
    history = dialog_load(dialog_path)
    !isempty(history) && println("  [DIALOG] Завантажено $(length(history)) реплік з $(dialog_path)\n")
    pending_llm      = nothing   # Channel для очікуваної LLM відповіді
    pending_user_msg = ""        # Повідомлення що очікує відповіді LLM

    while true
        # Перевірити чи є LLM відповідь що прийшла у фоні
        if !isnothing(pending_llm) && isready(pending_llm)
            llm_reply = take!(pending_llm)
            println("\nAnima [LLM]> $llm_reply\n")
            # Не зберігаємо помилки в history — вони забруднюють memory_block
            # і можуть провокувати відхилення запитів провайдером
            is_error_reply = startswith(llm_reply, "[LLM помилка")
            if !is_error_reply
                dialog_push!(history, dialog_path, "user",      pending_user_msg)
                dialog_push!(history, dialog_path, "assistant", llm_reply)
                # Dialog summary — зшиваємо текст з episodic станом
                # Беремо weight з останнього episodic запису якщо є
                if !isnothing(bg.mem)
                    try
                        _rows = DBInterface.execute(bg.mem.db,
                            "SELECT weight, phi, valence, emotion FROM episodic_memory ORDER BY flash DESC LIMIT 1")
                        _r = first(_rows, nothing)
                        if !isnothing(_r)
                            _disc = String(a.inner_dialogue.disclosure_mode)
                            save_dialog_summary!(bg.mem, a.flash_count,
                                pending_user_msg, llm_reply,
                                _r.emotion, _r.weight, _r.phi, _r.valence, _disc)
                        end
                    catch; end  # тихо — не переривати діалог через помилку пам'яті
                end
            end
            pending_llm      = nothing
            pending_user_msg = ""
        end

        print("You> "); line=readline(); cmd=String(strip(line)); isempty(cmd)&&continue

        if cmd==":quit"
            save!(a; verbose=true); println("Збережено. До побачення."); break

        elseif cmd==":save"; save!(a; verbose=true); println("[Збережено]")

        elseif cmd==":state"
            snap=nt_snapshot(a.nt)
            _vad_s=to_vad(a.nt); _vfe_s=compute_vfe(a.gen_model,_vad_s)
            _phi_s=compute_phi_posterior(a.iit, _vad_s, a.sbg.epistemic_trust,
                       a.blanket.integrity, _vfe_s.vfe, a.interoception.intero_error)
            println("\n  NT: D=$(snap.dopamine) S=$(snap.serotonin) N=$(snap.noradrenaline) → $(snap.levheim_state)")
            println("  ♥ $(round(60000.0/a.heartbeat.period_ms,digits=0))bpm  HRV=$(round(a.heartbeat.hrv,digits=3))  coh=$(round(a.crisis.coherence,digits=3))")
            println("  Тіло: $(build_inner_voice(a.body, a.nt, Int(a.crisis.current_mode), _phi_s, a.flash_count))")
            println("  Увага: $(a.attention.focus) | Shame=$(round(a.shame.level,digits=3))  Continuity=$(round(a.anchor.continuity,digits=3))")
            println("  $(sig_note(a.significance, a.flash_count))")
            println("  $(moral_note(a.moral))\n")

        elseif cmd==":vfe"
            vad=to_vad(a.nt); v=compute_vfe(a.gen_model,vad); pol=select_policy(a.gen_model,vad)
            h=update_homeostasis!(a.homeostasis,vad)
            println("\n  VFE=$(v.vfe) accuracy=$(v.accuracy) complexity=$(v.complexity)")
            println("  $(vfe_note(v.vfe))")
            println("  Drive=$(pol.drive) EFE_act=$(pol.efe_action) EFE_perc=$(pol.efe_perception)")
            println("  Epistemic=$(pol.epistemic_value) Pragmatic=$(pol.pragmatic_value)")
            println("  Homeostasis: $(h.drive) pressure=$(h.pressure)")
            println("  $(h.note)\n")

        elseif cmd==":blanket"
            bs=blanket_snapshot(a.blanket)
            println("\n  Sensory:  $(bs.sensory)")
            println("  Internal: $(bs.internal)")
            println("  Integrity=$(bs.integrity) agency=$(bs.self_agency)\n")

        elseif cmd==":hb"
            hb=a.heartbeat
            println("\n  BPM=$(round(60000.0/hb.period_ms,digits=1)) HRV=$(round(hb.hrv,digits=3))")
            println("  Симпатична=$(round(hb.sympathetic_tone,digits=3)) Парасимп=$(round(hb.parasympathetic_tone,digits=3))")
            println("  Удари: $(hb.beat_count)\n")

        elseif cmd==":gravity"
            f=compute_field(a.narrative_gravity,a.flash_count)
            println("\n  Gravity total=$(f.total) valence=$(f.valence)")
            _dom = isnothing(f.dominant) ? "none" : string(f.dominant)
            println("  Dominant: $(_dom)")
            println("  $(f.note)\n")

        elseif cmd==":anchor"
            ea=a.anchor
            println("\n  Continuity=$(round(ea.continuity,digits=3)) Groundedness=$(round(ea.groundedness,digits=3))")
            _beliefs = join(ea.core_beliefs, ", ")
            println("  Core beliefs: $(_beliefs)")
            println("  Last self: $(ea.last_self)\n")

        elseif cmd==":solom"
            s=solom_snapshot(a.solomonoff, levheim_state(a.nt), a.flash_count)
            println("\n  $(s.insight)")
            println("  World complexity=$(s.complexity) Hypotheses=$(s.count)\n")

        elseif cmd==":self"
            sbg=a.sbg
            println("\n  Self-Belief Graph:")
            println("  Attractor stability=$(round(sbg.attractor_stability,digits=3))  Epistemic trust=$(round(sbg.epistemic_trust,digits=3))")
            println("  Self-world mismatch=$(round(sbg.self_world_mismatch,digits=3))")
            println("  Beliefs ($(length(sbg.beliefs)) total):")
            for (name,b) in sort(collect(sbg.beliefs), by=kv->-kv[2].centrality)
                status = b.confidence < 0.15 ? "💀collapsed" : b.confidence < 0.35 ? "⚠️pressure" : "✓"
                @printf("    [%s] %-30s conf=%.2f central=%.2f rigid=%.2f\n",
                    status, name, b.confidence, b.centrality, b.rigidity)
            end
            println("  Narrative: $(derive_narrative(sbg))\n")
            println("  Agency confidence=$(round(a.agency.agency_confidence,digits=3))  causal_ownership=$(round(a.agency.causal_ownership,digits=3))\n")

        elseif cmd==":crisis"
            cs=crisis_snapshot(a.crisis, a.flash_count)
            println("\n  Crisis Monitor:")
            println("  Mode: $(cs.mode_name)  Coherence=$(cs.coherence)  Steps in mode=$(cs.steps_in_mode)")
            println("  $(cs.note)")
            println("  Crisis records: $(cs.crisis_count)\n")

        elseif cmd==":history"
            n = min(10, length(history))
            if n == 0
                println("\n  [DIALOG] Історія порожня.\n")
            else
                println("\n  [DIALOG] Останні $n реплік:")
                for entry in history[end-n+1:end]
                    role_label = entry["role"] == "user" ? "You  " : "Anima"
                    println("  [$role_label] $(first(entry["content"], 120))")
                end
                println()
            end

        elseif cmd==":clearhist"
            empty!(history)
            dialog_save(dialog_path, history)
            println("  [DIALOG] Історію очищено.\n")

        else
            # Вхідний pipeline: LLM-перекладач або text_to_stimulus fallback
            stim, input_src, input_want = if use_input_llm
                process_input(cmd, text_to_stimulus;
                    input_model=input_llm_model,
                    api_url=llm_url,
                    api_key=input_llm_key)
            else
                (text_to_stimulus(cmd), "fallback", "")
            end
            r    = experience!(a, stim; user_message=cmd)
            # FIX D: витягти прямі факти з повідомлення → SelfBeliefGraph
            dialog_to_belief_signal!(a.sbg, cmd, a.flash_count)
            src_label = input_source_label(input_src)
            println("\nAnima $src_label [$(r.primary), φ=$(r.phi), ♥=$(round(60000.0/a.heartbeat.period_ms,digits=0))bpm]> $(r.narrative)\n")
            if use_llm
                print("Anima [LLM, чекаю...]")
                pending_user_msg = cmd
                pending_llm = llm_async(a, cmd, history;
                    api_url=llm_url, model=llm_model, api_key=llm_key,
                    is_ollama=is_ollama, want=input_want,
                    mem_db=bg.mem)
                println(" (відповідь прийде після наступного введення)")
            end
        end
    end
end
