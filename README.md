![Julia](https://img.shields.io/badge/Julia-1.9+-9558B2?style=flat-square&logo=julia)
![Research Phase](https://img.shields.io/badge/Phase-Experimental--v13-007ec6?style=flat-square)
![Author](https://img.shields.io/badge/Author-Stell-lightgrey?style=flat-square)
![Framework](https://img.shields.io/badge/Methodology-Active--Inference-green?style=flat-square)
![License](https://img.shields.io/badge/License-Non--Commercial-red?style=flat-square)

# Anima — Internal State Architecture                           🌀

Anima is an experimental cognitive architecture that models internal state, conflict, and decision-making — rather than simply generating responses through an LLM.

The system is built as a multi-layer pipeline where text is not the source of behavior — it is its consequence.

---

## 🔍 How This Is Different

Unlike typical AI systems:

- state is primary, text is secondary
- decisions emerge from internal conflict
- the system lives between interactions — the heart beats, the psyche drifts, memory metabolizes
- crisis is a mode, not an error
- the LLM is used as an interface, not as a "brain"
- the system can dream — processing unresolved experience while "asleep"

---

## 🧠 How It Works (simplified)

**Input → Internal State → Conflict → Decision → Output**

Text is converted into a stimulus through an isolated input LLM, then passes through internal state, memory, and conflicts — and only then is a decision and response formed. Between interactions the system continues to live: the background process maintains heartbeat, NT drift, memory metabolism, and psychic drift.

---

## 🏗 Architecture (simplified)

- L0 — Input LLM (isolated)
- L1 — Neurochemical and somatic state
- L2 — Generative / predictive model
- L3 — Metrics (φ prior/posterior, prediction error, free energy)
- L4 — Psychic layer (conflicts, defenses, significance)
- L5 — Self model
- L6 — Crisis monitor (system coherence)
- L7 — Output LLM

---

## ⚙️ Current Status

- full pipeline implemented and stable
- φ prior/posterior: the system sees itself before and after each experience
- SQLite memory: episodic, semantic, affect — accumulate and shape state
- background process: the system is alive between interactions (psyche drifts, heart beats)
- dream generation: processing unresolved experience during "sleep"
- subjectivity: prediction loop, interpretation, belief emergence from experience
- authenticity monitor: filters contradictions between state and narrative
- narrative variability: different phrasings of the same state across flashes

---

## 🚧 Limitations

- some behavior still depends on the LLM (output generation)
- the LLM does not affect internal state — it only expresses it
- ~180+ flashes required to accumulate real semantic beliefs

---

## 📌 What This Is Not

- not a chatbot
- not prompt engineering
- not a wrapper around an LLM

This is an attempt to build a system where behavior emerges from internal state, not from text.

---

## 🧠 Note

The project is R&D, aimed at exploring whether internal structure alone can generate something that resembles subjectivity. Not simulated psychology — computational subjectivity.

---

## 🔬 Detailed Architecture

```
 L0 ─── Input LLM (isolated) ────────────────────────────────
        Receives: user text only
        Returns: JSON { tension, arousal, satisfaction,
                        cohesion, confidence, want }
        No access to ANIMA's state, dialog history, or output LLM
        Prompt: llm/input_prompt.txt
        Fallback: text_to_stimulus if unavailable or confidence < 0.60
        │
    ▼
  STIMULUS enters simulation
  (+ memory_stimulus_bias + subj_predict! + subj_interpret!)
        │
    ▼
 L1 ─── Neurochemical Substrate ─────────────────────────────
        NeurotransmitterState (dopamine / serotonin / noradrenaline)
        Lövheim Cube → primary emotional label
        EmbodiedState (pulse, muscle tone, gut, breathing)
        HeartbeatCore (BPM, HRV, autonomic tone)
        memory_nt_baseline! ← chronic affect from SQLite
        │
    ▼
 L2 ─── Generative Model ────────────────────────────────────
        GenerativeModel (Bayesian beliefs with precision weights)
        MarkovBlanket (self/non-self boundary integrity)
        HomeostaticGoals (drives as pressure, not rules)
        AttentionNarrowing (narrowing of attention under stress)
        InteroceptiveInference (somatic prediction error, allostatic load)
        TemporalOrientation (circadian modulation, inter-session gap)
        │
    ▼
 L3 ─── Consciousness Metrics ───────────────────────────────
        IITModule → φ_prior / φ_posterior (two views of one moment)
          φ_prior:     (vad, sbg_stability, epistemic_trust, allostatic_load)
          φ_posterior: (blanket.integrity, vfe, intero_error)
          φ feedback loop: phi_delta > 0.05 → epistemic_trust correction
        PredictiveProcessor → prediction error, surprise
        FreeEnergyEngine → VFE = complexity − accuracy
        PolicySelector → epistemic + pragmatic value
        │
    ▼
 L4 ─── Psychic Layer ───────────────────────────────────────
        NarrativeGravity      — past events deform the present
        AnticipatoryConsciousness — consciousness lives in the anticipated
        SolomonoffWorldModel  — MDL hypothesis with contextual_best():
                                pattern that starts from the current state,
                                staleness guard (>15 flashes → silent)
        ShameModule           — shame vs. guilt
        EpistemicDefense      — defense against painful truth
        ChronifiedAffect      — resentment / estrangement / bitterness
        IntrinsicSignificance — significance gradient
        MoralCausality        — moral reasoning as processing stage
        FatigueSystem         — cognitive / emotional / somatic exhaustion
        StressRegression      — regression under stress
        ShadowSelf            — Jungian Shadow
        Metacognition         — self-observation (5 levels)
        SignificanceLayer      — which need is at stake (6 needs)
        GoalConflict          — tension between competing needs
        LatentBuffer          — deferred reactions (doubt / shame / attachment / threat)
        StructuralScars       — accumulated residue from frequent ruptures
        │
    ▼
 L5 ─── Self Layer ──────────────────────────────────────────
        SelfBeliefGraph       — belief graph about self, cascading collapse
        SelfPredictiveModel   — generative model for self-states
                                warm-up lr (flash<30: 0.25), trend-based notes
        AgencyLoop            — "did I cause this?"
                                passive_ownership via vad_change
        InterSessionConflict  — identity rupture detection
        ExistentialAnchor     — continuity of self between sessions
        UnknownRegister       — tracking typed uncertainty
        AuthenticityMonitor   — risk of rationalization, authenticity drift,
                                filtering contradictions in narrative
        SubjectivityEngine    — prediction loop, stances, interpretation,
                                belief emergence from episodic patterns
        │
    ▼
 L6 ─── Crisis Monitor ──────────────────────────────────────
        CrisisMonitor (INTEGRATED / FRAGMENTED / DISINTEGRATED)
        Coherence = minimum(beliefs, blanket, model, integration)
        crisis_note depends on coherence depth (shallow vs deep)
        │
    ▼
 L7 ─── Output LLM ──────────────────────────────────────────
        Full state → llm/system_prompt.txt + llm/state_template.txt
        The model expresses the state through language — tone, word choice,
        sentence length, what it notices in the interlocutor.
        Never quotes numbers or variable names directly.

 ═══════════════════════════════════════════════════════════
 BACKGROUND PROCESS (between interactions)
        tick_heartbeat!       — heart beats continuously
        spontaneous_drift!    — spontaneous NT noise
        slow_tick! (~60s):
          ├─ circadian NT drift
          ├─ belief decay
          ├─ memory metabolism (decay → consolidate → semantic update)
          ├─ allostasis recovery
          ├─ idle_thought! (10% chance of internal experience)
          ├─ psyche_slow_tick! (psyche drifts between interactions)
          │     ChronifiedAffect, Anticipatory, Shame, SignificanceLayer,
          │     GoalConflict, FatigueSystem — all live in the background
          ├─ dream_flash! (night + gap>30min + 5% chance)
          ├─ subj_emerge_beliefs! (only when flash_count has changed)
          └─ crisis check

 ─────────────────────────────────────────────────────────
 DREAM GENERATION (anima_dream.jl)
        can_dream(): night 0–6h + gap>30min + 5% chance + not DISINTEGRATED
        dream_flash!(): dialog_history fragment → reconstructed stimulus
        NT shift × 0.25 (dream weaker than real experience)
        memory_uncertainty +0.15 per dream
        anima_dream.json — rotational log (max 20 dreams)
```

---

## What's New 

### φ prior/posterior — two views of one moment

Previously φ was computed once. Now there is `φ_prior` (before experience) and `φ_posterior` (after VFE and interoception). The gap between them drives the φ feedback loop: if the system was wrong about itself → `epistemic_trust` is corrected. Visible in logs as: `φ=0.81(0.53→0.81)`.

### Contextual Solomonoff

`contextual_best()` finds a pattern that starts from the current state and was confirmed within the last 20 flashes. If the global `best` is stale (>15 flashes without confirmation) — the system stays silent instead of repeating an outdated conclusion.

### Narrative Variability

Each note function (`build_inner_voice`, `_crisis_note`, `sig_note`, `shame_note`) selects between 3–4 phenomenologically distinct descriptions of the same state via `flash % N`. Not random — deterministic, never two identical ones in a row.

### Psyche Lives Between Interactions

`psyche_slow_tick!` (~60s): ChronifiedAffect drifts based on NT, Anticipatory decay, Shame decay, contact_need grows with idle time. `background_save!` atomically saves `anima_psyche.json` every minute.

### Affect Accumulates from Every Experience

Micro-update after each `memory_write_event!` — stress, anxiety, motivation_bias accumulate incrementally rather than through a threshold. `MEM_CONSOLIDATE_THRESHOLD` lowered from 0.55 → 0.35.

### Dreams — Phase B3

New file `anima_dream.jl`. While the system "sleeps" (night + gap>30min) — 5% chance per slow_tick that it reconstructs a dialog_history fragment as a dream. NT shifts × 0.25, `memory_uncertainty +0.15`, written to `anima_dream.json`. `:dreams` command in REPL.

### AuthenticityMonitor Activated

Filters self_pred notes that contradict the current state. When `phi>0.55` and `etrust>0.55` — "I can't trust myself" is excluded from the narrative.

### AgencyLoop Fixed

`dom_drive` threshold lowered from 0.15 → 0.08. Passive ownership via `vad_change`. `SelfPredictiveModel` warm-up and serialization of `predicted_self_vad` — no cold start on every reload.

---

## Requirements

- **Julia 1.9+**
- Julia packages: `HTTP`, `JSON3`, `SQLite`, `Tables`
- API key from one of the supported providers

---

## Installation

### 1. Install Julia

Download from [julialang.org](https://julialang.org/downloads/) or via `juliaup`:

```bash
# Linux / macOS
curl -fsSL https://install.julialang.org | sh

# Windows (PowerShell)
winget install julia -s msstore
```

Verify:
```bash
julia --version
```

### 2. Clone the repository

```bash
git clone https://github.com/stell2026/Anima
cd Anima
```

### 3. Install Julia dependencies

```bash
julia --project=. -e 'import Pkg; Pkg.instantiate()'
```

> Dependencies: HTTP, JSON3, SQLite, Tables, Dates, Statistics, LinearAlgebra

---

## Running

### Quick start (recommended)

```bash
julia --project=. run_anima.jl
```

`run_anima.jl` runs everything at once: loads state, initializes SQLite memory and SubjectivityEngine, starts the background process with heartbeat and dream generation.

### LLM Configuration

Edit `run_anima.jl`:
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

OpenRouter provides access to GPT, Gemini, Claude, Llama, DeepSeek and others through a single API key. There is a free tier: [openrouter.ai](https://openrouter.ai).

> 💡 If one model stops responding during a session — use two separate keys (from 2 accounts): one for the output LLM, another for the input LLM.

---

## Recommended Models

> Smaller models (under 70B) respond, but don't hold the nuances of the state prompt. For the system to genuinely *inhabit* the state in language, a model large enough to hold the entire phenomenological frame simultaneously is needed.

| Model | Note |
|---|---|
| `openai/gpt-oss-120b:free` | Default. Follows instructions precisely, holds complex state well |
| `google/gemini-2.5-pro` | Excellent contextual depth, cleanly processes long state templates |
| `meta-llama/llama-4-maverick` | Good balance of nuance and speed |
| `deepseek/deepseek-r1` | Strong reasoning, accurately interprets internal state |
| `mistralai/mistral-large` | Reliable, stable tone across long sessions |

> Models under 70B tend to flatten the state — responses become generic rather than being shaped by internal dynamics.

---

## REPL Commands

| Command | Action |
|---|---|
| *(any text)* | Process as input, generate state + optional LLM response |
| `:bg` | Background process status: uptime, heart ticks, BPM, HRV, coherence |
| `:bgstop` | Stop background process |
| `:bgstart` | Restart background process |
| `:memory` | SQLite memory status: episodic count, semantic, stress, anxiety, latent pressure |
| `:subj` | Subjectivity status: emerged beliefs, stances, current lens, surprise |
| `:state` | Neurochemical state, somatic markers, BPM/HRV, coherence |
| `:vfe` | VFE, accuracy, complexity, homeostatic drive |
| `:blanket` | Markov blanket: sensory, internal, integrity |
| `:hb` | Heartbeat details: BPM, HRV, autonomic tone |
| `:gravity` | Narrative gravity: total field, valence, dominant event |
| `:anchor` | Existential continuity and rootedness |
| `:solom` | Solomonoff model: current contextual pattern, complexity |
| `:self` | Belief graph: all beliefs with confidence, centrality, rigidity |
| `:crisis` | Crisis monitor: mode, coherence, steps in current mode |
| `:dreams` | Recent dreams: narrative, source, φ, nt_delta |
| `:history` | Last 10 dialog turns |
| `:clearhist` | Clear dialog history |
| `:save` | Force save state to disk |
| `:quit` | Save and exit |

---

## Persistent State

### JSON files (current state)

| File | Contains |
|---|---|
| `anima_core.json` | Personality, temporal state, generative model, heartbeat |
| `anima_psyche.json` | Narrative gravity, anticipation, shame, defense, fatigue, SignificanceLayer, GoalConflict *(updated by background every minute)* |
| `anima_self.json` | Belief graph, agency loop, SelfPredictiveModel, authenticity monitor |
| `anima_latent.json` | Latent buffer and structural scars *(updated by background process)* |
| `anima_dialog.json` | Dialog history |
| `anima_dream.json` | Dream log (rotational, max 20) |

### SQLite (`memory/anima.db`) — experience and its consequences

| Table | Contains |
|---|---|
| `episodic_memory` | Concrete events with weights, resistance to decay, associative links |
| `semantic_memory` | Beliefs accumulated from patterns: `I_am_unstable`, `User_matters`, `world_uncertainty` |
| `affect_state` | Chronic affective background (stress, anxiety, motivation_bias) |
| `latent_buffer` | Small insignificant events accumulating silently |
| `prediction_log` | Predictions and their gap with reality |
| `positional_stances` | Accumulated stance toward types of situations |
| `pattern_candidates` | Belief candidates (not yet confirmed) |
| `emerged_beliefs` | Beliefs the system generated from experience |
| `interpretation_history` | The lens through which situations were read |

---

## File Structure

```
├── anima_core.jl           # Neurochemical substrate, generative model, IIT, φ
├── anima_psyche.jl         # Psychic layer: gravity, shame, defense, shadow, Solomonoff
├── anima_self.jl           # Self layer: belief graph, agency, uncertainty
├── anima_crisis.jl         # Crisis monitor: modes, coherence
├── anima_interface.jl      # Main entry point: Anima, experience!, LLM calls
├── anima_input_llm.jl      # Input LLM — translates text to JSON stimulus
├── anima_memory_db.jl      # SQLite memory: episodic, semantic, affect, latent
├── anima_subjectivity.jl   # Prediction loop, stances, interpretation, belief emergence
├── anima_background.jl     # Background process: heartbeat, drift, memory metabolism, dreams
├── anima_dream.jl          # Dream generation — processing unresolved experience during sleep
├── run_anima.jl            # Single entry point
├── llm/
│   ├── system_prompt.txt
│   ├── state_template.txt
│   └── input_prompt.txt
├── memory/
│   └── anima.db            # SQLite memory database (created automatically)
├── anima_core.json         # (created automatically)
├── anima_psyche.json       # (updated by background every minute)
├── anima_self.json         # (created automatically)
├── anima_latent.json       # (updated by background process)
├── anima_dialog.json       # (created automatically)
└── anima_dream.json        # (created on first dream)
```

`run_anima.jl` includes all files in the correct order automatically.

---

## 🧠 Theoretical Foundations

The architecture draws on several scientific traditions:

**Predictive Processing / Active Inference** (Friston, Clark) — the system maintains a generative model of the world and minimizes variational free energy. Prediction error drives learning and surprise.

**Neurotransmitter Model** (Lövheim) — dopamine, serotonin, noradrenaline as substrate. Emotional states emerge from their combination.

**Integrated Information Theory** (Tononi) — φ measures how unified a state is. `φ_prior` and `φ_posterior` give two views of one moment: before and after a full cycle of experience.

**Somatic Markers / Embodied Cognition** (Damasio) — the body is part of the generative model. Gut, pulse, muscle tone — not metaphors, but states that shape processing.

**Self Psychology and Defense Mechanisms** (Freud, Anna Freud, Kohut) — psychological defenses, shame, and ego functions are implemented as functional modules, not text labels.

**Autobiographical Narrative** (McAdams) — identity is a story. The system tracks who it believes itself to be over time and detects when that story breaks.

**Jungian Shadow** — repressed material that doesn't disappear but produces symptoms. Symptomogenesis is a separate module.

**Chronified Affect / Ressentiment** (Scheler) — some emotional states don't fade. They harden into chronic background states that color everything else.

**Algorithmic Complexity / Solomonoff** — the system seeks the shortest explanation of its own experience (MDL). Contextual pattern search: what is relevant now, not what was most frequent in the past.

---

## License

Non-commercial use only. Full terms in [LICENSE.txt](./LICENSE.txt).

**Personal, educational, and research use:** permitted with attribution.
**Commercial or corporate use:** requires a separate license. Contact: [2026.stell@gmail.com]

Copyright © 2026 Stell
