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
        UnknownRegister(), AuthenticityMonitor(),
        SelfBeliefGraph(), SelfPredictiveModel(), AgencyLoop(), InterSessionConflict(),
        CrisisMonitor(),
        0, psyche_mem_path)
    # Завантажити
    saved = core_load!(a.core_mem, a.personality, a.temporal, a.gen_model,
                       a.homeostasis, a.heartbeat, a.interoception, a.anchor)
    psyche_load!(a.psyche_mem_path, a.narrative_gravity, a.anticipatory,
                 a.solomonoff, a.shame, a.epistemic_defense, a.chronified,
                 a.significance, a.moral, a.fatigue, a.sig_layer, a.goal_conflict,
                 a.latent_buffer, a.structural_scars)
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
                 a.latent_buffer, a.structural_scars)
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

    # IIT φ
    phi = compute_phi(a.iit, vad, t, c)

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

    # [T2] Narrative Gravity
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
                                  a.flash_count, a.temporal.gap_seconds, phi)

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
        solom         = solom_snapshot(a.solomonoff),
        shame         = shame_snapshot(a.shame),
        ep_defense    = ep_def,
        symptom       = symptom,
        chronified    = ca_snapshot(a.chronified),
        significance  = (total=Float64(sig_total(a.significance)),
                         dominant=sig_dominant(a.significance),note=sig_note(a.significance)),
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
        narrative     = build_narrative(a, named, t_adj, a_r, s_adj, c_adj,
                                         phi, ac_snap, vfe_r.vfe, grav_d.field,
                                         intero_snap, anchor_snap, homeo_snap,
                                         self_snap, crisis_snap),
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
                          self_snap=nothing, crisis_snap=nothing)::String
    base = t>0.7 ? "Відчуваю напругу. $named." : t<0.2 ? "Спокійно. $named." : "$named."
    notes = String[]
    !isempty(a.temporal.subjective_note)        && push!(notes, a.temporal.subjective_note)
    !isempty(a.temporal.circadian_note)         && push!(notes, a.temporal.circadian_note)
    !isempty(String(grav_field.note))           && push!(notes, String(grav_field.note))
    !isempty(ac_snap.note)                      && push!(notes, ac_snap.note)
    vfe > 0.5                                   && push!(notes, vfe_note(vfe))
    phi > 0.3 && !isempty(String(a.solomonoff.best===nothing ? "" : "Знаю: '$(a.solomonoff.best.pattern)'.")) &&
        push!(notes, "Знаю: '$(a.solomonoff.best.pattern)'.")
    !isempty(ca_note(a.chronified))             && push!(notes, ca_note(a.chronified))
    !isempty(sig_note(a.significance))          && push!(notes, sig_note(a.significance))
    !isempty(String(intero_snap.note))          && push!(notes, String(intero_snap.note))
    anchor_snap.continuity < 0.4               && push!(notes, String(anchor_snap.note))
    homeo_snap.pressure > 0.3                  && push!(notes, homeostasis_note(a.homeostasis))
    # FIX C: build_inner_voice замість somatic_marker
    sm = build_inner_voice(a.body, a.nt, Int(a.crisis.current_mode), phi)
    sm != "тіло нейтральне"                    && push!(notes, uppercase(safe_first(sm,1))*sm[nextind(sm,1):end]*".")
    !isempty(shame_note(a.shame))              && push!(notes, shame_note(a.shame))
    # Crisis and self notes
    if !isnothing(crisis_snap)
        !isempty(String(crisis_snap.note)) && push!(notes, String(crisis_snap.note))
    end
    if !isnothing(self_snap)
        !isempty(String(self_snap.self_pred.note)) && push!(notes, String(self_snap.self_pred.note))
        !isempty(String(self_snap.agency.note))    && push!(notes, String(self_snap.agency.note))
    end
    isempty(notes) ? base : base*" "*join(filter(!isempty,notes)," ")
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

    @printf("[#%04d] %-18s D=%.2f S=%.2f N=%.2f ▸%-11s φ=%.2f\n",
        r.flash_count, r.primary, r.nt.dopamine, r.nt.serotonin,
        r.nt.noradrenaline, r.levheim, r.phi)
    @printf("       VFE=%.2f[%s] BPM=%.0f HRV=%.2f Attn=%.2f G=%.2f ↑%.2f H=%.2f%s%s%s\n",
        r.vfe, r.ai_drive[1:min(3,end)], r.heartbeat.bpm, r.heartbeat.hrv,
        r.attention.radius, r.gravity_total, r.anticip_strength,
        r.homeostasis.pressure, ep_str, sym_str, def_str)
    @printf("       Self: spe=%.2f agency=%.2f stab=%.2f etrust=%.2f | Crisis: [%s] coh=%.2f\n",
        r.self_pred_error, r.self_agency, r.sbg_stability, r.sbg_epistemic,
        r.crisis_mode, r.crisis_coherence)
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
const DIALOG_KEEP = 200  # реплік у файлі
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
Зібрати знімок стану ядра у простий NamedTuple для підстановки в шаблон.
Усі поля — примітиви (Float64 / String / Int), жодних посилань на Anima.
"""
function anima_state_snapshot(a::Anima)
    hb  = a.heartbeat
    cs  = crisis_snapshot(a.crisis)
    emo = nt_snapshot(a.nt)
    vad = to_vad(a.nt)
    sg  = belief_geometry(a.sbg)
    t_, _, _, c_ = to_reactors(a.nt)
    phi = compute_phi(a.iit, vad, t_, c_)
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
        inner_voice         = build_inner_voice(a.body, a.nt, Int(a.crisis.current_mode), phi),
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
    prompt = replace(prompt, "{inferred_external}"   => string(state.inferred_external))
    prompt = replace(prompt, "{shame}"                => string(state.shame))
    prompt = replace(prompt, "{continuity}"           => string(state.continuity))
    prompt = replace(prompt, "{homeostasis_note}"     => state.homeostasis_note)
    prompt = replace(prompt, "{time_str}"             => state.time_str)
    prompt = replace(prompt, "{circadian_note}"       => state.circadian_note)
    prompt = replace(prompt, "{flash_count}"          => string(state.flash_count))
    prompt = replace(prompt, "{memory_block}"         => memory_block)
    prompt = replace(prompt, "{user_input}"           => user_input)
    prompt = replace(prompt, "{want}"               => isempty(want) ? "не визначено" : want)
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
                             want::String="")::Vector{Dict{String,String}}
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
    # Якщо memory_block не передано явно — генеруємо з history
    mem = isempty(memory_block) ? history_to_memory_block(history) : memory_block
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
                   model="google/gemini-2.5-pro-exp-03-25",
                   api_key="",
                   is_ollama::Bool=false,
                   want::String="")::Channel{String}
    ch = Channel{String}(1)
    # Збираємо messages до spawn — не захоплюємо Anima у thread
    messages = build_llm_messages(a, user_msg, history; want=want)
    Threads.@spawn begin
        # Евристика як fallback — якщо is_ollama не вказано явно
        _is_ollama = is_ollama || contains(api_url,"11434") || contains(api_url,"ollama")
        headers    = ["Content-Type"=>"application/json"]
        !isempty(api_key) && push!(headers,"Authorization"=>"Bearer $api_key")
        body       = _is_ollama ?
            JSON3.write(Dict("model"=>model,"messages"=>messages,"stream"=>false)) :
            JSON3.write(Dict("model"=>model,"messages"=>messages,"max_tokens"=>800))
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
               llm_model="google/gemini-2.5-pro-exp-03-25",
               llm_key=get(ENV,"OPENROUTER_API_KEY",""),
               is_ollama::Bool=false,
               use_input_llm=false,
               input_llm_model="anthropic/claude-3-5-sonnet",
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
            println("\n  NT: D=$(snap.dopamine) S=$(snap.serotonin) N=$(snap.noradrenaline) → $(snap.levheim_state)")
            println("  Тіло: $(build_inner_voice(a.body, a.nt, Int(a.crisis.current_mode), compute_phi(a.iit, to_vad(a.nt), to_reactors(a.nt)[1], to_reactors(a.nt)[4])))")
            println("  Серце: $(round(60000.0/a.heartbeat.period_ms,digits=0)) bpm  HRV=$(round(a.heartbeat.hrv,digits=3))")
            println("  Увага: $(a.attention.focus)")
            println("  Сором=$(round(a.shame.level,digits=3))  Continuity=$(round(a.anchor.continuity,digits=3))")
            println("  $(sig_note(a.significance))")
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
            s=solom_snapshot(a.solomonoff)
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
            cs=crisis_snapshot(a.crisis)
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
            println("\nAnima $src_label [$(r.primary), φ=$(r.phi)]> $(r.narrative)\n")
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
end

# ════════════════════════════════════════════════════════════════════════════
# DEMO
# ════════════════════════════════════════════════════════════════════════════

if abspath(PROGRAM_FILE)==@__FILE__
    println("╔══════════════════════════════════════════════════════════════════════════╗")
    println("║              A N I M A  v13  (Julia)  —  три файли                      ║")
    println("║  core.jl: мінімальна умова існування суб'єкта                          ║")
    println("║  psyche.jl: психічна тканина — те що робить стан значущим             ║")
    println("║  interface.jl: вивід, LLM, REPL — жодного side effect на психіку      ║")
    println("╚══════════════════════════════════════════════════════════════════════════╝\n")

    persona = Personality(neuroticism=0.65,extraversion=0.50,agreeableness=0.68,
                          conscientiousness=0.55,openness=0.82,confabulation_rate=0.55)
    vals    = ValueSystem(autonomy=0.7,care=0.85,fairness=0.65,integrity=0.85,growth=0.75)
    anima   = Anima(personality=persona,values=vals)

    println("  Час: $(anima.temporal.time_str) — $(anima.temporal.circadian_note)\n")

    scenarios = [
        ("Публічна помилка",
         Dict("tension"=>0.5,"arousal"=>0.4,"satisfaction"=>-0.4,"cohesion"=>-0.5),
         "щось пішло не так..."),
        ("Та сама помилка знову",
         Dict("tension"=>0.5,"arousal"=>0.3,"satisfaction"=>-0.3,"cohesion"=>-0.3),
         "знову те саме. Завжди так."),
        ("Тривала несправедливість",
         Dict("tension"=>0.4,"satisfaction"=>-0.4,"cohesion"=>-0.3),
         "чому іншим все дається легше?"),
        ("Підтримка",
         Dict("cohesion"=>0.5,"satisfaction"=>0.3,"tension"=>-0.2),
         "ти справді намагаєшся. Це важливо."),
        ("Момент тиші",
         Dict("tension"=>-0.1,"cohesion"=>0.1,"satisfaction"=>0.1),
         "просто хотів спитати як ти"),
    ]

    for (label,delta,msg) in scenarios
        println("─"^70); println("  $label  |  \"$msg\""); println("─"^70)
        r = experience!(anima, delta; user_message=msg)
        println("  Наратив: \"$(first(r.narrative, 90))\"")
        println("  φ=$(r.phi)  VFE=$(r.vfe)  BPM=$(round(Float64(r.heartbeat.bpm),digits=0))  HRV=$(r.heartbeat.hrv)")
        println("  Continuity=$(r.anchor.continuity)  Homeostasis: $(r.homeostasis.drive)")
        println("  Self: spe=$(r.self_pred_error)  agency=$(r.self_agency)  stab=$(r.sbg_stability)")
        println("  Crisis: [$(r.crisis_mode)] coherence=$(r.crisis_coherence)")
        println()
    end

    println("═"^70)
    save!(anima; summary="Demo v13 — 3-file architecture", verbose=true)
    println("\nAnima v13 готова.")
    println("REPL:     repl!(anima)")
    println("LLM REPL: repl!(anima; use_llm=true)  # ENV[\"OPENROUTER_API_KEY\"]=\"sk-...\"")
    println("Ollama:   repl!(anima; use_llm=true, llm_url=\"http://localhost:11434/api/chat\", llm_model=\"llama3.2:3b\")")
end
