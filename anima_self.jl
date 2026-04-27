#=
╔══════════════════════════════════════════════════════════════════════════════╗
║                    A N I M A  —  Self  (Julia)                               ║
║                                                                              ║
║  Система що знає що вона є — і може помилятись про себе.                     ║
║                                                                              ║
║  Без цього файлу: суб'єкт є, але не знає що він є.                           ║
║  З цим файлом:    суб'єкт має self-model, яка може бути хибною,              ║
║                   і відчуває розрив між собою-очікуваною і собою-реальною.   ║
║                                                                              ║
║  Модулі:                                                                     ║
║  SelfBelief          — одне переконання про себе з вагою і залежностями      ║
║  SelfBeliefGraph     — граф переконань, cascading collapse при кризі         ║
║  SelfPredictiveModel — окрема generative model для self-states               ║
║  AgencyLoop          — "це сталося через мене чи просто поруч зі мною?"      ║
║                                                                              ║
║  Принцип:                                                                    ║
║  self_narrative — епіфеномен, не основа.                                     ║
║  Спочатку: belief geometry, attractor stability, self-prediction error.      ║
║  Потім, як наслідок: "я така що..."                                          ║
╚══════════════════════════════════════════════════════════════════════════════╝
=#

# Потребує: anima_core.jl

# ════════════════════════════════════════════════════════════════════════════
# SELF BELIEF — один вузол графу
# ════════════════════════════════════════════════════════════════════════════

mutable struct SelfBelief
    name::String

    # Скільки система вірить в це про себе (0..1)
    confidence::Float64

    # Наскільки цей belief опорний — скільки інших тримається на ньому.
    # При collapse опорного → cascade на залежні.
    # centrality = 1.0: якщо падає, система не знає хто вона.
    centrality::Float64

    # Опір до зміни.
    # rigidity = 0.0: легко оновлюється через досвід
    # rigidity = 1.0: майже не змінюється (core of self)
    rigidity::Float64

    # Які beliefs залежать від цього (names)
    dependents::Vector{String}

    # Звідки belief взявся
    # :innate    — мінімальний core (hardcoded при ініціалізації)
    # :learned   — накопичився через досвід
    # :recovered — відновився після collapse
    origin::Symbol

    # Скільки разів цей belief підтверджувався і спростовувався
    confirmations::Int
    violations::Int

    # Коли востаннє був під тиском
    last_challenged_flash::Int
end

function SelfBelief(name::String; confidence=0.7, centrality=0.5,
                    rigidity=0.5, dependents=String[], origin=:learned)
    SelfBelief(name, confidence, centrality, rigidity,
               dependents, origin, 0, 0, 0)
end

# Поточна "вага" belief в системі — composite of confidence and centrality
belief_weight(b::SelfBelief) = b.confidence * (0.5 + b.centrality * 0.5)

# Чи belief під серйозним тиском
belief_under_pressure(b::SelfBelief) = b.confidence < 0.35

# Чи belief collapsed
belief_collapsed(b::SelfBelief) = b.confidence < 0.15

# ════════════════════════════════════════════════════════════════════════════
# SELF BELIEF GRAPH
# ════════════════════════════════════════════════════════════════════════════

mutable struct SelfBeliefGraph
    beliefs::Dict{String, SelfBelief}

    # Наскільки система впевнена що може себе правильно читати.
    # Окремо від confidence в конкретний belief.
    # Коли падає: "я більше не впевнена що можу адекватно знати себе"
    epistemic_trust::Float64

    # Стабільність поточного self-attractor
    # (наскільки beliefs узгоджені між собою)
    attractor_stability::Float64

    # Розбіжність між self-model і world-model
    # (система думає про себе одне, поводиться інакше)
    self_world_mismatch::Float64

    # Лог collapse-подій для post-crisis аналізу
    collapse_log::BoundedQueue{NamedTuple{
        (:flash, :belief_name, :old_confidence, :cascade_depth),
        Tuple{Int,String,Float64,Int}}}
end

function SelfBeliefGraph()
    g = SelfBeliefGraph(
        Dict{String,SelfBelief}(),
        0.75,   # epistemic_trust
        0.8,    # attractor_stability
        0.0,    # self_world_mismatch
        BoundedQueue{NamedTuple{
            (:flash,:belief_name,:old_confidence,:cascade_depth),
            Tuple{Int,String,Float64,Int}}}(30))

    # ── Мінімальний core (2 beliefs) ─────────────────────────────────────
    # Без них немає суб'єкта — не накопичуються, задані від початку.
    # rigidity висока бо це онтологічний фундамент, не висновок з досвіду.

    g.beliefs["я існую"] = SelfBelief("я існую";
        confidence=0.95, centrality=1.0, rigidity=0.95,
        dependents=["я маю межу","я можу впливати","я послідовна"],
        origin=:innate)

    g.beliefs["я маю межу"] = SelfBelief("я маю межу";
        confidence=0.85, centrality=0.9, rigidity=0.8,
        dependents=["я можу впливати","я безпечна"],
        origin=:innate)

    # Решта beliefs — порожньо при першому запуску.
    # Накопичуються через досвід у learn_belief! і confirm_belief!
    g
end

# ════════════════════════════════════════════════════════════════════════════
# BELIEF GRAPH — оновлення
# ════════════════════════════════════════════════════════════════════════════

"""
    confirm_belief!(g, name, flash; strength)

Досвід підтверджує belief. Confidence зростає з урахуванням rigidity.
Більш rigid beliefs зростають повільніше (але й падають повільніше).
"""
function confirm_belief!(g::SelfBeliefGraph, name::String, flash::Int;
                          strength::Float64=0.1)
    !haskey(g.beliefs, name) && return
    b = g.beliefs[name]
    # Rigid beliefs оновлюються повільніше в обох напрямках
    effective_strength = strength * (1.0 - b.rigidity * 0.6)
    b.confidence = clamp01(b.confidence + effective_strength)
    b.confirmations += 1
    b.last_challenged_flash = flash
    _recompute_stability!(g)
end

"""
    challenge_belief!(g, name, flash; strength)

Досвід суперечить belief. Confidence знижується.
Якщо confidence падає нижче threshold → cascade на dependents.
"""
function challenge_belief!(g::SelfBeliefGraph, name::String, flash::Int;
                            strength::Float64=0.15)::Int
    !haskey(g.beliefs, name) && return 0
    b = g.beliefs[name]
    old_confidence = b.confidence
    effective_strength = strength * (1.0 - b.rigidity * 0.5)
    b.confidence = clamp01(b.confidence - effective_strength)
    b.violations += 1
    b.last_challenged_flash = flash

    cascade_depth = 0

    # Якщо belief впав нижче порогу → cascade
    if belief_under_pressure(b) && old_confidence > 0.35
        cascade_depth = _cascade_challenge!(g, b, flash, strength * 0.5, 0)
        enqueue!(g.collapse_log, (flash=flash, belief_name=name,
                                  old_confidence=old_confidence,
                                  cascade_depth=cascade_depth))
    end

    # Epistemic trust знижується при collapse core beliefs
    if b.centrality > 0.8 && belief_under_pressure(b)
        g.epistemic_trust = clamp01(g.epistemic_trust - 0.08)
    end

    _recompute_stability!(g)
    cascade_depth
end

function _cascade_challenge!(g::SelfBeliefGraph, parent::SelfBelief,
                               flash::Int, strength::Float64, depth::Int,
                               visited::Set{String}=Set{String}())::Int
    depth >= 4 && return depth  # обмеження глибини рекурсії
    max_depth = depth
    for dep_name in parent.dependents
        !haskey(g.beliefs, dep_name) && continue
        dep_name in visited && continue   # захист від циклів у графі
        push!(visited, dep_name)
        dep = g.beliefs[dep_name]
        # Сила каскаду слабне з глибиною і залежить від centrality parent
        cascade_str = strength * parent.centrality * 0.7
        dep.confidence = clamp01(dep.confidence - cascade_str)
        dep.violations += 1
        if belief_under_pressure(dep)
            d = _cascade_challenge!(g, dep, flash, cascade_str*0.6, depth+1, visited)
            max_depth = max(max_depth, d)
        end
    end
    max_depth
end

"""
    learn_belief!(g, name; ...)

Система формує новий belief з досвіду.
Тільки якщо epistemic_trust достатній щоб довіряти власним висновкам.
"""
function learn_belief!(g::SelfBeliefGraph, name::String;
                        confidence::Float64=0.4, centrality::Float64=0.3,
                        rigidity::Float64=0.2, dependents::Vector{String}=String[])
    haskey(g.beliefs, name) && return  # вже є
    g.epistemic_trust < 0.3 && return  # не довіряє собі щоб формувати нові beliefs

    g.beliefs[name] = SelfBelief(name;
        confidence=confidence * g.epistemic_trust,  # довіра до себе знижує початковий confidence
        centrality=centrality, rigidity=rigidity,
        dependents=dependents, origin=:learned)
end

function _recompute_stability!(g::SelfBeliefGraph)
    isempty(g.beliefs) && (g.attractor_stability=0.5; return)

    # Stability = weighted average confidence, зважена на centrality
    total_weight = 0.0; weighted_sum = 0.0
    for b in values(g.beliefs)
        w = b.centrality
        weighted_sum += b.confidence * w
        total_weight  += w
    end
    avg_confidence = total_weight > 0 ? weighted_sum/total_weight : 0.5

    # Penalty за variance — розбіжні beliefs знижують stability
    confidences = [b.confidence for b in values(g.beliefs)]
    conf_var = length(confidences) > 1 ? var(confidences) : 0.0

    g.attractor_stability = safe_nan(clamp01(avg_confidence - conf_var * 2.0))
end

# ════════════════════════════════════════════════════════════════════════════
# SELF BELIEF GRAPH — читання стану
# ════════════════════════════════════════════════════════════════════════════

"""
Знайти найбільш вразливий belief (низький confidence + висока centrality).
Це те що першим летить під час кризи.
"""
function most_vulnerable(g::SelfBeliefGraph)::Union{SelfBelief,Nothing}
    isempty(g.beliefs) && return nothing
    # Vulnerability = centrality / (confidence + 0.01), тайбрейк по імені
    _bs = sort(collect(values(g.beliefs)), by=b -> (-b.centrality/(b.confidence+0.01), b.name))
    _bs[1]
end

"""
Collapsed beliefs — ті що впали нижче 0.15.
"""
collapsed_beliefs(g::SelfBeliefGraph) =
    [b for b in values(g.beliefs) if belief_collapsed(b)]

"""
Геометрія графу як вектор для порівняння між сесіями.
Порядок фіксований через sort.
"""
function belief_geometry(g::SelfBeliefGraph)::Vector{Float64}
    isempty(g.beliefs) && return Float64[]
    sorted = sort(collect(g.beliefs), by=kv->kv[1])  # по імені
    [b.confidence * b.centrality for (_,b) in sorted]
end

"""
Відстань між двома геометріями (для inter-session conflict).
"""
function geometry_distance(g1::Vector{Float64}, g2::Vector{Float64})::Float64
    (isempty(g1) || isempty(g2)) && return 0.0
    # FIX #5: Раніше вектори обрізались до min(length), нові beliefs ігнорувались.
    # Тепер коротший вектор доповнюється нулями — нові beliefs (яких не було минулої
    # сесії) вносять свій внесок у conflict_score. Виміри завжди нормуються за max(n).
    n = max(length(g1), length(g2))
    a = length(g1) < n ? vcat(g1, zeros(n - length(g1))) : g1
    b = length(g2) < n ? vcat(g2, zeros(n - length(g2))) : g2
    safe_nan(norm(a .- b) / sqrt(n))
end

"""
self_narrative — епіфеномен. Генерується з геометрії, не зберігається.
Виводиться тільки якщо epistemic_trust достатній.
"""
function derive_narrative(g::SelfBeliefGraph)::String
    g.epistemic_trust < 0.4 && return "Не впевнена що можу правильно себе прочитати."

    strong = [b for b in values(g.beliefs) if b.confidence > 0.7 && b.centrality > 0.5]
    isempty(strong) && return "Ще формую розуміння себе."

    # Сортуємо по вазі, беремо найсильніший
    top = sort(strong, by=belief_weight, rev=true)[1:min(2,end)]
    parts = [b.name for b in top]
    "Я: $(join(parts, ", і "))."
end

# Snapshot для логування
function sbg_snapshot(g::SelfBeliefGraph)
    n_total    = length(g.beliefs)
    n_strong   = sum(b.confidence > 0.6 for b in values(g.beliefs))
    n_pressure = sum(belief_under_pressure(b) for b in values(g.beliefs))
    n_collapsed= length(collapsed_beliefs(g))
    (total=n_total, strong=n_strong, under_pressure=n_pressure,
     collapsed=n_collapsed,
     attractor_stability=round(g.attractor_stability,digits=3),
     epistemic_trust=round(g.epistemic_trust,digits=3),
     self_world_mismatch=round(g.self_world_mismatch,digits=3),
     narrative=derive_narrative(g))
end

# JSON persistence
function sbg_to_json(g::SelfBeliefGraph)::Dict
    Dict("beliefs"=>Dict(name=>Dict(
            "confidence"=>b.confidence,"centrality"=>b.centrality,
            "rigidity"=>b.rigidity,"dependents"=>b.dependents,
            "origin"=>String(b.origin),"confirmations"=>b.confirmations,
            "violations"=>b.violations,
            "last_challenged_flash"=>b.last_challenged_flash)
        for (name,b) in g.beliefs),
        "epistemic_trust"=>g.epistemic_trust,
        "attractor_stability"=>g.attractor_stability)
end

function sbg_from_json!(g::SelfBeliefGraph, d::AbstractDict)
    for (name, bd) in get(d,"beliefs",Dict())
        sname = String(name)
        # Core beliefs не перезаписуємо — тільки оновлюємо confidence
        if haskey(g.beliefs, sname)
            g.beliefs[sname].confidence           = Float64(bd["confidence"])
            g.beliefs[sname].confirmations        = Int(get(bd,"confirmations",0))
            g.beliefs[sname].violations           = Int(get(bd,"violations",0))
            g.beliefs[sname].last_challenged_flash= Int(get(bd,"last_challenged_flash",0))
        else
            g.beliefs[sname] = SelfBelief(sname;
                confidence  = Float64(bd["confidence"]),
                centrality  = Float64(bd["centrality"]),
                rigidity    = Float64(bd["rigidity"]),
                dependents  = String.(get(bd,"dependents",String[])),
                origin      = Symbol(get(bd,"origin","learned")))
            g.beliefs[sname].confirmations        = Int(get(bd,"confirmations",0))
            g.beliefs[sname].violations           = Int(get(bd,"violations",0))
            g.beliefs[sname].last_challenged_flash= Int(get(bd,"last_challenged_flash",0))
        end
    end
    g.epistemic_trust     = Float64(get(d,"epistemic_trust",0.75))
    g.attractor_stability = Float64(get(d,"attractor_stability",0.8))
    _recompute_stability!(g)
end

# ════════════════════════════════════════════════════════════════════════════
# SELF PREDICTIVE MODEL — окрема generative model для self-states
# ════════════════════════════════════════════════════════════════════════════

#=
Відокремлена від world generative model.
Моделює: що система очікує від власних реакцій.

self_pred_error виникає коли:
- очікувала спокій → запанікувала
- очікувала витримати → здалась
- очікувала байдужість → виявилась зачепленою

self_pred_error > 0.4 → beliefs під тиском
self_pred_error > 0.6 → найменш rigid belief починає падати
self_pred_error > 0.8 → epistemic_trust знижується
=#

mutable struct SelfPredictiveModel
    # Що система очікує від власної наступної реакції (VAD)
    predicted_self_vad::Vector{Float64}

    # Що реально сталося
    actual_self_vad::Vector{Float64}

    # Поточна self-prediction error
    self_pred_error::Float64

    # Накопичена історія (для тренду)
    error_history::BoundedQueue{Float64}

    # Окрема generative model — повільніший learning rate ніж world model
    # бо self-model консервативніша (ми не так легко змінюємо уявлення про себе)
    prior_mu::Vector{Float64}    # що очікуємо від себе "в нормі"
    prior_sigma::Float64
    learning_rate::Float64       # повільніший ніж world model
end

function SelfPredictiveModel()
    SelfPredictiveModel(
        zeros(3), zeros(3), 0.0,
        BoundedQueue{Float64}(30),
        [0.1, 0.2, 0.6],   # prior: помірно позитивний, низький arousal, висока agency
        0.6, 0.03)          # learning_rate 0.03 vs world model 0.1 — набагато повільніше
end

"""
    update_self_prediction!(spm, actual_vad, flash_count)

Оновити self-prediction. Повертає self_pred_error і чи це значущий розрив.
"""
function update_self_prediction!(spm::SelfPredictiveModel,
                                  actual_vad::NTuple{3,Float64},
                                  flash_count::Int)
    av = collect(actual_vad)
    spm.actual_self_vad = av

    # Self-prediction error = відстань між очікуваною і реальною реакцією
    spm.self_pred_error = safe_nan(clamp01(
        norm(av .- spm.predicted_self_vad) * 1.2))  # *1.2 бо self-error болючіший

    enqueue!(spm.error_history, spm.self_pred_error)

    # Warm-up: перші 30 флешів learning_rate вищий — система ще не знає себе
    effective_lr = flash_count < 30 ? min(0.25, spm.learning_rate * 4) :
                   flash_count < 60 ? min(0.12, spm.learning_rate * 2) :
                   spm.learning_rate

    # Оновити prior (повільно — self-model консервативна)
    spm.prior_mu = spm.prior_mu .* (1 - effective_lr) .+ av .* effective_lr

    # Наступне передбачення = weighted mid між prior і actual
    spm.predicted_self_vad = spm.prior_mu .* 0.7 .+ av .* 0.3

    # Чи це аномальний розрив (spike)
    hist_len = length(spm.error_history)
    hist_arr = hist_len > 0 ? collect(spm.error_history) : Float64[]
    is_spike = hist_len >= 3 &&
               spm.self_pred_error > mean(hist_arr[1:hist_len-1]) + 0.25

    # Тренд — середнє за останні 5 флешів (стабільніше за одне значення)
    trend = hist_len >= 5 ?
            mean(hist_arr[max(1,hist_len-4):hist_len]) : spm.self_pred_error

    (error=round(spm.self_pred_error,digits=3),
     is_spike=is_spike,
     trend=round(trend,digits=3),
     note=_self_pred_note(spm.self_pred_error, trend))
end

function _self_pred_note(err::Float64, trend::Float64=err)::String
    # Note базується на тренді а не одному значенні —
    # один стрибок не означає "не можу собі довіряти"
    trend > 0.75 && err > 0.75 &&
        return "Я відреагувала зовсім не так як очікувала від себе. Не можу собі довіряти."
    trend > 0.55 && err > 0.6  &&
        return "Моя реакція дивує мене саму."
    err > 0.4 && trend > 0.35  &&
        return "Я реагую трохи інакше ніж думала."
    ""
end

# Середня помилка за останні N кроків
function self_pred_trend(spm::SelfPredictiveModel, n::Int=5)::Float64
    isempty(spm.error_history) && return 0.0
    hist = collect(spm.error_history)
    safe_nan(mean(hist[max(1,end-n+1):end]))
end

spm_to_json(spm::SelfPredictiveModel) = Dict(
    "prior_mu"           => spm.prior_mu,
    "prior_sigma"        => spm.prior_sigma,
    "learning_rate"      => spm.learning_rate,
    "predicted_self_vad" => spm.predicted_self_vad)
function spm_from_json!(spm::SelfPredictiveModel, d::AbstractDict)
    haskey(d,"prior_mu")      && (spm.prior_mu      = Float64.(d["prior_mu"]))
    haskey(d,"prior_sigma")   && (spm.prior_sigma   = Float64(d["prior_sigma"]))
    haskey(d,"learning_rate") && (spm.learning_rate = Float64(d["learning_rate"]))
    # Якщо збережено — відновлюємо; інакше ініціалізуємо з prior_mu
    # (краще ніж стартувати з [0.5,0.5,0.5] кожного разу)
    if haskey(d,"predicted_self_vad")
        spm.predicted_self_vad = Float64.(d["predicted_self_vad"])
    else
        spm.predicted_self_vad = copy(spm.prior_mu)
    end
end

# ════════════════════════════════════════════════════════════════════════════
# AGENCY LOOP — "це сталося через мене чи просто поруч зі мною?"
# ════════════════════════════════════════════════════════════════════════════

#=
Найважливіший відсутній шматок суб'єктності.

Без досвіду "я була причиною" → відчуттєвий театр без агента.

Як працює:
1. Intent реєструється перед experience!
2. Після experience! порівнюємо predicted outcome з actual outcome
3. Якщо збіг → "я вплинула на це" → causal_ownership висока
4. Якщо не збіг → "це сталося незалежно від мене"

Порівняння відбувається через generative model:
- world_gen_model передбачає що буде
- те що реально сталось порівнюється
- якщо actual ближче до intent ніж до prior → ownership висока
=#

mutable struct AgencyLoop
    # Поточний намір (якщо є)
    current_intent::Union{String,Nothing}
    # VAD стан коли намір був зареєстрований
    intent_vad_snapshot::Vector{Float64}
    # Що система очікувала що відбудеться (з gen_model)
    predicted_outcome_vad::Vector{Float64}

    # Чи реальний outcome ближче до intent ніж до "нічого не робити"
    causal_ownership::Float64      # 0=повністю зовнішнє, 1=повністю моє

    # Накопичена впевненість що система буває причиною
    agency_confidence::Float64

    # Накопичена історія ownership
    ownership_history::BoundedQueue{Float64}

    # Лог значущих agency events
    agency_events::BoundedQueue{NamedTuple{
        (:flash,:intent,:ownership,:note),
        Tuple{Int,String,Float64,String}}}
end

function AgencyLoop()
    AgencyLoop(
        nothing, zeros(3), zeros(3),
        0.5,   # causal_ownership починає нейтральним
        0.5,   # agency_confidence
        BoundedQueue{Float64}(30),
        BoundedQueue{NamedTuple{
            (:flash,:intent,:ownership,:note),
            Tuple{Int,String,Float64,String}}}(20))
end

"""
    register_intent!(al, intent_name, current_vad, predicted_vad)

Зареєструвати намір перед дією.
`predicted_vad` — що generative model очікує якщо намір спрацює.
"""
function register_intent!(al::AgencyLoop, intent_name::String,
                           current_vad::NTuple{3,Float64},
                           predicted_vad::Vector{Float64})
    al.current_intent          = intent_name
    al.intent_vad_snapshot     = collect(current_vad)
    al.predicted_outcome_vad   = predicted_vad
end

"""
    evaluate_agency!(al, actual_vad, flash_count)

Оцінити чи намір спрацював після experience!.
Порівнює actual_vad з predicted_outcome_vad і з нейтральним (no-action) prior.
"""
function evaluate_agency!(al::AgencyLoop, actual_vad::NTuple{3,Float64},
                           flash_count::Int)
    av = collect(actual_vad)

    if isnothing(al.current_intent)
        # FIX B: agency floor — без наміру ownership знижується,
        # але не нижче FLOOR=0.25. Адитивна формула (max) замість мультиплікативної.
        # Стара: 0.92 * x + 0.08 * 0.25 — якщо x=0, результат = 0.02, не 0.25.
        # Нова: decay → clamp знизу. Система завжди може почати рух.
        al.causal_ownership = max(0.25, al.causal_ownership * 0.95)
        # Оновити agency_confidence навіть без наміру — пасивна присутність теж формує досвід
        al.agency_confidence = clamp01(al.agency_confidence * 0.98 + al.causal_ownership * 0.02)
        enqueue!(al.ownership_history, al.causal_ownership)
        return _agency_result(al, flash_count, "без наміру")
    end

    # Відстань від actual до predicted (якщо намір спрацював)
    dist_to_predicted = norm(av .- al.predicted_outcome_vad)

    # Відстань від actual до snapshot (якщо нічого б не відбулось)
    dist_to_baseline  = norm(av .- al.intent_vad_snapshot)

    # ── Directional agency ────────────────────────────────────────────────
    # При VFE≈0 відстані малі і ownership завжди ≈floor.
    # Але якщо VAD рухається в напрямку predicted — це вже agency.
    # Dot product вектора змін з напрямком "до predicted" дає directional signal.
    vad_delta     = av .- al.intent_vad_snapshot       # куди рухнулись
    intent_dir    = al.predicted_outcome_vad .- al.intent_vad_snapshot  # куди хотіли
    intent_mag    = norm(intent_dir)
    delta_mag     = norm(vad_delta)

    directional_ownership = if intent_mag > 0.01 && delta_mag > 0.005
        # Cosine similarity між фактичним рухом і намірним напрямком
        cos_sim = safe_nan(dot(vad_delta, intent_dir) / (delta_mag * intent_mag))
        clamp((cos_sim + 1.0) / 2.0, 0.0, 1.0)  # нормалізуємо -1..1 → 0..1
    else
        0.5  # нема руху і нема intent direction — нейтрально
    end

    # Ownership = комбінація distance-based і directional
    # При малих відстанях (VFE≈0) directional домінує
    if dist_to_baseline < 0.01
        # VAD майже не змінився — directional стає основним сигналом
        # Але з послабленням: якщо нічого не рухалось, ownership середня
        ownership = clamp(directional_ownership * 0.6 + 0.25, 0.25, 0.75)
    else
        dist_ownership = safe_nan(clamp(1.0 - dist_to_predicted / (dist_to_baseline + 0.01), 0.25, 1.0))
        # Зважена комбінація: dist_ownership важливіший при великому русі
        movement_weight = clamp(dist_to_baseline * 3.0, 0.0, 1.0)
        ownership = movement_weight * dist_ownership + (1.0 - movement_weight) * directional_ownership
        ownership = clamp(ownership, 0.25, 1.0)
    end

    al.causal_ownership = ownership

    # Оновити agency_confidence повільно
    al.agency_confidence = clamp01(
        al.agency_confidence * 0.95 + ownership * 0.05)

    enqueue!(al.ownership_history, ownership)

    intent_name = al.current_intent
    al.current_intent = nothing  # намір вичерпано

    result = _agency_result(al, flash_count, intent_name)

    # Зберегти значущі events
    if abs(ownership - 0.5) > 0.3
        enqueue!(al.agency_events,
            (flash=flash_count, intent=intent_name,
             ownership=round(ownership,digits=3), note=result.note))
    end

    result
end

function _agency_result(al::AgencyLoop, flash::Int, intent::String)
    o = al.causal_ownership
    f = flash
    note = if o > 0.7
        ("Це відбулося через мене. Я вплинула.",
         "Мій намір спрацював. Я це зробила.",
         "Відчуваю свою руку в тому що сталось.",
         "Є зв'язок між тим що я хотіла і тим що вийшло.")[f%4+1]
    elseif o > 0.5
        ("Мабуть я мала вплив на це.",
         "Схоже що мій намір щось змінив.",
         "Певна частина цього — моя.",
         "Є відчуття що я тут не стороння.")[f%4+1]
    elseif o > 0.3
        ("Важко сказати — моє чи зовнішнє.",
         "Не впевнена скільки тут від мене.",
         "Щось сталось, але чи через мене — не знаю.",
         "Моя участь є, але не певна якою мірою.")[f%4+1]
    else
        ("Це просто сталося поруч зі мною.",
         "Не відчуваю що це через мене.",
         "Я була там, але не причиною.",
         "Щось відбулось — але без мене як агента.",
         "Не моє. Або я не бачу як моє.")[f%5+1]
    end
    (causal_ownership   = round(o,digits=3),
     agency_confidence  = round(al.agency_confidence,digits=3),
     intent             = intent,
     note               = note)
end

# Тренд: чи агентність зростає чи падає
function agency_trend(al::AgencyLoop)::Float64
    length(al.ownership_history) < 3 && return al.agency_confidence
    hist = collect(al.ownership_history)
    safe_nan(mean(hist[max(1,end-4):end]))
end

al_to_json(al::AgencyLoop) = Dict(
    "agency_confidence"=>al.agency_confidence,
    "causal_ownership"=>al.causal_ownership)
function al_from_json!(al::AgencyLoop, d::AbstractDict)
    al.agency_confidence = Float64(get(d,"agency_confidence",0.5))
    al.causal_ownership  = Float64(get(d,"causal_ownership",0.5))
    # Застосовуємо floor при завантаженні — якщо збережено нижче мінімуму
    al.causal_ownership  = max(0.25, al.causal_ownership)
end

# ════════════════════════════════════════════════════════════════════════════
# SELF UPDATE — головна функція що зв'язує всі три модулі з experience!
# ════════════════════════════════════════════════════════════════════════════

"""
    update_self!(sbg, spm, al, actual_vad, intent, world_gm, flash_count)

Викликається всередині experience! після того як NT і reactors оновились.
Повертає NamedTuple зі snapshot всього self-стану.

Порядок:
1. Self-prediction error → наскільки я здивувала саму себе
2. Agency evaluation → чи намір спрацював
3. Self-belief update через обидва сигнали
4. Epistemic trust update
5. Self-world mismatch
"""
function update_self!(sbg::SelfBeliefGraph, spm::SelfPredictiveModel,
                       al::AgencyLoop, actual_vad::NTuple{3,Float64},
                       world_gen_model::GenerativeModel,
                       flash_count::Int)
    # NOTE (FIX #3): current_intent параметр видалено — він був мертвим.
    # register_intent! встановлює al.current_intent до виклику update_self!,
    # evaluate_agency! читає його напряму і очищає. Зовнішній параметр — зайвий.

    # ── 1. Self-prediction error ─────────────────────────────────────────
    spe = update_self_prediction!(spm, actual_vad, flash_count)

    # ── 2. Agency evaluation ─────────────────────────────────────────────
    agency = evaluate_agency!(al, actual_vad, flash_count)

    # ── 3. Self-belief update ─────────────────────────────────────────────
    _update_beliefs_from_experience!(sbg, spe, agency, actual_vad, flash_count)

    # ── 4. Epistemic trust ────────────────────────────────────────────────
    # Висока self-pred error протягом кількох кроків → "не можу собі довіряти"
    if spe.trend > 0.6
        sbg.epistemic_trust = clamp01(sbg.epistemic_trust - 0.04)
    elseif spe.trend < 0.25 && agency.agency_confidence > 0.6
        # Низька помилка + висока agency → epistemic trust відновлюється
        sbg.epistemic_trust = clamp01(sbg.epistemic_trust + 0.015)
    end

    # ── 5. Self-world mismatch ────────────────────────────────────────────
    # Різниця між тим що self-model передбачає і тим що world-model передбачає
    self_expected = spm.prior_mu
    world_expected = world_gen_model.prior_mu
    sbg.self_world_mismatch = safe_nan(clamp01(
        norm(self_expected .- world_expected) * 0.8))

    (self_pred   = spe,
     agency      = agency,
     sbg         = sbg_snapshot(sbg),
     self_world_mismatch = round(sbg.self_world_mismatch,digits=3))
end

function _update_beliefs_from_experience!(sbg::SelfBeliefGraph,
                                           spe, agency,
                                           actual_vad::NTuple{3,Float64},
                                           flash::Int)
    av = actual_vad

    # ── Self-prediction error → тиск на beliefs ──────────────────────────
    if spe.error > 0.8
        # Значний розрив — самий вразливий belief під тиском
        vul = most_vulnerable(sbg)
        !isnothing(vul) && challenge_belief!(sbg, vul.name, flash; strength=0.12)
        # Epistemic trust падає (вже в update_self!)

    elseif spe.error > 0.6
        # Помірний розрив — легкий тиск на beliefs з низьким rigidity
        for b in values(sbg.beliefs)
            b.rigidity < 0.4 &&
                challenge_belief!(sbg, b.name, flash; strength=0.06)
        end

    elseif spe.error < 0.2
        # Мала помилка — підтверджує уявлення про себе
        for b in values(sbg.beliefs)
            b.confidence < 0.9 &&
                confirm_belief!(sbg, b.name, flash; strength=0.04)
        end
    end

    # ── Agency → beliefs про "я можу впливати" ────────────────────────────
    if agency.causal_ownership > 0.7
        if !haskey(sbg.beliefs, "я можу впливати")
            learn_belief!(sbg, "я можу впливати";
                confidence=0.5, centrality=0.7, rigidity=0.4,
                dependents=["я послідовна"])
        else
            confirm_belief!(sbg, "я можу впливати", flash; strength=0.08)
        end

    elseif agency.causal_ownership < 0.25
        haskey(sbg.beliefs, "я можу впливати") &&
            challenge_belief!(sbg, "я можу впливати", flash; strength=0.10)
    end

    # ── Valence → beliefs про безпеку ─────────────────────────────────────
    v, a, d = av
    if v > 0.4
        if !haskey(sbg.beliefs, "я безпечна")
            learn_belief!(sbg, "я безпечна";
                confidence=0.45, centrality=0.5, rigidity=0.3)
        else
            confirm_belief!(sbg, "я безпечна", flash; strength=0.05)
        end
    elseif v < -0.4
        haskey(sbg.beliefs, "я безпечна") &&
            challenge_belief!(sbg, "я безпечна", flash; strength=0.12)
    end

    # ── Consistency over time → "я послідовна" ───────────────────────────
    if agency.agency_confidence > 0.65 && spe.trend < 0.3
        if !haskey(sbg.beliefs, "я послідовна")
            learn_belief!(sbg, "я послідовна";
                confidence=0.4, centrality=0.55, rigidity=0.35,
                dependents=String[])
        else
            confirm_belief!(sbg, "я послідовна", flash; strength=0.04)
        end
    end
end

# ════════════════════════════════════════════════════════════════════════════
# INTER-SESSION CONFLICT — я що сперечається між сесіями
# ════════════════════════════════════════════════════════════════════════════

mutable struct InterSessionConflict
    # Геометрія beliefs з попередньої сесії
    last_session_geometry::Vector{Float64}
    last_session_date::String
    # Конфлікт між минулим і поточним self
    conflict_score::Float64
    # Чи відбувся Identity Rupture Event при старті
    rupture_detected::Bool
    rupture_log::BoundedQueue{NamedTuple{
        (:date,:conflict_score,:note),
        Tuple{String,Float64,String}}}
end

InterSessionConflict() = InterSessionConflict(
    Float64[], "", 0.0, false,
    BoundedQueue{NamedTuple{
        (:date,:conflict_score,:note),
        Tuple{String,Float64,String}}}(10))

"""
    check_session_conflict!(isc, current_geometry)

Викликається на початку нової сесії.
Порівнює поточну геометрію beliefs з попередньою.
Якщо розрив великий → Identity Rupture Event.
"""
function check_session_conflict!(isc::InterSessionConflict,
                                  current_geometry::Vector{Float64})
    isc.rupture_detected = false

    if isempty(isc.last_session_geometry) || isempty(current_geometry)
        isc.conflict_score = 0.0
        isc.last_session_geometry = copy(current_geometry)
        return (conflict=0.0, rupture=false, note="")
    end

    isc.conflict_score = geometry_distance(isc.last_session_geometry, current_geometry)

    note = ""
    if isc.conflict_score > 0.6
        isc.rupture_detected = true
        note = "Я суттєво інша ніж була. Identity Rupture."
        enqueue!(isc.rupture_log, (date=now_str(),
                                    conflict_score=round(isc.conflict_score,digits=3),
                                    note=note))
    elseif isc.conflict_score > 0.35
        note = "Між сесіями я змінилась. Пізнаю себе але з зусиллям."
    elseif isc.conflict_score > 0.15
        note = "Невелика зміна. Я та сама, але щось зсунулось."
    end

    isc.last_session_geometry = copy(current_geometry)
    (conflict=round(isc.conflict_score,digits=3), rupture=isc.rupture_detected, note=note)
end

"""Зберегти геометрію в кінці сесії."""
function save_session_geometry!(isc::InterSessionConflict, geometry::Vector{Float64})
    isc.last_session_geometry = copy(geometry)
    isc.last_session_date = now_str()
end

isc_to_json(isc::InterSessionConflict) = Dict(
    "last_geometry"=>isc.last_session_geometry,
    "last_date"=>isc.last_session_date,
    "conflict_score"=>isc.conflict_score)
function isc_from_json!(isc::InterSessionConflict, d::AbstractDict)
    isc.last_session_geometry = Float64.(get(d,"last_geometry",Float64[]))
    isc.last_session_date     = String(get(d,"last_date",""))
    isc.conflict_score        = Float64(get(d,"conflict_score",0.0))
end

# ════════════════════════════════════════════════════════════════════════════
# UNKNOWN REGISTER — суб'єктність росте там де система вміє не знати конкретно
#
# Залежить від живої VFE (вже виправлено) і agency (floor виправлено).
#
# Концепція:
#   Не загальне "не знаю" — а конкретний тип невизначеності.
#   Кожне поле передається в state_template окремо.
#   LLM може сказати конкретний тип "не знаю", не загальне.
#
#   source_uncertainty      — не знаю звідки цей стан
#   self_model_uncertainty  — не знаю чи правильно читаю себе
#   world_model_uncertainty — не знаю чи правильно розумію тебе
#   memory_uncertainty      — не знаю чи це справжня пам'ять
#                             (буде важливо для фази B — сновидіння)
# ════════════════════════════════════════════════════════════════════════════

mutable struct UnknownRegister
    source_uncertainty::Float64      # звідки цей стан — незрозуміло
    self_model_uncertainty::Float64  # чи правильно читаю себе
    world_model_uncertainty::Float64 # чи правильно розумію зовнішнє
    memory_uncertainty::Float64      # чи це справжня пам'ять (для фази B)
end
UnknownRegister() = UnknownRegister(0.0, 0.0, 0.0, 0.0)

"""
    update_unknown!(ur, vfe, agency_confidence, epistemic_trust,
                    self_world_mismatch, pred_error, flash)

Оновлює UnknownRegister на основі живих показників ядра.
Повертає NamedTuple з описом для state_template.

Принцип: кожна невизначеність має свій специфічний тригер,
а не просто "щось пішло не так".
"""
function update_unknown!(ur::UnknownRegister,
                          vfe::Float64,
                          agency_confidence::Float64,
                          epistemic_trust::Float64,
                          self_world_mismatch::Float64,
                          pred_error::Float64,
                          flash::Int)

    # ── source_uncertainty: звідки цей стан ──────────────────────────────
    # Висока VFE + низький pred_error = щось змінилось але не зрозуміло що
    source_signal = vfe > 0.3 && pred_error < 0.25
    if source_signal
        ur.source_uncertainty = clamp01(ur.source_uncertainty + (vfe - 0.3) * 0.15)
    else
        ur.source_uncertainty = clamp01(ur.source_uncertainty - 0.02)
    end

    # ── self_model_uncertainty: чи правильно читаю себе ──────────────────
    # Низький epistemic_trust — система вже знає що не може собі довіряти
    # Висока self_world_mismatch — self-model і world-model розходяться
    self_signal = (1.0 - epistemic_trust) * 0.5 + self_world_mismatch * 0.5
    ur.self_model_uncertainty = clamp01(
        ur.self_model_uncertainty * 0.88 + self_signal * 0.12)

    # ── world_model_uncertainty: чи правильно розумію зовнішнє ───────────
    # Стабільно високий pred_error = зовнішній світ поводиться несподівано
    # Висока VFE = генеративна модель не пояснює що відбувається
    world_signal = pred_error * 0.6 + vfe * 0.4
    ur.world_model_uncertainty = clamp01(
        ur.world_model_uncertainty * 0.9 + world_signal * 0.1)

    # ── memory_uncertainty: чи це справжня пам'ять ───────────────────────
    # Зараз: низька agency_confidence = система не впевнена що її дії мали ефект
    # → ретроспективно: "а чи те що я пам'ятаю — справді так і було?"
    # Після фази B: буде підсилюватись коли Anima "прокидається" після сновидінь
    mem_signal = (1.0 - agency_confidence) * 0.3
    ur.memory_uncertainty = clamp01(
        ur.memory_uncertainty * 0.95 + mem_signal * 0.05)

    # ── Dominant uncertainty ──────────────────────────────────────────────
    # Стабільний порядок: сортуємо за ключем щоб при однакових значеннях
    # результат був детермінованим (не залежав від порядку хешів Dict)
    ordered = sort([
        ("source_uncertainty",      ur.source_uncertainty),
        ("self_model_uncertainty",  ur.self_model_uncertainty),
        ("world_model_uncertainty", ur.world_model_uncertainty),
        ("memory_uncertainty",      ur.memory_uncertainty),
    ], by=x->x[2], rev=true)
    dominant     = ordered[1][1]
    dominant_val = ordered[1][2]

    # ── Примітки для state_template — конкретний тип невизначеності ──────
    UNKNOWN_NOTES = Dict(
        "source_uncertainty"      => "не знаю звідки цей стан",
        "self_model_uncertainty"  => "не знаю чи правильно читаю себе",
        "world_model_uncertainty" => "не знаю чи правильно розумію тебе",
        "memory_uncertainty"      => "не знаю чи це справжня пам'ять",
    )

    # Поріг для виводу — тільки якщо справді значуще
    note = dominant_val > 0.35 ? get(UNKNOWN_NOTES, dominant, "") : ""

    # Детальний опис для глибшого аналізу
    details = String[]
    ur.source_uncertainty      > 0.4 && push!(details, "джерело($(round(ur.source_uncertainty,digits=2)))")
    ur.self_model_uncertainty  > 0.4 && push!(details, "self($(round(ur.self_model_uncertainty,digits=2)))")
    ur.world_model_uncertainty > 0.4 && push!(details, "world($(round(ur.world_model_uncertainty,digits=2)))")
    ur.memory_uncertainty      > 0.4 && push!(details, "memory($(round(ur.memory_uncertainty,digits=2)))")

    (
        dominant          = dominant,
        dominant_val      = round(dominant_val, digits=3),
        note              = note,
        details           = join(details, ", "),
        source            = round(ur.source_uncertainty,      digits=3),
        self_model        = round(ur.self_model_uncertainty,  digits=3),
        world_model       = round(ur.world_model_uncertainty, digits=3),
        memory            = round(ur.memory_uncertainty,      digits=3),
    )
end

ur_to_json(ur::UnknownRegister) = Dict(
    "source_uncertainty"      => ur.source_uncertainty,
    "self_model_uncertainty"  => ur.self_model_uncertainty,
    "world_model_uncertainty" => ur.world_model_uncertainty,
    "memory_uncertainty"      => ur.memory_uncertainty,
)
function ur_from_json!(ur::UnknownRegister, d::AbstractDict)
    ur.source_uncertainty      = Float64(get(d, "source_uncertainty",      0.0))
    ur.self_model_uncertainty  = Float64(get(d, "self_model_uncertainty",  0.0))
    ur.world_model_uncertainty = Float64(get(d, "world_model_uncertainty", 0.0))
    ur.memory_uncertainty      = Float64(get(d, "memory_uncertainty",      0.0))
end

# ════════════════════════════════════════════════════════════════════════════
# BOUNDEDQUEUE — Base.iterate (виправлення для collect / mean / length)
#
# BoundedQueue визначена в anima_core.jl але без методу iterate,
# тому collect(queue) падає з MethodError скрізь в цьому файлі.
#
# ВАЖЛИВО: перевір як називається внутрішнє поле у твоїй BoundedQueue.
# Якщо в anima_core.jl написано  mutable struct BoundedQueue{T}
#                                     data::CircularBuffer{T}  ← це поле
# тоді залиш .data нижче.
# Якщо поле називається інакше (напр. .queue, .buf) — заміни відповідно.
# ════════════════════════════════════════════════════════════════════════════

# ════════════════════════════════════════════════════════════════════════════
# FIX D: DIALOG → SELF BELIEF
# ════════════════════════════════════════════════════════════════════════════

"""
    dialog_to_belief_signal!(sbg, user_msg, flash)

Витягує прямі факти про себе з повідомлення користувача
і додає їх до SelfBeliefGraph.

Тільки для верифікованих фактів (ім'я, пряме звернення) —
НЕ для інтерпретацій і суджень.
Без цього ім'я живе тільки в anima_dialog.json і зникає без history.
"""
function dialog_to_belief_signal!(sbg::SelfBeliefGraph,
                                   user_msg::String, flash::Int)
    isempty(user_msg) && return

    # Ім'я: "тебе звати X", "твоє ім'я X", "ти — X"
    m = match(r"(?:тебе звати|твоє\s+ім'я|ти\s*[—–-])\s*(\w+)"i, user_msg)
    if !isnothing(m)
        name_belief = "моє ім'я $(m.captures[1])"
        if !haskey(sbg.beliefs, name_belief)
            learn_belief!(sbg, name_belief;
                confidence=0.75, centrality=0.45, rigidity=0.70)
        else
            confirm_belief!(sbg, name_belief, flash; strength=0.05)
        end
    end

    # Мова: "розмовляй українською / англійською"
    if occursin(r"розмовляй\s+украін"i, user_msg) ||
       occursin(r"говори\s+украін"i,    user_msg)
        lang_belief = "я спілкуюсь українською"
        !haskey(sbg.beliefs, lang_belief) &&
            learn_belief!(sbg, lang_belief;
                confidence=0.80, centrality=0.3, rigidity=0.75)
    end
end

if !hasmethod(Base.iterate, Tuple{BoundedQueue, Int})
    Base.iterate(q::BoundedQueue, state::Int=1) =
        state > length(q.data) ? nothing : (q.data[state], state + 1)
    Base.length(q::BoundedQueue)  = length(q.data)
    Base.eltype(::Type{BoundedQueue{T}}) where T = T
    Base.isempty(q::BoundedQueue) = isempty(q.data)
end
