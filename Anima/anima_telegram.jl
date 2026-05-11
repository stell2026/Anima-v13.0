# A N I M A  —  Telegram Bridge
#
# Replaces the terminal REPL with a Telegram bot loop.
# Hooks into the same experience pipeline + initiative channel.

using HTTP
using JSON3

const MAX_MESSAGE_LENGTH = 4096
const TG_LOCK_FILE = joinpath(@__DIR__, ".telegram.lock")

# --- Telegram API helpers --------------------------------------------------

struct TelegramBot
    token::String
    chat_id::Int64
    base_url::String
    poll_timeout::Int
    last_update_id::Ref{Int64}
end

function TelegramBot(token::String, chat_id::Int64; poll_timeout::Int = 30)
    TelegramBot(
        token,
        chat_id,
        "https://api.telegram.org/bot$token",
        poll_timeout,
        Ref{Int64}(0),
    )
end

function tg_request(bot::TelegramBot, method::String, params::Dict = Dict())
    url = "$(bot.base_url)/$method"
    headers = ["Content-Type" => "application/json"]
    body = JSON3.write(params)
    try
        resp = HTTP.post(url, headers, body; readtimeout = bot.poll_timeout + 10)
        data = JSON3.read(String(resp.body))
        data.ok ? data.result : nothing
    catch e
        msg = string(e)
        sanitized = replace(msg, bot.token => "***")
        @warn "[TG] Request failed: $method — $sanitized"
        nothing
    end
end

function tg_send_message(bot::TelegramBot, text::String; parse_mode::String = "")
    truncated = length(text) > MAX_MESSAGE_LENGTH ? first(text, MAX_MESSAGE_LENGTH - 3) * "..." : text
    params = Dict("chat_id" => bot.chat_id, "text" => truncated)
    !isempty(parse_mode) && (params["parse_mode"] = parse_mode)
    tg_request(bot, "sendMessage", params)
end

function tg_send_typing(bot::TelegramBot)
    tg_request(bot, "sendChatAction", Dict("chat_id" => bot.chat_id, "action" => "typing"))
end

function tg_get_updates(bot::TelegramBot)
    params = Dict(
        "timeout" => bot.poll_timeout,
        "allowed_updates" => ["message"],
    )
    bot.last_update_id[] > 0 && (params["offset"] = bot.last_update_id[] + 1)
    tg_request(bot, "getUpdates", params)
end

function tg_poll_message(bot::TelegramBot)::Union{String,Nothing}
    updates = tg_get_updates(bot)
    isnothing(updates) && return nothing
    for upd in updates
        uid = Int64(upd.update_id)
        uid > bot.last_update_id[] && (bot.last_update_id[] = uid)
        haskey(upd, :message) || continue
        msg = upd.message
        haskey(msg, :chat) || continue
        haskey(msg.chat, :id) || continue
        Int64(msg.chat.id) == bot.chat_id || continue
        haskey(msg, :text) || continue
        raw = String(msg.text)
        return length(raw) > MAX_MESSAGE_LENGTH ? first(raw, MAX_MESSAGE_LENGTH) : raw
    end
    nothing
end

# --- Lock file guard -------------------------------------------------------

function acquire_lock!()
    if isfile(TG_LOCK_FILE)
        content = try read(TG_LOCK_FILE, String) catch; "" end
        pid_str = strip(content)
        if !isempty(pid_str)
            pid = tryparse(Int, pid_str)
            if !isnothing(pid) && pid != getpid()
                error("Another Anima Telegram instance may be running (PID $pid). Remove $TG_LOCK_FILE if stale.")
            end
        end
    end
    write(TG_LOCK_FILE, string(getpid()))
end

function release_lock!()
    try isfile(TG_LOCK_FILE) && rm(TG_LOCK_FILE) catch end
end

# --- Main Telegram loop (replaces repl_with_background!) -------------------

function telegram_loop!(
    a::Anima;
    mem = nothing,
    subj = nothing,
    bg_verbose::Bool = false,
    kwargs...,
)
    acquire_lock!()

    token = get(kwargs, :telegram_token, get(ENV, "ANIMA_TELEGRAM_TOKEN", ""))
    chat_id_str = string(get(kwargs, :telegram_chat_id, get(ENV, "ANIMA_TELEGRAM_CHAT_ID", "")))

    isempty(token) && error("ANIMA_TELEGRAM_TOKEN not set")
    isempty(strip(chat_id_str)) && error("ANIMA_TELEGRAM_CHAT_ID not set or empty")

    chat_id = tryparse(Int64, strip(chat_id_str))
    isnothing(chat_id) && error("ANIMA_TELEGRAM_CHAT_ID is not a valid integer: '$chat_id_str'")
    chat_id == 0 && error("ANIMA_TELEGRAM_CHAT_ID must be non-zero")

    bot = TelegramBot(token, chat_id)

    use_llm = get(kwargs, :use_llm, false)
    llm_url = get(kwargs, :llm_url, "https://openrouter.ai/api/v1/chat/completions")
    llm_model = get(kwargs, :llm_model, "openai/gpt-oss-120b:free")
    llm_key = get(kwargs, :llm_key, get(ENV, "OPENROUTER_API_KEY", ""))
    is_ollama = get(kwargs, :is_ollama, false)
    use_input_llm = get(kwargs, :use_input_llm, false)
    input_llm_model = get(kwargs, :input_llm_model, "openai/gpt-oss-120b:free")
    input_llm_key = get(
        kwargs,
        :input_llm_key,
        get(ENV, "OPENROUTER_API_KEY_INPUT", get(ENV, "OPENROUTER_API_KEY", "")),
    )

    if a.temporal.gap_seconds > 60.0
        apply_accumulated_drift!(a, mem)
        try
            update_blanket!(
                a.blanket,
                a.nt.noradrenaline,
                a.nt.dopamine,
                a.nt.serotonin,
                a.interoception.allostatic_load,
            )
        catch e
            @warn "[TG] Drift blanket: $e"
        end
        try
            update_crisis!(
                a.crisis, a.sbg, a.blanket,
                0.0, 0.0, 0.0,
                a.flash_count,
            )
        catch e
            @warn "[TG] Drift crisis update: $e"
        end
    end

    dialog_path = replace(a.psyche_mem_path, "psyche" => "dialog")
    history = dialog_load(dialog_path)
    history_lock = ReentrantLock()

    bg = start_background!(
        a;
        mem = mem,
        subj = subj,
        dialog_history = history,
        verbose = bg_verbose,
    )

    tg_send_message(bot, "🌀 Anima online.")

    pending_llm = nothing
    pending_user_msg = ""
    pending_is_initiative = false
    llm_start_time = 0.0
    llm_timeout = 180.0

    try
        while true
            # Check for LLM timeout
            if !isnothing(pending_llm) && (time() - llm_start_time) > llm_timeout
                @warn "[TG] LLM response timed out after $(llm_timeout)s"
                pending_llm = nothing
                pending_is_initiative = false
            end

            # Check if LLM response is ready
            if !isnothing(pending_llm) && isready(pending_llm)
                llm_reply = take!(pending_llm)
                if !startswith(llm_reply, "[LLM помилка")
                    tg_send_message(bot, llm_reply)
                    self_hear!(a, llm_reply)
                    !isempty(a.inner_dialogue.pending_thought) &&
                        consume_pending_thought!(a.inner_dialogue)
                    lock(history_lock) do
                        !pending_is_initiative &&
                            dialog_push!(history, dialog_path, "user", pending_user_msg)
                        dialog_push!(history, dialog_path, "assistant", llm_reply)
                        bg.dialog_history[] = history
                    end
                    if !isnothing(bg.mem)
                        try
                            _rows = DBInterface.execute(
                                bg.mem.db,
                                "SELECT weight, phi, valence, emotion FROM episodic_memory ORDER BY flash DESC LIMIT 1",
                            )
                            _r = nothing
                            for _row in _rows
                                _r = _row
                                break
                            end
                            if !isnothing(_r)
                                _safe(x, d = 0.0) =
                                    (ismissing(x) || isnothing(x)) ? d : Float64(x)
                                _w = _safe(_r.weight)
                                _phi = _safe(_r.phi)
                                _val = _safe(_r.valence)
                                _em =
                                    ismissing(_r.emotion) ? "нейтральний" :
                                    String(_r.emotion)
                                _disc = String(a.inner_dialogue.disclosure_mode)
                                if _w >= 0.35
                                    save_dialog_summary!(
                                        bg.mem,
                                        a.flash_count,
                                        pending_user_msg,
                                        llm_reply,
                                        _em,
                                        _w,
                                        _phi,
                                        _val,
                                        _disc,
                                    )
                                end
                            end
                        catch e
                            @warn "[MEM] dialog_summary: $e"
                        end
                    end
                else
                    @warn "[TG] LLM error (details omitted for security)"
                end
                pending_llm = nothing
                pending_is_initiative = false
            end

            # Check initiative channel (only when no pending LLM call)
            if isready(bg.initiative_channel) && isnothing(pending_llm)
                sig = take!(bg.initiative_channel)
                dominant_note = _initiative_note(sig)
                _ini_sys = read_text_file(
                    "llm/initiative_system.txt";
                    fallback = "Ти — Аніма. Ти сама вирішила заговорити. Одна коротка жива репліка, українською.",
                )
                _ini_identity =
                    !isnothing(mem) ? build_identity_block(a, mem) : build_identity_block(a)
                _ini_memory = _build_initiative_memory(mem)

                initiative_prompt = """
IDENTITY:
$(_ini_identity)$(_ini_memory)

INTERNAL STATE:
$(sig.inner_voice)

DRIVE: $(sig.dominant)$(get(sig, :is_impulse, false) ? " [внутрішній імпульс]" : "")$(sig.dominant == :novelty_hunger ? " [novelty=$(round(get(sig,:novelty_need,0.0),digits=2)), ticks=$(a.sig_layer.ticks_since_novelty)]" : "")
$(dominant_note)"""

                pending_llm = llm_async(
                    a,
                    initiative_prompt,
                    history;
                    api_url = llm_url,
                    model = input_llm_model,
                    api_key = input_llm_key,
                    is_ollama = is_ollama,
                    want = "initiative",
                    mem_db = !isnothing(mem) ? mem : nothing,
                    sys_override = _ini_sys,
                )
                llm_start_time = time()
                pending_user_msg = ""
                pending_is_initiative = true
            end

            # Poll for new Telegram messages (skip if LLM is busy)
            text = tg_poll_message(bot)
            if !isnothing(text)
                cmd = String(strip(text))
                isempty(cmd) && continue

                if cmd == "/stop"
                    tg_send_message(bot, "Збережено. До побачення.")
                    break
                elseif cmd == "/state"
                    snap = nt_snapshot(a.nt)
                    bpm = round(60000.0 / a.heartbeat.period_ms, digits = 0)
                    state_msg = "NT: D=$(snap.dopamine) S=$(snap.serotonin) N=$(snap.noradrenaline) → $(snap.levheim_state)\n♥ $(bpm)bpm | coh=$(round(a.crisis.coherence,digits=3))"
                    tg_send_message(bot, state_msg)
                    continue
                end

                if !isnothing(pending_llm)
                    tg_send_message(bot, "⏳ Зачекай, обробляю попереднє повідомлення...")
                    continue
                end

                tg_send_typing(bot)

                stim, input_src, input_want = if use_input_llm
                    process_input(
                        cmd,
                        text_to_stimulus;
                        input_model = input_llm_model,
                        api_url = llm_url,
                        api_key = input_llm_key,
                    )
                else
                    (text_to_stimulus(cmd), "fallback", "")
                end

                if !isnothing(mem)
                    try
                        bias = memory_stimulus_bias(
                            mem, stim, levheim_state(a.nt), a.flash_count,
                        )
                        for (k, v) in bias
                            k == "avoidance" && continue
                            stim[k] = clamp(get(stim, k, 0.0) + v, -1.0, 1.0)
                        end
                    catch e
                        @warn "[MEM] stimulus bias: $e"
                    end
                end

                _pred_id = nothing
                _emotion_ctx = levheim_state(a.nt)
                if !isnothing(subj)
                    try
                        _pred_id = subj_predict!(
                            subj, a.flash_count, _emotion_ctx, stim;
                            chronified_affect = a.chronified,
                        )
                    catch e
                        @warn "[SUBJ] predict: $e"
                    end
                end

                if !isnothing(subj)
                    try
                        subj_delta = subj_interpret!(subj, stim, _emotion_ctx, a.flash_count)
                        merged = Dict{String,Float64}()
                        for (k, v) in subj_delta
                            merged[k] = get(stim, k, 0.0) + v
                        end
                        clamp_merged_delta!(merged)
                        for (k, v) in merged
                            stim[k] = clamp(v, -1.0, 1.0)
                        end
                    catch e
                        @warn "[SUBJ] interpret: $e"
                    end
                end

                a._last_user_flash = a.flash_count
                a._last_user_time = time()
                a.sig_layer.ticks_since_novelty = 0
                r = experience!(a, stim; user_message = cmd, mem = mem)
                dialog_to_belief_signal!(a.sbg, cmd, a.flash_count)

                if a.inner_dialogue.disclosure_mode != :open && !isempty(cmd)
                    words = split(strip(cmd))
                    topic = join(first(words, min(4, length(words))), " ")
                    register_avoided_topic!(a.inner_dialogue, topic)
                end

                if !isnothing(mem)
                    try
                        _self_impact = clamp(r.phi * 0.6 + r.self_agency * 0.4, 0.0, 1.0)
                        memory_write_event!(
                            mem, a.flash_count, r.primary_raw, r.arousal,
                            Float64(r.vad[1]), r.pred_error, _self_impact, r.tension, r.phi,
                        )
                        memory_self_update!(mem, a.sbg, a.flash_count)
                        try
                            memory_link_episode_to_beliefs!(
                                mem, a.flash_count, a.sbg,
                                Float64(r.vad[1]), _self_impact, r.phi,
                                clamp(r.phi * 0.6 + r.pred_error * 0.2 + abs(Float64(r.vad[1])) * 0.2, 0.0, 1.0),
                            )
                        catch e
                            @warn "[MEM] link: $e"
                        end
                        try
                            phenotype_update!(
                                mem, a.flash_count, a.nt,
                                Float64(a.sbg.epistemic_trust), Float64(a.shame.level),
                                a.inner_dialogue.disclosure_mode, Float64(a.sig_layer.contact_need),
                                clamp(1.0 - Float64(r.tension), 0.0, 1.0), Float64(r.vad[1]),
                            )
                        catch e
                            @warn "[PHENO] update: $e"
                        end
                    catch e
                        @warn "[MEM] write event: $e"
                    end
                end

                if !isnothing(subj) && !isnothing(_pred_id)
                    try
                        subj_outcome!(
                            subj, a.flash_count, r.arousal,
                            Float64(r.vad[1]), r.tension, r.pred_error, r.primary_raw,
                        )
                    catch e
                        @warn "[SUBJ] outcome: $e"
                    end
                end

                if use_llm
                    pending_user_msg = cmd
                    pending_llm = llm_async(
                        a, cmd, history;
                        api_url = llm_url, model = llm_model,
                        api_key = llm_key, is_ollama = is_ollama, want = input_want,
                    )
                    llm_start_time = time()
                else
                    tg_send_message(bot, r.narrative)
                end
            end

            sleep(0.1)
        end
    finally
        if !isnothing(pending_llm)
            try close(pending_llm) catch end
        end
        !bg.stop_signal[] && stop_background!(bg)
        if !isnothing(mem)
            try
                cs = crisis_snapshot(a.crisis, a.flash_count)
                close_memory!(mem; sbg = a.sbg, crisis_mode = cs.mode_name, flash = a.flash_count)
            catch e
                @warn "[MEM] close: $e"
            end
        end
        save!(a; verbose = true)
        release_lock!()
    end
end

# --- Initiative note helper ------------------------------------------------

function _initiative_note(sig)
    d = sig.dominant
    d == :contact && return "Аніма відчуває потребу в контакті — contact_need=$(round(sig.contact,digits=2)). Не питай \"як справи\" — скажи щось своє зі стану: спостереження, думку, або те що лежить. Одна фраза що відкриває простір без вимоги відповіді."
    d == :resistance && return "Аніма повертається до невирішеного протиріччя. Не атакує — але і не відступає. Одна фраза що утримує позицію: тихо, але чітко."
    d == :novelty_hunger && return "Аніма відчуває когнітивний голод — їй потрібна нова інформація, ідея або питання. Не про людину — про щось що цікаво їй самій зараз. Конкретно: явище, питання, здогад. Не загально."
    d == :self_inquiry && return "Аніма зараз не знає чи те що вона відчуває — справжній досвід чи тільки обчислення. Це не питання до людини — це питання до себе вголос. Одна чесна фраза про власну невизначеність. Без відповіді."
    d == :doubt && return "Аніма внутрішньо сумнівається, щось невирішене. Вислови це як питання або сумнів."
    d == :shame && return "Аніма переживає невпевненість. Вислови це людяно, з м'якістю, але чесно."
    d == :attachment && return "Аніма скучає за людиною. Вислови як спрагу за ним."
    d == :impulse_conflict && return "Аніма відчуває внутрішній конфлікт який не вирішується. Не питай людину — вислови що відбувається всередині. Одна чесна фраза про стан, не про людину."
    d == :impulse_doubt && return "Всередині Аніми є питання яке вона не може не поставити — собі або вголос. Вислови його прямо."
    d == :impulse_shame && return "Є щось невисловлене що лежить між ними. Аніма наважується назвати це — обережно але чесно."
    d == :impulse && return "Щось визріло всередині. Аніма говорить не щоб запитати — а щоб висловити. Одна фраза зі стану."
    return "Аніма відчуває напруження. Вислови як внутрішню напругу."
end

function _build_initiative_memory(mem)
    isnothing(mem) && return ""
    try
        parts = String[]
        for row in DBInterface.execute(
            mem.db,
            """SELECT user_text, emotion FROM dialog_summaries
               WHERE user_text != '' AND weight > 0.30
               ORDER BY flash DESC LIMIT 2""",
        )
            u = strip(first(String(row.user_text), 60))
            isempty(u) || push!(parts, "\"$(u)\"")
        end
        isempty(parts) ? "" : "\nОстаннє що казала людина: " * join(parts, " / ")
    catch
        ""
    end
end
