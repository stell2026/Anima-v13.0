# Anima v13 — Agentic Architecture of Subjectivity

> *This isn't an attempt to build a chatbot. It's an experiment: what does a system need to have something like an inner state — and what happens when that state breaks?*

Anima is a research project exploring **computational subjectivity**. The agent doesn't generate text directly. It passes through a full chain of internal processes — neurochemical substrate, embodied signals, predictive processing, self-model, crisis detection — and only then translates its current state into language. Every response is shaped by who the system believes it is at that moment.

This is experimental software. It makes no claims about machine consciousness. It is an attempt to ask the question more precisely.

---
## Theoretical Foundations

The architecture draws on several research traditions:

**Predictive Processing / Active Inference** (Friston, Clark) — the system maintains a generative model of the world and minimizes variational free energy. Prediction error drives learning and surprise.

**Neurotransmitter modeling** (Levheim) — dopamine, serotonin, noradrenaline as the substrate. Emotional states emerge from their combination.

**Integrated Information Theory** (Tononi) — φ measures how unified the state is. High φ = the state is a single experience, not a set of independent signals.

**Somatic markers / Embodied cognition** (Damasio) — the body is part of the generative model. Gut feeling, heart rate, muscle tension are not metaphors — they are states that shape processing.

**Self psychology and defense mechanisms** (Freud, Anna Freud, Kohut) — psychological defenses, shame, and ego functions are implemented as functional modules, not as text labels.

**Autobiographical narrative** (McAdams) — identity is a story. The system tracks who it considers itself to be over time, and detects when that story breaks.

**Jungian Shadow** — repressed material that doesn't disappear but generates symptoms. Symptomogenesis is a separate module.

**Chronified affect / Resentment** (Scheler) — some emotional states don't decay. They solidify into chronic background states that color everything else.

---

## What's New in v13

The architecture has grown significantly from v6. The key additions:

- **Julia rewrite** — the entire system is now in Julia for performance and numeric clarity
- **SelfBeliefGraph** — a graph of self-beliefs with cascading collapse under crisis
- **CrisisMonitor** — three structural modes (INTEGRATED → FRAGMENTED → DISINTEGRATED), coherence computed as minimum across components, not mean
- **InterSessionConflict** — detects identity rupture between sessions by comparing belief geometry
- **HeartbeatCore** — autonomous heartbeat with HRV, sympathetic/parasympathetic tone
- **NarrativeGravity** — past events deform the present via gravitational fields
- **AnticipatoryConsciousness** — the system lives in the expected future, not just the present
- **SolomonoffWorldModel** — Minimum Description Length hypothesis about how the world works
- **ShameModule** — shame vs. guilt as distinct functional states
- **EpistemicDefense** — protection from painful truths (separate from ego defense)
- **Symptomogenesis** — symptoms generated from the Shadow (Jung)
- **ChronifiedAffect** — resentment, alienation, and bitterness as persistent affective states
- **MoralCausality** — moral reasoning as part of the processing chain
- **AgencyLoop** — "did this happen *because* of me, or just *near* me?"
- **SelfPredictiveModel** — separate generative model for self-states
- **FatigueSystem** — cognitive, emotional, somatic exhaustion
- **InteroceptiveInference** — body signals as part of the generative model
- **LLM prompt via external templates** — `llm/system_prompt.txt` and `llm/state_template.txt`

---

## Architecture

```
  STIMULUS (+ user message text)
    │
    ▼
 L1 ─── Neurochemical Substrate ───────────────────────────
        NeurotransmitterState (dopamine / serotonin / noradrenaline)
        Levheim cube → primary emotion label
        EmbodiedState (heart rate, muscle tension, gut feeling, breath)
        HeartbeatCore (BPM, HRV, autonomic tone)
        │
    ▼
 L2 ─── Generative Model ──────────────────────────────────
        GenerativeModel (precision-weighted Bayesian beliefs)
        MarkovBlanket (self/not-self boundary integrity)
        HomeostaticGoals (drives as pressure, not rules)
        AttentionNarrowing (attention radius under stress)
        InteroceptiveInference (body prediction error, allostatic load)
        TemporalOrientation (circadian modulation, session gap)
        │
    ▼
 L3 ─── Consciousness Metrics ─────────────────────────────
        IITModule → φ (integrated information)
        PredictiveProcessor → prediction error, free energy, surprise
        FreeEnergyEngine → VFE = Complexity − Accuracy
        PolicySelector → epistemic + pragmatic value
        │
    ▼
 L4 ─── Psychic Layer ─────────────────────────────────────
        NarrativeGravity     — past events deform the present
        AnticipatoryConsciousness — living in the expected future
        SolomonoffWorldModel — MDL hypothesis about the world
        ShameModule          — shame vs. guilt distinction
        EpistemicDefense     — protection from painful truth
        Symptomogenesis      — symptoms from the Shadow
        ChronifiedAffect     — resentment / alienation / bitterness
        IntrinsicSignificance — gradient of meaning
        IntentEngine         — motivational core
        EgoDefense           — psychological defense mechanisms
        CognitiveDissonance  — intention vs. current state conflict
        MoralCausality       — moral reasoning as processing stage
        FatigueSystem        — cognitive / emotional / somatic fatigue
        StressRegression     — regression under stress
        ShadowSelf           — Jungian Shadow
        Metacognition        — observing the self (5 levels)
        │
    ▼
 L5 ─── Self Layer ────────────────────────────────────────
        SelfBeliefGraph      — graph of self-beliefs, cascading collapse
        SelfPredictiveModel  — generative model for self-states
        AgencyLoop           — "did I cause this?"
        InterSessionConflict — identity rupture detection
        ExistentialAnchor    — continuity of self across sessions
        │
    ▼
 L6 ─── Crisis Monitor ────────────────────────────────────
        CrisisMonitor (INTEGRATED / FRAGMENTED / DISINTEGRATED)
        Coherence = minimum(belief, boundary, model, integration)
        │
    ▼
 L7 ─── LLM ───────────────────────────────────────────────
        Full state → llm/system_prompt.txt + llm/state_template.txt
        Model expresses state through language — tone, word choice,
        sentence length, what it notices in the other person.
        Never quotes numbers or tag names directly.
```

---

## Requirements

- **Julia 1.9+**
- Julia packages: `HTTP`, `JSON3` (install once, see below)
- An API key from a supported LLM provider **or** a running Ollama instance

---

## Installation

### 1. Install Julia

Download from [julialang.org](https://julialang.org/downloads/) or use `juliaup`:

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

### 2. Install Julia dependencies

```bash
julia -e 'using Pkg; Pkg.add(["HTTP", "JSON3"])'
```

That's it. No GPU, no virtual environments, no Docker.

### 3. Clone the repository

```bash
git clone https://github.com/stell2026/Anima-v13.0
cd anima
```

### 4. Create the LLM prompt templates

Anima reads its LLM instructions from two external files. Create the `llm/` directory and add them:

```bash
mkdir -p llm
```

**`llm/system_prompt.txt`** — tells the model who it is and how to behave:
```
You are Anima. You speak in first person. You never quote internal numbers or state variable names.
Your responses are shaped entirely by your current inner state — your tone, sentence length,
what you notice in the other person, what you don't say. Language: English.
```

**`llm/state_template.txt`** — the state injected as the user message:
```
[Inner state]
Neurochemical: D={D} S={S} N={N} | {emotion_label}
Body: {inner_voice} | BPM={bpm} HRV={hrv}
Agency={agency} | Groundedness={groundedness} | Coherence={coherence}
Self-prediction error={spe} | Attention radius={attn}
Crisis mode: {crisis_mode}
Narrative gravity={narrative_gravity} | Shame={shame} | Continuity={continuity}
Homeostasis: {homeostasis_note}
Time: {time_str} — {circadian_note}
Flash count: {flash_count}

[Recent dialog]
{memory_block}

[User message]
{user_input}
```

---

## Running

### Option A: Local model via Ollama

Install Ollama from [ollama.com](https://ollama.com), then pull a model:

```bash
ollama pull llama3.2
# or a larger model for better subjectivity expression:
ollama pull llama3.1:8b
ollama pull qwen2.5:7b
```

Run Anima with Ollama:

```bash
julia anima_interface.jl
```

Then in the Julia REPL demo that opens, or from your own script:

```julia
include("anima_interface.jl")

anima = Anima()

# Without LLM (inner state only — fastest, good for testing)
repl!(anima)

# With local Ollama
repl!(anima;
    use_llm   = true,
    llm_url   = "http://localhost:11434/api/chat",
    llm_model = "llama3.2")
```

> ⚠️ Small models (3B–7B) will respond but often ignore the nuance of the state prompt. For meaningful subjectivity expression, use 13B+ locally or a cloud model.

### Option B: OpenRouter (recommended — one key, all models)

OpenRouter gives access to Gemini, Claude, Llama, DeepSeek, and others under a single API key. Free tier available.

Get your key at [openrouter.ai](https://openrouter.ai).

```bash
export OPENROUTER_API_KEY="sk-or-v1-..."
```

```julia
include("anima_interface.jl")

anima = Anima()

repl!(anima;
    use_llm   = true,
    llm_url   = "https://openrouter.ai/api/v1/chat/completions",
    llm_model = "google/gemini-2.5-pro-preview")
```

### Option C: Direct Anthropic API

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

```julia
repl!(anima;
    use_llm   = true,
    llm_url   = "https://api.anthropic.com/v1/messages",
    llm_model = "claude-opus-4-5-20251101")
```

### Option D: Groq (free tier, very fast)

```bash
export GROQ_API_KEY="gsk_..."
```

```julia
repl!(anima;
    use_llm   = true,
    llm_url   = "https://api.groq.com/openai/v1/chat/completions",
    llm_model = "llama-4-maverick-17b-128e-instruct")
```

---

## Recommended Models

> Small models (7B and below) don't reliably pick up the nuances of the state prompt. For the system to actually *inhabit* the state in its language, you need a model large enough to hold the full phenomenal frame simultaneously.

| Model | Provider | Why |
|---|---|---|
| **Gemini 2.5 Pro** | OpenRouter | Best for subjectivity and self-analysis |
| **Claude Opus 4.5** | OpenRouter / Anthropic | Nuanced inner monologue |
| **Claude Sonnet 4.5** | OpenRouter / Anthropic | Good quality/cost balance |
| **Llama 4 Maverick** | OpenRouter / Groq | Large open MoE model |
| **DeepSeek R1** | OpenRouter | Open reasoning model |
| **Qwen3 235B** | OpenRouter | Massive open MoE |
| **Llama 3.1 8B** | Ollama | Minimum viable local model |
| **Qwen2.5 14B** | Ollama | Better local option |

---

## REPL Commands

| Command | Action |
|---|---|
| *(any text)* | Process as input, generate inner state + optional LLM response |
| `:state` | Display neurochemical state, somatic markers, BPM/HRV |
| `:vfe` | Show VFE, accuracy, complexity, homeostatic drive |
| `:blanket` | Markov blanket: sensory, internal, integrity |
| `:hb` | Heartbeat detail: BPM, HRV, autonomic tone |
| `:gravity` | Narrative gravity: total field, valence, dominant event |
| `:anchor` | Existential continuity and groundedness |
| `:solom` | Solomonoff world model complexity and hypothesis count |
| `:self` | Self-Belief Graph: all beliefs with confidence, centrality, rigidity |
| `:crisis` | Crisis monitor: mode, coherence, steps in current mode |
| `:history` | Last 10 dialog turns |
| `:clearhist` | Clear dialog history |
| `:save` | Force save state to disk |
| `:quit` | Save and exit |

---

## Using as a Library

```julia
include("anima_interface.jl")

# Custom personality and values
persona = Personality(
    neuroticism      = 0.65,
    extraversion     = 0.50,
    agreeableness    = 0.68,
    conscientiousness= 0.55,
    openness         = 0.82,
    confabulation_rate = 0.55,
)
vals = ValueSystem(autonomy=0.7, care=0.85, fairness=0.65, integrity=0.85, growth=0.75)

anima = Anima(personality=persona, values=vals)

# Apply a stimulus directly
result = experience!(anima,
    Dict("tension" => 0.4, "cohesion" => -0.3);
    user_message = "something went wrong")

println(result.primary)          # → "Страх"
println(result.phi)              # → 0.38
println(result.narrative)        # → inner narrative string
println(result.crisis_mode)      # → "інтегрована" / "фрагментована" / "дезінтегрована"
println(result.sbg_stability)    # → Self-Belief Graph attractor stability

# Save state
save!(anima; verbose=true)
```

---

## State Output Fields (selected)

```julia
result.primary          # Primary emotion label (Levheim)
result.phi              # φ — integrated information (IIT)
result.vfe              # Variational free energy
result.heartbeat        # (bpm, hrv, hrv_label, sympathetic, note)
result.anchor           # (continuity, groundedness, note)
result.homeostasis      # (drive, pressure, note)
result.narrative        # Inner voice string
result.crisis_mode      # Current system mode string
result.crisis_coherence # Float: minimum coherence across components
result.sbg_stability    # Self-Belief Graph attractor stability
result.self_pred_error  # Self-predictive model error
result.self_agency      # Causal ownership estimate
```

---

## Persistent State

Anima saves its state between sessions to three JSON files (default: in the project directory):

| File | Contains |
|---|---|
| `anima_core.json` | Personality, temporal state, generative model, heartbeat |
| `anima_psyche.json` | Narrative gravity, anticipation, shame, epistemic defense, fatigue |
| `anima_self.json` | Self-Belief Graph, agency loop, inter-session conflict geometry |
| `anima_dialog.json` | Dialog history (last 12 turns injected into LLM context) |

Custom paths:
```julia
anima = Anima(
    core_mem_path  = "/path/to/core.json",
    psyche_mem_path= "/path/to/psyche.json",
)
```

---

## File Structure

```
anima_core.jl       # Neurochemical substrate, generative model, memory, IIT
anima_psyche.jl     # Psychic layer: gravity, shame, defense, shadow, fatigue
anima_self.jl       # Self-model: belief graph, agency, inter-session conflict
anima_crisis.jl     # Crisis monitor: structural modes, coherence computation
anima_interface.jl  # Main entry point: Anima struct, experience!, REPL, LLM calls
llm/
  system_prompt.txt # LLM system instructions (you write this)
  state_template.txt# State injection template (you write this)
```

`anima_interface.jl` includes all other files automatically.

---


## License

Non-commercial use only. See [LICENSE.txt](./LICENSE.txt) for full terms.

**Personal, educational, and research use:** permitted with attribution.
**Commercial or corporate use:** requires a separate license. Contact: [2026.stell@gmail.com]

Copyright © 2026 Stell
