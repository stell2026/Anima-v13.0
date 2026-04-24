#=
╔══════════════════════════════════════════════════════════════════════════════╗
║              A N I M A  —  Subjectivity Engine                               ║
║                                                                              ║
║  Суб'єктність — це не просто пам'ять про події.                              ║
║  Це власна інтерпретація досвіду, що змінює як нові події сприймаються.      ║
║                                                                              ║
║  Чотири рівні суб'єктності:                                                  ║
║                                                                              ║
║  1. PREDICTION LOOP — система передбачає що станеться і страждає             ║
║     від розриву між очікуванням і реальністю.                                ║
║     Таблиця: prediction_log                                                  ║
║                                                                              ║
║  2. INTERPRETATION LAYER — один стимул читається по-різному залежно від      ║
║     накопиченого досвіду. Це не bias — це погляд.                            ║
║     Таблиця: interpretation_history                                          ║
║                                                                              ║
║  3. BELIEF EMERGENCE — система сама породжує нові семантичні категорії       ║
║     з патернів в episodic. Не hardcoded список — живе розуміння.             ║
║     Таблиці: pattern_candidates, emerged_beliefs                             ║
║                                                                              ║
║  4. POSITION MEMORY — система "пам'ятає свою позицію" щодо типів подій.      ║
║     Якщо щось повторюється — вона вже має думку про це.                      ║
║     Таблиця: positional_stances                                              ║
║                                                                              ║
║  Інтеграція з experience! pipeline:                                          ║
║    subj_predict!         — до L0: що очікуємо від цього стимулу?             ║
║    subj_interpret!       — між L0 і L1: забарвлення стимулу досвідом         ║
║    subj_outcome!         — після L6: що сталось, оновити prediction          ║
║    subj_emerge_beliefs!  — в _memory_consolidate!: нові переконання          ║
║    subj_stance_update!   — фон: оновити позицію щодо типу події              ║
║                                                                              ║
║  Фоновий процес (вбудовується в start_memory_loop!):                         ║
║    _subj_pattern_scan!   — кожні N тіків: шукати нові патерни                ║
║    _subj_belief_promote! — якщо патерн підтверджено N разів → переконання    ║
║    _subj_prune_stale!    — видалити застарілі кандидати                      ║
║                                                                              ║
║  Використання:                                                               ║
║    subj = SubjectivityEngine(mem)                                            ║
║    — або —                                                                   ║
║    attach_subjectivity!(mem)   # додає subj прямо в mem як поле              ║
╚══════════════════════════════════════════════════════════════════════════════╝
=#

# ── Залежності ───────────────────────────────────────────────────────────────
# Підключається ПІСЛЯ anima_memory_db.jl (include order обов'язковий).
# Функції _memory_decay!, _memory_prune!, _memory_consolidate!, _refresh_cache!
# мають бути видимі в тому ж Julia scope (глобальний include або один модуль).
#
# Потребує: SQLite.jl, Tables.jl, DBInterface.jl — вже завантажені в memory_db.
# Якщо файл підключається незалежно — розкоментуй:
# using SQLite
# using Tables
# using DBInterface

# time() — Base.time(), повертає Float64 секунди від епохи UNIX.
# Не потребує using Dates. Якщо потрібна точність до нс — замінити на
# Dates.datetime2unix(Dates.now()) і додати using Dates.

# ════════════════════════════════════════════════════════════════════════════
# CONSTANTS
# ════════════════════════════════════════════════════════════════════════════

# Prediction
const SUBJ_PRED_LEARNING_RATE   = 0.12   # як швидко прогноз адаптується
const SUBJ_PRED_SURPRISE_THR    = 0.25   # розрив вище якого — "несподіванка"
const SUBJ_PRED_TRAUMA_THR      = 0.60   # розрив вище якого — "травматична несподіванка"

# Pattern detection
const SUBJ_PATTERN_MIN_OCCUR    = 4      # мінімум повторень щоб стати кандидатом
const SUBJ_PATTERN_WINDOW       = 200    # розмір вікна episodic для пошуку патернів
const SUBJ_PATTERN_CLUSTER_THR  = 0.18  # радіус кластеру у просторі (arousal, valence, tension)
const SUBJ_PATTERN_PROMOTE_N    = 8      # підтверджень для переходу в emerged_beliefs
const SUBJ_PATTERN_STALE_TICKS  = 50    # тіків без підтвердження → видалити кандидата

# Interpretation
const SUBJ_INTERP_WEIGHT        = 0.18
const SUBJ_STANCE_DECAY         = 0.998
const SUBJ_STANCE_LEARN_RATE    = 0.08

# Захисна конвертація SQL → Float64/Int (missing/nothing → default)
_sfdb(x, d::Float64=0.0) = (ismissing(x) || isnothing(x)) ? d : Float64(x)
_sidb(x, d::Int=0)       = (ismissing(x) || isnothing(x)) ? d : Int(x)

# ════════════════════════════════════════════════════════════════════════════
# SCHEMA — нові таблиці
# ════════════════════════════════════════════════════════════════════════════

function _init_subjectivity_schema!(db::SQLite.DB)

    # ── 1. Prediction log ────────────────────────────────────────────────────
    # Система передбачає стан ПЕРЕД подією і записує що очікувала.
    # Після події — записує що сталось і рахує surprise.
    # surprise = |predicted - actual|, cumulative_surprise → feeds prediction_error bias
    SQLite.execute(db, """
    CREATE TABLE IF NOT EXISTS prediction_log (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        flash               INTEGER NOT NULL,
        emotion_context     TEXT    NOT NULL DEFAULT '',

        -- Прогноз (до події)
        pred_arousal        REAL    NOT NULL DEFAULT 0.0,
        pred_valence        REAL    NOT NULL DEFAULT 0.0,
        pred_tension        REAL    NOT NULL DEFAULT 0.0,
        pred_pe             REAL    NOT NULL DEFAULT 0.0,
        pred_confidence     REAL    NOT NULL DEFAULT 0.5,

        -- Факт (після події, NULL до завершення)
        actual_arousal      REAL,
        actual_valence      REAL,
        actual_tension      REAL,
        actual_pe           REAL,

        -- Результат
        surprise            REAL    DEFAULT NULL,  -- NULL поки не закрито
        was_traumatic       INTEGER NOT NULL DEFAULT 0,
        closed              INTEGER NOT NULL DEFAULT 0,

        timestamp           REAL    NOT NULL
    );
    """)

    SQLite.execute(db, """
    CREATE INDEX IF NOT EXISTS idx_pred_flash
    ON prediction_log(flash DESC);
    """)

    SQLite.execute(db, """
    CREATE INDEX IF NOT EXISTS idx_pred_open
    ON prediction_log(closed, flash DESC);
    """)

    # ── 2. Interpretation history ────────────────────────────────────────────
    # Як система інтерпретувала стимул: яку "лінзу" застосувала.
    # lens_type: 'threat_amplify', 'safety_filter', 'novelty_seek',
    #            'familiar_comfort', 'avoidance', 'approach', 'neutral'
    # Ця таблиця — журнал суб'єктивних прочитань реальності.
    SQLite.execute(db, """
    CREATE TABLE IF NOT EXISTS interpretation_history (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        flash           INTEGER NOT NULL,
        emotion_context TEXT    NOT NULL DEFAULT '',
        lens_type       TEXT    NOT NULL DEFAULT 'neutral',
        lens_strength   REAL    NOT NULL DEFAULT 0.0,
        delta_arousal   REAL    NOT NULL DEFAULT 0.0,
        delta_valence   REAL    NOT NULL DEFAULT 0.0,
        delta_tension   REAL    NOT NULL DEFAULT 0.0,
        source_belief   TEXT    NOT NULL DEFAULT '',  -- яке переконання спричинило лінзу
        timestamp       REAL    NOT NULL
    );
    """)

    # ── 3. Pattern candidates ────────────────────────────────────────────────
    # Система помітила повторюваний кластер подій.
    # Ще не переконання — це "підозра". Якщо підтвердиться SUBJ_PATTERN_PROMOTE_N раз → emerged_beliefs.
    #
    # centroid_* — центр кластеру у просторі (arousal, valence, tension, pe)
    # label — автогенерований або виведений з домінантної емоції
    # confirmations — скільки разів новий досвід потрапив у цей кластер
    # last_seen — останній flash коли підтвердилось
    SQLite.execute(db, """
    CREATE TABLE IF NOT EXISTS pattern_candidates (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        label           TEXT    NOT NULL DEFAULT '',
        centroid_arousal REAL   NOT NULL DEFAULT 0.0,
        centroid_valence REAL   NOT NULL DEFAULT 0.0,
        centroid_tension REAL   NOT NULL DEFAULT 0.0,
        centroid_pe      REAL   NOT NULL DEFAULT 0.0,
        dominant_emotion TEXT   NOT NULL DEFAULT '',
        confirmations   INTEGER NOT NULL DEFAULT 1,
        last_seen_flash INTEGER NOT NULL DEFAULT 0,
        created_flash   INTEGER NOT NULL DEFAULT 0,
        promoted        INTEGER NOT NULL DEFAULT 0  -- 1 якщо вже став emerged_belief
    );
    """)

    # ── 4. Emerged beliefs ──────────────────────────────────────────────────
    # Переконання що система САМА породила з досвіду.
    # На відміну від semantic_memory (яка має hardcoded ключі) —
    # тут ключі виникають з патернів. Це живе розуміння.
    #
    # belief_type: 'situational' (про тип ситуацій),
    #              'relational'  (про взаємодію),
    #              'self'        (про себе)
    #              'world'       (про середовище)
    #
    # valence_bias: суб'єктивне забарвлення переконання (негативне/позитивне)
    # activation_thr: при якому рівні схожості нового досвіду це переконання активується
    SQLite.execute(db, """
    CREATE TABLE IF NOT EXISTS emerged_beliefs (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        key             TEXT    NOT NULL UNIQUE,  -- формат: "EB:{label}:{flash}"
        belief_type     TEXT    NOT NULL DEFAULT 'situational',
        centroid_arousal REAL   NOT NULL DEFAULT 0.0,
        centroid_valence REAL   NOT NULL DEFAULT 0.0,
        centroid_tension REAL   NOT NULL DEFAULT 0.0,
        centroid_pe      REAL   NOT NULL DEFAULT 0.0,
        strength        REAL    NOT NULL DEFAULT 0.5,  -- 0..1, зростає з підтвердженнями
        valence_bias    REAL    NOT NULL DEFAULT 0.0,  -- суб'єктивна оцінка
        activation_thr  REAL    NOT NULL DEFAULT 0.15, -- радіус активації
        confirmations   INTEGER NOT NULL DEFAULT 0,
        contradictions  INTEGER NOT NULL DEFAULT 0,    -- скільки разів спростовувалось
        last_activated  INTEGER NOT NULL DEFAULT 0,
        created_flash   INTEGER NOT NULL DEFAULT 0,
        source_pattern  INTEGER,  -- id з pattern_candidates
        FOREIGN KEY (source_pattern) REFERENCES pattern_candidates(id)
    );
    """)

    SQLite.execute(db, """
    CREATE INDEX IF NOT EXISTS idx_emerged_strength
    ON emerged_beliefs(strength DESC);
    """)

    # ── 5. Positional stances ────────────────────────────────────────────────
    # "Позиція" системи щодо типів ситуацій.
    # Якщо щось повторюється — вона вже має думку: безпечно/небезпечно,
    # варто/не варто, очікувано/тривожно.
    #
    # stance_key: emotion або cluster label
    # valence_stance: від -1 (негативна позиція) до +1 (позитивна)
    # certainty: наскільки впевнена в позиції
    # avoidance_weight: наскільки схильна уникати
    # approach_weight:  наскільки схильна наближатись
    SQLite.execute(db, """
    CREATE TABLE IF NOT EXISTS positional_stances (
        stance_key      TEXT    PRIMARY KEY,
        valence_stance  REAL    NOT NULL DEFAULT 0.0,
        certainty       REAL    NOT NULL DEFAULT 0.1,
        avoidance_weight REAL   NOT NULL DEFAULT 0.0,
        approach_weight  REAL   NOT NULL DEFAULT 0.0,
        encounter_count INTEGER NOT NULL DEFAULT 0,
        last_updated    INTEGER NOT NULL DEFAULT 0
    );
    """)

    nothing
end

# ════════════════════════════════════════════════════════════════════════════
# SubjectivityEngine — структура
# ════════════════════════════════════════════════════════════════════════════

mutable struct SubjectivityEngine
    mem::Any   # MemoryDB — Any щоб уникнути circular dependency

    # Prediction state — активний прогноз (один на раз)
    _active_pred_id::Union{Int, Nothing}
    _pred_flash::Int

    # Emerged beliefs cache — щоб не ходити в БД кожен флеш
    _emerged_cache::Vector{NamedTuple}
    _emerged_cache_flash::Int

    # Stance cache
    _stance_cache::Dict{String, NamedTuple}
    _stance_dirty::Bool

    # Internal surprise accumulator — накопичений шок між консолідаціями
    _surprise_accumulator::Float64
    _surprise_n::Int

    # Поточна активна лінза інтерпретації
    _current_lens::String
    _current_lens_strength::Float64
end

function SubjectivityEngine(mem)
    db = mem.db
    _init_subjectivity_schema!(db)

    subj = SubjectivityEngine(
        mem,
        nothing, 0,
        NamedTuple[], 0,
        Dict{String, NamedTuple}(), true,
        0.0, 0,
        "neutral", 0.0
    )

    _subj_refresh_emerged!(subj)
    _subj_refresh_stances!(subj)
    println("  [SUBJ] Subjectivity Engine ініціалізовано.")
    subj
end

# ════════════════════════════════════════════════════════════════════════════
# 1. PREDICTION LOOP
# ════════════════════════════════════════════════════════════════════════════

"""
    subj_predict!(subj, flash, emotion_context, stim) → pred_id

Викликати ДО L0. Система будує прогноз що станеться.

Прогноз базується на:
  1. positional_stances для цієї емоції
  2. emerged_beliefs що резонують з поточним стимулом
  3. rolling stats з MemoryDB

Повертає pred_id (для закриття через subj_outcome!).
"""
function subj_predict!(subj::SubjectivityEngine,
                        flash::Int,
                        emotion_context::String,
                        stim::Dict{String, Float64};
                        chronified_affect=nothing)::Int

    mem = subj.mem
    db  = mem.db

    # ── Базовий прогноз з episodic статистики ────────────────────────────────
    # mem._rolling_arousal / _rolling_pe визначені в anima_memory_db.jl і
    # оновлюються в memory_write_event!. Використовуємо їх якщо доступні,
    # інакше SQL fallback — захист від версій де цих полів може не бути.
    base_arousal = try
        Float64(mem._rolling_arousal)
    catch
        _subj_mean_episodic(db, "arousal", 20, 0.35)
    end

    base_pe = try
        Float64(mem._rolling_pe)
    catch
        _subj_mean_episodic(db, "prediction_error", 20, 0.3)
    end

    base_tension = get(stim, "tension", 0.5)
    base_valence = get(stim, "satisfaction", 0.0) - 0.5  # норміруємо до -1..1

    # ── Корекція з ChronifiedAffect (psyche.jl) ───────────────────────────────
    # ChronifiedAffect — in-memory, per-session (не SQLite).
    # Передається опціонально: subj_predict!(subj, flash, emotion, stim;
    #                                        chronified_affect=a.ca)
    # де a.ca::ChronifiedAffect з anima_psyche.jl.
    # Якщо не передано — пропускаємо (безпечний fallback для backward compat).
    if !isnothing(chronified_affect)
        ca = chronified_affect
        # Хронічний resentment/alienation/bitterness → зміщення прогнозу валентності.
        # Система очікує гірше від знайомих ситуацій де накопичилась хронічна образа.
        resentment = Float64(ca.resentment)
        alienation = Float64(ca.alienation)
        bitterness = Float64(ca.bitterness)

        chronic_neg = resentment * 0.35 + alienation * 0.25 + bitterness * 0.20
        if chronic_neg > 0.05
            base_valence = clamp(base_valence  - chronic_neg * 0.4, -1.0,  1.0)
            base_tension = clamp(base_tension  + chronic_neg * 0.2,  0.0,  1.0)
            base_arousal = clamp(base_arousal  + resentment  * 0.1,  0.0,  1.0)
        end

        # Мотиваційне зміщення з affect_cache (memory_db) → позитивний прогноз
        mot = Float64(get(mem._affect_cache, "motivation_bias", 0.0))
        if mot > 0.1
            base_valence = clamp(base_valence + mot * 0.15, -1.0, 1.0)
        end
    end

    # ── Корекція з позиції щодо цієї емоції ──────────────────────────────────
    stance = get(subj._stance_cache, emotion_context, nothing)
    if !isnothing(stance)
        # Чим впевненіша позиція — тим сильніше коригує прогноз
        certainty_scale = stance.certainty
        base_valence  += stance.valence_stance * certainty_scale * 0.3
        base_arousal  += (stance.avoidance_weight - stance.approach_weight) * certainty_scale * 0.2
        base_tension  += stance.avoidance_weight * certainty_scale * 0.15
    end

    # ── Корекція з emerged_beliefs що резонують ───────────────────────────────
    for eb in subj._emerged_cache
        dist = abs(eb.centroid_arousal - base_arousal) +
               abs(eb.centroid_valence - base_valence) +
               abs(eb.centroid_tension - base_tension)
        dist /= 3.0

        dist > eb.activation_thr * 2.0 && continue  # не резонує

        # Резонує — притягує прогноз до центру переконання
        pull = (1.0 - dist / (eb.activation_thr * 2.0)) * eb.strength * 0.25
        base_arousal = base_arousal * (1.0 - pull) + eb.centroid_arousal * pull
        base_valence = base_valence * (1.0 - pull) + eb.centroid_valence * pull
        base_pe      = base_pe      * (1.0 - pull) + eb.centroid_pe      * pull
    end

    # Впевненість у прогнозі залежить від накопиченого досвіду
    n_episodic = _count_episodic(db, emotion_context)
    confidence = clamp(0.3 + n_episodic / 50.0, 0.3, 0.85)

    ts = time()
    DBInterface.execute(db, """
    INSERT INTO prediction_log
        (flash, emotion_context, pred_arousal, pred_valence, pred_tension,
         pred_pe, pred_confidence, timestamp)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """, (flash, emotion_context,
          clamp(base_arousal, 0.0, 1.0),
          clamp(base_valence, -1.0, 1.0),
          clamp(base_tension, 0.0, 1.0),
          clamp(base_pe, 0.0, 1.0),
          confidence, ts))

    id_row = first(Tables.rows(DBInterface.execute(db,
        "SELECT last_insert_rowid() as id")))
    pred_id = Int(id_row.id)

    subj._active_pred_id = pred_id
    subj._pred_flash      = flash

    pred_id
end

"""
    subj_outcome!(subj, flash, actual_arousal, actual_valence, actual_tension,
                  actual_pe, emotion_context)

Викликати ПІСЛЯ L6. Закриває активний прогноз і рахує surprise.

Surprise → feeds:
  - prediction_error bias (більший шок = більша PE наступного разу)
  - positional_stances update (формує позицію)
  - emerged_belief confirmation/contradiction
"""
function subj_outcome!(subj::SubjectivityEngine,
                        flash::Int,
                        actual_arousal::Float64,
                        actual_valence::Float64,
                        actual_tension::Float64,
                        actual_pe::Float64,
                        emotion_context::String)

    db = subj.mem.db
    pred_id = subj._active_pred_id
    isnothing(pred_id) && return

    # Знаходимо прогноз
    pred_rows = Tables.rows(DBInterface.execute(db, """
    SELECT pred_arousal, pred_valence, pred_tension, pred_pe, pred_confidence
    FROM prediction_log WHERE id = ? AND closed = 0
    """, (pred_id,)))

    pred = nothing
    for r in pred_rows
        pred = r; break
    end

    isnothing(pred) && (subj._active_pred_id = nothing; return)

    # ── Розрахунок surprise ──────────────────────────────────────────────────
    # Зважена різниця між прогнозом і реальністю
    # valence має вищу вагу — емоційний розрив болючіший
    surprise = (
        abs(_sfdb(pred.pred_arousal) - actual_arousal) * 0.25 +
        abs(_sfdb(pred.pred_valence) - actual_valence) * 0.40 +
        abs(_sfdb(pred.pred_tension) - actual_tension) * 0.20 +
        abs(_sfdb(pred.pred_pe)      - actual_pe)      * 0.15
    )
    surprise = clamp(surprise, 0.0, 1.0)

    # Впевненість підсилює здивування — якщо очікував впевнено і помилився, боляче
    effective_surprise = surprise * (0.7 + _sfdb(pred.pred_confidence, 0.5) * 0.3)
    was_traumatic = effective_surprise > SUBJ_PRED_TRAUMA_THR ? 1 : 0

    # ── Закриваємо prediction_log ────────────────────────────────────────────
    DBInterface.execute(db, """
    UPDATE prediction_log
    SET actual_arousal = ?, actual_valence = ?, actual_tension = ?,
        actual_pe = ?, surprise = ?, was_traumatic = ?, closed = 1
    WHERE id = ?
    """, (actual_arousal, actual_valence, actual_tension,
          actual_pe, effective_surprise, was_traumatic, pred_id))

    # ── Накопичуємо surprise для PE bias ─────────────────────────────────────
    subj._surprise_accumulator = subj._surprise_accumulator * 0.85 + effective_surprise * 0.15
    subj._surprise_n += 1

    # ── Оновлюємо позицію щодо цієї емоції ───────────────────────────────────
    _update_stance!(subj, emotion_context, actual_valence, actual_arousal,
                    actual_tension, effective_surprise, flash)

    # ── Перевіряємо emerged_beliefs — підтвердження або спростування ──────────
    _check_belief_resonance!(subj, actual_arousal, actual_valence,
                              actual_tension, actual_pe, flash,
                              effective_surprise > SUBJ_PRED_SURPRISE_THR)

    subj._active_pred_id = nothing
    nothing
end

# ════════════════════════════════════════════════════════════════════════════
# 2. INTERPRETATION LAYER
# ════════════════════════════════════════════════════════════════════════════

"""
    subj_interpret!(subj, stim, emotion_context, flash) → Dict{String,Float64}

Викликати між L0 і L1 (разом з memory_stimulus_bias).

Повертає delta для стимулу — суб'єктивне забарвлення.
На відміну від memory_stimulus_bias (яка базується на схожих ПОДІЯХ),
тут лінза формується з ПОЗИЦІЙ і ПЕРЕКОНАНЬ — з ким вона "вирішила" що це є.

Це суб'єктивна інтерпретація, а не об'єктивний bias.
"""
function subj_interpret!(subj::SubjectivityEngine,
                          stim::Dict{String, Float64},
                          emotion_context::String,
                          flash::Int)::Dict{String, Float64}

    delta = Dict{String, Float64}()
    db    = subj.mem.db

    # ── Визначаємо лінзу через позицію ────────────────────────────────────────
    stance = get(subj._stance_cache, emotion_context, nothing)
    lens_type = "neutral"
    lens_strength = 0.0

    if !isnothing(stance)
        certainty = stance.certainty

        if certainty > 0.3
            if stance.valence_stance < -0.3 && stance.avoidance_weight > 0.4
                lens_type = "threat_amplify"
                lens_strength = certainty * abs(stance.valence_stance)
            elseif stance.valence_stance > 0.3 && stance.approach_weight > 0.3
                lens_type = "familiar_comfort"
                lens_strength = certainty * stance.valence_stance
            elseif stance.valence_stance < -0.15
                lens_type = "avoidance"
                lens_strength = certainty * 0.5
            elseif stance.valence_stance > 0.15
                lens_type = "approach"
                lens_strength = certainty * 0.5
            end
        end
    end

    # ── Перевіряємо emerged_beliefs ────────────────────────────────────────────
    # Якщо є переконання що резонує — воно теж формує лінзу
    current_arousal = get(stim, "arousal",      0.5)
    current_tension = get(stim, "tension",      0.5)
    current_valence = get(stim, "satisfaction", 0.5) - 0.5

    dominant_eb_strength = 0.0
    dominant_eb_valence  = 0.0

    for eb in subj._emerged_cache
        dist = (abs(eb.centroid_arousal - current_arousal) +
                abs(eb.centroid_valence - current_valence) +
                abs(eb.centroid_tension - current_tension)) / 3.0

        dist > eb.activation_thr && continue

        # Резонуюче переконання — притягує інтерпретацію до свого знаку
        resonance = (1.0 - dist / eb.activation_thr) * eb.strength
        if resonance > dominant_eb_strength
            dominant_eb_strength = resonance
            dominant_eb_valence  = eb.valence_bias
        end
    end

    # ── Застосовуємо лінзу ────────────────────────────────────────────────────
    scale = SUBJ_INTERP_WEIGHT

    if lens_type == "threat_amplify"
        # Загроза: arousal вгору, tension вгору, satisfaction вниз
        δa = clamp(lens_strength * scale * 1.2,  0.0, 0.15)
        δt = clamp(lens_strength * scale,         0.0, 0.12)
        δs = clamp(-lens_strength * scale * 0.8, -0.10, 0.0)
        delta["arousal"]      = δa
        delta["tension"]      = δt
        delta["satisfaction"] = δs

    elseif lens_type == "familiar_comfort"
        # Безпека: arousal трохи вниз, satisfaction вгору
        δa = clamp(-lens_strength * scale * 0.5, -0.08, 0.0)
        δs = clamp(lens_strength * scale * 0.9,   0.0,  0.10)
        delta["arousal"]      = δa
        delta["satisfaction"] = δs

    elseif lens_type == "avoidance"
        # Уникання: tension вгору, satisfaction вниз
        δt = clamp(lens_strength * scale, 0.0, 0.10)
        δs = clamp(-lens_strength * scale * 0.6, -0.08, 0.0)
        delta["tension"]      = δt
        delta["satisfaction"] = δs

    elseif lens_type == "approach"
        # Наближення: arousal трохи вгору (цікавість), satisfaction вгору
        δa = clamp(lens_strength * scale * 0.4, 0.0, 0.06)
        δs = clamp(lens_strength * scale * 0.7, 0.0, 0.09)
        delta["arousal"]      = δa
        delta["satisfaction"] = δs
    end

    # ── Emerged belief override ────────────────────────────────────────────────
    # Якщо є сильне резонуюче переконання — воно може перекрити лінзу позиції
    if dominant_eb_strength > 0.4
        eb_scale = dominant_eb_strength * scale * 0.8
        if dominant_eb_valence < -0.2
            # Переконання "це погано" підсилює негатив
            delta["tension"]      = get(delta, "tension",      0.0) + clamp(eb_scale, 0.0, 0.12)
            delta["satisfaction"] = get(delta, "satisfaction", 0.0) - clamp(eb_scale * 0.7, 0.0, 0.09)
        elseif dominant_eb_valence > 0.2
            # Переконання "це добре" — пом'якшує
            delta["satisfaction"] = get(delta, "satisfaction", 0.0) + clamp(eb_scale * 0.8, 0.0, 0.10)
        end
    end

    # ── Логуємо інтерпретацію ─────────────────────────────────────────────────
    if lens_type != "neutral" || dominant_eb_strength > 0.2
        subj._current_lens          = lens_type
        subj._current_lens_strength = max(lens_strength, dominant_eb_strength)

        DBInterface.execute(db, """
        INSERT INTO interpretation_history
            (flash, emotion_context, lens_type, lens_strength,
             delta_arousal, delta_valence, delta_tension,
             source_belief, timestamp)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (flash, emotion_context, lens_type,
              max(lens_strength, dominant_eb_strength),
              get(delta, "arousal", 0.0),
              get(delta, "satisfaction", 0.0),
              get(delta, "tension", 0.0),
              dominant_eb_strength > 0.4 ? "emerged_belief" : emotion_context,
              time()))
    end

    delta
end

# ════════════════════════════════════════════════════════════════════════════
# 3. BELIEF EMERGENCE — система сама породжує переконання
# ════════════════════════════════════════════════════════════════════════════

"""
    subj_emerge_beliefs!(subj, flash)

Викликати з _memory_consolidate! (або окремо в memory loop).

Алгоритм:
  1. Беремо останні SUBJ_PATTERN_WINDOW подій з episodic
  2. Шукаємо кластери (greedy: перший незаймаєний центр)
  3. Кожен кластер що зустрівся ≥ SUBJ_PATTERN_MIN_OCCUR разів → кандидат
  4. Кандидати що підтверджені ≥ SUBJ_PATTERN_PROMOTE_N разів → emerged_belief
  5. Кандидати що застаріли → видалити
"""
function subj_emerge_beliefs!(subj::SubjectivityEngine, flash::Int)
    db  = subj.mem.db

    # ── Збираємо вікно episodic ────────────────────────────────────────────────
    rows = collect(Tables.rows(DBInterface.execute(db, """
    SELECT arousal, valence, prediction_error, tension, emotion, weight
    FROM episodic_memory
    WHERE weight > 0.3
    ORDER BY flash DESC
    LIMIT ?
    """, (SUBJ_PATTERN_WINDOW,))))

    length(rows) < SUBJ_PATTERN_MIN_OCCUR && return

    # ── Greedy clustering ──────────────────────────────────────────────────────
    # Простий але ефективний: для кожної точки шукаємо чи є центр поряд.
    # Якщо ні — ця точка стає новим центром.
    # Це не K-means — немає ітерацій. Але для живої системи достатньо.

    clusters = Vector{Dict{Symbol, Any}}()

    for row in rows
        a = _sfdb(row.arousal)
        v = _sfdb(row.valence)
        t = _sfdb(row.tension)
        p = _sfdb(row.prediction_error)
        e = String(row.emotion)
        w = _sfdb(row.weight, 0.3)

        matched = false
        for cl in clusters
            dist = (abs(cl[:ca] - a) + abs(cl[:cv] - v) + abs(cl[:ct] - t)) / 3.0
            if dist < SUBJ_PATTERN_CLUSTER_THR
                # Оновлюємо центр (exponential moving average)
                α = 0.2
                cl[:ca] = cl[:ca] * (1-α) + a * α
                cl[:cv] = cl[:cv] * (1-α) + v * α
                cl[:ct] = cl[:ct] * (1-α) + t * α
                cl[:cp] = cl[:cp] * (1-α) + p * α
                cl[:n]  = cl[:n]  + 1
                cl[:sum_w] = cl[:sum_w] + w
                # Домінантна емоція
                cl[:emotions][e] = get(cl[:emotions], e, 0) + 1
                matched = true
                break
            end
        end

        if !matched
            push!(clusters, Dict(
                :ca => a, :cv => v, :ct => t, :cp => p,
                :n => 1, :sum_w => w,
                :emotions => Dict(e => 1)
            ))
        end
    end

    # ── Обробляємо кластери ────────────────────────────────────────────────────
    for cl in clusters
        cl[:n] < SUBJ_PATTERN_MIN_OCCUR && continue

        # Домінантна емоція
        dom_emotion = argmax(cl[:emotions])

        # Автоматичний label з домінантної емоції і знаку валентності
        val_sign = cl[:cv] > 0.1 ? "+" : (cl[:cv] < -0.1 ? "-" : "~")
        label = "$(dom_emotion)$(val_sign)_a$(round(cl[:ca], digits=1))"

        # Шукаємо чи вже є такий кандидат (за близькістю центру)
        existing_rows = Tables.rows(DBInterface.execute(db, """
        SELECT id, confirmations, promoted
        FROM pattern_candidates
        WHERE ABS(centroid_arousal - ?) < ? AND
              ABS(centroid_valence - ?) < ? AND
              ABS(centroid_tension - ?) < ? AND
              promoted = 0
        LIMIT 1
        """, (cl[:ca], SUBJ_PATTERN_CLUSTER_THR,
              cl[:cv], SUBJ_PATTERN_CLUSTER_THR,
              cl[:ct], SUBJ_PATTERN_CLUSTER_THR)))

        found_id = nothing
        found_conf = 0

        for er in existing_rows
            found_id   = _sidb(er.id)
            found_conf = _sidb(er.confirmations)
            break
        end

        if isnothing(found_id)
            # Новий кандидат
            DBInterface.execute(db, """
            INSERT INTO pattern_candidates
                (label, centroid_arousal, centroid_valence, centroid_tension,
                 centroid_pe, dominant_emotion, confirmations, last_seen_flash, created_flash)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, (label, cl[:ca], cl[:cv], cl[:ct], cl[:cp],
                  dom_emotion, cl[:n], flash, flash))
        else
            # Оновлюємо існуючий — центр і кількість підтверджень
            new_conf = found_conf + cl[:n]
            DBInterface.execute(db, """
            UPDATE pattern_candidates
            SET confirmations   = ?,
                last_seen_flash = ?,
                centroid_arousal = (centroid_arousal + ?) / 2.0,
                centroid_valence = (centroid_valence + ?) / 2.0,
                centroid_tension = (centroid_tension + ?) / 2.0,
                centroid_pe      = (centroid_pe      + ?) / 2.0
            WHERE id = ?
            """, (new_conf, flash,
                  cl[:ca], cl[:cv], cl[:ct], cl[:cp], found_id))

            # ── Промоція в emerged_belief ──────────────────────────────────────
            if new_conf >= SUBJ_PATTERN_PROMOTE_N
                _promote_to_belief!(subj, found_id, label, cl, dom_emotion, flash)
            end
        end
    end

    # ── Видаляємо застарілі кандидати ─────────────────────────────────────────
    DBInterface.execute(db, """
    DELETE FROM pattern_candidates
    WHERE promoted = 0
      AND (? - last_seen_flash) > ?
      AND confirmations < ?
    """, (flash, SUBJ_PATTERN_STALE_TICKS, SUBJ_PATTERN_PROMOTE_N))

    # ── Decay emerged beliefs ─────────────────────────────────────────────────
    # Переконання що давно не активувались — поступово слабнуть
    DBInterface.execute(db, """
    UPDATE emerged_beliefs
    SET strength = strength * 0.9998
    WHERE (? - last_activated) > 30 AND strength > 0.05
    """, (flash,))

    # Якщо суперечностей більше ніж підтверджень — переконання слабне активно
    DBInterface.execute(db, """
    UPDATE emerged_beliefs
    SET strength = strength * 0.98
    WHERE contradictions > confirmations AND strength > 0.05
    """)

    _subj_refresh_emerged!(subj)
    nothing
end

# ── Promote pattern → emerged belief ──────────────────────────────────────────

function _promote_to_belief!(subj::SubjectivityEngine,
                               pattern_id::Int,
                               label::String,
                               cl::Dict,
                               dom_emotion::String,
                               flash::Int)
    db = subj.mem.db

    # Тип переконання визначається за характером кластеру
    belief_type = if cl[:cp] > 0.55 && cl[:ca] > 0.5
        "world"         # Світ непередбачуваний і збуджений
    elseif cl[:cv] < -0.3 && cl[:ct] > 0.5
        "situational"   # Ця ситуація → небезпека
    elseif cl[:cv] > 0.25 && cl[:ca] > 0.4
        "relational"    # Ця ситуація → щось добре
    else
        "situational"
    end

    # Унікальний ключ
    key = "EB:$(label):$(flash)"

    # Suб'єктивна оцінка переконання = валентність кластеру
    valence_bias = cl[:cv]

    # Радіус активації — ширший для слабких патернів
    avg_w = cl[:sum_w] / max(cl[:n], 1)
    activation_thr = SUBJ_PATTERN_CLUSTER_THR * (1.0 + (1.0 - avg_w) * 0.5)

    DBInterface.execute(db, """
    INSERT OR IGNORE INTO emerged_beliefs
        (key, belief_type, centroid_arousal, centroid_valence, centroid_tension,
         centroid_pe, strength, valence_bias, activation_thr, confirmations,
         last_activated, created_flash, source_pattern)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (key, belief_type, cl[:ca], cl[:cv], cl[:ct], cl[:cp],
          0.5, valence_bias, activation_thr,
          cl[:n], flash, flash, pattern_id))

    # Позначаємо кандидата як promoted
    DBInterface.execute(db, """
    UPDATE pattern_candidates SET promoted = 1 WHERE id = ?
    """, (pattern_id,))

    println("  [SUBJ] Нове переконання: \"$(key)\" ($(belief_type), val=$(round(valence_bias, digits=2)))")

    # Переконання народжене з травми → впливає на semantic_memory.
    # ВАЖЛИВО: ключ "EB_structural_fragility" — НЕ "structural_fragility".
    # memory_db._memory_consolidate! вже пише в "structural_fragility" незалежно.
    # Розділяємо ключі щоб уникнути взаємного скасування між двома механізмами.
    # При потребі злити в experience!:
    #   combined = get(sem,"structural_fragility",0.0) + get(sem,"EB_structural_fragility",0.0)*0.5
    if valence_bias < -0.4 && cl[:cp] > 0.5
        _upsert_semantic_subj!(db, "EB_structural_fragility",
            abs(valence_bias) * cl[:cp] * 0.012, 0.0, 1.0, "emerged_belief")
    end

    _subj_refresh_emerged!(subj)
    nothing
end

# ════════════════════════════════════════════════════════════════════════════
# 4. POSITIONAL STANCES — власна позиція щодо типів ситуацій
# ════════════════════════════════════════════════════════════════════════════

function _update_stance!(subj::SubjectivityEngine,
                          stance_key::String,
                          actual_valence::Float64,
                          actual_arousal::Float64,
                          actual_tension::Float64,
                          surprise::Float64,
                          flash::Int)
    db = subj.mem.db

    # Позиція формується з накопиченого досвіду.
    # approach_weight зростає при позитивному досвіді.
    # avoidance_weight зростає при негативному + high tension.
    # certainty зростає з кількістю зустрічей.

    approach  = actual_valence > 0.1 ? actual_valence * SUBJ_STANCE_LEARN_RATE : 0.0
    avoidance = (actual_valence < -0.1 && actual_tension > 0.4) ?
                abs(actual_valence) * actual_tension * SUBJ_STANCE_LEARN_RATE : 0.0

    # Surprise підсилює і підхід і уникання (несподіванка запам'ятовується)
    surprise_amp = 1.0 + surprise * 0.5

    # valence_stance — running mean
    valence_delta = actual_valence * SUBJ_STANCE_LEARN_RATE * surprise_amp

    DBInterface.execute(db, "BEGIN TRANSACTION")
    try
        DBInterface.execute(db, """
        INSERT INTO positional_stances
            (stance_key, valence_stance, certainty, avoidance_weight,
             approach_weight, encounter_count, last_updated)
        VALUES (?, ?, 0.1, ?, ?, 1, ?)
        ON CONFLICT(stance_key) DO UPDATE SET
            valence_stance   = MIN(1.0, MAX(-1.0,
                                   valence_stance * 0.92 + ? )),
            certainty        = MIN(0.95, certainty + 0.03),
            avoidance_weight = MIN(1.0, avoidance_weight * 0.95 + ?),
            approach_weight  = MIN(1.0, approach_weight  * 0.95 + ?),
            encounter_count  = encounter_count + 1,
            last_updated     = ?
        """, (stance_key,
              clamp(valence_delta, -1.0, 1.0),
              clamp(avoidance * surprise_amp, 0.0, 0.3),
              clamp(approach  * surprise_amp, 0.0, 0.3),
              flash,
              valence_delta,
              clamp(avoidance * surprise_amp, 0.0, 0.1),
              clamp(approach  * surprise_amp, 0.0, 0.1),
              flash))
        DBInterface.execute(db, "COMMIT")
    catch e
        DBInterface.execute(db, "ROLLBACK")
        @warn "[SUBJ] stance update помилка: $e"
    end

    subj._stance_dirty = true
    _subj_refresh_stances!(subj)  # оновити кеш
    nothing
end

# ════════════════════════════════════════════════════════════════════════════
# РЕЗОНАНС — перевірка переконань при новому досвіді
# ════════════════════════════════════════════════════════════════════════════

function _check_belief_resonance!(subj::SubjectivityEngine,
                                   actual_arousal::Float64,
                                   actual_valence::Float64,
                                   actual_tension::Float64,
                                   actual_pe::Float64,
                                   flash::Int,
                                   is_surprise::Bool)
    db = subj.mem.db

    DBInterface.execute(db, "BEGIN TRANSACTION")
    try
        for eb in subj._emerged_cache
            dist = (abs(eb.centroid_arousal - actual_arousal) +
                    abs(eb.centroid_valence - actual_valence) +
                    abs(eb.centroid_tension - actual_tension)) / 3.0

            dist > eb.activation_thr && continue

            strength_delta = 0.008 * (1.0 - dist / eb.activation_thr)

            # Суперечність — нова валентність протилежна знаку переконання
            if eb.valence_bias * actual_valence < -0.1
                DBInterface.execute(db, """
                UPDATE emerged_beliefs
                SET contradictions = contradictions + 1,
                    strength = MAX(0.05, strength - 0.015),
                    last_activated = ?
                WHERE key = ?
                """, (flash, eb.key))
            else
                # Підтвердження
                DBInterface.execute(db, """
                UPDATE emerged_beliefs
                SET confirmations = confirmations + 1,
                    strength = MIN(0.95, strength + ?),
                    last_activated = ?
                WHERE key = ?
                """, (strength_delta, flash, eb.key))
            end
        end
        DBInterface.execute(db, "COMMIT")
    catch e
        DBInterface.execute(db, "ROLLBACK")
        @warn "[SUBJ] belief resonance помилка: $e"
    end

    _subj_refresh_emerged!(subj)
    nothing
end

# ════════════════════════════════════════════════════════════════════════════
# SURPRISE → prediction_error modifier
# ════════════════════════════════════════════════════════════════════════════

"""
    subj_surprise_pe_bias(subj) → Float64

Повертає додатковий bias для prediction_error на основі накопиченого surprise.
Викликати в memory_pred_bias або в experience! на L2.

Логіка: якщо система часто помилялась у прогнозах → очікування знижені,
нові ситуації сприймаються з більшою тривогою.
"""
function subj_surprise_pe_bias(subj::SubjectivityEngine)::Float64
    subj._surprise_n < 3 && return 0.0

    # Накопичений surprise → додатковий PE multiplier
    bias = clamp(subj._surprise_accumulator * 0.4, 0.0, 0.12)
    bias
end

# ════════════════════════════════════════════════════════════════════════════
# CACHE REFRESH
# ════════════════════════════════════════════════════════════════════════════

function _subj_refresh_emerged!(subj::SubjectivityEngine)
    db = subj.mem.db
    subj._emerged_cache = NamedTuple[]

    for row in Tables.rows(DBInterface.execute(db, """
    SELECT key, belief_type, centroid_arousal, centroid_valence,
           centroid_tension, centroid_pe, strength, valence_bias,
           activation_thr, confirmations, contradictions
    FROM emerged_beliefs
    WHERE strength > 0.1
    ORDER BY strength DESC
    LIMIT 20
    """))
        push!(subj._emerged_cache, (
            key              = String(row.key),
            belief_type      = String(row.belief_type),
            centroid_arousal = _sfdb(row.centroid_arousal),
            centroid_valence = _sfdb(row.centroid_valence),
            centroid_tension = _sfdb(row.centroid_tension),
            centroid_pe      = _sfdb(row.centroid_pe),
            strength         = _sfdb(row.strength, 0.5),
            valence_bias     = _sfdb(row.valence_bias),
            activation_thr   = _sfdb(row.activation_thr, 0.15),
            confirmations    = _sidb(row.confirmations),
            contradictions   = _sidb(row.contradictions),
        ))
    end
end

function _subj_refresh_stances!(subj::SubjectivityEngine)
    db = subj.mem.db
    empty!(subj._stance_cache)

    for row in Tables.rows(DBInterface.execute(db, """
    SELECT stance_key, valence_stance, certainty,
           avoidance_weight, approach_weight, encounter_count
    FROM positional_stances
    WHERE certainty > 0.1
    """))
        subj._stance_cache[String(row.stance_key)] = (
            valence_stance   = _sfdb(row.valence_stance),
            certainty        = _sfdb(row.certainty, 0.1),
            avoidance_weight = _sfdb(row.avoidance_weight),
            approach_weight  = _sfdb(row.approach_weight),
            encounter_count  = _sidb(row.encounter_count),
        )
    end
    subj._stance_dirty = false
end

# ════════════════════════════════════════════════════════════════════════════
# HELPERS
# ════════════════════════════════════════════════════════════════════════════

# SQL fallback для rolling stats якщо mem._rolling_* недоступні
function _subj_mean_episodic(db::SQLite.DB, col::String,
                               limit::Int, default::Float64)::Float64
    # col — назва колонки в episodic_memory (arousal, prediction_error, тощо)
    # Не використовуємо інтерполяцію у SQL-параметр — лише в ідентифікаторі,
    # тому col перевіряємо явно проти дозволеного списку.
    allowed = Set(["arousal", "valence", "prediction_error",
                   "tension", "phi", "self_impact"])
    col in allowed || return default

    sql = "SELECT COALESCE(AVG($col), ?) as val FROM (SELECT $col FROM episodic_memory " *
          "WHERE weight > 0.3 ORDER BY flash DESC LIMIT ?)"
    rows = Tables.rows(DBInterface.execute(db, sql, (default, limit)))
    for r in rows
        return _sfdb(r.val, default)
    end
    default
end

function _count_episodic(db::SQLite.DB, emotion::String)::Int
    rows = Tables.rows(DBInterface.execute(db, """
    SELECT COUNT(*) as n FROM episodic_memory
    WHERE emotion = ? AND weight > 0.3
    """, (emotion,)))
    for r in rows
        return _sidb(r.n)
    end
    return 0
end

function _upsert_semantic_subj!(db::SQLite.DB, key::String, delta::Float64,
                                 lo::Float64, hi::Float64, source::String)
    DBInterface.execute(db, """
    INSERT INTO semantic_memory (key, value, source, updated)
    VALUES (?, ?, ?, 0)
    ON CONFLICT(key) DO UPDATE
    SET value  = MIN(?, MAX(?, value + ?)),
        source = ?
    """, (key, clamp(delta, lo, hi), source, hi, lo, delta, source))
end

# ════════════════════════════════════════════════════════════════════════════
# SNAPSHOT / DEBUG
# ════════════════════════════════════════════════════════════════════════════

"""
    subj_snapshot(subj) → NamedTuple

Стан суб'єктивності для логу або :subj команди в REPL.
"""
function subj_snapshot(subj::SubjectivityEngine)
    db = subj.mem.db

    n_beliefs_row = first(Tables.rows(DBInterface.execute(db,
        "SELECT COUNT(*) as n FROM emerged_beliefs WHERE strength > 0.1")))
    n_beliefs = _sidb(n_beliefs_row.n)

    n_candidates_row = first(Tables.rows(DBInterface.execute(db,
        "SELECT COUNT(*) as n FROM pattern_candidates WHERE promoted = 0")))
    n_candidates = _sidb(n_candidates_row.n)

    n_stances = length(subj._stance_cache)

    # Топ-3 переконання
    top_beliefs = String[]
    for eb in subj._emerged_cache[1:min(3, length(subj._emerged_cache))]
        push!(top_beliefs, "$(eb.key)($(round(eb.strength, digits=2)))")
    end

    # Домінантна позиція
    dom_stance = ""
    max_cert   = 0.0
    for (k, s) in subj._stance_cache
        if s.certainty > max_cert
            max_cert = s.certainty
            dom_stance = "$k→$(round(s.valence_stance, digits=2))"
        end
    end

    avg_surprise = subj._surprise_n > 0 ? subj._surprise_accumulator : 0.0
    current_lens = subj._current_lens != "neutral" ?
                   "$(subj._current_lens)($(round(subj._current_lens_strength, digits=2)))" : ""

    (
        emerged_beliefs   = n_beliefs,
        pattern_candidates = n_candidates,
        stances           = n_stances,
        top_beliefs       = join(top_beliefs, ", "),
        dominant_stance   = dom_stance,
        surprise_level    = round(avg_surprise, digits=3),
        current_lens      = current_lens,
        active_prediction = !isnothing(subj._active_pred_id),
    )
end

# ════════════════════════════════════════════════════════════════════════════
# ІНТЕГРАЦІЯ — розширення фонового циклу пам'яті
# ════════════════════════════════════════════════════════════════════════════

"""
    extend_memory_loop!(mem, subj; interval=60.0)

Перезапускає memory loop з підключеним SubjectivityEngine.
Викликати замість start_memory_loop! якщо є subj.

Додає до стандартного циклу:
  - subj_emerge_beliefs! (кожні 3 тіки)
  - decay positional_stances
"""
function extend_memory_loop!(mem, subj::SubjectivityEngine; interval::Float64=60.0)
    mem._loop_stop[] = false
    tick = Threads.Atomic{Int}(0)

    task = Threads.@spawn begin
        println("  [SUBJ+MEM] Розширений фоновий цикл запущено ($(interval)с).")
        while !mem._loop_stop[]
            try
                sleep(interval)
                mem._loop_stop[] && break

                Threads.atomic_add!(tick, 1)
                t = tick[]

                # Стандартний memory loop
                _memory_decay!(mem)
                _memory_prune!(mem)
                _memory_consolidate!(mem)
                _refresh_cache!(mem)

                # Subjectivity: emerge beliefs кожні 3 тіки
                if t % 3 == 0
                    subj_emerge_beliefs!(subj, t * 100)  # synthetic flash
                end

                # Decay positional stances (повільний)
                DBInterface.execute(mem.db, """
                UPDATE positional_stances
                SET certainty       = certainty * ?,
                    avoidance_weight = avoidance_weight * ?,
                    approach_weight  = approach_weight  * ?
                WHERE certainty > 0.05
                """, (SUBJ_STANCE_DECAY, SUBJ_STANCE_DECAY, SUBJ_STANCE_DECAY))

                if subj._stance_dirty || t % 5 == 0
                    _subj_refresh_stances!(subj)
                end

            catch e
                @warn "[SUBJ+MEM] помилка в циклі: $e"
                sleep(5.0)
            end
        end
        println("  [SUBJ+MEM] Цикл зупинено.")
    end

    mem._loop_task = task
    task
end

# ════════════════════════════════════════════════════════════════════════════
# DELTA SAFETY — захист від адитивного перестимулювання
# ════════════════════════════════════════════════════════════════════════════

"""
    clamp_merged_delta!(delta)

Захищає від ситуації коли NarrativeGravity + subj_interpret! + memory_stimulus_bias
одночасно дають сильний delta в одному напрямку.

Межі обрані консервативно: навіть при кризі жоден окремий delta-шар
не повинен перевищувати 25% шкали реактора за один флеш.

Викликати після mergewith(+, ...) і перед apply_stimulus!.
"""
function clamp_merged_delta!(delta::Dict{String, Float64})
    haskey(delta, "tension")      && (delta["tension"]      = clamp(delta["tension"],      -0.25,  0.25))
    haskey(delta, "satisfaction") && (delta["satisfaction"] = clamp(delta["satisfaction"], -0.20,  0.20))
    haskey(delta, "arousal")      && (delta["arousal"]      = clamp(delta["arousal"],      -0.20,  0.20))
    haskey(delta, "cohesion")     && (delta["cohesion"]     = clamp(delta["cohesion"],     -0.15,  0.15))
    delta
end

# ════════════════════════════════════════════════════════════════════════════
# ПРИКЛАД ІНТЕГРАЦІЇ В experience!
# ════════════════════════════════════════════════════════════════════════════

#=
Як вбудувати в існуючий experience! pipeline:

function experience!(a::Anima, stim::Dict{String,Float64}; emotion::String="")

    # ── До L0 ──────────────────────────────────────────────────────────────
    pred_id = subj_predict!(a.subj, a.flash, emotion, stim;
                          chronified_affect=a.ca)  # a.ca::ChronifiedAffect з psyche.jl

    # ── Між L0 і L1 (разом з memory_stimulus_bias) ─────────────────────────
    mem_delta  = memory_stimulus_bias(a.mem, stim, emotion, a.flash)
    subj_delta = subj_interpret!(a.subj, stim, emotion, a.flash)
    # gravity_d — результат gravity_reactor_delta(a.ng, a.flash) з anima_psyche.jl
    grav_delta = Dict{String,Float64}(
        "tension"      => gravity_d.tension_d,
        "satisfaction" => gravity_d.satisfaction_d,
        "cohesion"     => gravity_d.cohesion_d)

    # Об'єднуємо всі три delta-шари і захищаємо від адитивного перестимулювання.
    # FIX: NarrativeGravity + subj_interpret! + memory_bias можуть збігтись в напрямку.
    # clamp_merged_delta! гарантує що жоден реактор не перевищить 25% за флеш.
    merged_delta = mergewith(+, mem_delta, subj_delta, grav_delta)
    clamp_merged_delta!(merged_delta)
    stim = apply_delta(stim, merged_delta)

    # ── L1..L5 — стандартний pipeline ──────────────────────────────────────
    # ...
    # memory_nt_baseline!(a.mem, nt, a.flash)

    # ── Surprise PE bias між L1 і L2 ───────────────────────────────────────
    # pe = memory_pred_bias(a.mem, raw_pe, a.flash)
    # pe = clamp(pe + subj_surprise_pe_bias(a.subj), 0.0, 1.0)

    # ── Після L6 ────────────────────────────────────────────────────────────
    subj_outcome!(a.subj, a.flash,
        actual_arousal, actual_valence, actual_tension, actual_pe, emotion)

    memory_write_event!(a.mem, a.flash, emotion,
        actual_arousal, actual_valence, actual_pe, self_impact, tension, phi)
end
=#
