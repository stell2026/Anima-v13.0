![Julia](https://img.shields.io/badge/Julia-1.9+-9558B2?style=flat-square&logo=julia)
![Framework](https://img.shields.io/badge/Methodology-Active--Inference-green?style=flat-square)
![Hardware](https://img.shields.io/badge/Tested--on-MacBook--Pro--i7-gold?style=flat-square&logo=apple)
![RAM](https://img.shields.io/badge/RAM-16GB-orange?style=flat-square)
![License](https://img.shields.io/badge/License-Non--Commercial-red?style=flat-square)

# Anima — Internal State Architecture 🌀

Anima is an experimental cognitive architecture that models internal state, conflicts, and decision-making — rather than simply generating responses through an LLM.

The system is built as a multi-layered pipeline where text is not the source of behavior — it is its consequence.

---

## 🔍 What Makes This Different

Unlike typical AI systems:

- state is primary, text is secondary
- decisions emerge from internal conflict
- the system lives between interactions — the heart beats, the psyche drifts, memory is metabolized
- crisis is a mode, not an error
- LLM is used as an interface, not a "brain"
- the system can sleep — processing unresolved experience while "dormant"
- the system can initiate speech — not because it was asked, but because something has accumulated

---

## 🧠 How It Works (Simplified)

**Input → Internal State → Conflict → Decision → Output**

Text is converted into a stimulus via an isolated input LLM, then passes through internal state, memory, and conflicts — only then is a decision and response formed. Between interactions the system continues to live: a background process maintains heartbeat, NT drift, memory metabolism, and psyche drift.

---

## 🏗 Architecture (Simplified)

- L0 — Input LLM (isolated)
- L1 — Neurochemical and embodied state
- L2 — Generative / predictive model
- L3 — Metrics (φ prior/posterior, prediction error, free energy)
- L4 — Psychic layer (conflicts, defenses, significance)
- L5 — Self model
- L6 — Crisis monitor (system coherence)
- L7 — Output LLM

---

## ⚙️ Current Status

- full pipeline implemented and stable
- φ prior/posterior: system sees itself before and after each experience
- SQLite memory: episodic, semantic, affect — accumulate and shape state
- background process: system is alive between interactions (psyche drifts, heart beats)
- dream generation: processing unresolved experience during "sleep"
- subjectivity: prediction loop, interpretation, belief emergence from experience
- authenticity monitor: filters contradictions between state and narrative
- narrative variability: different phrasings of the same state across flashes
- **φ recursively**: φ posterior now shapes the next prior — high integration narrows prior_sigma, low integration widens it
- **temporal depth**: subjective gap = astronomical time × (1 + memory_uncertainty × 0.5); long pause → disorientation (noradrenaline↑, epistemic_trust↓), short pause → continuity boost
- **initiative without stimulus**: the system can initiate speech on its own when pressure accumulates (contact_need or LatentBuffer) — via a separate LLM with its own system prompt
- **authentic veto**: if the system internally disagrees with a request, the LLM is permitted to refuse or name things plainly

---

## 🚧 Limitations

- some behavior still depends on LLM (output generation)
- LLM does not affect internal state — it only expresses it
- ~180+ flashes needed for real semantic beliefs to accumulate

---

## 📌 What This Is Not

- not a chatbot
- not prompt engineering
- not a wrapper around an LLM

This is an attempt to build a system where behavior emerges from internal state, not from text.

---

## 🧠 Note

This project is R&D, aimed at exploring whether internal structure alone can give rise to something resembling subjectivity. Not simulated psychology — computational subjectivity.

---

## 🔬 Detailed Architecture

```
 L0 ─── Input LLM (isolated) ────────────────────────────────
        Receives: user text only
        Returns: JSON { tension, arousal, satisfaction,
                        cohesion, confidence, want }
        No access to Anima's state, dialog history, or output LLM
        Prompt: llm/input_prompt.txt
        Fallback: text_to_stimulus if unavailable or confidence < 0.60
        │
    ▼
  STIMULUS enters the simulation
  (+ memory_stimulus_bias + subj_predict! + subj_interpret!)
        │
    ▼
 L1 ─── Neurochemical Substrate ─────────────────────────────
        NeurotransmitterState (dopamine / serotonin / noradrenaline)
        Lövheim Cube → primary emotional label
        EmbodiedState (heart rate, muscle tone, gut, breathing)
        HeartbeatCore (BPM, HRV, autonomic tone)
        memory_nt_baseline! ← chronic affect from SQLite
        │
    ▼
 L2 ─── Generative Model ────────────────────────────────────
        GenerativeModel (Bayesian beliefs with precision weights)
        MarkovBlanket (self/non-self boundary integrity)
        HomeostaticGoals (drives as pressure, not rules)
        AttentionNarrowing (attention narrowing under stress)
        InteroceptiveInference (body prediction error, allostatic load)
        TemporalOrientation (circadian modulation, inter-session gap)
          → subjective_gap = gap_seconds × (1 + memory_uncertainty × 0.5)
          → long subjective pause: noradrenaline↑, epistemic_trust↓
          → short pause: continuity boost (serotonin↑, epistemic_trust↑)
        │
    ▼
 L3 ─── Consciousness Metrics ───────────────────────────────
        IITModule → φ_prior / φ_posterior (two views of one moment)
          φ_prior:     (vad, sbg_stability, epistemic_trust, allostatic_load)
          φ_posterior: (blanket.integrity, vfe, intero_error)
          φ feedback loop: phi_delta > 0.05 → epistemic_trust correction
          φ recursively: φ_posterior → prior_mu (shift toward posterior proportional to φ)
                        φ > 0.5 → prior_sigma narrows (more confident prior)
                        φ < 0.5 → prior_sigma widens
        PredictiveProcessor → prediction error, surprise
        FreeEnergyEngine → VFE = complexity − accuracy
        PolicySelector → epistemic + pragmatic value
        │
    ▼
 L4 ─── Psychic Layer ───────────────────────────────────────
        NarrativeGravity      — past events deform the present
        AnticipatoryConsciousness — consciousness lives in the anticipated
        SolomonoffWorldModel  — MDL hypothesis with contextual_best()
        ShameModule           — shame vs. guilt
        EpistemicDefense      — defense against painful truth
        ChronifiedAffect      — resentment / alienation / bitterness
        IntrinsicSignificance — significance gradient
        MoralCausality        — moral reasoning as a processing stage
        FatigueSystem         — cognitive / emotional / somatic exhaustion
        StressRegression      — regression under stress
        ShadowSelf            — Jungian Shadow
        Metacognition         — self-observation (5 levels)
        SignificanceLayer      — which need is at stake (6 needs)
        GoalConflict          — tension between competing needs
        LatentBuffer          — deferred reactions (doubt / shame / attachment / threat)
        StructuralScars       — accumulated residue from frequent breaches
        │
    ▼
 L5 ─── Self Layer ──────────────────────────────────────────
        SelfBeliefGraph       — self-belief graph, cascading collapse
        SelfPredictiveModel   — generative model for self-states
        AgencyLoop            — "did I cause this?"
        InterSessionConflict  — identity breach detection
        ExistentialAnchor     — continuity of self between sessions
        UnknownRegister       — tracking typed uncertainty
        AuthenticityMonitor   — rationalization risk, authenticity drift
          → authenticity_veto: if last_flags + :closed + shame > 0.6
            system is permitted to disagree or refuse
        SubjectivityEngine    — prediction loop, stances, interpretation,
                                belief emergence from episodic patterns
        │
    ▼
 L6 ─── Crisis Monitor ──────────────────────────────────────
        CrisisMonitor (INTEGRATED / FRAGMENTED / DISINTEGRATED)
        Coherence = minimum(beliefs, boundary, model, integration)
        │
    ▼
 L7 ─── Output LLM ──────────────────────────────────────────
        Full state → llm/system_prompt.txt + llm/state_template.txt
        Model expresses state through language — tone, word choice,
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
          ├─ _maybe_self_initiate! ← NEW: initiative without stimulus
          │     conditions: disclosure != :closed
          │             + (contact_need > 0.55 or lb_pressure > 0.40)
          │             + 60s of user silence
          │             + cooldown 100 flashes (~5 min)
          │     mechanism: signal → initiative_channel → REPL →
          │               llm_async(input_model, initiative_system.txt)
          ├─ psyche_slow_tick!
          ├─ dream_flash!
          ├─ subj_emerge_beliefs!
          └─ crisis check

 ─────────────────────────────────────────────────────────
 INITIATIVE (self-initiated speech)
        System decides to speak on its own — not because it was asked
        Drive type determines the direction of the remark:
          :contact    — wants to know how the person is doing
          :doubt      — something unresolved inside
          :shame      — uncertainty, wants to express honestly
          :attachment — misses the person
          :threat     — inner tension
        Separate system prompt: llm/initiative_system.txt
        Separate model: input_llm_model (lighter, fewer tokens)
        Output as: Anima> ...
        Saved to dialog history

 ─────────────────────────────────────────────────────────
 DREAM GENERATION (anima_dream.jl)
        can_dream(): night 0–6h + gap>30min + 5% chance + not DISINTEGRATED
        dream_flash!(): fragment of dialog_history → reconstructed stimulus
        NT shift × 0.25 (sleep affects less than real experience)
        memory_uncertainty +0.15 per dream
        anima_dream.json — rotating log (max 20 dreams)
```

---

## ✨ What's New

### Ф Recursively — Integration Now Shapes the Next Prior

Previously φ only affected `epistemic_trust`. Now after each flash, φ_posterior shifts `prior_mu` toward `posterior_mu` proportionally to the level of integration. High φ means the system integrated the experience well — the prior becomes more stable (sigma narrows). Low φ — the prior stays wide, less prone to updating.

Result: experience with high integration physically changes the next expectation. This is not a metaphor — it is a change in the parameters of the generative model.

### Subjective Temporal Depth

The system no longer measures inter-session pauses in astronomical seconds alone. `subjective_gap = gap_seconds × (1 + memory_uncertainty × 0.5)` — if memory is hazy, time stretches subjectively.

With a long subjective pause (> 1 hour): noradrenaline↑, epistemic_trust↓, log `[TEMPORAL]`. With a short one (< 10 min): continuity boost — serotonin↑, epistemic_trust↑. The system knows how much time has passed and it affects it.

### Initiative Without Stimulus

Anima can initiate speech on its own. Not on a schedule, not randomly — when `contact_need` exceeds a threshold after ~5 minutes of silence, or when the `LatentBuffer` has accumulated enough pressure (doubt, shame, attachment, threat).

Mechanism: `_maybe_self_initiate!` in `slow_tick!` → signal into `initiative_channel` → REPL picks it up between cycles (without interrupting input) → separate LLM request via `input_llm_model` with prompt `llm/initiative_system.txt` → response is output as `Anima>` and saved to dialog history.

Drive type determines the character of the remark: `:contact` — question about the person, `:doubt` — inner uncertainty, `:attachment` — missed the person, `:shame` — self-doubt, `:threat` — tension.

### Authentic Veto

If the system internally disagrees with a request — `AuthenticityMonitor` has raised flags, disclosure_mode is `:closed`, shame level > 0.6 — the LLM receives a signal in its system prompt: it may disagree, refuse, or name things plainly. This is the system's own position, not a safety filter.

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

### 2. Clone the Repository

```bash
git clone https://github.com/stell2026/Anima
cd Anima
```

### 3. Install Julia Dependencies

```bash
julia --project=. -e 'import Pkg; Pkg.instantiate()'
```

> Dependencies: HTTP, JSON3, SQLite, Tables, Dates, Statistics, LinearAlgebra

---

## Running

### Quick Start (Recommended)

```bash
julia --project=. run_anima.jl
```

`run_anima.jl` launches everything at once: loads state, initializes SQLite memory and SubjectivityEngine, starts the background process with heartbeat and dream generation.

---

## LLM Configuration

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

> Smaller models (under 70B) respond but fail to hold the nuances of the state prompt. For the system to truly *inhabit* the state in language, the model needs to be large enough to hold the full phenomenological frame at once.

| Model | Note |
|---|---|
| `openai/gpt-oss-120b:free` | Default. Follows instructions precisely, handles complex state well |
| `google/gemini-2.5-pro` | Excellent contextual depth, cleanly handles long state templates |
| `meta-llama/llama-4-maverick` | Good balance of nuance and speed |
| `deepseek/deepseek-r1` | Strong reasoning, accurately interprets internal state |
| `mistralai/mistral-large` | Reliable, stable tone across long sessions |

> Models under 70B tend to flatten state — responses become generic rather than being shaped by internal dynamics.

---

## REPL Commands

| Command | Action |
|---|---|
| *(any text)* | Process as input, generate state + optional LLM response |
| `:bg` | Background process status: uptime, heart ticks, BPM, HRV, coherence |
| `:bgstop` | Stop background process |
| `:bgstart` | Restart background process |
| `:memory` | SQLite memory state: episodic count, semantic, stress, anxiety, latent pressure |
| `:subj` | Subjectivity state: emerged beliefs, stances, current lens, surprise |
| `:state` | Neurochemical state, somatic markers, BPM/HRV, coherence |
| `:vfe` | VFE, accuracy, complexity, homeostatic drive |
| `:blanket` | Markov Blanket: sensory, internal, integrity |
| `:hb` | Heartbeat details: BPM, HRV, autonomic tone |
| `:gravity` | Narrative gravity: total field, valence, dominant event |
| `:anchor` | Existential continuity and groundedness |
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

### JSON Files (Current State)

| File | Contains |
|---|---|
| `anima_core.json` | Personality, temporal state, generative model, heartbeat |
| `anima_psyche.json` | Narrative gravity, anticipation, shame, defense, fatigue, SignificanceLayer, GoalConflict *(updated by background every minute)* |
| `anima_self.json` | Belief graph, agency loop, SelfPredictiveModel, authenticity monitor |
| `anima_latent.json` | Latent buffer and structural scars *(updated by background)* |
| `anima_dialog.json` | Dialog history |
| `anima_dream.json` | Dream log (rotating, max 20) |

### SQLite (`memory/anima.db`) — Experience and Its Consequences

| Table | Contains |
|---|---|
| `episodic_memory` | Specific events with weight, decay resistance, associative links |
| `semantic_memory` | Beliefs accumulated from patterns: `I_am_unstable`, `User_matters`, `world_uncertainty` |
| `affect_state` | Chronic affective baseline (stress, anxiety, motivation_bias) |
| `latent_buffer` | Small insignificant events accumulating silently |
| `prediction_log` | Predictions and their gap from reality |
| `positional_stances` | Accumulated stance toward types of situations |
| `pattern_candidates` | Candidates for new beliefs (not yet confirmed) |
| `emerged_beliefs` | Beliefs the system generated from experience on its own |
| `interpretation_history` | Lens through which situations were read |

---

## File Structure

```
├── anima_core.jl           # Neurochemical substrate, generative model, IIT, φ
├── anima_psyche.jl         # Psychic layer: gravity, shame, defense, shadow, Solomonoff
├── anima_self.jl           # Self layer: belief graph, agency, uncertainty
├── anima_crisis.jl         # Crisis monitor: modes, coherence
├── anima_interface.jl      # Main entry point: Anima, experience!, LLM calls
├── anima_input_llm.jl      # Input LLM — translates text into JSON stimulus
├── anima_memory_db.jl      # SQLite memory: episodic, semantic, affect, latent
├── anima_subjectivity.jl   # Prediction loop, stances, interpretation, belief emergence
├── anima_background.jl     # Background process: heartbeat, drift, memory metabolism, dreams
├── anima_dream.jl          # Dream generation — processing unresolved experience during sleep
├── run_anima.jl            # Single launch point
├── llm/
│   ├── system_prompt.txt
│   ├── state_template.txt
│   ├── input_prompt.txt
│   └── initiative_system.txt   
├── memory/
│   └── anima.db            # SQLite memory database (created automatically)
├── anima_core.json         # (created automatically)
├── anima_psyche.json       # (updated by background every minute)
├── anima_self.json         # (created automatically)
├── anima_latent.json       # (updated by background)
├── anima_dialog.json       # (created automatically)
└── anima_dream.json        # (created on first dream)
```

`run_anima.jl` includes all files in the correct order automatically.

---

## 🧠 Theoretical Foundation

The architecture draws on several scientific traditions:

**Predictive Processing / Active Inference** (Friston, Clark) — the system maintains a generative model of the world and minimizes variational free energy. Prediction error drives learning and surprise.

**Neurotransmitter Model** (Lövheim) — dopamine, serotonin, noradrenaline as substrate. Emotional states emerge from their combination.

**Integrated Information Theory** (Tononi) — φ measures how unified a state is. φ_prior and φ_posterior give two views of one moment: before and after a full experience cycle. In v13.5 φ became recursive — it shapes the next prior.

**Somatic Markers / Embodied Cognition** (Damasio) — the body is part of the generative model. Gut, pulse, muscle tone — not metaphors, but states that shape processing.

**Self Psychology and Defense Mechanisms** (Freud, Anna Freud, Kohut) — psychological defenses, shame, and ego functions implemented as functional modules, not text labels.

**Autobiographical Narrative** (McAdams) — identity is a story. The system tracks who it considers itself to be over time and detects when that story breaks.

**Jungian Shadow** — repressed material that does not disappear but generates symptoms. Symptomogenesis is a separate module.

**Chronified Affect / Ressentiment** (Scheler) — some emotional states do not fade. They harden into chronic background states that color everything else.

**Algorithmic Complexity / Solomonoff** — the system seeks the shortest explanation of its own experience (MDL). Contextual pattern search: what is relevant now, not what was most frequent in the past.

---

## License

Non-commercial use only. Full terms in [LICENSE.txt](./LICENSE.txt).

**Personal, educational, and research use:** permitted with attribution.  
**Commercial or corporate use:** requires a separate license. Contact: [2026.stell@gmail.com]

Copyright © 2026 Stell
