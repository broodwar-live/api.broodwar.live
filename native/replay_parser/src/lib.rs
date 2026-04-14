use replay_core::header::{Engine, GameType, PlayerType, Race, Speed};
use rustler::{Encoder, Env, NifResult, Term};

mod atoms {
    rustler::atoms! {
        ok,
        error,

        // Engine
        starcraft,
        brood_war,

        // Race
        terran,
        protoss,
        zerg,
        unknown,

        // Player type
        human,
        computer,
        inactive,

        // Speed
        slowest,
        slower,
        slow,
        normal,
        fast,
        faster,
        fastest,

        // Game type
        none,
        custom,
        melee,
        free_for_all,
        one_on_one,
        use_map_settings,
        top_vs_bottom,
    }
}

/// Parse a replay from raw binary data.
///
/// Returns `{:ok, replay_map}` or `{:error, reason}`.
#[rustler::nif(schedule = "DirtyCpu")]
fn parse<'a>(env: Env<'a>, data: rustler::Binary<'a>) -> NifResult<Term<'a>> {
    match replay_core::parse(data.as_slice()) {
        Ok(replay) => {
            let result = encode_replay(env, &replay);
            Ok((atoms::ok(), result).encode(env))
        }
        Err(e) => Ok((atoms::error(), e.to_string()).encode(env)),
    }
}

fn encode_replay<'a>(env: Env<'a>, replay: &replay_core::Replay) -> Term<'a> {
    let header = encode_header(env, &replay.header);

    let build_order: Vec<Term> = replay
        .build_order
        .iter()
        .map(|entry| encode_build_order_entry(env, entry))
        .collect();

    let player_apm: Vec<Term> = replay
        .player_apm
        .iter()
        .map(|apm| encode_player_apm(env, apm))
        .collect();

    let timeline: Vec<Term> = replay
        .timeline
        .iter()
        .map(|snap| encode_timeline_snapshot(env, snap))
        .collect();

    // APM over time: sampled every 5 seconds with a 30-second window
    let apm_samples = replay.apm_over_time(30.0, 5.0);
    let apm_timeline: Vec<Term> = apm_samples
        .iter()
        .map(|s| {
            rustler::Term::map_from_pairs(
                env,
                &[
                    ("frame", s.frame.encode(env)),
                    ("real_seconds", s.real_seconds.encode(env)),
                    ("player_id", s.player_id.encode(env)),
                    ("apm", (s.apm.round() as u32).encode(env)),
                    ("eapm", (s.eapm.round() as u32).encode(env)),
                ],
            )
            .unwrap()
        })
        .collect();

    // Metadata
    let metadata = encode_metadata(env, &replay.metadata);

    // Classification
    let players_for_classify: Vec<(u8, Race)> = replay
        .header
        .players
        .iter()
        .map(|p| (p.player_id, p.race))
        .collect();
    let classifications: Vec<Term> = replay_core::classify::classify_all(
        &replay.build_order,
        &players_for_classify,
    )
    .iter()
    .map(|c| encode_classification(env, c))
    .collect();

    // Phases
    let phase_analysis = replay_core::phases::detect_phases(
        &replay.build_order,
        replay.header.frame_count,
    );
    let phases = encode_phase_analysis(env, &phase_analysis);

    // Skill
    let skill_profiles = replay_core::skill::estimate_skill(
        &replay.commands,
        &replay.player_apm,
        &apm_samples,
        replay.header.frame_count,
    );
    let skills: Vec<Term> = skill_profiles
        .iter()
        .map(|p| encode_skill_profile(env, p))
        .collect();

    rustler::Term::map_from_pairs(
        env,
        &[
            ("header", header),
            ("build_order", build_order.encode(env)),
            ("player_apm", player_apm.encode(env)),
            ("command_count", replay.commands.len().encode(env)),
            ("timeline", timeline.encode(env)),
            ("apm_timeline", apm_timeline.encode(env)),
            ("metadata", metadata),
            ("classifications", classifications.encode(env)),
            ("phases", phases),
            ("skill_profiles", skills.encode(env)),
        ],
    )
    .unwrap()
}

fn encode_header<'a>(env: Env<'a>, header: &replay_core::header::Header) -> Term<'a> {
    let engine = match header.engine {
        Engine::StarCraft => atoms::starcraft().encode(env),
        Engine::BroodWar => atoms::brood_war().encode(env),
    };

    let speed = match header.game_speed {
        Speed::Slowest => atoms::slowest().encode(env),
        Speed::Slower => atoms::slower().encode(env),
        Speed::Slow => atoms::slow().encode(env),
        Speed::Normal => atoms::normal().encode(env),
        Speed::Fast => atoms::fast().encode(env),
        Speed::Faster => atoms::faster().encode(env),
        Speed::Fastest => atoms::fastest().encode(env),
        Speed::Unknown(v) => format!("unknown_{v}").encode(env),
    };

    let game_type = match header.game_type {
        GameType::None => atoms::none().encode(env),
        GameType::Custom => atoms::custom().encode(env),
        GameType::Melee => atoms::melee().encode(env),
        GameType::FreeForAll => atoms::free_for_all().encode(env),
        GameType::OneOnOne => atoms::one_on_one().encode(env),
        GameType::UseMapSettings => atoms::use_map_settings().encode(env),
        GameType::TopVsBottom => atoms::top_vs_bottom().encode(env),
        _ => atoms::custom().encode(env),
    };

    let players: Vec<Term> = header
        .players
        .iter()
        .map(|p| encode_player(env, p))
        .collect();

    rustler::Term::map_from_pairs(
        env,
        &[
            ("engine", engine),
            ("frame_count", header.frame_count.encode(env)),
            ("duration_secs", header.duration_secs().encode(env)),
            ("start_time", header.start_time.encode(env)),
            ("map_name", header.map_name.as_str().encode(env)),
            ("map_width", header.map_width.encode(env)),
            ("map_height", header.map_height.encode(env)),
            ("game_speed", speed),
            ("game_type", game_type),
            ("game_title", header.game_title.as_str().encode(env)),
            ("host_name", header.host_name.as_str().encode(env)),
            ("players", players.encode(env)),
        ],
    )
    .unwrap()
}

fn encode_player<'a>(env: Env<'a>, player: &replay_core::header::Player) -> Term<'a> {
    let race = match player.race {
        Race::Terran => atoms::terran().encode(env),
        Race::Protoss => atoms::protoss().encode(env),
        Race::Zerg => atoms::zerg().encode(env),
        Race::Unknown(_) => atoms::unknown().encode(env),
    };

    let player_type = match player.player_type {
        PlayerType::Human => atoms::human().encode(env),
        PlayerType::Computer => atoms::computer().encode(env),
        _ => atoms::inactive().encode(env),
    };

    let color_hex = bw_color_hex(player.color);

    rustler::Term::map_from_pairs(
        env,
        &[
            ("slot_id", player.slot_id.encode(env)),
            ("player_id", player.player_id.encode(env)),
            ("name", player.name.as_str().encode(env)),
            ("race", race),
            ("race_code", player.race.code().encode(env)),
            ("player_type", player_type),
            ("team", player.team.encode(env)),
            ("color", player.color.encode(env)),
            ("color_hex", color_hex.encode(env)),
        ],
    )
    .unwrap()
}

/// Map BW color index to hex color string.
fn bw_color_hex(idx: u32) -> &'static str {
    match idx {
        0 => "#F40404",  // Red
        1 => "#0C48CC",  // Blue
        2 => "#2CB494",  // Teal
        3 => "#88409C",  // Purple
        4 => "#F88C14",  // Orange
        5 => "#703014",  // Brown
        6 => "#CCE0D0",  // White
        7 => "#FCFC38",  // Yellow
        8 => "#088008",  // Green
        9 => "#FCFC7C",  // Pale Yellow
        10 => "#ECC4B0", // Tan
        11 => "#4068D4", // Aqua
        12 => "#74A47C", // Pale Green
        13 => "#9090B8", // Bluish Grey
        14 => "#FCE4AC", // Pale Yellow 2
        15 => "#00E4FC", // Cyan
        16 => "#FCA0E0", // Pink
        17 => "#787800", // Olive
        18 => "#D2F53C", // Lime
        19 => "#0000E6", // Navy
        20 => "#006464", // Dark Aqua
        21 => "#B800B8", // Magenta
        22 => "#B8B8E8", // Grey
        23 => "#3C3C3C", // Black
        _ => "#CCCCCC",
    }
}

fn encode_build_order_entry<'a>(
    env: Env<'a>,
    entry: &replay_core::analysis::BuildOrderEntry,
) -> Term<'a> {
    rustler::Term::map_from_pairs(
        env,
        &[
            ("frame", entry.frame.encode(env)),
            ("real_seconds", entry.real_seconds.encode(env)),
            ("player_id", entry.player_id.encode(env)),
            ("action", entry.action.to_string().encode(env)),
            ("name", entry.action.name().encode(env)),
        ],
    )
    .unwrap()
}

fn encode_player_apm<'a>(env: Env<'a>, apm: &replay_core::analysis::PlayerApm) -> Term<'a> {
    rustler::Term::map_from_pairs(
        env,
        &[
            ("player_id", apm.player_id.encode(env)),
            ("apm", (apm.apm.round() as u32).encode(env)),
            ("eapm", (apm.eapm.round() as u32).encode(env)),
        ],
    )
    .unwrap()
}

fn encode_timeline_snapshot<'a>(
    env: Env<'a>,
    snap: &replay_core::timeline::TimelineSnapshot,
) -> Term<'a> {
    let players: Vec<Term> = snap
        .players
        .iter()
        .map(|ps| encode_player_state(env, ps))
        .collect();

    rustler::Term::map_from_pairs(
        env,
        &[
            ("frame", snap.frame.encode(env)),
            ("real_seconds", snap.real_seconds.encode(env)),
            ("players", players.encode(env)),
        ],
    )
    .unwrap()
}

fn encode_player_state<'a>(
    env: Env<'a>,
    ps: &replay_core::timeline::PlayerState,
) -> Term<'a> {
    // Encode units/buildings as list of {name, count} pairs
    let units: Vec<Term> = ps
        .units
        .iter()
        .map(|(&id, &count)| {
            let name = replay_core::gamedata::unit_name(id);
            rustler::Term::map_from_pairs(
                env,
                &[
                    ("id", id.encode(env)),
                    ("name", name.encode(env)),
                    ("count", count.encode(env)),
                ],
            )
            .unwrap()
        })
        .collect();

    let buildings: Vec<Term> = ps
        .buildings
        .iter()
        .map(|(&id, &count)| {
            let name = replay_core::gamedata::unit_name(id);
            rustler::Term::map_from_pairs(
                env,
                &[
                    ("id", id.encode(env)),
                    ("name", name.encode(env)),
                    ("count", count.encode(env)),
                ],
            )
            .unwrap()
        })
        .collect();

    let techs: Vec<Term> = ps
        .techs
        .iter()
        .map(|&id| {
            let name = replay_core::gamedata::tech_name(id);
            rustler::Term::map_from_pairs(
                env,
                &[("id", (id as u16).encode(env)), ("name", name.encode(env))],
            )
            .unwrap()
        })
        .collect();

    let upgrades: Vec<Term> = ps
        .upgrades
        .iter()
        .map(|(&id, &level)| {
            let name = replay_core::gamedata::upgrade_name(id);
            rustler::Term::map_from_pairs(
                env,
                &[
                    ("id", (id as u16).encode(env)),
                    ("name", name.encode(env)),
                    ("level", level.encode(env)),
                ],
            )
            .unwrap()
        })
        .collect();

    rustler::Term::map_from_pairs(
        env,
        &[
            ("player_id", ps.player_id.encode(env)),
            ("minerals_invested", ps.minerals_invested.encode(env)),
            ("gas_invested", ps.gas_invested.encode(env)),
            ("supply_used", ps.supply_used.encode(env)),
            ("supply_max", ps.supply_max.encode(env)),
            ("units", units.encode(env)),
            ("buildings", buildings.encode(env)),
            ("techs", techs.encode(env)),
            ("upgrades", upgrades.encode(env)),
        ],
    )
    .unwrap()
}

// ---------------------------------------------------------------------------
// NIF: compare_builds
// ---------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyCpu")]
fn compare_builds<'a>(
    env: Env<'a>,
    data_a: rustler::Binary<'a>,
    data_b: rustler::Binary<'a>,
    player_index: u8,
) -> NifResult<Term<'a>> {
    let ra = replay_core::parse(data_a.as_slice());
    let rb = replay_core::parse(data_b.as_slice());
    match (ra, rb) {
        (Ok(a), Ok(b)) => {
            let pid_a = a.header.players.get(player_index as usize).map(|p| p.player_id).unwrap_or(0);
            let pid_b = b.header.players.get(player_index as usize).map(|p| p.player_id).unwrap_or(0);
            let seq_a = replay_core::similarity::BuildSequence::from_build_order(&a.build_order, pid_a);
            let seq_b = replay_core::similarity::BuildSequence::from_build_order(&b.build_order, pid_b);
            let result = replay_core::similarity::compare(&seq_a, &seq_b);
            let map = rustler::Term::map_from_pairs(env, &[
                ("edit_similarity", result.edit_similarity.encode(env)),
                ("lcs_similarity", result.lcs_similarity.encode(env)),
                ("len_a", result.len_a.encode(env)),
                ("len_b", result.len_b.encode(env)),
            ]).unwrap();
            Ok((atoms::ok(), map).encode(env))
        }
        (Err(e), _) | (_, Err(e)) => Ok((atoms::error(), e.to_string()).encode(env)),
    }
}

// ---------------------------------------------------------------------------
// NIF: normalize_name
// ---------------------------------------------------------------------------

#[rustler::nif]
fn normalize_name<'a>(env: Env<'a>, name: &str) -> NifResult<Term<'a>> {
    let result = replay_core::identity::normalize_name(name);
    let clan = result.clan_tag.as_deref().map(|s| s.encode(env))
        .unwrap_or_else(|| rustler::types::atom::nil().encode(env));
    let map = rustler::Term::map_from_pairs(env, &[
        ("original", result.original.as_str().encode(env)),
        ("normalized", result.normalized.as_str().encode(env)),
        ("clan_tag", clan),
    ]).unwrap();
    Ok(map)
}

// ---------------------------------------------------------------------------
// Metadata / phases / skill / classification encoding
// ---------------------------------------------------------------------------

fn encode_metadata<'a>(env: Env<'a>, meta: &replay_core::metadata::GameMetadata) -> Term<'a> {
    use replay_core::metadata::GameResult;

    let matchup = match &meta.matchup {
        Some(m) => rustler::Term::map_from_pairs(env, &[
            ("code", m.code.as_str().encode(env)),
            ("mirror", m.mirror.encode(env)),
        ]).unwrap(),
        None => rustler::types::atom::nil().encode(env),
    };

    let result = match &meta.result {
        GameResult::Winner { player_id, player_name } => rustler::Term::map_from_pairs(env, &[
            ("result", "winner".encode(env)),
            ("player_id", player_id.encode(env)),
            ("player_name", player_name.as_str().encode(env)),
        ]).unwrap(),
        GameResult::Unknown => "unknown".encode(env),
    };

    rustler::Term::map_from_pairs(env, &[
        ("matchup", matchup),
        ("map_name", meta.map_name.as_str().encode(env)),
        ("map_name_raw", meta.map_name_raw.as_str().encode(env)),
        ("result", result),
        ("duration_secs", meta.duration_secs.encode(env)),
        ("is_1v1", meta.is_1v1.encode(env)),
        ("player_count", meta.player_count.encode(env)),
    ]).unwrap()
}

fn encode_classification<'a>(env: Env<'a>, c: &replay_core::classify::OpeningClassification) -> Term<'a> {
    rustler::Term::map_from_pairs(env, &[
        ("name", c.name.as_str().encode(env)),
        ("tag", c.tag.as_str().encode(env)),
        ("confidence", c.confidence.encode(env)),
        ("race", c.race.as_str().encode(env)),
        ("actions_analyzed", c.actions_analyzed.encode(env)),
    ]).unwrap()
}

fn encode_phase_analysis<'a>(env: Env<'a>, analysis: &replay_core::phases::PhaseAnalysis) -> Term<'a> {
    let nil = || rustler::types::atom::nil().encode(env);
    let opt = |v: Option<u32>| v.map(|f| f.encode(env)).unwrap_or_else(nil);

    let phases: Vec<Term> = analysis.phases.iter().map(|p| {
        let name = p.phase.name();
        rustler::Term::map_from_pairs(env, &[
            ("phase", name.encode(env)),
            ("start_frame", p.start_frame.encode(env)),
            ("start_seconds", p.start_seconds.encode(env)),
            ("end_frame", p.end_frame.map(|f| f.encode(env)).unwrap_or_else(nil)),
            ("end_seconds", p.end_seconds.map(|s| s.encode(env)).unwrap_or_else(nil)),
        ]).unwrap()
    }).collect();

    let lm = &analysis.landmarks;
    let landmarks = rustler::Term::map_from_pairs(env, &[
        ("first_gas", opt(lm.first_gas)),
        ("first_tech", opt(lm.first_tech)),
        ("first_tier2", opt(lm.first_tier2)),
        ("first_tier3", opt(lm.first_tier3)),
        ("first_expansion", opt(lm.first_expansion)),
    ]).unwrap();

    rustler::Term::map_from_pairs(env, &[
        ("phases", phases.encode(env)),
        ("landmarks", landmarks),
    ]).unwrap()
}

fn encode_skill_profile<'a>(env: Env<'a>, p: &replay_core::skill::SkillProfile) -> Term<'a> {
    let first_action = p.first_action_frame.map(|f| f.encode(env))
        .unwrap_or_else(|| rustler::types::atom::nil().encode(env));
    rustler::Term::map_from_pairs(env, &[
        ("player_id", p.player_id.encode(env)),
        ("apm", p.apm.encode(env)),
        ("eapm", p.eapm.encode(env)),
        ("efficiency", p.efficiency.encode(env)),
        ("hotkey_assigns_per_min", p.hotkey_assigns_per_min.encode(env)),
        ("hotkey_recalls_per_min", p.hotkey_recalls_per_min.encode(env)),
        ("apm_consistency", p.apm_consistency.encode(env)),
        ("first_action_frame", first_action),
        ("skill_score", p.skill_score.encode(env)),
        ("tier", p.tier.name().encode(env)),
    ]).unwrap()
}

rustler::init!("Elixir.BroodwarNif.ReplayParser");
