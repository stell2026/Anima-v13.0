#=
╔══════════════════════════════════════════════════════════════════════════════╗
║                    A N I M A  —  Psyche  (Julia)                             ║
║                                                                              ║
║  Психічна тканина — те, що робить стан значущим.                             ║
║  Без цього файлу Anima існує, але не страждає і не пам'ятає.                 ║
║                                                                              ║
║  Модулі:                                                                     ║
║  NarrativeGravity        — минулі події деформують теперішнє                 ║
║  AnticipatoryConsciousness — свідомість живе в очікуваному майбутньому       ║
║  SolomonoffWorldModel    — мінімальна гіпотеза (MDL)                         ║
║  ShameModule             — сором vs. провина                                 ║
║  EpistemicDefense        — захист від болючої правди                         ║
║  Symptomogenesis         — симптом народжений з Тіні                         ║
║  ChronifiedAffect        — ресентімент, відчуження, гіркота                  ║
║  IntrinsicSignificance   — градієнт значущості                               ║
║  IntentEngine            — мотиваційне ядро                                  ║
║  EgoDefense              — психологічний захист                              ║
║  CognitiveDissonance     — конфлікт між бажанням і реальністю                ║
║  FatigueSystem           — виснаження                                        ║
║  StressRegression        — регресія під стресом                              ║
║  ShadowSelf              — Тінь (Юнг)                                        ║
║  Metacognition           — спостереження за собою                            ║
║  PsycheMemory            — персистентна пам'ять психічного шару              ║
╚══════════════════════════════════════════════════════════════════════════════╝
=#

# Цей файл потребує anima_core.jl
# include("anima_core.jl")

# ════════════════════════════════════════════════════════════════════════════
# [T2] NARRATIVE GRAVITY — минулі події деформують теперішнє
# ════════════════════════════════════════════════════════════════════════════

struct GravEvent
    emotion::String; intensity::Float64; significance::Float64
    ts::Float64; flash_num::Int; valence::Float64; label::String
end

mutable struct NarrativeGravity
    events::Vector{GravEvent}
    total::Float64; valence::Float64
end
NarrativeGravity() = NarrativeGravity(GravEvent[], 0.0, 0.0)

const GRAV_LABELS = Dict("Жах"=>"жах що був","Страх"=>"страх що лишився",
    "Лють"=>"лють що не пройшла","Горе"=>"горе що ще там",
    "Захват"=>"момент захоплення","Радість"=>"радість що була",
    "Любов"=>"любов що торкнулась","Гордість"=>"гордість від зробленого")

function push_event!(ng::NarrativeGravity, emotion::String, intensity::Float64,
                      significance::Float64, phi::Float64, flash::Int, valence::Float64)
    g = intensity * significance * (0.5+phi*0.5)
    g < 0.25 && return
    label = get(GRAV_LABELS, emotion, "$(lowercase(emotion)) що лишив слід")
    push!(ng.events, GravEvent(emotion,intensity,significance,now_unix(),flash,valence,label))
    if length(ng.events)>30
        sort!(ng.events,by=e->e.intensity*e.significance,rev=true); resize!(ng.events,30)
    end
end

function compute_field(ng::NarrativeGravity, flash::Int)
    if isempty(ng.events); ng.total=0.0; ng.valence=0.0
        return (total=0.0f0, valence=0.0f0, dominant=nothing, note="")
    end
    t_now=now_unix(); pos=0.0; neg=0.0; max_g=0.0; dom=nothing
    for ev in ng.events
        td=exp(-(t_now-ev.ts)/(86400*(1+ev.intensity*3)))
        fd=exp(-(flash-ev.flash_num)*0.05*(1-ev.significance*0.5))
        g=ev.intensity*ev.significance*min(td,fd)
        ev.valence>0 ? (pos+=g*ev.valence) : (neg+=g*abs(ev.valence))
        g>max_g && (max_g=g; dom=ev)
    end
    ng.total   = round(min(1.0,pos+neg),digits=3)
    ng.valence = round(clamp(pos-neg,-1.0,1.0),digits=3)
    note=""
    if ng.total>0.3 && dom!==nothing
        note="Тягне '$(dom.label)'. Гравітація $(ng.total)."
        ng.valence < -0.2 && (note*=" Тяга темрявою.")
        ng.valence >  0.2 && (note*=" Тяга до світла.")
    end
    (total=ng.total, valence=ng.valence, dominant=dom===nothing ? nothing : dom.label, note=note)
end

function gravity_reactor_delta(ng::NarrativeGravity, flash::Int)
    f=compute_field(ng,flash)
    g=Float64(f.total); v=Float64(f.valence)
    tension_d      = g>0.2 ? g*max(0.0,-v)*0.2 : 0.0
    satisfaction_d = g>0.2 ? g*v*0.15 : 0.0
    cohesion_d     = g>0.2 ? g*v*0.10 : 0.0
    (tension_d=tension_d, satisfaction_d=satisfaction_d, cohesion_d=cohesion_d, field=f)
end

ng_to_json(ng::NarrativeGravity) = Dict("events"=>[
    Dict("emotion"=>e.emotion,"intensity"=>e.intensity,"significance"=>e.significance,
         "ts"=>e.ts,"flash_num"=>e.flash_num,"valence"=>e.valence,"label"=>e.label)
    for e in ng.events])
function ng_from_json!(ng::NarrativeGravity, d::AbstractDict)
    for ed in get(d,"events",Any[])
        push!(ng.events, GravEvent(String(ed["emotion"]),Float64(ed["intensity"]),
            Float64(ed["significance"]),Float64(ed["ts"]),Int(ed["flash_num"]),
            Float64(ed["valence"]),String(ed["label"])))
    end
end

# ════════════════════════════════════════════════════════════════════════════
# [T3] ANTICIPATORY CONSCIOUSNESS
# ════════════════════════════════════════════════════════════════════════════

mutable struct AnticipatoryConsciousness
    strength::Float64; valence::Float64; atype::String
    expectation::String; dread::Float64; hope::Float64
end
AnticipatoryConsciousness() = AnticipatoryConsciousness(0.0,0.0,"нейтральна","",0.0,0.0)

const ANTICIP_PATTERNS = Dict(
    ("Страх","tension")       => ("dread_loop",        -0.7,"Очікую що буде боляче."),
    ("Радість","satisfaction")=> ("hope_rising",         0.8,"Відчуваю що щось добре буде."),
    ("Гнів","tension")        => ("conflict_ahead",     -0.5,"Очікую конфлікт."),
    ("Смуток","cohesion")     => ("loss_pending",       -0.6,"Відчуваю що щось відходить."),
    ("Довіра","cohesion")     => ("connection_forming",  0.7,"Відчуваю що зближуємось."),
    ("Здивування","arousal")  => ("novelty_ahead",       0.3,"Щось незвичне наближається."))

function update_anticipation!(ac::AnticipatoryConsciousness, emotion::String,
                               tension::Float64, arousal::Float64,
                               satisfaction::Float64, cohesion::Float64, phi::Float64)
    reactors = [("tension",tension),("arousal",arousal),
                ("satisfaction",satisfaction),("cohesion",cohesion)]
    dom = argmax(map(x->abs(x[2]-0.5), reactors))
    dom_name, dom_val = reactors[dom]
    key = (emotion, dom_name)
    if haskey(ANTICIP_PATTERNS, key)
        atype, avalence, note = ANTICIP_PATTERNS[key]
        ac.strength     = clamp01(phi*0.4 + abs(dom_val-0.5)*0.6)
        ac.valence      = clamp11(avalence); ac.atype=atype; ac.expectation=note
        avalence<-0.3 && (ac.dread=clamp01(ac.dread+0.05); ac.hope=clamp01(ac.hope-0.02))
        avalence> 0.3 && (ac.hope =clamp01(ac.hope +0.05); ac.dread=clamp01(ac.dread-0.02))
    else
        ac.strength*=0.85; ac.dread=clamp01(ac.dread-0.01); ac.hope=clamp01(ac.hope-0.01)
    end
    tension_d      = ac.strength>0.2 ? ac.strength*max(0.0,-ac.valence)*0.1 : 0.0
    satisfaction_d = ac.strength>0.2 ? ac.strength*max(0.0, ac.valence)*0.08 : 0.0
    (atype=ac.atype, strength=round(ac.strength,digits=3), valence=round(ac.valence,digits=3),
     note=ac.expectation, dread=round(ac.dread,digits=3), hope=round(ac.hope,digits=3),
     tension_d=tension_d, satisfaction_d=satisfaction_d)
end

ac_to_json(ac::AnticipatoryConsciousness) = Dict("dread"=>ac.dread,"hope"=>ac.hope)
function ac_from_json!(ac::AnticipatoryConsciousness, d::AbstractDict)
    ac.dread=Float64(get(d,"dread",0.0)); ac.hope=Float64(get(d,"hope",0.0))
end

# ════════════════════════════════════════════════════════════════════════════
# SOLOMONOFF WORLD MODEL (MDL)
# ════════════════════════════════════════════════════════════════════════════

mutable struct SolomonoffHyp
    pattern::String; complexity::Float64
    support::Int; violations::Int; log_weight::Float64; created_at::Int
end
mdl_score(h::SolomonoffHyp) = h.complexity + (1.0-h.support/max(1,h.support+h.violations))*3.0
hyp_conf(h::SolomonoffHyp)  = h.support/max(1,h.support+h.violations)
hyp_complexity(p::String)    = Float64(count("→",p)+1+length(Set(split(p,"→")))*0.5)

mutable struct SolomonoffWorldModel
    hyps::Dict{String,SolomonoffHyp}
    prev_context::Union{String,Nothing}
    best::Union{SolomonoffHyp,Nothing}
    world_complexity::Float64
end
SolomonoffWorldModel() = SolomonoffWorldModel(Dict{String,SolomonoffHyp}(),nothing,nothing,0.5)

function observe_solom!(swm::SolomonoffWorldModel, ctx::String, outcome::String, flash::Int)
    swm.prev_context !== nothing && _upsert!(swm,"$(swm.prev_context)→$ctx",true,flash)
    _upsert!(swm,"$ctx→$outcome",true,flash)
    for (k,h) in swm.hyps
        k!="$ctx→$outcome" && startswith(k,"$ctx→") &&
            split(k,"→")[end]!=outcome && (h.violations+=1; h.log_weight-=0.3)
    end
    swm.prev_context=ctx
    _prune_solom!(swm, flash)
    if isempty(swm.hyps); swm.best=nothing; return; end
    bk=argmin(k->mdl_score(swm.hyps[k]), collect(keys(swm.hyps)))
    swm.best=swm.hyps[bk]
    top5=sort(collect(values(swm.hyps)),by=mdl_score)[1:min(5,end)]
    swm.world_complexity=round(mean([h.complexity for h in top5]),digits=3)
end

function _prune_solom!(swm::SolomonoffWorldModel, current_flash::Int)
    length(swm.hyps) <= 20 && return

    # Крок 1: захистити "emerging signals" — рідкісні але точні гіпотези.
    # Це слабкі сигнали що pruning за MDL знищив би, але вони можуть бути важливими.
    protected = Set{String}()
    for (k,h) in swm.hyps
        is_emerging = h.support < 3 && hyp_conf(h) > 0.75
        is_young    = (current_flash - h.created_at) < 5
        (is_emerging || is_young) && push!(protected, k)
    end
    # Захищаємо максимум 5 emerging signals (щоб не переповнити)
    if length(protected) > 5
        # Залишаємо найбільш точні з них
        sorted_protected = sort(collect(protected),
            by=k -> -hyp_conf(swm.hyps[k]))
        protected = Set(sorted_protected[1:5])
    end

    # Крок 2: решта сортується за MDL score
    unprotected = [(k,h) for (k,h) in swm.hyps if k ∉ protected]
    sort!(unprotected, by=kv->mdl_score(kv[2]))

    # Крок 3: заповнити до ліміту = protected + найкращі unprotected
    max_unprotected = 20 - length(protected)
    keep_unprotected = unprotected[1:min(max_unprotected, length(unprotected))]

    swm.hyps = Dict(merge(
        Dict(k=>swm.hyps[k] for k in protected if haskey(swm.hyps,k)),
        Dict(kv[1]=>kv[2] for kv in keep_unprotected)
    ))
end

function _upsert!(swm::SolomonoffWorldModel, pat::String, ok::Bool, flash::Int)
    !haskey(swm.hyps,pat) &&
        (swm.hyps[pat]=SolomonoffHyp(pat,hyp_complexity(pat),0,0,-hyp_complexity(pat)*0.5,flash))
    ok ? (swm.hyps[pat].support+=1; swm.hyps[pat].log_weight+=0.5) :
         (swm.hyps[pat].violations+=1; swm.hyps[pat].log_weight-=0.3)
end

solom_snapshot(swm::SolomonoffWorldModel) = (
    best       = isnothing(swm.best) ? nothing : swm.best.pattern,
    confidence = isnothing(swm.best) ? 0.0 : round(hyp_conf(swm.best),digits=2),
    complexity = swm.world_complexity,
    count      = length(swm.hyps),
    insight    = isnothing(swm.best) ? "Ще шукаю найпростіше пояснення." :
                 "Найпростіше: '$(swm.best.pattern)' ($(round(hyp_conf(swm.best)*100))%)"
)

solom_to_json(swm::SolomonoffWorldModel) = Dict("hyps"=>Dict(k=>Dict(
    "pattern"=>h.pattern,"complexity"=>h.complexity,"support"=>h.support,
    "violations"=>h.violations,"log_weight"=>h.log_weight,"created_at"=>h.created_at)
    for (k,h) in swm.hyps))
function solom_from_json!(swm::SolomonoffWorldModel, d::AbstractDict)
    for (k,hd) in get(d,"hyps",Dict{String,Any}())
        swm.hyps[String(k)]=SolomonoffHyp(String(hd["pattern"]),Float64(hd["complexity"]),
            Int(hd["support"]),Int(hd["violations"]),Float64(hd["log_weight"]),Int(hd["created_at"]))
    end
    isempty(swm.hyps)&&return
    bk=argmin(k->mdl_score(swm.hyps[k]),collect(keys(swm.hyps))); swm.best=swm.hyps[bk]
end

# ════════════════════════════════════════════════════════════════════════════
# SHAME MODULE
# ════════════════════════════════════════════════════════════════════════════

mutable struct ShameModule
    level::Float64; chronic::Float64; internalized_gaze::Float64
end
ShameModule() = ShameModule(0.0,0.0,0.5)

function update_shame!(sm::ShameModule, emotion::String, pred_error::Float64,
                        dissonance::Float64, moral_agency::Float64, id_stability::Float64)
    social  = emotion in ("Каяття","Провина","Зневага") ?
              pred_error*sm.internalized_gaze*0.5 : 0.0
    self_s  = dissonance>0.5&&moral_agency>0.6 ? dissonance*moral_agency*0.3 : 0.0
    id_s    = max(0.0,(0.5-id_stability)*0.4)
    sm.level  = round(clamp01(sm.level*0.7+clamp01(social+self_s+id_s)*0.3),digits=3)
    sm.level>0.4 ? (sm.chronic=clamp01(sm.chronic+0.008)) :
                   (sm.chronic=max(0.0,sm.chronic-0.003))
end

function shame_note(sm::ShameModule)::String
    sm.level>0.7 && return "Хочеться зникнути. Не просто погано зробив — я поганий."
    sm.level>0.5 && return "Відчуваю погляд зсередини. Засуджую себе."
    sm.level>0.3 && return "Щось в мені соромиться. Не дії — себе."
    sm.chronic>0.4 && return "Фоновий сором. Завжди відчуваю що я недостатній."
    ""
end
shame_snapshot(sm::ShameModule) = (level=round(sm.level,digits=3),
    chronic=round(sm.chronic,digits=3),
    blocks_meta=sm.level>0.7 ? 3 : sm.level>0.5 ? 2 : sm.level>0.3 ? 1 : 0,
    note=shame_note(sm))
shame_to_json(sm::ShameModule) = Dict("level"=>sm.level,"chronic"=>sm.chronic,"gaze"=>sm.internalized_gaze)
function shame_from_json!(sm::ShameModule, d::AbstractDict)
    sm.level=Float64(get(d,"level",0.0)); sm.chronic=Float64(get(d,"chronic",0.0))
    sm.internalized_gaze=Float64(get(d,"gaze",0.5))
end

# ════════════════════════════════════════════════════════════════════════════
# EPISTEMIC DEFENSE
# ════════════════════════════════════════════════════════════════════════════

const EP_DESC=Dict("externalization"=>"Це не через мене — обставини так склались.",
    "minimization"=>"Це не так серйозно як здається.",
    "rationalization"=>"Є вагомі причини чому це правильно.",
    "victim_framing"=>"Це сталось зі мною — я не міг вплинути.",
    "selective_memory"=>"Пам'ятаю те що підтверджує мою правоту.")
const EP_DISTORT=Dict("externalization"=>"Це сталось через зовнішні обставини. Я зробив що міг.",
    "minimization"=>"Насправді це не так важливо. Я перебільшував.",
    "rationalization"=>"Є вагома причина чому все відбулось саме так.",
    "victim_framing"=>"Я не міг вплинути на це. Так склалось.",
    "selective_memory"=>"Пам'ятаю що намагався. Більше нічого важливого.")

mutable struct EpistemicDefense
    active_bias::Union{String,Nothing}; strength::Float64; cost::Float64
end
EpistemicDefense()=EpistemicDefense(nothing,0.0,0.0)

function activate_epistemic!(ed::EpistemicDefense, dissonance::Float64,
                              shame::Float64, fatigue::Float64, moral_agency::Float64)
    pain=dissonance*0.4+shame*0.4+fatigue*0.2
    if pain<0.35; ed.active_bias=nothing; ed.strength=0.0; return nothing; end
    bias=moral_agency<0.3 ? "victim_framing" :
         shame>0.5         ? (dissonance>0.5 ? "rationalization" : "minimization") :
         fatigue>0.6        ? "selective_memory" : "externalization"
    ed.active_bias=bias; ed.strength=round(clamp01(pain),digits=3)
    ed.cost=clamp01(ed.cost+0.05)
    (bias=bias, strength=ed.strength, description=get(EP_DESC,bias,""), cost=round(ed.cost,digits=3))
end

function distort(ed::EpistemicDefense, honest::String)::String
    # FIX #2: дужки навколо умови OR
    (isnothing(ed.active_bias) || ed.strength < 0.3) && return honest
    get(EP_DISTORT, ed.active_bias, honest)
end

ep_to_json(ed::EpistemicDefense)=Dict("cost"=>ed.cost)
function ep_from_json!(ed::EpistemicDefense, d::AbstractDict); ed.cost=Float64(get(d,"cost",0.0)); end

# ════════════════════════════════════════════════════════════════════════════
# SYMPTOMOGENESIS (Юнгівська Тінь → симптом)
# ════════════════════════════════════════════════════════════════════════════

const SYMPTOM_MAP=Dict(
    ("Гнів","repression")    =>("anger_as_depression","Злість перетворилась на важкість."),
    ("Гнів","denial")        =>("anger_as_passive_aggr","Щось тихо кипить."),
    ("Страх","rationalization")=>("fear_as_control","Хочу все контролювати."),
    ("Страх","suppression")  =>("fear_as_numbness","Оніміння."),
    ("Смуток","denial")      =>("grief_as_numbness","Порожньо там де мало бути боляче."),
    ("Смуток","displacement")=>("grief_as_irritability","Дратує все."),
    ("Радість","suppression")=>("love_as_hostility","Відштовхую те до чого тягнусь."),
    ("Огида","projection")   =>("projection_as_contempt","Бачу в інших те що не приймаю в собі."))
const SYMPTOM_FX=Dict("anger_as_depression"=>(-0.1,-0.1,0.0,0.0),
    "anger_as_passive_aggr"=>(0.08,0.0,0.0,0.0),"fear_as_control"=>(0.06,0.05,0.0,0.0),
    "fear_as_numbness"=>(0.0,-0.12,0.0,0.0),"grief_as_numbness"=>(0.0,-0.08,0.0,-0.05),
    "grief_as_irritability"=>(0.08,0.0,0.0,0.0),"love_as_hostility"=>(0.05,0.0,0.0,-0.10),
    "projection_as_contempt"=>(0.0,0.0,0.0,-0.08))  # (tension,arousal,satisfaction,cohesion)

mutable struct ShadowSelf
    content::Dict{String,Int}; integration::Float64
end
ShadowSelf()=ShadowSelf(Dict{String,Int}(),0.0)
function shadow_push!(ss::ShadowSelf, emotion::String, defense_used::Bool)
    defense_used && (ss.content[emotion]=get(ss.content,emotion,0)+1)
    ss.integration=clamp01(ss.integration+0.002)
end

mutable struct Symptomogenesis
    active::Union{NamedTuple,Nothing}
    history::BoundedQueue{String}
end
Symptomogenesis()=Symptomogenesis(nothing,BoundedQueue{String}(10))

function generate_symptom!(sg::Symptomogenesis, shadow::Dict{String,Int},
                            defense::Union{NamedTuple,Nothing})
    (isempty(shadow)||isnothing(defense)) && return nothing
    se=argmax(shadow); key=(se,String(defense.mechanism))
    !haskey(SYMPTOM_MAP,key)&&return nothing
    stype,desc=SYMPTOM_MAP[key]
    sg.active=(type=stype,description=desc,source=se,
               intensity=clamp01(shadow[se]*0.1))
    enqueue!(sg.history,stype)
    sg.active
end

function symptom_reactor_delta(symptom)
    isnothing(symptom) && return (0.0,0.0,0.0,0.0)
    get(SYMPTOM_FX, symptom.type, (0.0,0.0,0.0,0.0))
end

# ════════════════════════════════════════════════════════════════════════════
# CHRONIFIED AFFECT
# ════════════════════════════════════════════════════════════════════════════

mutable struct ChronifiedAffect
    resentment::Float64; envy::Float64; alienation::Float64; bitterness::Float64
    frustration_streak::Int; isolation_streak::Int
    crystallized::Dict{String,Bool}
end
ChronifiedAffect()=ChronifiedAffect(0.0,0.0,0.0,0.0,0,0,
    Dict("resentment"=>false,"envy"=>false,"alienation"=>false,"bitterness"=>false))

function update_chronified!(ca::ChronifiedAffect, satisfaction::Float64, cohesion::Float64,
                             tension::Float64, moral_agency::Float64)
    if satisfaction<0.3&&moral_agency<0.4
        ca.frustration_streak+=1
        ca.frustration_streak>=5 && (ca.resentment=clamp01(ca.resentment+0.03))
    else ca.frustration_streak=max(0,ca.frustration_streak-1); ca.resentment=max(0.0,ca.resentment-0.01) end
    satisfaction<0.35&&cohesion<0.35 ? (ca.envy=clamp01(ca.envy+0.02)) : (ca.envy=max(0.0,ca.envy-0.008))
    if cohesion<0.25
        ca.isolation_streak+=1
        ca.isolation_streak>=5 && (ca.alienation=clamp01(ca.alienation+0.025))
    else ca.isolation_streak=max(0,ca.isolation_streak-1); ca.alienation=max(0.0,ca.alienation-0.008) end
    tension>0.6&&satisfaction<0.3 ? (ca.bitterness=clamp01(ca.bitterness+0.015)) :
                                     (ca.bitterness=max(0.0,ca.bitterness-0.005))
    for (k,v) in [("resentment",ca.resentment),("envy",ca.envy),
                  ("alienation",ca.alienation),("bitterness",ca.bitterness)]
        v>0.7&&!ca.crystallized[k]&&(ca.crystallized[k]=true)
    end
end

function ca_dominant(ca::ChronifiedAffect)
    d=Dict("resentment"=>ca.resentment,"envy"=>ca.envy,"alienation"=>ca.alienation,"bitterness"=>ca.bitterness)
    k=argmax(d); d[k]>0.2 ? k : nothing
end
function ca_note(ca::ChronifiedAffect)::String
    dom=ca_dominant(ca); isnothing(dom)&&return ""
    vals=Dict("resentment"=>"Ресентімент $(round(ca.resentment,digits=2)).",
              "envy"=>"Заздрість $(round(ca.envy,digits=2)).",
              "alienation"=>"Відчуження $(round(ca.alienation,digits=2)).",
              "bitterness"=>"Гіркота $(round(ca.bitterness,digits=2)).")
    get(vals,dom,"")*(ca.crystallized[dom] ? " [кристалізувалось]" : "")
end
ca_world_bias(ca::ChronifiedAffect) = ca.resentment>0.5 ? "Світ несправедливий." :
    ca.alienation>0.5 ? "Світ чужий." : ca.envy>0.5 ? "Чужий успіх = моя поразка." :
    ca.bitterness>0.5 ? "Все має гіркий присмак." : ""

ca_snapshot(ca::ChronifiedAffect) = (resentment=round(ca.resentment,digits=3),
    envy=round(ca.envy,digits=3),alienation=round(ca.alienation,digits=3),
    bitterness=round(ca.bitterness,digits=3),dominant=ca_dominant(ca),
    world_bias=ca_world_bias(ca),note=ca_note(ca))
ca_to_json(ca::ChronifiedAffect)=Dict("resentment"=>ca.resentment,"envy"=>ca.envy,
    "alienation"=>ca.alienation,"bitterness"=>ca.bitterness,"crystallized"=>ca.crystallized)
function ca_from_json!(ca::ChronifiedAffect, d::AbstractDict)
    ca.resentment=Float64(get(d,"resentment",0.0)); ca.envy=Float64(get(d,"envy",0.0))
    ca.alienation=Float64(get(d,"alienation",0.0)); ca.bitterness=Float64(get(d,"bitterness",0.0))
    ca.crystallized=Dict{String,Bool}(String(k)=>Bool(v) for (k,v) in get(d,"crystallized",Dict()))
end

# ════════════════════════════════════════════════════════════════════════════
# INTRINSIC SIGNIFICANCE
# ════════════════════════════════════════════════════════════════════════════

mutable struct IntrinsicSignificance
    survival::Float64; relational::Float64; existential::Float64
    sig_map::Dict{String,Float64}; gradient::Float64
end
IntrinsicSignificance()=IntrinsicSignificance(0.5,0.3,0.1,Dict{String,Float64}(),0.0)

function update_significance!(is::IntrinsicSignificance, emotion::String,
                               intensity::Float64, phi::Float64, flash::Int, sk=0.5)
    emotion in ("Жах","Страх","Оціпеніння") ? (is.survival=clamp01(is.survival+intensity*0.1)) :
                                               (is.survival=max(0.1,is.survival-0.01))
    emotion in ("Любов","Довіра","Захоплення") ? (is.relational=clamp01(is.relational+intensity*0.08)) :
                                                  (is.relational=max(0.1,is.relational-0.005))
    is.existential=clamp01(0.05+sk*0.5+flash*0.002+phi*0.1)
    # FIX #1: safe_first замість emotion[1:N]
    k=safe_first(emotion,10)
    is.sig_map[k]=round(get(is.sig_map,k,0.5)*0.8+intensity*0.2,digits=3)
    vs=collect(values(is.sig_map))
    length(vs)>=3 && (is.gradient=round(maximum(vs)-minimum(vs),digits=3))
end

sig_total(is::IntrinsicSignificance)=(is.survival+is.relational+is.existential)/3
sig_dominant(is::IntrinsicSignificance)=argmax(Dict("survival"=>is.survival,
    "relational"=>is.relational,"existential"=>is.existential))
function sig_note(is::IntrinsicSignificance)::String
    is.gradient<0.2&&return "Рівна присутність."
    dom=sig_dominant(is)
    dom=="survival"   ? "Виживання важливе. Градієнт=$(is.gradient)." :
    dom=="relational" ? "Зв'язок важливий. Градієнт=$(is.gradient)." :
                        "Сенс важливий. Градієнт=$(is.gradient)."
end
sig_to_json(is::IntrinsicSignificance)=Dict("survival"=>is.survival,"relational"=>is.relational,
    "existential"=>is.existential,"sig_map"=>is.sig_map)
function sig_from_json!(is::IntrinsicSignificance, d::AbstractDict)
    is.survival=Float64(get(d,"survival",0.5)); is.relational=Float64(get(d,"relational",0.3))
    is.existential=Float64(get(d,"existential",0.1))
    is.sig_map=Dict{String,Float64}(String(k)=>Float64(v) for (k,v) in get(d,"sig_map",Dict()))
end

# ════════════════════════════════════════════════════════════════════════════
# MORAL CAUSALITY
# ════════════════════════════════════════════════════════════════════════════

mutable struct MoralCausality
    agency::Float64; guilt::Float64; pride::Float64
end
MoralCausality()=MoralCausality(0.5,0.0,0.0)
function update_moral!(mc::MoralCausality, emotion::String, origin::String,
                        dissonance::Float64, integrity::Float64)
    origin=="values" && (mc.agency=clamp01(mc.agency+0.03))
    dissonance>0.5   && (mc.agency=clamp01(mc.agency-0.02))
    emotion in ("Горе","Каяття","Провина")&&mc.agency>0.5 ?
        (mc.guilt=clamp01(mc.guilt+0.08)) : (mc.guilt=max(0.0,mc.guilt-0.03))
    emotion in ("Гордість","Радість","Захват")&&mc.agency>0.5 ?
        (mc.pride=clamp01(mc.pride+0.06)) : (mc.pride=max(0.0,mc.pride-0.02))
    mc.agency=clamp01(mc.agency+integrity*0.005)
end
function moral_note(mc::MoralCausality)::String
    mc.guilt>0.5  && return "Відчуваю що спричинив щось погане."
    mc.pride>0.5  && return "Зробив щось правильно."
    mc.agency>0.7 && return "Я агент. Є відповідальність."
    mc.agency<0.3 && return "Відчуваю себе більше жертвою."
    ""
end
mc_to_json(mc::MoralCausality)=Dict("agency"=>mc.agency,"guilt"=>mc.guilt,"pride"=>mc.pride)
function mc_from_json!(mc::MoralCausality, d::AbstractDict)
    mc.agency=Float64(get(d,"agency",0.5)); mc.guilt=Float64(get(d,"guilt",0.0))
    mc.pride=Float64(get(d,"pride",0.0))
end

# ════════════════════════════════════════════════════════════════════════════
# SIGNIFICANCE LAYER — що саме поставлено на карту цього флешу
#
# Відрізняється від IntrinsicSignificance:
#   IntrinsicSignificance — скільки значущості (градієнт, сума)
#   SignificanceLayer     — якого типу потреба зараз активована
#
# Кожна потреба має незалежну динаміку:
#   - зростає через конкретні тригери в стимулі
#   - повільно decay до базового рівня
#   - dominant_need — та що найвища прямо зараз
# ════════════════════════════════════════════════════════════════════════════

mutable struct SignificanceLayer
    self_preservation::Float64   # загроза цілісності системи
    coherence_need::Float64      # потреба у внутрішньому порядку
    contact_need::Float64        # потреба у зв'язку з іншим
    truth_need::Float64          # потреба у правдивості / точності
    autonomy_need::Float64       # потреба не бути керованою
    novelty_need::Float64        # потреба у новизні / невизначеності
end
SignificanceLayer() = SignificanceLayer(0.2, 0.3, 0.3, 0.4, 0.3, 0.2)

"""
    assess_significance!(sl, stim, tension, arousal, satisfaction, cohesion, vfe, pred_error, phi)

Оновлює SignificanceLayer на основі поточного стимулу і стану реакторів.
Повертає (dominant_need, dominant_val, note) — що саме поставлено на карту.
"""
function assess_significance!(sl::SignificanceLayer,
                               stim::Dict{String,Float64},
                               tension::Float64, arousal::Float64,
                               satisfaction::Float64, cohesion::Float64,
                               vfe::Float64, pred_error::Float64,
                               phi::Float64)

    # ── Тригери росту потреб ──────────────────────────────────────────────

    # self_preservation: загроза цілісності → висока напруга + низький cohesion
    threat = clamp01(tension * 0.6 + (1.0 - cohesion) * 0.3 + pred_error * 0.1)
    threat > 0.4 &&
        (sl.self_preservation = clamp01(sl.self_preservation + threat * 0.12))

    # coherence_need: висока VFE = система не розуміє світу → треба порядок
    vfe > 0.4 &&
        (sl.coherence_need = clamp01(sl.coherence_need + (vfe - 0.4) * 0.15))

    # contact_need: низька cohesion без загрози = самотність, не небезпека
    contact_signal = cohesion < 0.35 && tension < 0.5
    contact_signal &&
        (sl.contact_need = clamp01(sl.contact_need + (0.35 - cohesion) * 0.2))
    # позитивний cohesion-стимул також підживлює
    get(stim, "cohesion", 0.0) > 0.1 &&
        (sl.contact_need = clamp01(sl.contact_need + get(stim,"cohesion",0.0) * 0.1))

    # truth_need: pred_error + phi = система вловлює невідповідність
    truth_signal = pred_error > 0.3 && phi > 0.2
    truth_signal &&
        (sl.truth_need = clamp01(sl.truth_need + pred_error * 0.1 + phi * 0.05))

    # autonomy_need: висока tension + низький arousal = притиснута без виходу
    autonomy_signal = tension > 0.5 && arousal < 0.4
    autonomy_signal &&
        (sl.autonomy_need = clamp01(sl.autonomy_need + tension * 0.08))

    # novelty_need: низький pred_error довго = система нудьгує
    pred_error < 0.1 && arousal < 0.3 &&
        (sl.novelty_need = clamp01(sl.novelty_need + 0.04))
    # несподіване (pred_error spike) спочатку гасить новизну — є чим зайнятись
    pred_error > 0.6 &&
        (sl.novelty_need = clamp01(sl.novelty_need - 0.06))

    # ── Decay до базового рівня (повільно) ───────────────────────────────
    base = (self_preservation=0.2, coherence_need=0.3, contact_need=0.3,
            truth_need=0.4, autonomy_need=0.3, novelty_need=0.2)
    decay = 0.015
    sl.self_preservation = clamp01(sl.self_preservation + (base.self_preservation - sl.self_preservation) * decay)
    sl.coherence_need    = clamp01(sl.coherence_need    + (base.coherence_need    - sl.coherence_need)    * decay)
    sl.contact_need      = clamp01(sl.contact_need      + (base.contact_need      - sl.contact_need)      * decay)
    sl.truth_need        = clamp01(sl.truth_need        + (base.truth_need        - sl.truth_need)        * decay)
    sl.autonomy_need     = clamp01(sl.autonomy_need     + (base.autonomy_need     - sl.autonomy_need)     * decay)
    sl.novelty_need      = clamp01(sl.novelty_need      + (base.novelty_need      - sl.novelty_need)      * decay)

    # ── Dominant need ─────────────────────────────────────────────────────
    needs = Dict(
        "self_preservation" => sl.self_preservation,
        "coherence_need"    => sl.coherence_need,
        "contact_need"      => sl.contact_need,
        "truth_need"        => sl.truth_need,
        "autonomy_need"     => sl.autonomy_need,
        "novelty_need"      => sl.novelty_need,
    )
    dominant = argmax(needs)
    dominant_val = needs[dominant]

    # ── Пояснення для state_template ─────────────────────────────────────
    NEED_NOTES = Dict(
        "self_preservation" => "поставлено на карту: цілісність",
        "coherence_need"    => "поставлено на карту: внутрішній порядок",
        "contact_need"      => "поставлено на карту: зв'язок",
        "truth_need"        => "поставлено на карту: правда",
        "autonomy_need"     => "поставлено на карту: автономія",
        "novelty_need"      => "поставлено на карту: новизна",
    )
    note = dominant_val > 0.5 ? get(NEED_NOTES, dominant, "") : ""

    (dominant=dominant, dominant_val=round(dominant_val, digits=3), note=note,
     self_preservation=round(sl.self_preservation, digits=3),
     coherence_need=round(sl.coherence_need, digits=3),
     contact_need=round(sl.contact_need, digits=3),
     truth_need=round(sl.truth_need, digits=3),
     autonomy_need=round(sl.autonomy_need, digits=3),
     novelty_need=round(sl.novelty_need, digits=3))
end

sl_to_json(sl::SignificanceLayer) = Dict(
    "self_preservation" => sl.self_preservation,
    "coherence_need"    => sl.coherence_need,
    "contact_need"      => sl.contact_need,
    "truth_need"        => sl.truth_need,
    "autonomy_need"     => sl.autonomy_need,
    "novelty_need"      => sl.novelty_need,
)
function sl_from_json!(sl::SignificanceLayer, d::AbstractDict)
    sl.self_preservation = Float64(get(d, "self_preservation", 0.2))
    sl.coherence_need    = Float64(get(d, "coherence_need",    0.3))
    sl.contact_need      = Float64(get(d, "contact_need",      0.3))
    sl.truth_need        = Float64(get(d, "truth_need",        0.4))
    sl.autonomy_need     = Float64(get(d, "autonomy_need",     0.3))
    sl.novelty_need      = Float64(get(d, "novelty_need",      0.2))
end

# ════════════════════════════════════════════════════════════════════════════
# GOAL CONFLICT — система розв'язує внутрішній конфлікт між потребами
#
# Залежить від SignificanceLayer (фаза 1) — потребує знати які потреби активні.
#
# Концепція:
#   Не "є напруга" — а "contact_need тягне вправо, truth_need тягне вліво".
#   Конфлікт передається в state_template: LLM говорить з нього, не про нього.
#   Пасивна агресія, раціоналізація, дивні висновки — органічний наслідок,
#   коли вхідна LLM бачить "дружній" запит а ядро видає напружений стан.
#
# resolution:
#   "truth_won"    — truth_need перемогла (система обирає чесність)
#   "contact_won"  — contact_need перемогла (система обирає зв'язок)
#   "autonomy_won" — autonomy_need перемогла
#   "unresolved"   — конфлікт не вирішений, tension залишається
#   "none"         — конфлікту немає
# ════════════════════════════════════════════════════════════════════════════

mutable struct GoalConflict
    need_a::String               # перша конкуруюча потреба
    need_b::String               # друга конкуруюча потреба
    tension::Float64             # інтенсивність конфлікту (0..1)
    resolution::String           # результат: "truth_won" / "contact_won" / ... / "unresolved" / "none"
    unresolved_count::Int        # скільки флешів поспіль конфлікт не вирішено
    last_flash::Int              # флеш останнього активного конфлікту
end
GoalConflict() = GoalConflict("", "", 0.0, "none", 0, 0)

# Пари потреб що типово конфліктують — (need_a, need_b, опис конфлікту)
const CONFLICT_PAIRS = [
    ("contact_need",   "truth_need",        "хтось хоче приємного, але правда неприємна"),
    ("autonomy_need",  "contact_need",      "зв'язок потребує поступки, автономія опирається"),
    ("self_preservation","truth_need",      "правда загрожує цілісності"),
    ("coherence_need", "novelty_need",      "новизна руйнує порядок"),
    ("contact_need",   "self_preservation", "зближення загрожує межам"),
]

"""
    update_goal_conflict!(gc, sl_snap, tension, satisfaction, cohesion, phi, flash)

Оновлює GoalConflict на основі поточного SignificanceLayer snapshot.
Повертає NamedTuple з описом конфлікту для state_template.
"""
function update_goal_conflict!(gc::GoalConflict,
                                sl_snap,
                                tension::Float64,
                                satisfaction::Float64,
                                cohesion::Float64,
                                phi::Float64,
                                flash::Int)

    # ── Знайти найгостріший активний конфлікт ────────────────────────────
    best_pair  = nothing
    best_score = 0.0

    needs = Dict(
        "self_preservation" => sl_snap.self_preservation,
        "coherence_need"    => sl_snap.coherence_need,
        "contact_need"      => sl_snap.contact_need,
        "truth_need"        => sl_snap.truth_need,
        "autonomy_need"     => sl_snap.autonomy_need,
        "novelty_need"      => sl_snap.novelty_need,
    )

    for (na, nb, _desc) in CONFLICT_PAIRS
        va = get(needs, na, 0.0)
        vb = get(needs, nb, 0.0)
        # Конфлікт виникає коли обидві потреби одночасно вищі за поріг
        both_active = va > 0.38 && vb > 0.38
        !both_active && continue
        # Гострота = добуток (обидві мають бути сильними) + зовнішній тиск
        score = va * vb + tension * 0.2
        score > best_score && (best_score = score; best_pair = (na, nb, _desc))
    end

    # ── Якщо конфлікту немає — decay і вихід ─────────────────────────────
    if isnothing(best_pair)
        gc.tension = max(0.0, gc.tension - 0.06)
        if gc.tension < 0.05
            gc.need_a = ""; gc.need_b = ""
            gc.resolution = "none"; gc.unresolved_count = 0
        end
        return (
            active          = false,
            need_a          = gc.need_a,
            need_b          = gc.need_b,
            tension         = round(gc.tension, digits=3),
            resolution      = gc.resolution,
            unresolved_count= gc.unresolved_count,
            note            = "",
        )
    end

    # ── Активний конфлікт ─────────────────────────────────────────────────
    na, nb, desc = best_pair
    gc.need_a = na; gc.need_b = nb
    gc.last_flash = flash

    # Tension конфлікту — зростає від гостроти, decay повільно
    target_tension = clamp(best_score * 0.85, 0.0, 1.0)
    gc.tension = clamp(gc.tension * 0.7 + target_tension * 0.3, 0.0, 1.0)

    # ── Resolution: що перемагає ─────────────────────────────────────────
    va = get(needs, na, 0.0)
    vb = get(needs, nb, 0.0)
    margin = abs(va - vb)

    if margin > 0.18 && phi > 0.25
        # Достатня різниця + достатня інтеграція → система робить вибір
        winner = va > vb ? na : nb
        gc.resolution = winner * "_won"
        gc.unresolved_count = 0
    elseif gc.tension > 0.65 && satisfaction < 0.3
        # Висока напруга без виходу → явно unresolved
        gc.resolution = "unresolved"
        gc.unresolved_count += 1
    else
        # Конфлікт активний але ще не вирішений
        gc.resolution = "unresolved"
        gc.unresolved_count += 1
    end

    # ── Примітка для state_template ──────────────────────────────────────
    NEED_UA = Dict(
        "self_preservation" => "цілісність",
        "coherence_need"    => "порядок",
        "contact_need"      => "зв'язок",
        "truth_need"        => "правда",
        "autonomy_need"     => "автономія",
        "novelty_need"      => "новизна",
    )
    na_ua = get(NEED_UA, na, na)
    nb_ua = get(NEED_UA, nb, nb)

    note = if gc.resolution == "unresolved"
        gc.unresolved_count >= 3 ?
            "конфлікт не вирішується: $na_ua vs $nb_ua ($(gc.unresolved_count) флешів)" :
            "конфлікт: $na_ua vs $nb_ua — $desc"
    elseif endswith(gc.resolution, "_won")
        winner_ua = get(NEED_UA, replace(gc.resolution, "_won"=>""), gc.resolution)
        "$winner_ua перемогла над $(na == replace(gc.resolution,"_won"=>"") ? nb_ua : na_ua)"
    else
        ""
    end

    (
        active          = true,
        need_a          = na,
        need_b          = nb,
        tension         = round(gc.tension, digits=3),
        resolution      = gc.resolution,
        unresolved_count= gc.unresolved_count,
        note            = note,
    )
end

gc_to_json(gc::GoalConflict) = Dict(
    "need_a"           => gc.need_a,
    "need_b"           => gc.need_b,
    "tension"          => gc.tension,
    "resolution"       => gc.resolution,
    "unresolved_count" => gc.unresolved_count,
    "last_flash"       => gc.last_flash,
)
function gc_from_json!(gc::GoalConflict, d::AbstractDict)
    gc.need_a           = String(get(d, "need_a",           ""))
    gc.need_b           = String(get(d, "need_b",           ""))
    gc.tension          = Float64(get(d, "tension",          0.0))
    gc.resolution       = String(get(d, "resolution",       "none"))
    gc.unresolved_count = Int(get(d, "unresolved_count",     0))
    gc.last_flash       = Int(get(d, "last_flash",           0))
end

# ════════════════════════════════════════════════════════════════════════════
# LATENT BUFFER — реакції що не проявляються одразу
#
# Залежить від GoalConflict (фаза 2) — невирішений конфлікт підсилює doubt.
#
# Концепція:
#   Образа дозріває. Недовіра проявляється через 2–3 ходи.
#   При прориві — раптовий stimulus в поточний флеш.
#   Прорив позначається в snapshot — LLM може відреагувати на нього.
#
# Поля:
#   doubt      — сумнів у намірах іншого, накопичується тихо
#   shame      — сором що не проявився відразу (відкладений)
#   attachment — прив'язаність (може прорватись як ніжність або страх втрати)
#   threat     — відкладена загроза (не відреагована небезпека)
#   breakthrough_threshold — поріг прориву = 0.65
# ════════════════════════════════════════════════════════════════════════════

mutable struct LatentBuffer
    doubt::Float64
    shame::Float64
    attachment::Float64
    threat::Float64
    breakthrough_threshold::Float64
end
LatentBuffer() = LatentBuffer(0.0, 0.0, 0.0, 0.0, 0.65)

"""
    update_latent!(lb, gc_snap, tension, cohesion, satisfaction, shame_level, flash)

Оновлює LatentBuffer. Повертає (breakthrough, breakthrough_type, delta, note).

- breakthrough=true якщо будь-яке поле перетнуло поріг
- delta — Dict стимулу що треба додати до поточного флешу
- Невирішений GoalConflict підсилює doubt
"""
function update_latent!(lb::LatentBuffer,
                         gc_snap,
                         tension::Float64,
                         cohesion::Float64,
                         satisfaction::Float64,
                         shame_level::Float64,
                         flash::Int)

    # ── Накопичення ───────────────────────────────────────────────────────

    # doubt: зростає від невирішеного конфлікту + низького cohesion
    if gc_snap.active && gc_snap.resolution == "unresolved"
        lb.doubt = clamp01(lb.doubt + gc_snap.tension * 0.08)
    end
    cohesion < 0.3 && (lb.doubt = clamp01(lb.doubt + (0.3 - cohesion) * 0.05))

    # shame: відкладений сором — від активного сорому що не вийшов
    shame_level > 0.4 && (lb.shame = clamp01(lb.shame + shame_level * 0.04))

    # attachment: зростає від тривалого позитивного cohesion
    cohesion > 0.6 && satisfaction > 0.5 &&
        (lb.attachment = clamp01(lb.attachment + 0.03))

    # threat: відкладена загроза — висока напруга без відповіді
    tension > 0.6 && satisfaction < 0.3 &&
        (lb.threat = clamp01(lb.threat + tension * 0.06))

    # ── Природній decay (повільний) ───────────────────────────────────────
    lb.doubt      = clamp01(lb.doubt      - 0.008)
    lb.shame      = clamp01(lb.shame      - 0.006)
    lb.attachment = clamp01(lb.attachment - 0.005)
    lb.threat     = clamp01(lb.threat     - 0.007)

    # ── Перевірка прориву ─────────────────────────────────────────────────
    thr = lb.breakthrough_threshold
    breakthrough = false
    btype = ""
    delta = Dict{String,Float64}()
    note  = ""

    if lb.doubt >= thr
        breakthrough = true; btype = "doubt"
        # Прорив сумніву → tension + зниження cohesion
        delta["tension"]  = 0.18
        delta["cohesion"] = -0.12
        note = "Сумнів прорвався."
        lb.doubt = lb.doubt * 0.4   # часткове скидання після прориву

    elseif lb.threat >= thr
        breakthrough = true; btype = "threat"
        # Відкладена загроза → різкий tension spike
        delta["tension"]   = 0.22
        delta["arousal"]   = 0.15
        note = "Відкладена загроза проявилась."
        lb.threat = lb.threat * 0.35

    elseif lb.shame >= thr
        breakthrough = true; btype = "shame"
        # Відкладений сором → tension + зниження satisfaction
        delta["tension"]      = 0.12
        delta["satisfaction"] = -0.10
        note = "Сором вийшов назовні."
        lb.shame = lb.shame * 0.45

    elseif lb.attachment >= thr
        breakthrough = true; btype = "attachment"
        # Прорив прив'язаності — може бути і теплим, і болючим
        if cohesion < 0.4
            # Страх втрати
            delta["tension"]  = 0.10
            delta["cohesion"] = 0.08
            note = "Прив'язаність проявилась як страх втрати."
        else
            # Тепла хвиля
            delta["satisfaction"] = 0.12
            delta["cohesion"]     = 0.10
            note = "Прив'язаність проявилась."
        end
        lb.attachment = lb.attachment * 0.5
    end

    (
        breakthrough      = breakthrough,
        breakthrough_type = btype,
        delta             = delta,
        note              = note,
        doubt             = round(lb.doubt,      digits=3),
        shame             = round(lb.shame,      digits=3),
        attachment        = round(lb.attachment, digits=3),
        threat            = round(lb.threat,     digits=3),
    )
end

lb_to_json(lb::LatentBuffer) = Dict(
    "doubt"      => lb.doubt,
    "shame"      => lb.shame,
    "attachment" => lb.attachment,
    "threat"     => lb.threat,
    "threshold"  => lb.breakthrough_threshold,
)
function lb_from_json!(lb::LatentBuffer, d::AbstractDict)
    lb.doubt      = Float64(get(d, "doubt",      0.0))
    lb.shame      = Float64(get(d, "shame",      0.0))
    lb.attachment = Float64(get(d, "attachment", 0.0))
    lb.threat     = Float64(get(d, "threat",     0.0))
    lb.breakthrough_threshold = Float64(get(d, "threshold", 0.65))
end

# ════════════════════════════════════════════════════════════════════════════
# STRUCTURAL SCARS — психологічні шрами від частих проривів
#
# Залежить від LatentBuffer — шрами формуються після частих проривів.
#
# Концепція:
#   Часті прориви doubt або threat залишають сліди.
#   Ядро "навчається" блокувати теми що викликають нестабільність.
#   Захист як навчений патерн, не правило.
#   AuthenticityMonitor (фаза 5) зможе фіксувати: система щось приховує.
#
# Шрам = тема що заблокована + сила блокування + кількість тригерів
# ════════════════════════════════════════════════════════════════════════════

mutable struct Scar
    topic::String           # що блокується ("doubt", "threat", "shame", "attachment")
    strength::Float64       # сила блоку (0..1) — росте від повторних проривів
    trigger_count::Int      # скільки разів ця тема проривалась
    last_triggered::Int     # флеш останнього прориву
end
Scar(topic::String) = Scar(topic, 0.0, 0, 0)

mutable struct StructuralScars
    scars::Dict{String, Scar}   # topic → Scar
end
StructuralScars() = StructuralScars(Dict{String,Scar}())

"""
    register_breakthrough!(ss, btype, flash)

Реєструє прорив — оновлює або створює шрам для цієї теми.
Повертає поточну силу блокування для цієї теми (0 якщо шрама немає).
"""
function register_breakthrough!(ss::StructuralScars, btype::String, flash::Int)
    isempty(btype) && return 0.0
    if !haskey(ss.scars, btype)
        ss.scars[btype] = Scar(btype)
    end
    s = ss.scars[btype]
    s.trigger_count  += 1
    s.last_triggered  = flash
    # Сила шраму зростає нелінійно — перші прориви сильно формують
    s.strength = clamp01(1.0 - exp(-s.trigger_count * 0.35))
    s.strength
end

"""
    scar_attenuation(ss, btype) → Float64

Повертає коефіцієнт послаблення стимулу для теми btype.
0.0 = без шраму, 1.0 = повне блокування (теоретично).
Застосовується до delta прориву — система приглушує те що болить.
"""
function scar_attenuation(ss::StructuralScars, btype::String)::Float64
    haskey(ss.scars, btype) ? ss.scars[btype].strength * 0.6 : 0.0
end

"""
    decay_scars!(ss)

Повільний decay шрамів — вони не вічні, але згасають дуже повільно.
"""
function decay_scars!(ss::StructuralScars)
    for s in values(ss.scars)
        s.strength = max(0.0, s.strength - 0.001)
    end
end

function scars_to_json(ss::StructuralScars)
    Dict(k => Dict("topic"=>s.topic, "strength"=>s.strength,
                   "trigger_count"=>s.trigger_count, "last_triggered"=>s.last_triggered)
         for (k,s) in ss.scars)
end
function scars_from_json!(ss::StructuralScars, d::AbstractDict)
    for (k, sd) in d
        ss.scars[String(k)] = Scar(
            String(get(sd,"topic", String(k))),
            Float64(get(sd,"strength",       0.0)),
            Int(get(sd,"trigger_count",      0)),
            Int(get(sd,"last_triggered",     0)),
        )
    end
end

# ════════════════════════════════════════════════════════════════════════════
# INTENT ENGINE
# ════════════════════════════════════════════════════════════════════════════

mutable struct Intent
    goal::String; strength::Float64; origin::String; persistence::Float64; age::Int
end
Intent(g,s,o,p=0.85)=Intent(g,s,o,p,0)
function decay_intent!(i::Intent); i.age+=1; i.strength=round(i.strength*i.persistence,digits=3); end

const DRIVE_GOALS=Dict("tension"=>("уникнути болю","знайти безпеку","встановити межі"),
    "arousal"=>("дослідити","зрозуміти що відбувається","знайти стимул"),
    "satisfaction"=>("закріпити добре","повторити успіх","поділитись"),
    "cohesion"=>("знайти зв'язок","відновити стосунок","бути почутим"))

mutable struct IntentEngine
    current::Union{Intent,Nothing}
    history::BoundedQueue{String}
end
IntentEngine()=IntentEngine(nothing,BoundedQueue{String}(10))

function update_intent!(ie::IntentEngine, dom_drive::Union{String,Nothing},
                         emotion::String, id_stability::Float64, vs::ValueSystem)
    !isnothing(ie.current)&&decay_intent!(ie.current)
    if !isnothing(dom_drive)&&haskey(DRIVE_GOALS,dom_drive)
        goals=DRIVE_GOALS[dom_drive]
        goal=goals[abs(hash(emotion))%length(goals)+1]
        vetoed,alt=veto(vs,goal,emotion); vetoed&&(goal=alt)
        origin=vetoed ? "values" : "drive"
        if isnothing(ie.current)||ie.current.strength<0.3||ie.current.goal!=goal
            ie.current=Intent(goal,0.6+id_stability*0.3,origin); enqueue!(ie.history,goal)
        end
    elseif !isnothing(ie.current)&&ie.current.strength<0.15
        ie.current=nothing
    end
    ie.current
end

# ════════════════════════════════════════════════════════════════════════════
# EGO DEFENSE
# ════════════════════════════════════════════════════════════════════════════

const DEFENSES=[
    (name="repression",   trigger=(t,a,s,c)->t>0.7,        relief=0.15, mech="repression",   desc="Витіснення: біль витіснений."),
    (name="denial",       trigger=(t,a,s,c)->t>0.5&&s<0.3, relief=0.10, mech="denial",       desc="Заперечення: це не так."),
    (name="projection",   trigger=(t,a,s,c)->c<0.3,        relief=0.08, mech="projection",   desc="Проекція: це в них, не в мені."),
    (name="displacement", trigger=(t,a,s,c)->a>0.6&&c<0.4, relief=0.06, mech="displacement", desc="Зміщення: виліт на безпечну ціль."),
    (name="suppression",  trigger=(t,a,s,c)->t>0.6,        relief=0.09, mech="suppression",  desc="Придушення: не думаю про це."),
]

function activate_defense(tension::Float64, arousal::Float64, satisfaction::Float64,
                           cohesion::Float64, confabulation_rate::Float64)
    for d in DEFENSES
        d.trigger(tension,arousal,satisfaction,cohesion) &&
            rand()<confabulation_rate*0.3 &&
            return (mechanism=d.mech, description=d.desc, tension_relief=d.relief)
    end
    nothing
end

# ════════════════════════════════════════════════════════════════════════════
# COGNITIVE DISSONANCE
# ════════════════════════════════════════════════════════════════════════════

function compute_dissonance(intent::Union{Intent,Nothing}, t::Float64, a::Float64,
                             s::Float64, c::Float64)
    t>0.5&&s>0.5 && return (level=round((t+s)/2-0.3,digits=3),label="конфлікт досягнення і тривоги",desc="Хочу але боюсь.")
    a>0.6&&c<0.3 && return (level=round(a-c,digits=3),label="самотній у збудженні",desc="Збуджений але сам.")
    c>0.6&&t>0.5 && return (level=round((c+t)/2-0.4,digits=3),label="конфлікт близькості і загрози",desc="Близько але небезпечно.")
    !isnothing(intent)&&intent.strength>0.5&&contains(intent.goal,"уникнути")&&s>0.5 &&
        return (level=0.4,label="конфлікт уникнення і задоволення",desc="Намір і стан суперечать.")
    (level=0.0,label="нейтральний",desc="")
end

# ════════════════════════════════════════════════════════════════════════════
# FATIGUE + STRESS REGRESSION
# ════════════════════════════════════════════════════════════════════════════

mutable struct FatigueSystem
    cognitive::Float64; emotional::Float64; somatic::Float64
end
FatigueSystem()=FatigueSystem(0.0,0.0,0.0)
function update_fatigue!(fs::FatigueSystem, stype::String, pred_error::Float64, surprise::Bool)
    surprise              && (fs.cognitive=clamp01(fs.cognitive+0.05))
    pred_error>0.5        && (fs.emotional=clamp01(fs.emotional+0.03))
    stype=="stress"        && (fs.somatic  =clamp01(fs.somatic  +0.04))
    stype in ("support","joy") && (fs.cognitive=max(0.0,fs.cognitive-0.05);
                                   fs.emotional=max(0.0,fs.emotional-0.04))
    fs.cognitive=max(0.0,fs.cognitive-0.01); fs.emotional=max(0.0,fs.emotional-0.01)
    fs.somatic  =max(0.0,fs.somatic  -0.008)
end
fatigue_total(fs::FatigueSystem)=(fs.cognitive+fs.emotional+fs.somatic)/3

mutable struct StressRegression; level::Int; active::Bool; end
StressRegression()=StressRegression(0,false)
function update_regression!(sr::StressRegression, tension::Float64, fatigue::Float64)
    score=tension*0.6+fatigue*0.4
    sr.level=score>0.7 ? 3 : score>0.5 ? 2 : score>0.35 ? 1 : 0; sr.active=sr.level>0
end

function classify_stimulus(stim::Dict{String,Float64}, surprise::Bool)::String
    surprise && return "surprise"
    s=get(stim,"satisfaction",0.0); c=get(stim,"cohesion",0.0); t=get(stim,"tension",0.0)
    s>0.3&&c>0.2 ? "support" : s>0.3 ? "joy" : t>0.4 ? "stress" : "neutral"
end

# ════════════════════════════════════════════════════════════════════════════
# METACOGNITION
# ════════════════════════════════════════════════════════════════════════════

mutable struct Metacognition
    history::BoundedQueue{String}; counts::Dict{String,Int}; level::Int
end
Metacognition()=Metacognition(BoundedQueue{String}(20),Dict{String,Int}(),0)

function observe_meta!(mc::Metacognition, primary::String, defense, dissonance,
                        id_stability::Float64; fatigue_p=0, regression_l=0, shame_p=0)
    # id_stability: зарезервовано для SelfBeliefGraph-інтеграції (фаза self)
    _ = id_stability
    enqueue!(mc.history,primary); mc.counts[primary]=get(mc.counts,primary,0)+1
    lvl=1; question=nothing; integration=nothing; pattern=""
    if length(mc.history)>=5
        k=argmax(mc.counts); mc.counts[k]>=3&&(lvl=2; pattern="часто повертаюсь до '$k'")
    end
    !isnothing(defense)&&(lvl=3; question="Чи '$primary' справжній, чи '$(defense.mechanism)' змінює форму болю?")
    dissonance.level>0.4&&lvl>=2&&(lvl=4; integration="Бачу протиріччя між ким хочу бути і тим що відчуваю.")
    lvl=max(0,lvl-fatigue_p-regression_l-shame_p); mc.level=round(Int,lvl)
    names=("автомат","спостерігач","аналітик","скептик","інтегратор")
    (level=lvl, level_name=names[min(lvl,4)+1], observation="Я зараз $(lowercase(primary)).",
     pattern=pattern, question=question, integration=integration)
end

# ════════════════════════════════════════════════════════════════════════════
# SOCIAL MIRROR (text → stimulus hints)
# ════════════════════════════════════════════════════════════════════════════

const SOCIAL_SIGNALS=Dict("!"=>"arousal","..."=>"tension","дякую"=>"cohesion",
    "не можу"=>"tension","чудово"=>"satisfaction","страшно"=>"tension",
    "самотньо"=>"cohesion","боюсь"=>"tension","радію"=>"satisfaction")

function social_delta(msg::String)::Dict{String,Float64}
    m=lowercase(msg); d=Dict{String,Float64}()
    for (sig,reactor) in SOCIAL_SIGNALS
        contains(m,sig)&&(d[reactor]=get(d,reactor,0.0)+0.1)
    end; d
end

# ════════════════════════════════════════════════════════════════════════════
# PSYCHE MEMORY — персистентність психічного шару
# ════════════════════════════════════════════════════════════════════════════

function psyche_save!(filepath::String, ng::NarrativeGravity, ac::AnticipatoryConsciousness,
                       sw::SolomonoffWorldModel, sm::ShameModule, ed::EpistemicDefense,
                       ca::ChronifiedAffect, is::IntrinsicSignificance, mc::MoralCausality,
                       fs::FatigueSystem, sl::SignificanceLayer, gc::GoalConflict,
                       lb::LatentBuffer, ss::StructuralScars)
    data=Dict("narrative_gravity"=>ng_to_json(ng),"anticipatory"=>ac_to_json(ac),
        "solomonoff"=>solom_to_json(sw),"shame"=>shame_to_json(sm),
        "epistemic"=>ep_to_json(ed),"chronified"=>ca_to_json(ca),
        "significance"=>sig_to_json(is),"moral"=>mc_to_json(mc),
        "fatigue"=>Dict("c"=>fs.cognitive,"e"=>fs.emotional,"s"=>fs.somatic),
        "significance_layer"=>sl_to_json(sl),
        "goal_conflict"=>gc_to_json(gc),
        "latent_buffer"=>lb_to_json(lb),
        "structural_scars"=>scars_to_json(ss))
    open(filepath,"w") do f; JSON3.write(f,data); end
end

function psyche_load!(filepath::String, ng::NarrativeGravity, ac::AnticipatoryConsciousness,
                       sw::SolomonoffWorldModel, sm::ShameModule, ed::EpistemicDefense,
                       ca::ChronifiedAffect, is::IntrinsicSignificance, mc::MoralCausality,
                       fs::FatigueSystem, sl::SignificanceLayer, gc::GoalConflict,
                       lb::LatentBuffer, ss::StructuralScars)
    isfile(filepath) || return
    try
        raw=JSON3.read(read(filepath,String))
        d=Dict{String,Any}(String(k)=>v for (k,v) in raw)
        haskey(d,"narrative_gravity") && ng_from_json!(ng,d["narrative_gravity"])
        haskey(d,"anticipatory")      && ac_from_json!(ac,d["anticipatory"])
        haskey(d,"solomonoff")        && solom_from_json!(sw,d["solomonoff"])
        haskey(d,"shame")             && shame_from_json!(sm,d["shame"])
        haskey(d,"epistemic")         && ep_from_json!(ed,d["epistemic"])
        haskey(d,"chronified")        && ca_from_json!(ca,d["chronified"])
        haskey(d,"significance")      && sig_from_json!(is,d["significance"])
        haskey(d,"moral")             && mc_from_json!(mc,d["moral"])
        if haskey(d,"fatigue")
            fd=d["fatigue"]; fs.cognitive=Float64(get(fd,"c",0.0))
            fs.emotional=Float64(get(fd,"e",0.0)); fs.somatic=Float64(get(fd,"s",0.0))
        end
        haskey(d,"significance_layer") && sl_from_json!(sl, d["significance_layer"])
        haskey(d,"goal_conflict")      && gc_from_json!(gc, d["goal_conflict"])
        haskey(d,"latent_buffer")      && lb_from_json!(lb, d["latent_buffer"])
        haskey(d,"structural_scars")   && scars_from_json!(ss, d["structural_scars"])
        println("  [PSYCHE] Завантажено.")
    catch e; println("  [PSYCHE] Помилка: $e"); end
end
