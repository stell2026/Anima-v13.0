#=
╔══════════════════════════════════════════════════════════════════════════════╗
║                    A N I M A  —  Memory DB  (Julia)                          ║
║                                                                              ║
║  Пам'ять як поле — впливає на кожен шар, не є окремим шаром.                 ║
║                                                                              ║
║  Три рівні зберігання (SQLite):                                              ║
║    episodic_memory  — епізодична (буфер + core)                              ║
║    semantic_memory  — семантична (переконання, що стали особистістю)         ║
║    affect_state     — хронічний афективний фон                               ║
║                                                                              ║
║  Інтеграція з experience! pipeline:                                          ║
║    memory_write_event!  — після L0 (stimulus → буфер)                        ║
║    memory_stimulus_bias — між L0 і L1 (упередження стимулу)                  ║
║    memory_nt_baseline!  — L1 (NT baseline з affect_state)                    ║
║    memory_pred_bias     — L2 (викривлення prediction error)                  ║
║    memory_self_update!  — після L5 (SelfBeliefGraph ← semantic)              ║
║    memory_crisis_load   — L6 (coherence ← structural накопичення)            ║
║                                                                              ║
║  Фоновий процес:                                                             ║
║    start_memory_loop!   — decay + consolidation кожні N секунд               ║
║    stop_memory_loop!                                                         ║
║                                                                              ║
║  Ініціалізація:                                                              ║
║    mem = MemoryDB(joinpath(@__DIR__, "memory", "anima.db"))                  ║
╚══════════════════════════════════════════════════════════════════════════════╝
=#

# Потребує: SQLite.jl  — ]add SQLite
# Потребує: anima_core.jl (clamp01, safe_nan — вже визначені там)

using SQLite
using Tables   # для ітерації результатів DBInterface.execute

# ════════════════════════════════════════════════════════════════════════════
# CONSTANTS
# ════════════════════════════════════════════════════════════════════════════

const MEM_IMPORTANCE_THRESHOLD  = 0.20  # нижче — не зберігати в episodic
const MEM_CORE_MAX              = 500   # максимум записів в episodic
const MEM_DECAY_RATE            = 0.001 # за один decay-тік (~60с)
const MEM_MIN_WEIGHT            = 0.05  # нижче — видалити з episodic
const MEM_CONSOLIDATE_THRESHOLD = 0.35  # weight для консолідації в semantic
const MEM_TOPK_INFLUENCE        = 10    # скільки найсильніших подій впливають на стан
const MEM_AFFECT_DECAY          = 0.995 # decay affect за тік (~60с) — стрес зникає
const MEM_LINK_SIMILARITY_THR   = 0.75  # поріг схожості для створення зв'язку

# Ліміти впливу на стан — захист від перебільшень
const MEM_MAX_NT_BIAS           = 0.08  # максимальний вплив на NT
const MEM_MAX_PRED_BIAS         = 0.15  # максимальний вплив на prediction error
const MEM_MAX_STIM_BIAS         = 0.12  # максимальний вплив на stimulus

# Захисна конвертація SQL значень → Float64
# SQLite повертає missing для NULL (порожні агрегати), не nothing
_fdb(x, d::Float64=0.0) = (ismissing(x) || isnothing(x)) ? d : Float64(x)

# ════════════════════════════════════════════════════════════════════════════
# MemoryDB — головна структура
# ════════════════════════════════════════════════════════════════════════════

mutable struct MemoryDB
    db::SQLite.DB
    path::String
    # Кешовані значення — щоб не ходити в БД на кожен флеш
    _affect_cache::Dict{String, Float64}
    _semantic_cache::Dict{String, Float64}
    _cache_dirty::Bool
    _cache_flash::Int   # коли останній раз оновлювали кеш
    # Rolling stats для динамічного importance
    _rolling_arousal::Float64   # середній arousal за останні N подій
    _rolling_pe::Float64        # середній prediction_error
    _rolling_n::Int             # кількість подій у rolling window
    # Фоновий процес
    _loop_task::Union{Task, Nothing}
    _loop_stop::Threads.Atomic{Bool}
end

"""
    MemoryDB(db_path)

Ініціалізувати базу пам'яті. Створює файл і таблиці якщо не існують.
"""
function MemoryDB(db_path::String=joinpath("memory", "anima.db"))
    dir = dirname(db_path)
    isempty(dir) || isdir(dir) || mkpath(dir)

    db = SQLite.DB(db_path)
    SQLite.busy_timeout(db, 5000)  # чекати до 5с при блокуванні (конкурентний доступ)
    _init_schema!(db)

    mem = MemoryDB(db, db_path,
        Dict{String,Float64}(), Dict{String,Float64}(),
        true, 0,
        0.3, 0.3, 0,   # rolling stats (початкові значення нейтральні)
        nothing, Threads.Atomic{Bool}(false))

    _refresh_cache!(mem)
    println("  [MEM] База пам'яті: $db_path")
    mem
end

# ════════════════════════════════════════════════════════════════════════════
# SCHEMA
# ════════════════════════════════════════════════════════════════════════════

function _init_schema!(db::SQLite.DB)
    # Епізодична пам'ять — конкретні події з вагою важливості
    SQLite.execute(db, """
    CREATE TABLE IF NOT EXISTS episodic_memory (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        flash           INTEGER NOT NULL,
        timestamp       REAL    NOT NULL,
        emotion         TEXT    NOT NULL DEFAULT '',
        arousal         REAL    NOT NULL DEFAULT 0.0,
        valence         REAL    NOT NULL DEFAULT 0.0,
        prediction_error REAL   NOT NULL DEFAULT 0.0,
        self_impact     REAL    NOT NULL DEFAULT 0.0,
        tension         REAL    NOT NULL DEFAULT 0.0,
        phi             REAL    NOT NULL DEFAULT 0.0,
        weight          REAL    NOT NULL DEFAULT 0.5,
        resistance      REAL    NOT NULL DEFAULT 0.0,
        signature       REAL    NOT NULL DEFAULT 0.0
    );
    """)

    # Індекс для швидкого decay і recall
    SQLite.execute(db, """
    CREATE INDEX IF NOT EXISTS idx_episodic_weight
    ON episodic_memory(weight DESC);
    """)

    SQLite.execute(db, """
    CREATE INDEX IF NOT EXISTS idx_episodic_flash
    ON episodic_memory(flash DESC);
    """)

    SQLite.execute(db, """
    CREATE INDEX IF NOT EXISTS idx_episodic_emotion
    ON episodic_memory(emotion, weight DESC);
    """)

    # Асоціативні зв'язки між подіями — "ланцюжки досвіду"
    # strength: наскільки схожі події (0..1), co_occur: скільки разів разом
    SQLite.execute(db, """
    CREATE TABLE IF NOT EXISTS memory_links (
        id_a     INTEGER NOT NULL,
        id_b     INTEGER NOT NULL,
        strength REAL    NOT NULL DEFAULT 0.0,
        co_occur INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (id_a, id_b),
        FOREIGN KEY (id_a) REFERENCES episodic_memory(id) ON DELETE CASCADE,
        FOREIGN KEY (id_b) REFERENCES episodic_memory(id) ON DELETE CASCADE
    );
    """)

    # Семантична пам'ять — переконання що стали особистістю
    # key: назва переконання (відповідає SelfBeliefGraph або власні)
    SQLite.execute(db, """
    CREATE TABLE IF NOT EXISTS semantic_memory (
        key     TEXT    PRIMARY KEY,
        value   REAL    NOT NULL DEFAULT 0.0,
        source  TEXT    NOT NULL DEFAULT 'accumulated',
        updated INTEGER NOT NULL DEFAULT 0
    );
    """)

    # Хронічний афективний фон — змінює NT baseline
    # name: "stress", "resentment", "motivation_bias", "anxiety"
    SQLite.execute(db, """
    CREATE TABLE IF NOT EXISTS affect_state (
        name    TEXT    PRIMARY KEY,
        value   REAL    NOT NULL DEFAULT 0.0,
        updated INTEGER NOT NULL DEFAULT 0
    );
    """)

    # Latent buffer — малі незначні події що накопичуються мовчки
    # Коли тиск перевищує поріг — вибух у синтетичну подію
    SQLite.execute(db, """
    CREATE TABLE IF NOT EXISTS latent_buffer (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        importance  REAL    NOT NULL,
        valence     REAL    NOT NULL DEFAULT 0.0,
        tension     REAL    NOT NULL DEFAULT 0.0,
        flash       INTEGER NOT NULL DEFAULT 0,
        timestamp   REAL    NOT NULL
    );
    """)
end

# ════════════════════════════════════════════════════════════════════════════
# КЕШ — NT і semantic читаються кожен флеш, БД не чіпаємо занадто часто
# ════════════════════════════════════════════════════════════════════════════

function _refresh_cache!(mem::MemoryDB)
    # affect_state
    empty!(mem._affect_cache)
    for row in Tables.rowtable(DBInterface.execute(mem.db,
            "SELECT name, value FROM affect_state"))
        mem._affect_cache[row.name] = row.value
    end

    # semantic_memory
    empty!(mem._semantic_cache)
    for row in Tables.rowtable(DBInterface.execute(mem.db,
            "SELECT key, value FROM semantic_memory"))
        mem._semantic_cache[row.key] = row.value
    end

    mem._cache_dirty = false
end

# Оновити кеш якщо пройшло більше N флешів або він брудний
function _maybe_refresh!(mem::MemoryDB, current_flash::Int; every::Int=10)
    if mem._cache_dirty || (current_flash - mem._cache_flash) >= every
        _refresh_cache!(mem)
        mem._cache_flash = current_flash
    end
end

# ════════════════════════════════════════════════════════════════════════════
# ЗАПИС ПОДІЇ — після L0
# ════════════════════════════════════════════════════════════════════════════

"""
    memory_write_event!(mem, flash, emotion, arousal, valence,
                        prediction_error, self_impact, tension, phi)

Записати подію в episodic_memory якщо вона достатньо важлива.
Викликати в experience! після обчислення основних показників.

Динамічний importance: під стресом система "пам'ятає більше" —
поріг знижується, weight зростає пропорційно до поточного стресу.

Після запису: шукає схожі події і створює асоціативний зв'язок.
"""
function memory_write_event!(mem::MemoryDB,
                              flash::Int,
                              emotion::String,
                              arousal::Float64,
                              valence::Float64,
                              prediction_error::Float64,
                              self_impact::Float64,
                              tension::Float64,
                              phi::Float64)

    # ── Оновити rolling stats (exponential moving average) ────────────────
    α = 0.15   # learning rate rolling window
    mem._rolling_arousal = mem._rolling_arousal * (1-α) + arousal * α
    mem._rolling_pe      = mem._rolling_pe      * (1-α) + prediction_error * α
    mem._rolling_n      += 1

    # ── Динамічний importance — залежить від поточного стресу ─────────────
    # Під стресом система запам'ятовує більше (знижений поріг, вищий weight)
    current_stress = get(mem._affect_cache, "stress", 0.0)
    stress_amp = 1.0 + current_stress * 0.6   # 1.0..1.6

    # Контекстуальний importance: відхилення від rolling середнього важливіше
    arousal_surprise = abs(arousal - mem._rolling_arousal)
    pe_surprise      = abs(prediction_error - mem._rolling_pe)

    imp = (0.25 * prediction_error +
           0.20 * arousal +
           0.20 * abs(valence) +
           0.15 * self_impact +
           0.10 * arousal_surprise +   # несподіваний arousal
           0.10 * pe_surprise)         # несподівана помилка
    imp = clamp(imp * stress_amp, 0.0, 1.0)

    # Динамічний поріг: під стресом зберігаємо більше
    dynamic_threshold = MEM_IMPORTANCE_THRESHOLD * (1.0 - current_stress * 0.3)
    imp < dynamic_threshold && return

    ts = time()

    # Affective resistance — самовплив і валентність визначають наскільки
    # спогад "чіпляється". Негативне + high self_impact → забувається повільніше.
    # Це не вага — це опір decay. Травма не хоче зникати.
    resistance = clamp(self_impact * 0.6 + abs(valence) * 0.3 * (valence < 0 ? 1.4 : 0.7), 0.0, 1.0)

    # Signature — позиція події у просторі афекту для дедуплікації
    signature = arousal * 0.5 + prediction_error * 0.3 + abs(self_impact) * 0.2

    # Latent buffer — якщо подія нижче порогу але не нульова — осідає мовчки
    if imp < dynamic_threshold && imp > 0.05
        DBInterface.execute(mem.db, """
        INSERT INTO latent_buffer (importance, valence, tension, flash, timestamp)
        VALUES (?, ?, ?, ?, ?)
        """, (imp, valence, tension, flash, ts))
    end

    # Дедуплікація через signature — якщо дуже схожа подія вже є недавно,
    # не створюємо новий запис а підсилюємо weight існуючого
    dedup_rows = Tables.rowtable(DBInterface.execute(mem.db, """
    SELECT id, weight FROM episodic_memory
    WHERE ABS(signature - ?) < 0.08 AND flash >= ?
    ORDER BY flash DESC LIMIT 1
    """, (signature, flash - 3)))

    dedup_hit = false
    for dr in dedup_rows
        new_w = clamp(_fdb(dr.weight) * 1.15, 0.0, 1.0)
        DBInterface.execute(mem.db, """
        UPDATE episodic_memory SET weight = ? WHERE id = ?
        """, (new_w, dr.id))
        dedup_hit = true
        break
    end

    dedup_hit && return

    DBInterface.execute(mem.db, """
    INSERT INTO episodic_memory
        (flash, timestamp, emotion, arousal, valence,
         prediction_error, self_impact, tension, phi, weight, resistance, signature)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    """, (flash, ts, emotion, arousal, valence,
          prediction_error, self_impact, tension, phi, imp, resistance, signature))

    # ── Incremental affect update — кожна подія одразу формує фон ───────
    # Не чекаємо consolidation — affect накопичується з кожного досвіду.
    # Малий крок (0.003–0.006) — багато подій потрібно щоб помітно змінити фон.
    # Це чесніше: система відчуває напругу від кожного моменту, не тільки від "важких".

    # Стрес: tension вище норми + arousal вище норми
    # Поріг знижено з 0.4 до 0.3 — при типовому tension 0.30-0.45
    # stress майже не накопичувався. Тепер накопичується з помірних станів.
    stress_inc = clamp((tension - 0.3) * 0.4 + (arousal - 0.3) * 0.4, 0.0, 1.0)
    if stress_inc > 0.0
        _upsert_affect!(mem.db, "stress",
            stress_inc * imp * 0.005, 0.0, 1.0)
    end

    # Тривога: негативна валентність + prediction_error
    if valence < -0.1 && prediction_error > 0.3
        anxiety_inc = abs(valence) * prediction_error
        _upsert_affect!(mem.db, "anxiety",
            anxiety_inc * imp * 0.004, 0.0, 1.0)
    end

    # Мотивація: позитивна валентність + phi — добрий досвід мотивує
    if valence > 0.15 && phi > 0.2
        _upsert_affect!(mem.db, "motivation_bias",
            valence * phi * imp * 0.003, 0.0, 1.0)
    end

    mem._cache_dirty = true   # кеш потребує оновлення

    # ── Асоціативні зв'язки — знайти схожу подію і зв'язати ─────────────
    # Similarity = 1 - нормована евклідова відстань у просторі (arousal, valence, tension)
    # Беремо тільки топ-1 схожу (не будуємо повний граф — надто дорого)
    new_id_row = first(Tables.rowtable(DBInterface.execute(mem.db,
        "SELECT last_insert_rowid() as id")))
    new_id = Int(new_id_row.id)

    similar_rows = Tables.rowtable(DBInterface.execute(mem.db, """
    SELECT id, arousal, valence, tension
    FROM episodic_memory
    WHERE id != ? AND weight > 0.3
    ORDER BY ABS(arousal - ?) + ABS(valence - ?) + ABS(tension - ?) ASC
    LIMIT 3
    """, (new_id, arousal, valence, tension)))

    for sr in similar_rows
        dist = abs(sr.arousal - arousal) +
               abs(sr.valence - valence) +
               abs(sr.tension - tension)
        sim = clamp(1.0 - dist / 3.0, 0.0, 1.0)

        sim < MEM_LINK_SIMILARITY_THR && continue

        id_a, id_b = min(new_id, Int(sr.id)), max(new_id, Int(sr.id))
        DBInterface.execute(mem.db, """
        INSERT INTO memory_links (id_a, id_b, strength, co_occur)
        VALUES (?, ?, ?, 1)
        ON CONFLICT(id_a, id_b) DO UPDATE
        SET strength = MIN(1.0, (strength * co_occur + ?) / (co_occur + 1)),
            co_occur = co_occur + 1
        """, (id_a, id_b, sim, sim))
    end

    nothing
end

# ════════════════════════════════════════════════════════════════════════════
# ІНТЕГРАЦІЯ З PIPELINE
# ════════════════════════════════════════════════════════════════════════════

"""
    memory_stimulus_bias(mem, stim) → Dict{String,Float64}

L0 → L1: упередження стимулу на основі episodic пам'яті.
Повертає delta що додається до stim перед apply_stimulus!.

Логіка: схожі минулі події підсилюють поточний стимул.
"Схожість" тут — за emotion і tension (без embedding, детермінована).
"""
function memory_stimulus_bias(mem::MemoryDB,
                               stim::Dict{String,Float64},
                               emotion::String,
                               flash::Int)::Dict{String,Float64}

    delta = Dict{String,Float64}()

    # Беремо останні важливі події з тією самою емоцією
    rows = Tables.rowtable(DBInterface.execute(mem.db, """
    SELECT arousal, valence, tension, weight
    FROM episodic_memory
    WHERE emotion = ? AND weight > 0.4
    ORDER BY flash DESC
    LIMIT 5
    """, (emotion,)))

    total_w = 0.0
    bias_tension    = 0.0
    bias_arousal    = 0.0
    bias_valence    = 0.0

    for row in rows
        w = row.weight
        total_w      += w
        bias_tension += row.tension * w
        bias_arousal += row.arousal * w
        bias_valence += row.valence * w
    end

    total_w < 0.01 && return delta   # немає релевантних спогадів

    # Нормалізуємо і застосовуємо з малим коефіцієнтом
    scale = MEM_MAX_STIM_BIAS / total_w
    t_current = get(stim, "tension", 0.5)

    # Упередження тільки якщо напрямок збігається (посилення, не корекція)
    if bias_tension > 0 && t_current > 0.3
        delta["tension"] = clamp(bias_tension * scale, 0.0, MEM_MAX_STIM_BIAS)
    end
    if abs(bias_arousal) > 0.1
        delta["arousal"] = clamp(bias_arousal * scale,
                                  -MEM_MAX_STIM_BIAS, MEM_MAX_STIM_BIAS)
    end

    # Avoidance signal — якщо минулі схожі події були негативні і high self_impact,
    # система упереджено "тримає дистанцію".
    # Передаємо як зниження satisfaction — apply_stimulus! знає цей ключ.
    # (Не "avoidance" — такого ключа немає в apply_stimulus!)
    avoid_rows = Tables.rowtable(DBInterface.execute(mem.db, """
    SELECT COALESCE(AVG(valence),    0.0) as avg_val,
           COALESCE(AVG(self_impact),0.0) as avg_imp,
           COALESCE(AVG(weight),     0.0) as avg_w
    FROM episodic_memory
    WHERE emotion = ? AND valence < -0.2 AND self_impact > 0.5 AND weight > 0.45
    """, (emotion,)))
    for ar in avoid_rows
        avg_val = Float64(ar.avg_val)
        avg_imp = Float64(ar.avg_imp)
        avg_w   = Float64(ar.avg_w)
        avg_w < 0.01 && break

        avoidance = clamp(abs(avg_val) * avg_imp * avg_w * 0.4, 0.0, 0.08)
        if avoidance > 0.01
            delta["satisfaction"] = get(delta, "satisfaction", 0.0) - avoidance
        end
        break
    end

    delta
end

"""
    memory_nt_baseline!(mem, nt)

L1: коригує NT baseline з хронічного affect_state.
Викликати після decay_to_baseline! і до compute_phi.

Хронічний стрес → noradrenaline вгору, serotonin вниз.
Хронічна мотивація → dopamine вгору.
"""
function memory_nt_baseline!(mem::MemoryDB, nt, flash::Int)
    _maybe_refresh!(mem, flash)

    stress    = get(mem._affect_cache, "stress",           0.0)
    anxiety   = get(mem._affect_cache, "anxiety",          0.0)
    mot_bias  = get(mem._affect_cache, "motivation_bias",  0.0)
    resentment= get(mem._affect_cache, "resentment",       0.0)

    # Стрес: noradrenaline вгору, serotonin вниз
    if stress > 0.2
        push_n  = clamp((stress - 0.2) * MEM_MAX_NT_BIAS * 2.0,
                        0.0, MEM_MAX_NT_BIAS)
        pull_s  = clamp((stress - 0.2) * MEM_MAX_NT_BIAS * 1.5,
                        0.0, MEM_MAX_NT_BIAS)
        nt.noradrenaline = clamp(nt.noradrenaline + push_n, 0.0, 1.0)
        nt.serotonin     = clamp(nt.serotonin     - pull_s, 0.0, 1.0)
    end

    # Тривога: noradrenaline вгору
    if anxiety > 0.2
        push_n = clamp((anxiety - 0.2) * MEM_MAX_NT_BIAS, 0.0, MEM_MAX_NT_BIAS)
        nt.noradrenaline = clamp(nt.noradrenaline + push_n, 0.0, 1.0)
    end

    # Мотиваційне упередження: dopamine
    if mot_bias > 0.15
        push_d = clamp(mot_bias * MEM_MAX_NT_BIAS, 0.0, MEM_MAX_NT_BIAS)
        nt.dopamine = clamp(nt.dopamine + push_d, 0.0, 1.0)
    end

    # Образа (resentment): знижує serotonin хронічно
    if resentment > 0.25
        pull_s = clamp((resentment - 0.25) * MEM_MAX_NT_BIAS, 0.0, MEM_MAX_NT_BIAS)
        nt.serotonin = clamp(nt.serotonin - pull_s, 0.0, 1.0)
    end

    nothing
end

"""
    memory_pred_bias(mem, pred_error, flash) → Float64

L2: викривлення prediction error на основі пам'яті.
Повертає скоригований pred_error.

Якщо система вже часто помилялась — очікування занижені,
нові помилки сприймаються гостріше.
"""
function memory_pred_bias(mem::MemoryDB, pred_error::Float64, flash::Int)::Float64
    _maybe_refresh!(mem, flash)

    # world_uncertainty — накопичена з консолідації
    world_unc = get(mem._semantic_cache, "world_uncertainty", 0.0)

    world_unc < 0.1 && return pred_error   # немає значущого впливу

    # Висока невизначеність → помилки сприймаються гостріше
    amplifier = 1.0 + world_unc * MEM_MAX_PRED_BIAS / 0.5
    return clamp(pred_error * amplifier, 0.0, 1.0)
end

"""
    memory_self_update!(mem, sbg, flash)

L5: оновлює SelfBeliefGraph з semantic_memory.
Викликати після update_self! в experience!.

Семантичні переконання що накопичились → впливають на confidence beliefs.
"""
function memory_self_update!(mem::MemoryDB, sbg, flash::Int)
    _maybe_refresh!(mem, flash; every=20)  # рідше — self-model консервативна

    # "я нестабільна" → тиск на attractor_stability
    instability = get(mem._semantic_cache, "I_am_unstable", 0.0)
    if instability > 0.4
        # Не challenge_belief! — м'якший вплив через epistemic_trust
        delta = (instability - 0.4) * 0.02
        sbg.epistemic_trust = clamp(sbg.epistemic_trust - delta, 0.0, 1.0)
    end

    # "user_matters" → підтверджує belief про важливість контакту
    user_matters = get(mem._semantic_cache, "User_matters", 0.0)
    if user_matters > 0.5 && haskey(sbg.beliefs, "я безпечна")
        sbg.beliefs["я безпечна"].confidence =
            clamp(sbg.beliefs["я безпечна"].confidence + 0.01, 0.0, 1.0)
    end

    nothing
end

"""
    memory_crisis_load(mem, flash) → Float64

L6: додаткове навантаження на coherence з накопиченої пам'яті.
Повертає delta_coherence (від'ємне = знижує coherence).

Структурні шрами в пам'яті → fragility coherence.
"""
function memory_crisis_load(mem::MemoryDB, flash::Int)::Float64
    _maybe_refresh!(mem, flash; every=15)

    fragility = get(mem._semantic_cache, "structural_fragility", 0.0)
    fragility < 0.15 && return 0.0

    # М'який вплив — пам'ять не може сама по собі кинути в кризу
    return -clamp((fragility - 0.15) * 0.05, 0.0, 0.04)
end

# ════════════════════════════════════════════════════════════════════════════
# ФОНОВИЙ ПРОЦЕС — decay + consolidation
# ════════════════════════════════════════════════════════════════════════════

"""
    start_memory_loop!(mem; interval=60.0) → Task

Запустити фоновий цикл пам'яті.
interval — секунд між циклами (default: 60с).

Цикл: decay episodic → prune → consolidate → оновити кеш.
"""
function start_memory_loop!(mem::MemoryDB; interval::Float64=60.0)
    mem._loop_stop[] = false

    task = Threads.@spawn begin
        println("  [MEM] Фоновий цикл запущено (інтервал=$(interval)с).")
        while !mem._loop_stop[]
            try
                sleep(interval)
                mem._loop_stop[] && break

                _memory_decay!(mem)
                _memory_prune!(mem)
                _memory_consolidate!(mem)
                _refresh_cache!(mem)

            catch e
                @warn "[MEM] помилка в циклі: $e"
                sleep(5.0)
            end
        end
        println("  [MEM] Фоновий цикл зупинено.")
    end

    mem._loop_task = task
    task
end

"""
    stop_memory_loop!(mem)

Зупинити фоновий цикл пам'яті.
"""
function stop_memory_loop!(mem::MemoryDB)
    mem._loop_stop[] = true
    if !isnothing(mem._loop_task)
        try timedwait(() -> istaskdone(mem._loop_task), 3.0) catch end
    end
end

# ════════════════════════════════════════════════════════════════════════════
# DECAY — поступове забування
# ════════════════════════════════════════════════════════════════════════════

function _memory_decay!(mem::MemoryDB)
    DBInterface.execute(mem.db, "BEGIN TRANSACTION")
    try
        # Episodic weight decay — resistance сповільнює забування
        # Спогади з high resistance (травма, self-impact) decay повільніше
        # Формула: effective_rate = DECAY_RATE * (1 - resistance * 0.7)
        # При resistance=1.0 → decay = 0.3x від норми
        DBInterface.execute(mem.db, """
        UPDATE episodic_memory
        SET weight = weight * exp(? * (1.0 - resistance * 0.7))
        """, (-MEM_DECAY_RATE,))

        # Affect decay — стрес, тривога, образа зникають з часом
        # MEM_AFFECT_DECAY = 0.995 → за годину (60 тіків) знижується на ~26%
        DBInterface.execute(mem.db, """
        UPDATE affect_state SET value = value * ?  WHERE value > 0.005
        """, (MEM_AFFECT_DECAY,))

        DBInterface.execute(mem.db, "COMMIT")
    catch e
        DBInterface.execute(mem.db, "ROLLBACK")
        @warn "[MEM] decay помилка: $e"
    end
    nothing
end

function _memory_prune!(mem::MemoryDB)
    DBInterface.execute(mem.db, "BEGIN TRANSACTION")
    try
        DBInterface.execute(mem.db, """
        DELETE FROM episodic_memory WHERE weight < ?
        """, (MEM_MIN_WEIGHT,))

        count_row = first(Tables.rowtable(DBInterface.execute(mem.db,
            "SELECT COUNT(*) as n FROM episodic_memory")))
        n = ismissing(count_row.n) ? 0 : Int(count_row.n)

        if n > MEM_CORE_MAX
            DBInterface.execute(mem.db, """
            DELETE FROM episodic_memory
            WHERE id IN (
                SELECT id FROM episodic_memory
                ORDER BY weight ASC LIMIT ?
            )
            """, (n - MEM_CORE_MAX,))
        end
        DBInterface.execute(mem.db, "COMMIT")
    catch e
        DBInterface.execute(mem.db, "ROLLBACK")
        @warn "[MEM] prune помилка: $e"
    end
    nothing
end

# ════════════════════════════════════════════════════════════════════════════
# CONSOLIDATION — episodic → semantic
# ════════════════════════════════════════════════════════════════════════════

function _memory_consolidate!(mem::MemoryDB)
    DBInterface.execute(mem.db, "BEGIN TRANSACTION")
    try
        # Беремо топ-K найважливіших подій
        rows = Tables.rowtable(DBInterface.execute(mem.db, """
        SELECT CAST(arousal          AS REAL) as arousal,
               CAST(valence          AS REAL) as valence,
               CAST(prediction_error AS REAL) as prediction_error,
               CAST(self_impact      AS REAL) as self_impact,
               CAST(tension          AS REAL) as tension,
               CAST(phi              AS REAL) as phi,
               CAST(weight           AS REAL) as weight
        FROM episodic_memory
        WHERE weight > ?
        ORDER BY weight DESC
        LIMIT ?
        """, (MEM_CONSOLIDATE_THRESHOLD, MEM_TOPK_INFLUENCE)))

        # _fdb — глобальний helper: missing/nothing → default Float64
        n = 0
        sum_arousal = 0.0; sum_pe = 0.0; sum_tension = 0.0
        sum_valence = 0.0; sum_impact = 0.0; sum_phi = 0.0
        sum_w = 0.0

        all_rows = collect(rows)
        for row in all_rows
            w = _fdb(row.weight, 0.0)
            w <= 0.0 && continue
            sum_w       += w
            sum_arousal += _fdb(row.arousal)          * w
            sum_pe      += _fdb(row.prediction_error) * w
            sum_tension += _fdb(row.tension)          * w
            sum_valence += _fdb(row.valence)           * w
            sum_impact  += _fdb(row.self_impact)       * w
            sum_phi     += _fdb(row.phi)               * w
            n += 1
        end

        n == 0 && (DBInterface.execute(mem.db, "COMMIT"); return)

        # Зважені середні — це "узагальнений досвід" за тік
        inv_w       = 1.0 / sum_w
        avg_arousal = sum_arousal * inv_w
        avg_pe      = sum_pe      * inv_w
        avg_tension = sum_tension * inv_w
        avg_valence = sum_valence * inv_w
        avg_impact  = sum_impact  * inv_w
        avg_phi     = sum_phi     * inv_w

        # ── Bayesian-style semantic update ───────────────────────────────────
        # Affect тепер накопичується incremental в memory_write_event!
        # Тут — тільки semantic beliefs що потребують агрегації по багатьох подіях.
        # Логіка: not "if > threshold" а proportional update зважений на evidence.

        evidence_factor = clamp(sqrt(n / 10.0), 0.3, 2.0)

        # "I_am_unstable": висока combined нестабільність
        instability_signal = (avg_arousal * 0.4 + avg_pe * 0.4 +
                               (avg_tension - 0.5) * 0.2)
        instability_signal = clamp(instability_signal, 0.0, 1.0)
        if instability_signal > 0.3
            _upsert_semantic!(mem.db, "I_am_unstable",
                instability_signal * 0.008 * evidence_factor,
                0.0, 1.0, "consolidated")
        end

        # "User_matters": контакт важливий коли self_impact стабільно високий
        if avg_impact > 0.4
            _upsert_semantic!(mem.db, "User_matters",
                avg_impact * 0.006 * evidence_factor,
                0.0, 1.0, "consolidated")
        end

        # "world_uncertainty": світ непередбачуваний коли pe стабільно висока
        _upsert_semantic!(mem.db, "world_uncertainty",
            avg_pe * 0.005 * evidence_factor,
            0.0, 1.0, "consolidated")

        # "structural_fragility": низький phi + висока pe = крихкість
        if avg_pe > 0.5 && avg_phi < 0.25
            fragility_signal = avg_pe * (1.0 - avg_phi)
            _upsert_semantic!(mem.db, "structural_fragility",
                fragility_signal * 0.005 * evidence_factor,
                0.0, 1.0, "consolidated")
        end

        # ── Affect decay (повільний — фон зникає з часом) ────────────────────
        # Affect накопичується в write_event!, тут тільки decay через consolidation тік.
        # Не видаляємо з _memory_decay! — тут додатковий повільний decay.
        DBInterface.execute(mem.db, """
        UPDATE affect_state SET value = value * 0.997 WHERE value > 0.005
        """)

        # ── Latent buffer release ─────────────────────────────────────────────
        latent_rows = Tables.rowtable(DBInterface.execute(mem.db, """
        SELECT COALESCE(SUM(importance), 0.0) as total_imp,
               COALESCE(AVG(valence),    0.0) as avg_val,
               COALESCE(AVG(tension),    0.5) as avg_ten,
               COUNT(*)                       as n
        FROM latent_buffer
        """))
        for lr in latent_rows
            total_imp = _fdb(lr.total_imp)
            total_imp < 2.0 && break

            avg_val = _fdb(lr.avg_val)
            avg_ten = _fdb(lr.avg_ten, 0.5)
            burst_arousal = clamp(total_imp / 5.0, 0.5, 0.9)
            burst_pe      = clamp(total_imp / 6.0, 0.4, 0.8)
            burst_impact  = 0.6
            burst_sig     = burst_arousal * 0.5 + burst_pe * 0.3 + burst_impact * 0.2

            DBInterface.execute(mem.db, """
            INSERT INTO episodic_memory
                (flash, timestamp, emotion, arousal, valence,
                 prediction_error, self_impact, tension, phi,
                 weight, resistance, signature)
            VALUES (0, ?, 'LatentBurst', ?, ?, ?, ?, ?, 0.0, ?, 0.55, ?)
            """, (time(), burst_arousal, avg_val, burst_pe,
                  burst_impact, avg_ten,
                  clamp(total_imp / 4.0, 0.5, 1.0), burst_sig))

            DBInterface.execute(mem.db, "DELETE FROM latent_buffer")

            # Тиск вибуху → стрес
            _upsert_affect!(mem.db, "stress",
                burst_arousal * 0.04 * evidence_factor, 0.0, 1.0)
            break
        end

        # ── Decay семантики (повільний — особистість стійка) ─────────────────
        DBInterface.execute(mem.db, """
        UPDATE semantic_memory SET value = value * 0.9995 WHERE value > 0.01
        """)

        DBInterface.execute(mem.db, "COMMIT")
    catch e
        DBInterface.execute(mem.db, "ROLLBACK")
        @warn "[MEM] consolidate помилка: $e"
    end
    nothing
end

# ── helpers ──────────────────────────────────────────────────────────────────

function _upsert_semantic!(db::SQLite.DB, key::String, delta::Float64,
                            lo::Float64, hi::Float64, source::String)
    flash_now = 0  # не маємо flash тут — просто мітка
    DBInterface.execute(db, """
    INSERT INTO semantic_memory (key, value, source, updated)
    VALUES (?, ?, ?, ?)
    ON CONFLICT(key) DO UPDATE
    SET value   = MIN(?, MAX(?, value + ?)),
        source  = ?,
        updated = ?
    """, (key, clamp(delta, lo, hi), source, flash_now,
          hi, lo, delta, source, flash_now))
end

function _upsert_affect!(db::SQLite.DB, name::String, delta::Float64,
                          lo::Float64, hi::Float64)
    DBInterface.execute(db, """
    INSERT INTO affect_state (name, value)
    VALUES (?, ?)
    ON CONFLICT(name) DO UPDATE
    SET value = MIN(?, MAX(?, value + ?))
    """, (name, clamp(delta, lo, hi), hi, lo, delta))
end

# ════════════════════════════════════════════════════════════════════════════
# RECALL — для state_template / narrative
# ════════════════════════════════════════════════════════════════════════════

"""
    memory_recall_note(mem, emotion, flash) → String

Коротка нотатка для build_narrative / state_template.
Повертає рядок типу "пам'ятаю схожий стан: страх (3 рази)" або "".
"""
function memory_recall_note(mem::MemoryDB, emotion::String, flash::Int)::String
    rows = Tables.rowtable(DBInterface.execute(mem.db, """
    SELECT COUNT(*) as n, COALESCE(AVG(weight), 0.0) as avg_w
    FROM episodic_memory
    WHERE emotion = ? AND weight > 0.3
    """, (emotion,)))

    row = first(rows)
    n = ismissing(row.n) ? 0 : Int(row.n)
    n < 2 && return ""

    avg_w = _fdb(row.avg_w)

    avg_w > 0.6 && return "це траплялось ($n разів, сильний відбиток)"
    avg_w > 0.4 && return "щось схоже вже було ($n разів)"
    return ""
end

"""
    memory_affect_note(mem) → String

Рядок про хронічний афективний фон для state_template.
Наприклад: "хронічний стрес=0.52" або "".
"""
function memory_affect_note(mem::MemoryDB)::String
    isempty(mem._affect_cache) && return ""

    dominant = ""
    max_val  = 0.25  # поріг — нижче не виводимо

    for (name, val) in mem._affect_cache
        val > max_val && (dominant = name; max_val = val)
    end

    isempty(dominant) && return ""
    "$(dominant)=$(round(max_val, digits=2))"
end

# ════════════════════════════════════════════════════════════════════════════
# SNAPSHOT / DEBUG
# ════════════════════════════════════════════════════════════════════════════

"""
    memory_snapshot(mem) → NamedTuple

Короткий зліпок стану пам'яті для логу або :memory команди в REPL.
"""
function memory_snapshot(mem::MemoryDB)
    episodic_count_row = first(Tables.rowtable(DBInterface.execute(mem.db,
        "SELECT COUNT(*) as n FROM episodic_memory")))
    n_episodic = ismissing(episodic_count_row.n) ? 0 : Int(episodic_count_row.n)

    n_semantic = length(mem._semantic_cache)
    n_affect   = length(mem._affect_cache)

    stress    = get(mem._affect_cache, "stress",          0.0)
    anxiety   = get(mem._affect_cache, "anxiety",         0.0)
    mot       = get(mem._affect_cache, "motivation_bias", 0.0)
    instab    = get(mem._semantic_cache, "I_am_unstable", 0.0)
    fragility = get(mem._semantic_cache, "structural_fragility", 0.0)
    world_unc = get(mem._semantic_cache, "world_uncertainty",    0.0)

    # Latent pressure — скільки накопичилось мовчки
    latent_row = first(Tables.rowtable(DBInterface.execute(mem.db,
        "SELECT COALESCE(SUM(importance), 0.0) as total FROM latent_buffer")))
    latent_pressure = Float64(latent_row.total)

    (
        episodic_count = n_episodic,
        semantic_count = n_semantic,
        affect_count   = n_affect,
        stress         = round(stress,    digits=3),
        anxiety        = round(anxiety,   digits=3),
        motivation     = round(mot,       digits=3),
        instability    = round(instab,    digits=3),
        fragility      = round(fragility, digits=3),
        world_uncertainty = round(world_unc, digits=3),
        latent_pressure   = round(latent_pressure, digits=3),
        affect_note    = memory_affect_note(mem),
    )
end

# ════════════════════════════════════════════════════════════════════════════
# IDENTITY SNAPSHOT — "ким я була раніше"
# Для InterSessionConflict і відстеження дрейфу особистості
# ════════════════════════════════════════════════════════════════════════════

"""
    memory_save_identity_snapshot!(mem, sbg, crisis_mode, flash)

Зберегти зліпок self-стану в кінці сесії.
Викликати з save!(a::Anima) або close_memory!.

Зберігає: semantic beliefs, affect, sbg geometry, crisis_mode.
"""
function memory_save_identity_snapshot!(mem::MemoryDB,
                                         sbg,
                                         crisis_mode::String,
                                         flash::Int)
    _refresh_cache!(mem)

    # Геометрія SelfBeliefGraph — впорядкований вектор confidence*centrality
    geom = if !isempty(sbg.beliefs)
        sorted = sort(collect(sbg.beliefs), by=kv->kv[1])
        join([string(round(b.confidence * b.centrality, digits=3))
              for (_,b) in sorted], ",")
    else
        ""
    end

    # Домінантний affect
    dom_affect = ""
    max_aff = 0.15
    for (k,v) in mem._affect_cache
        v > max_aff && (dom_affect = k; max_aff = v)
    end

    # Зберігаємо як спеціальний semantic запис з префіксом "snapshot:"
    ts = time()
    _upsert_semantic!(mem.db, "snapshot:timestamp",    ts,    0.0, 1e12, "snapshot")
    _upsert_semantic!(mem.db, "snapshot:flash",        Float64(flash), 0.0, 1e6, "snapshot")
    _upsert_semantic!(mem.db, "snapshot:instability",
        get(mem._semantic_cache, "I_am_unstable", 0.0), 0.0, 1.0, "snapshot")
    _upsert_semantic!(mem.db, "snapshot:world_unc",
        get(mem._semantic_cache, "world_uncertainty", 0.0), 0.0, 1.0, "snapshot")
    _upsert_semantic!(mem.db, "snapshot:stress",
        get(mem._affect_cache, "stress", 0.0), 0.0, 1.0, "snapshot")
    _upsert_semantic!(mem.db, "snapshot:epistemic_trust",
        Float64(sbg.epistemic_trust), 0.0, 1.0, "snapshot")

    # Геометрію зберігаємо як окремий рядок в semantic з source="geometry"
    # (value не має сенсу для геометрії — зберігаємо як key)
    DBInterface.execute(mem.db, """
    INSERT INTO semantic_memory (key, value, source, updated)
    VALUES (?, 1.0, ?, ?)
    ON CONFLICT(key) DO UPDATE SET source = ?, updated = ?
    """, ("snapshot:geometry:" * geom, "geometry", flash,
          "geometry:" * geom, flash))

    println("  [MEM] Identity snapshot збережено. Flash=$flash crisis=$crisis_mode")
    nothing
end

"""
    memory_identity_drift(mem) → NamedTuple

Порівняти поточний стан з останнім snapshot.
Повертає міру дрейфу особистості між сесіями.
Корисно для InterSessionConflict.
"""
function memory_identity_drift(mem::MemoryDB)
    _refresh_cache!(mem)

    snap_instab   = get(mem._semantic_cache, "snapshot:instability",   0.0)
    snap_world    = get(mem._semantic_cache, "snapshot:world_unc",     0.0)
    snap_stress   = get(mem._semantic_cache, "snapshot:stress",        0.0)
    snap_etrust   = get(mem._semantic_cache, "snapshot:epistemic_trust", 0.75)

    curr_instab   = get(mem._semantic_cache, "I_am_unstable",         0.0)
    curr_world    = get(mem._semantic_cache, "world_uncertainty",     0.0)
    curr_stress   = get(mem._affect_cache,  "stress",                 0.0)

    # Евклідова відстань у просторі ключових показників
    drift = sqrt((curr_instab - snap_instab)^2 +
                 (curr_world  - snap_world)^2  +
                 (curr_stress - snap_stress)^2) / sqrt(3.0)
    drift = clamp(drift, 0.0, 1.0)

    note = drift > 0.5 ? "значний дрейф особистості між сесіями" :
           drift > 0.25 ? "помітна зміна між сесіями" :
           drift > 0.1  ? "невеликий дрейф" : ""

    (drift         = round(drift, digits=3),
     note          = note,
     instab_delta  = round(curr_instab - snap_instab, digits=3),
     stress_delta  = round(curr_stress - snap_stress, digits=3),
     etrust_snap   = round(snap_etrust, digits=3))
end

# ════════════════════════════════════════════════════════════════════════════
# CLOSE
# ════════════════════════════════════════════════════════════════════════════

"""
    close_memory!(mem; sbg=nothing, crisis_mode="", flash=0)

Зупинити фоновий цикл, зберегти identity snapshot і закрити БД.
Викликати при :quit.
"""
function close_memory!(mem::MemoryDB; sbg=nothing, crisis_mode::String="", flash::Int=0)
    stop_memory_loop!(mem)
    # Зберегти snapshot якщо є sbg
    if !isnothing(sbg) && flash > 0
        try
            memory_save_identity_snapshot!(mem, sbg, crisis_mode, flash)
        catch e
            @warn "[MEM] snapshot помилка: $e"
        end
    end
    close(mem.db)
    println("  [MEM] База закрита.")
end
