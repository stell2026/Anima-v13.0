# Anima — Архітектура внутрішнього стану 🌀

Anima — це експериментальна когнітивна архітектура, яка моделює внутрішній стан, конфлікти та прийняття рішень, а не просто генерує відповіді через LLM.

Система побудована як багаторівневий пайплайн, де текст не є джерелом поведінки — він є її наслідком.

---

## 🔍 Чим це відрізняється

На відміну від типових AI систем:

- стан первинний, текст вторинний
- рішення виникають із внутрішнього конфлікту
- система живе між взаємодіями — серце б'ється, психіка дрейфує, пам'ять метаболізується
- криза — це режим, а не помилка
- LLM використовується як інтерфейс, а не як "мозок"
- система може спати — обробляти невирішений досвід поки "спить"

---

## 🧠 Як це працює (спрощено)

**Input → Internal State → Conflict → Decision → Output**

Текст перетворюється у стимул через ізольовану вхідну LLM, далі проходить через внутрішній стан, пам'ять і конфлікти — і лише потім формується рішення та відповідь. Між взаємодіями система продовжує жити: фоновий процес підтримує серцебиття, NT дрейф, метаболізм пам'яті і психічний дрейф.

---

## 🏗 Архітектура (спрощено)

- L0 — Вхідна LLM (ізольована)
- L1 — Нейрохімічний та тілесний стан
- L2 — Генеративна / предиктивна модель
- L3 — Метрики (φ prior/posterior, prediction error, free energy)
- L4 — Психічний шар (конфлікти, захисти, значущість)
- L5 — Модель Я
- L6 — Монітор кризи (когерентність системи)
- L7 — Вихідна LLM

---

## ⚙️ Поточний стан 

- повний pipeline реалізований і стабільний
- φ prior/posterior: система бачить себе до і після кожного досвіду
- SQLite пам'ять: episodic, semantic, affect — накопичуються і формують стан
- фоновий процес: система жива між взаємодіями (психіка дрейфує, серце б'ється)
- dream generation: обробка невирішеного досвіду під час "сну"
- суб'єктивність: prediction loop, interpretation, belief emergence з досвіду
- authenticity monitor: фільтрує суперечності між станом і наративом
- narrative варіабельність: різні формулювання одного стану між флешами

---

## 🚧 Обмеження

- частина поведінки все ще залежить від LLM (вихідна генерація)
- LLM не впливає на внутрішній стан — тільки виражає його
- ~180+ флешів для накопичення реальних semantic beliefs

---

## 📌 Що це не є

- це не чат-бот
- це не prompt engineering
- це не обгортка над LLM

Це спроба побудувати систему, де поведінка виникає з внутрішнього стану, а не з тексту.

---

## 🧠 Нотатка

Проєкт є дослідницьким (R&D) і спрямований на дослідження того, чи може внутрішня структура сама по собі породжувати щось, що нагадує суб'єктність. Не симульована психологія — обчислювальна суб'єктність.

---

## 🔬 Детальна архітектура

```
 L0 ─── Вхідна LLM (ізольована) ───────────────────────────
        Отримує: тільки текст користувача
        Повертає: JSON { tension, arousal, satisfaction,
                         cohesion, confidence, want }
        Немає доступу до стану Аніми, історії діалогу або вихідної LLM
        Промпт: llm/input_prompt.txt
        Fallback: text_to_stimulus якщо недоступна або confidence < 0.60
        │
    ▼
  СТИМУЛ входить у симуляцію
  (+ memory_stimulus_bias + subj_predict! + subj_interpret!)
        │
    ▼
 L1 ─── Нейрохімічний субстрат ────────────────────────────
        NeurotransmitterState (дофамін / серотонін / норадреналін)
        Куб Левхейма → первинна емоційна мітка
        EmbodiedState (пульс, м'язовий тонус, нутро, дихання)
        HeartbeatCore (ЧСС, HRV, вегетативний тонус)
        memory_nt_baseline! ← хронічний affect з SQLite
        │
    ▼
 L2 ─── Генеративна модель ────────────────────────────────
        GenerativeModel (байєсівські переконання з precision-вагами)
        MarkovBlanket (цілісність межі я/не-я)
        HomeostaticGoals (потяги як тиск, а не правила)
        AttentionNarrowing (звуження уваги під стресом)
        InteroceptiveInference (помилка тілесного прогнозу, алостатичне навантаження)
        TemporalOrientation (циркадна модуляція, розрив між сесіями)
        │
    ▼
 L3 ─── Метрики свідомості ────────────────────────────────
        IITModule → φ_prior / φ_posterior (два погляди на один момент)
          φ_prior:     (vad, sbg_stability, epistemic_trust, allostatic_load)
          φ_posterior: (blanket.integrity, vfe, intero_error)
          φ feedback loop: phi_delta > 0.05 → корекція epistemic_trust
        PredictiveProcessor → помилка прогнозу, здивування
        FreeEnergyEngine → VFE = складність − точність
        PolicySelector → епістемічна + прагматична цінність
        │
    ▼
 L4 ─── Психічний шар ─────────────────────────────────────
        NarrativeGravity      — минулі події деформують теперішнє
        AnticipatoryConsciousness — свідомість живе в очікуваному
        SolomonoffWorldModel  — MDL-гіпотеза з contextual_best():
                                патерн що стартує з поточного стану,
                                staleness guard (>15 флешів → мовчить)
        ShameModule           — сором vs. провина
        EpistemicDefense      — захист від болючої правди
        ChronifiedAffect      — образа / відчуження / гіркота
        IntrinsicSignificance — градієнт значущості
        MoralCausality        — моральне міркування як етап обробки
        FatigueSystem         — когнітивне / емоційне / соматичне виснаження
        StressRegression      — регресія під стресом
        ShadowSelf            — Юнгівська Тінь
        Metacognition         — спостереження за собою (5 рівнів)
        SignificanceLayer      — яка потреба поставлена на карту (6 потреб)
        GoalConflict          — напруга між конкурентними потребами
        LatentBuffer          — відкладені реакції (сумнів / сором / прив'язаність / загроза)
        StructuralScars       — накопичений осад від частих проривів
        │
    ▼
 L5 ─── Шар Я ─────────────────────────────────────────────
        SelfBeliefGraph       — граф переконань про себе, каскадний колапс
        SelfPredictiveModel   — генеративна модель для станів себе
                                warm-up lr (flash<30: 0.25), trend-based notes
        AgencyLoop            — "чи я спричинив це?"
                                passive_ownership через vad_change
        InterSessionConflict  — виявлення розриву ідентичності
        ExistentialAnchor     — неперервність себе між сесіями
        UnknownRegister       — відстеження типізованої невизначеності
        AuthenticityMonitor   — ризик раціоналізації, дрейф автентичності,
                                фільтрація суперечностей у narrative
        SubjectivityEngine    — prediction loop, стансів, interpretation,
                                belief emergence з episodic патернів
        │
    ▼
 L6 ─── Монітор кризи ─────────────────────────────────────
        CrisisMonitor (INTEGRATED / FRAGMENTED / DISINTEGRATED)
        Когерентність = мінімум(переконання, межа, модель, інтеграція)
        crisis_note залежить від coherence depth (shallow vs deep)
        │
    ▼
 L7 ─── Вихідна LLM ───────────────────────────────────────
        Повний стан → llm/system_prompt.txt + llm/state_template.txt
        Модель виражає стан через мову — тон, вибір слів,
        довжину речень, що вона помічає в співрозмовнику.
        Ніколи не цитує числа чи назви змінних напряму.

 ═══════════════════════════════════════════════════════════
 ФОНОВИЙ ПРОЦЕС (між взаємодіями)
        tick_heartbeat!       — серце б'ється безперервно
        spontaneous_drift!    — спонтанний шум NT
        slow_tick! (~60с):
          ├─ циркадний дрейф NT
          ├─ belief decay
          ├─ memory metabolism (decay → consolidate → semantic update)
          ├─ allostasis recovery
          ├─ idle_thought! (10% шанс внутрішнього досвіду)
          ├─ psyche_slow_tick! (психіка дрейфує між взаємодіями)
          │     ChronifiedAffect, Anticipatory, Shame, SignificanceLayer,
          │     GoalConflict, FatigueSystem — всі живуть у фоні
          ├─ dream_flash! (ніч + gap>30хв + 5% chance)
          ├─ subj_emerge_beliefs! (тільки при новому flash_count)
          └─ crisis check

 ─────────────────────────────────────────────────────────
 DREAM GENERATION (anima_dream.jl)
        can_dream(): ніч 0–6h + gap>30хв + 5% chance + не DISINTEGRATED
        dream_flash!(): уламок dialog_history → реконструйований стимул
        NT зсув × 0.25 (сон впливає слабше ніж реальний досвід)
        memory_uncertainty +0.15 per dream
        anima_dream.json — ротаційний лог (max 20 снів)
```

---

## Що нового 

### φ prior/posterior — два погляди на один момент

Раніше φ рахувалась один раз. Тепер — `φ_prior` (до досвіду) і `φ_posterior` (після VFE і interoception). Розрив між ними — φ feedback loop: якщо система помилилась про себе → коригує `epistemic_trust`. В логах видно: `φ=0.81(0.53→0.81)`.

### Контекстуальний Solomonoff

`contextual_best()` шукає патерн що стартує з поточного стану і підтверджувався останні 20 флешів. Якщо глобальний `best` застарів (>15 флешів без підтвердження) — система мовчить замість того щоб повторювати неактуальний висновок.

### Narrative варіабельність

Кожна note-функція (`build_inner_voice`, `_crisis_note`, `sig_note`, `shame_note`) обирає між 3–4 феноменологічно різними описами одного стану через `flash % N`. Не рандом — детерміновано, ніколи два поспіль однакових.

### Психіка живе між взаємодіями

`psyche_slow_tick!` (~60с): ChronifiedAffect дрейфує залежно від NT, Anticipatory decay, Shame decay, contact_need зростає з часом бездіяльності. `background_save!` атомарно зберігає `anima_psyche.json` кожну хвилину.

### Affect накопичується з кожного досвіду

Мікро-update після кожного `memory_write_event!` — stress, anxiety, motivation_bias накопичуються incrementally а не через threshold. `MEM_CONSOLIDATE_THRESHOLD` знижено 0.55→0.35.

### Сновидіння — фаза B3

Новий файл `anima_dream.jl`. Поки система "спить" (ніч + gap>30хв) — 5% шанс на slow_tick що вона реконструює уламок dialog_history як сон. NT зсувається × 0.25, `memory_uncertainty +0.15`, запис у `anima_dream.json`. `:dreams` команда в REPL.

### AuthenticityMonitor активований

Фільтрує self_pred notes що суперечать поточному стану. При `phi>0.55` і `etrust>0.55` — "Не можу собі довіряти" не потрапляє в narrative.

### AgencyLoop виправлено

`dom_drive` поріг знижено 0.15→0.08. Passive ownership через `vad_change`. `SelfPredictiveModel` warm-up і серіалізація `predicted_self_vad` — без cold start при кожному запуску.

---

## Вимоги

- **Julia 1.9+**
- Julia-пакети: `HTTP`, `JSON3`, `SQLite`, `Tables`
- API-ключ від одного з підтримуваних провайдерів 

---

## Встановлення

### 1. Встановити Julia

Завантажити з [julialang.org](https://julialang.org/downloads/) або через `juliaup`:

```bash
# Linux / macOS
curl -fsSL https://install.julialang.org | sh

# Windows (PowerShell)
winget install julia -s msstore
```

Перевірити:
```bash
julia --version
```

### 2. Клонувати репозиторій

```bash
git clone https://github.com/stell2026/Anima
cd Anima
```

### 3. Встановити Julia-залежності

```bash
julia --project=. -e 'import Pkg; Pkg.instantiate()'
```

> Залежності: HTTP, JSON3, SQLite, Tables, Dates, Statistics, LinearAlgebra

---

## Запуск

### Швидкий старт (рекомендовано)

```bash
julia --project=. run_anima.jl
```

`run_anima.jl` запускає все одразу: завантажує стан, ініціалізує SQLite пам'ять і SubjectivityEngine, запускає фоновий процес із серцебиттям і dream generation.

### Налаштування LLM

Відредагуйте `run_anima.jl`:
```julia
include("anima_interface.jl")
include("anima_memory_db.jl")
include("anima_subjectivity.jl")
include("anima_dream.jl")
include("anima_background.jl")

anima = Anima()
mem   = MemoryDB()
subj  = SubjectivityEngine(mem)

repl_with_background!(anima;
    mem             = mem,
    subj            = subj,
    use_llm         = true,
    llm_url         = "https://openrouter.ai/api/v1/chat/completions",
    llm_model       = "openai/gpt-oss-120b:free",
    llm_key         = "YOUR_OPENROUTER_API_KEY",
    use_input_llm   = true,
    input_llm_model = "openai/gpt-oss-120b:free",
    input_llm_key   = "YOUR_OPENROUTER_API_KEY")
```

OpenRouter дає доступ до GPT, Gemini, Claude, Llama, DeepSeek та інших через один API-ключ. Є безкоштовний рівень: [openrouter.ai](https://openrouter.ai).

> 💡 Якщо одна модель перестає відповідати під час сесії — використовуйте два окремих ключі (з 2 акаунтів): один для вихідної LLM, інший для вхідної.

---

## Рекомендовані моделі

> Менші моделі (менше 70B) відповідають, але не утримують нюанси state-prompt. Щоб система справді *населяла* стан у мові, потрібна модель достатньо велика, щоб одночасно тримати весь феноменологічний фрейм.

| Модель | Примітка |
|---|---|
| `openai/gpt-oss-120b:free` | За замовчуванням. Чітко слідує інструкціям, добре тримає складний стан |
| `google/gemini-2.5-pro` | Відмінна контекстна глибина, чисто обробляє довгі state-шаблони |
| `meta-llama/llama-4-maverick` | Хороший баланс нюансів і швидкості |
| `deepseek/deepseek-r1` | Сильне міркування, точно інтерпретує внутрішній стан |
| `mistralai/mistral-large` | Надійна, стабільна тональність у довгих сесіях |

> Моделі менше 70B схильні вирівнювати стан — відповіді стають загальними замість того, щоб бути сформованими внутрішньою динамікою.

---

## Команди REPL

| Команда | Дія |
|---|---|
| *(будь-який текст)* | Обробити як вхід, згенерувати стан + опціональну LLM-відповідь |
| `:bg` | Статус фонового процесу: uptime, тіки серця, BPM, HRV, coherence |
| `:bgstop` | Зупинити фоновий процес |
| `:bgstart` | Перезапустити фоновий процес |
| `:memory` | Стан SQLite пам'яті: episodic count, semantic, stress, anxiety, latent pressure |
| `:subj` | Стан суб'єктивності: emerged beliefs, стансів, поточна лінза, surprise |
| `:state` | Нейрохімічний стан, соматичні маркери, ЧСС/HRV, coherence |
| `:vfe` | VFE, точність, складність, гомеостатичний потяг |
| `:blanket` | Ковдра Маркова: sensory, internal, integrity |
| `:hb` | Деталі серцебиття: ЧСС, HRV, вегетативний тонус |
| `:gravity` | Наративна гравітація: загальне поле, валентність, домінантна подія |
| `:anchor` | Екзистенційна неперервність і вкоріненість |
| `:solom` | Модель Соломонова: поточний контекстуальний патерн, складність |
| `:self` | Граф переконань: всі beliefs із confidence, centrality, rigidity |
| `:crisis` | Монітор кризи: режим, когерентність, кроки в поточному режимі |
| `:dreams` | Останні сни: narrative, джерело, φ, nt_delta |
| `:history` | Останні 10 реплік діалогу |
| `:clearhist` | Очистити історію діалогу |
| `:save` | Примусово зберегти стан на диск |
| `:quit` | Зберегти і вийти |

---

## Персистентний стан

### JSON-файли (поточний стан)

| Файл | Містить |
|---|---|
| `anima_core.json` | Особистість, темпоральний стан, генеративна модель, серцебиття |
| `anima_psyche.json` | Наративна гравітація, антиципація, сором, захист, виснаження, SignificanceLayer, GoalConflict *(оновлюється фоново щохвилини)* |
| `anima_self.json` | Граф переконань, агентська петля, SelfPredictiveModel, монітор автентичності |
| `anima_latent.json` | Латентний буфер і структурні шрами *(оновлюється фоново)* |
| `anima_dialog.json` | Історія діалогу |
| `anima_dream.json` | Лог сновидінь (ротаційний, max 20) |

### SQLite (`memory/anima.db`) — досвід і його наслідки

| Таблиця | Містить |
|---|---|
| `episodic_memory` | Конкретні події з вагою, resistance до decay, асоціативними зв'язками |
| `semantic_memory` | Переконання що накопичились з патернів: `I_am_unstable`, `User_matters`, `world_uncertainty` |
| `affect_state` | Хронічний афективний фон (stress, anxiety, motivation_bias) |
| `latent_buffer` | Малі незначні події що накопичуються мовчки |
| `prediction_log` | Прогнози і їхній розрив із реальністю |
| `positional_stances` | Накопичена позиція щодо типів ситуацій |
| `pattern_candidates` | Кандидати на нові переконання (ще не підтверджені) |
| `emerged_beliefs` | Переконання що система сама породила з досвіду |
| `interpretation_history` | Лінза через яку читались ситуації |

---

## Структура файлів

```
├── anima_core.jl           # Нейрохімічний субстрат, генеративна модель, IIT, φ
├── anima_psyche.jl         # Психічний шар: гравітація, сором, захист, тінь, Solomonoff
├── anima_self.jl           # Шар Я: граф переконань, агентність, невизначеність
├── anima_crisis.jl         # Монітор кризи: режими, когерентність
├── anima_interface.jl      # Головна точка входу: Anima, experience!, LLM-виклики
├── anima_input_llm.jl      # Вхідна LLM — перекладає текст у JSON-стимул
├── anima_memory_db.jl      # SQLite пам'ять: episodic, semantic, affect, latent
├── anima_subjectivity.jl   # Prediction loop, стансів, interpretation, belief emergence
├── anima_background.jl     # Фоновий процес: серцебиття, drift, memory metabolism, dreams
├── anima_dream.jl          # Dream generation — обробка невирішеного досвіду уві сні
├── run_anima.jl            # Єдина точка запуску
├── llm/
│   ├── system_prompt.txt
│   ├── state_template.txt
│   └── input_prompt.txt
├── memory/
│   └── anima.db            # SQLite база пам'яті (створюється автоматично)
├── anima_core.json         # (створюється автоматично)
├── anima_psyche.json       # (оновлюється фоново щохвилини)
├── anima_self.json         # (створюється автоматично)
├── anima_latent.json       # (оновлюється фоново)
├── anima_dialog.json       # (створюється автоматично)
└── anima_dream.json        # (створюється при першому сні)
```

`run_anima.jl` підключає всі файли у правильному порядку автоматично.

---

## 🧠 Теоретична база

Архітектура спирається на кілька наукових традицій:

**Передбачувальна обробка / Active Inference** (Фрістон, Кларк) — система підтримує генеративну модель світу і мінімізує варіаційну вільну енергію. Помилка прогнозу керує навчанням і здивуванням.

**Нейромедіаторна модель** (Левхейм) — дофамін, серотонін, норадреналін як субстрат. Емоційні стани виникають з їхньої комбінації.

**Теорія інтегрованої інформації** (Тононі) — φ вимірює наскільки стан є єдиним. φ_prior і φ_posterior дають два погляди на один момент: до і після повного циклу досвіду.

**Соматичні маркери / Втілена когніція** (Дамасіо) — тіло є частиною генеративної моделі. Нутро, пульс, м'язовий тонус — не метафори, а стани, що формують обробку.

**Психологія Я і захисні механізми** (Фрейд, Анна Фрейд, Кохут) — психологічні захисти, сором і функції Его реалізовані як функціональні модулі, а не текстові мітки.

**Автобіографічний наратив** (МакАдамс) — ідентичність — це історія. Система відстежує ким вона себе вважає з часом і виявляє коли ця історія рветься.

**Юнгівська Тінь** — витіснений матеріал, який не зникає, а породжує симптоми. Symptomogenesis — окремий модуль.

**Хронізований афект / Ressentiment** (Шелер) — деякі емоційні стани не загасають. Вони твердіють у хронічні фонові стани, які забарвлюють все решту.

**Алгоритмічна складність / Solomonoff** — система шукає найкоротше пояснення власного досвіду (MDL). Контекстуальний пошук патернів: те що зараз актуально, а не те що колись було найчастішим.

---

## Ліцензія

Тільки некомерційне використання. Повні умови у [LICENSE.txt](./LICENSE.txt).

**Особисте, освітнє та дослідницьке використання:** дозволено з атрибуцією.
**Комерційне або корпоративне використання:** потребує окремої ліцензії. Контакт: [2026.stell@gmail.com]

Copyright © 2026 Stell
