use base64::Engine;
use image::codecs::png::PngEncoder;
use image::imageops::{FilterType, overlay, resize};
use image::{ColorType, DynamicImage, ImageBuffer, ImageEncoder, Rgba, RgbaImage};
use serde::{Deserialize, Serialize};
use std::env;
use std::fs::{self, File};
use std::io::Cursor;
use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant, SystemTime};
use time::OffsetDateTime;
use time::format_description::well_known::Rfc3339;
use tiny_http::{Header, Response, Server, StatusCode};

const OUTPUT_SIZE: u32 = 144;
const COLUMNS: u32 = 8;
const ROWS: u32 = 9;
const SLOT_COUNT: u64 = 8;

type Result<T> = std::result::Result<T, Box<dyn std::error::Error + Send + Sync>>;

#[derive(Clone, Debug)]
struct Config {
    fps: f64,
    retry_interval: Duration,
    duration: Option<Duration>,
    output_dir: PathBuf,
    pet_id: Option<String>,
    pet_state: Option<PetAnimationState>,
    http_addr: Option<String>,
    debug: bool,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "kebab-case")]
enum PetAnimationState {
    Idle,
    Running,
    Waiting,
    Failed,
    Review,
}

impl PetAnimationState {
    fn parse(value: &str) -> Option<Self> {
        match value {
            "idle" => Some(Self::Idle),
            "running" => Some(Self::Running),
            "waiting" => Some(Self::Waiting),
            "failed" => Some(Self::Failed),
            "review" => Some(Self::Review),
            _ => None,
        }
    }

    fn as_str(self) -> &'static str {
        match self {
            Self::Idle => "idle",
            Self::Running => "running",
            Self::Waiting => "waiting",
            Self::Failed => "failed",
            Self::Review => "review",
        }
    }
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct PetManifest {
    #[serde(default)]
    id: String,
    #[serde(default)]
    spritesheet_path: Option<String>,
}

#[derive(Clone, Debug)]
struct ResolvedPet {
    id: String,
    spritesheet_path: PathBuf,
}

#[derive(Clone, Copy, Debug)]
struct SpriteFrameOverride {
    row: u32,
    column: u32,
}

#[derive(Clone, Debug)]
struct ActivityState {
    state: PetAnimationState,
    source: String,
    sprite_frame_override: Option<SpriteFrameOverride>,
    notification_badge_count: Option<u32>,
}

#[derive(Clone, Copy, Debug)]
struct TimelineFrame {
    row: u32,
    column: u32,
    duration_ms: u64,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct RenderStatus {
    version: u32,
    status: String,
    source: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    state_source: Option<String>,
    updated_at: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    frame_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    frame_sequence: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    frame_slot: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    frame_data_path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    capture_mode: Option<String>,
    #[serde(rename = "captureFPS")]
    #[serde(skip_serializing_if = "Option::is_none")]
    capture_fps: Option<f64>,
    #[serde(rename = "renderFPS")]
    #[serde(skip_serializing_if = "Option::is_none")]
    render_fps: Option<f64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    crop: Option<serde_json::Value>,
    #[serde(rename = "targetWindowID")]
    #[serde(skip_serializing_if = "Option::is_none")]
    target_window_id: Option<u32>,
    #[serde(rename = "petID")]
    #[serde(skip_serializing_if = "Option::is_none")]
    pet_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pet_state: Option<PetAnimationState>,
    #[serde(skip_serializing_if = "Option::is_none")]
    notification_badge_count: Option<u32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    message: Option<String>,
}

#[derive(Clone, Debug, Default)]
struct SharedFrame {
    png: Vec<u8>,
    data_url: String,
    status_json: String,
}

fn main() -> Result<()> {
    let config = Config::parse(env::args().skip(1).collect())?;
    fs::create_dir_all(&config.output_dir)?;

    let shared = Arc::new(Mutex::new(SharedFrame::default()));
    if let Some(addr) = config.http_addr.clone() {
        let shared_for_server = Arc::clone(&shared);
        thread::spawn(move || {
            if let Err(error) = run_http_server(&addr, shared_for_server) {
                eprintln!("http server failed: {error}");
            }
        });
    }

    run_renderer(config, shared)
}

impl Config {
    fn parse(args: Vec<String>) -> Result<Self> {
        let mut config = Self {
            fps: 10.0,
            retry_interval: Duration::from_secs(2),
            duration: None,
            output_dir: PathBuf::from("frames"),
            pet_id: None,
            pet_state: None,
            http_addr: None,
            debug: false,
        };

        let mut index = 0;
        while index < args.len() {
            match args[index].as_str() {
                "--fps" => {
                    config.fps = parse_next(&args, &mut index, "--fps")?.parse()?;
                }
                "--retry-interval" => {
                    let seconds: f64 =
                        parse_next(&args, &mut index, "--retry-interval")?.parse()?;
                    config.retry_interval = Duration::from_secs_f64(seconds.max(0.1));
                }
                "--duration" => {
                    let seconds: f64 = parse_next(&args, &mut index, "--duration")?.parse()?;
                    config.duration = Some(Duration::from_secs_f64(seconds.max(0.0)));
                }
                "--output-dir" => {
                    config.output_dir =
                        PathBuf::from(parse_next(&args, &mut index, "--output-dir")?);
                }
                "--pet-id" => {
                    config.pet_id = Some(parse_next(&args, &mut index, "--pet-id")?);
                }
                "--pet-state" => {
                    let value = parse_next(&args, &mut index, "--pet-state")?;
                    config.pet_state = Some(
                        PetAnimationState::parse(&value)
                            .ok_or_else(|| format!("unsupported pet state: {value}"))?,
                    );
                }
                "--http" => {
                    config.http_addr = Some(parse_next(&args, &mut index, "--http")?);
                }
                "--debug" => {
                    config.debug = true;
                }
                "--help" | "-h" => {
                    print_help();
                    std::process::exit(0);
                }
                other => return Err(format!("unknown argument: {other}").into()),
            }
            index += 1;
        }

        if !(1.0..=30.0).contains(&config.fps) {
            return Err("--fps must be between 1 and 30".into());
        }

        Ok(config)
    }
}

fn parse_next(args: &[String], index: &mut usize, name: &str) -> Result<String> {
    *index += 1;
    args.get(*index)
        .cloned()
        .ok_or_else(|| format!("{name} needs a value").into())
}

fn print_help() {
    println!(
        "codex-pet-renderer\n\n\
         Usage:\n\
           codex-pet-renderer --output-dir <frames-dir> [options]\n\n\
         Options:\n\
           --fps <n>                 Render FPS, default 10\n\
           --duration <seconds>      Stop after a duration\n\
           --pet-id <id>             Custom pet id, with or without custom: prefix\n\
           --pet-state <state>       idle, running, waiting, failed, review\n\
           --http <addr:port>        Serve /status and /frame/latest.png\n\
           --debug                   Print per-frame logs"
    );
}

fn run_renderer(config: Config, shared: Arc<Mutex<SharedFrame>>) -> Result<()> {
    let frame_interval = Duration::from_secs_f64(1.0 / config.fps);
    let started_at = Instant::now();
    let mut sequence = 0;
    let mut animation_key = String::new();
    let mut animation_started_at = Instant::now();

    loop {
        if config
            .duration
            .is_some_and(|duration| started_at.elapsed() >= duration)
        {
            return Ok(());
        }

        match publish_frame(
            &config,
            sequence,
            &mut animation_key,
            &mut animation_started_at,
            Arc::clone(&shared),
        ) {
            Ok(()) => {
                sequence += 1;
                thread::sleep(frame_interval);
            }
            Err(error) => {
                write_error_status(&config, &error.to_string(), Arc::clone(&shared))?;
                thread::sleep(config.retry_interval);
            }
        }
    }
}

fn publish_frame(
    config: &Config,
    sequence: u64,
    animation_key: &mut String,
    animation_started_at: &mut Instant,
    shared: Arc<Mutex<SharedFrame>>,
) -> Result<()> {
    let codex_home = codex_home();
    let pet = resolve_pet(config.pet_id.as_deref(), &codex_home)?;
    let activity = resolve_activity_state(config.pet_state, &codex_home);
    let state = activity.state;
    let key = format!("{}:{}", pet.id, state.as_str());
    if *animation_key != key {
        *animation_key = key;
        *animation_started_at = Instant::now();
    }

    let elapsed_ms = animation_started_at.elapsed().as_millis() as u64;
    let sprite = activity
        .sprite_frame_override
        .map(|frame| TimelineFrame {
            row: frame.row,
            column: frame.column,
            duration_ms: 0,
        })
        .unwrap_or_else(|| timeline_frame(state, elapsed_ms));
    let image = render_sprite_frame(
        &pet.spritesheet_path,
        sprite,
        activity.notification_badge_count,
    )?;
    let png = encode_png(&image)?;
    let data_url = format!(
        "data:image/png;base64,{}",
        base64::engine::general_purpose::STANDARD.encode(&png)
    );

    let slot = sequence % SLOT_COUNT;
    let slot_path = config.output_dir.join(format!("frame-{slot}.png"));
    let latest_path = config.output_dir.join("latest.png");
    let data_url_path = config.output_dir.join("latest-data-url.txt");
    let status_path = config.output_dir.join("status.json");

    atomic_write(&slot_path, &png)?;
    atomic_write(&latest_path, &png)?;
    atomic_write(data_url_path.as_path(), data_url.as_bytes())?;

    let status = RenderStatus {
        version: 2,
        status: "ok".to_string(),
        source: "asset-renderer".to_string(),
        state_source: Some(activity.source.clone()),
        updated_at: iso8601_now(),
        frame_path: Some(slot_path.to_string_lossy().to_string()),
        frame_sequence: Some(sequence),
        frame_slot: Some(slot),
        frame_data_path: Some(data_url_path.to_string_lossy().to_string()),
        capture_mode: Some("render-assets".to_string()),
        capture_fps: Some(config.fps),
        render_fps: Some(config.fps),
        crop: None,
        target_window_id: None,
        pet_id: Some(pet.id.clone()),
        pet_state: Some(state),
        notification_badge_count: activity.notification_badge_count,
        message: None,
    };
    let status_json = serde_json::to_string_pretty(&status)?;
    atomic_write(status_path.as_path(), status_json.as_bytes())?;

    {
        let mut guard = shared.lock().expect("shared frame lock poisoned");
        guard.png = png;
        guard.data_url = data_url;
        guard.status_json = status_json;
    }

    if config.debug {
        println!(
            "render frame {sequence} slot={slot} pet={} state={} source={} row={} col={} -> {}",
            pet.id,
            state.as_str(),
            activity.source,
            sprite.row,
            sprite.column,
            slot_path.display()
        );
    }

    Ok(())
}

fn write_error_status(
    config: &Config,
    message: &str,
    shared: Arc<Mutex<SharedFrame>>,
) -> Result<()> {
    let status = RenderStatus {
        version: 2,
        status: "render-failed".to_string(),
        source: "asset-renderer".to_string(),
        state_source: None,
        updated_at: iso8601_now(),
        frame_path: None,
        frame_sequence: None,
        frame_slot: None,
        frame_data_path: None,
        capture_mode: Some("render-assets".to_string()),
        capture_fps: Some(config.fps),
        render_fps: Some(config.fps),
        crop: None,
        target_window_id: None,
        pet_id: None,
        pet_state: None,
        notification_badge_count: None,
        message: Some(message.to_string()),
    };
    let status_json = serde_json::to_string_pretty(&status)?;
    atomic_write(
        config.output_dir.join("status.json").as_path(),
        status_json.as_bytes(),
    )?;
    shared
        .lock()
        .expect("shared frame lock poisoned")
        .status_json = status_json;
    eprintln!("render-failed: {message}");
    Ok(())
}

fn resolve_pet(preferred_id: Option<&str>, codex_home: &Path) -> Result<ResolvedPet> {
    let pets_dir = codex_home.join("pets");
    let selected_id = preferred_id
        .map(str::to_string)
        .or_else(|| override_pet_id(codex_home))
        .or_else(|| persisted_custom_pet_id(codex_home));

    if let Some(id) = selected_id.as_deref() {
        return resolve_pet_dir(&pets_dir, normalize_pet_id(id))
            .ok_or_else(|| format!("No Codex custom pet found for {id}.").into());
    }

    let mut entries = fs::read_dir(&pets_dir)?
        .filter_map(std::result::Result::ok)
        .filter(|entry| entry.file_type().map(|kind| kind.is_dir()).unwrap_or(false))
        .collect::<Vec<_>>();
    entries.sort_by_key(|entry| entry.file_name());

    for entry in entries {
        if let Some(pet) = resolve_pet_dir(&pets_dir, &entry.file_name().to_string_lossy()) {
            return Ok(pet);
        }
    }

    Err("No Codex custom pet found.".into())
}

fn codex_home() -> PathBuf {
    env::var_os("CODEX_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(".codex"))
}

fn resolve_pet_dir(pets_dir: &Path, id: &str) -> Option<ResolvedPet> {
    let dir = pets_dir.join(id);
    let manifest_path = dir.join("pet.json");
    let manifest_text = fs::read_to_string(&manifest_path).ok()?;
    let manifest: PetManifest = serde_json::from_str(&manifest_text).ok()?;
    let spritesheet_name = manifest
        .spritesheet_path
        .as_deref()
        .unwrap_or("spritesheet.webp");
    let spritesheet_path = dir.join(spritesheet_name);
    if !spritesheet_path.is_file() {
        return None;
    }

    let pet_id = if manifest.id.is_empty() {
        id.to_string()
    } else {
        manifest.id
    };
    Some(ResolvedPet {
        id: format!("custom:{pet_id}"),
        spritesheet_path,
    })
}

fn normalize_pet_id(value: &str) -> &str {
    value.strip_prefix("custom:").unwrap_or(value)
}

fn override_pet_id(codex_home: &Path) -> Option<String> {
    let value = read_json(codex_home.join("pet-streamdeck-state.json")).ok()?;
    value
        .get("petId")
        .and_then(serde_json::Value::as_str)
        .filter(|id| !id.is_empty())
        .map(str::to_string)
}

fn persisted_custom_pet_id(codex_home: &Path) -> Option<String> {
    let value = read_json(codex_home.join(".codex-global-state.json")).ok()?;
    let persisted = value.get("electron-persisted-atom-state")?.as_object()?;

    for (key, value) in persisted {
        let key = key.to_ascii_lowercase();
        if !key.contains("pet") && !key.contains("avatar") {
            continue;
        }

        if let Some(string) = value.as_str().filter(|value| value.starts_with("custom:")) {
            return Some(string.to_string());
        }

        if let Some(strings) = value.as_array() {
            for string in strings
                .iter()
                .filter_map(serde_json::Value::as_str)
                .filter(|value| value.starts_with("custom:"))
            {
                return Some(string.to_string());
            }
        }
    }

    None
}

fn resolve_activity_state(
    explicit_state: Option<PetAnimationState>,
    codex_home: &Path,
) -> ActivityState {
    if let Some(state) = explicit_state {
        return ActivityState {
            state,
            source: "cli".to_string(),
            sprite_frame_override: None,
            notification_badge_count: None,
        };
    }

    if let Some(activity) = override_activity_state(codex_home) {
        return activity;
    }

    if let Some(activity) = infer_activity_from_recent_session(codex_home) {
        return activity;
    }

    ActivityState {
        state: PetAnimationState::Idle,
        source: "default".to_string(),
        sprite_frame_override: None,
        notification_badge_count: None,
    }
}

fn override_activity_state(codex_home: &Path) -> Option<ActivityState> {
    let value = read_json(codex_home.join("pet-streamdeck-state.json")).ok()?;
    let frame_override = fresh_sprite_frame_override(&value);
    let state = value
        .get("state")
        .and_then(serde_json::Value::as_str)
        .and_then(PetAnimationState::parse)
        .or_else(|| frame_override.map(|frame| state_for_sprite_row(frame.row)))?;

    let notification_badge_count = if frame_override.is_some() {
        value
            .get("notificationBadgeCount")
            .and_then(serde_json::Value::as_u64)
            .filter(|count| *count > 0)
            .map(|count| count.min(99) as u32)
    } else {
        None
    };

    Some(ActivityState {
        state,
        source: if frame_override.is_some() {
            "codex-debug-overlay"
        } else {
            "override-file"
        }
        .to_string(),
        sprite_frame_override: frame_override,
        notification_badge_count,
    })
}

fn fresh_sprite_frame_override(value: &serde_json::Value) -> Option<SpriteFrameOverride> {
    let source = value.get("source")?.as_str()?;
    if source != "codex-debug-overlay" {
        return None;
    }

    let updated_at = value.get("updatedAt")?.as_str()?;
    let updated_at = OffsetDateTime::parse(updated_at, &Rfc3339).ok()?;
    if (OffsetDateTime::now_utc() - updated_at).whole_seconds() >= 2 {
        return None;
    }

    let row = value.get("spriteRow")?.as_u64()? as u32;
    let column = value.get("spriteColumn")?.as_u64()? as u32;
    if row >= ROWS || column >= COLUMNS {
        return None;
    }

    Some(SpriteFrameOverride { row, column })
}

fn state_for_sprite_row(row: u32) -> PetAnimationState {
    match row {
        5 => PetAnimationState::Failed,
        6 => PetAnimationState::Waiting,
        7 => PetAnimationState::Running,
        8 => PetAnimationState::Review,
        _ => PetAnimationState::Idle,
    }
}

fn infer_activity_from_recent_session(codex_home: &Path) -> Option<ActivityState> {
    let session = newest_jsonl_file(&codex_home.join("sessions"))?;
    let tail = read_tail(&session, 128 * 1024).ok()?.to_ascii_lowercase();

    for line in tail.lines().rev() {
        let state =
            if line.contains("\"type\":\"event_msg\"") && line.contains("\"type\":\"error\"") {
                Some(PetAnimationState::Failed)
            } else if line.contains("approval_request") || line.contains("request_user_input") {
                Some(PetAnimationState::Waiting)
            } else if line.contains("\"type\":\"task_complete\"")
                || line.contains("\"phase\":\"final_answer\"")
            {
                Some(PetAnimationState::Review)
            } else if line.contains("\"type\":\"task_started\"")
                || line.contains("\"type\":\"function_call\"")
            {
                Some(PetAnimationState::Running)
            } else {
                None
            };

        if let Some(state) = state {
            return Some(ActivityState {
                state,
                source: "codex-session".to_string(),
                sprite_frame_override: None,
                notification_badge_count: None,
            });
        }
    }

    Some(ActivityState {
        state: PetAnimationState::Idle,
        source: "codex-session".to_string(),
        sprite_frame_override: None,
        notification_badge_count: None,
    })
}

fn newest_jsonl_file(directory: &Path) -> Option<PathBuf> {
    let mut newest: Option<(PathBuf, SystemTime)> = None;
    visit_files(directory, &mut |path| {
        if path.extension().and_then(|ext| ext.to_str()) != Some("jsonl") {
            return;
        }
        let Ok(metadata) = fs::metadata(path) else {
            return;
        };
        if !metadata.is_file() {
            return;
        }
        let Ok(modified) = metadata.modified() else {
            return;
        };
        if newest
            .as_ref()
            .is_none_or(|(_, newest_modified)| modified > *newest_modified)
        {
            newest = Some((path.to_path_buf(), modified));
        }
    });
    newest.map(|(path, _)| path)
}

fn visit_files(directory: &Path, visitor: &mut impl FnMut(&Path)) {
    let Ok(entries) = fs::read_dir(directory) else {
        return;
    };
    for entry in entries.filter_map(std::result::Result::ok) {
        let path = entry.path();
        let Ok(file_type) = entry.file_type() else {
            continue;
        };
        if file_type.is_dir() {
            visit_files(&path, visitor);
        } else if file_type.is_file() {
            visitor(&path);
        }
    }
}

fn read_tail(path: &Path, max_bytes: u64) -> Result<String> {
    let mut file = File::open(path)?;
    let size = file.seek(SeekFrom::End(0))?;
    let offset = size.saturating_sub(max_bytes);
    file.seek(SeekFrom::Start(offset))?;
    let mut text = String::new();
    file.read_to_string(&mut text)?;
    Ok(text)
}

fn read_json(path: impl AsRef<Path>) -> Result<serde_json::Value> {
    let text = fs::read_to_string(path)?;
    Ok(serde_json::from_str(&text)?)
}

fn home_dir() -> PathBuf {
    env::var_os("HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("USERPROFILE").map(PathBuf::from))
        .unwrap_or_else(|| PathBuf::from("."))
}

fn render_sprite_frame(
    spritesheet_path: &Path,
    sprite: TimelineFrame,
    badge_count: Option<u32>,
) -> Result<RgbaImage> {
    let spritesheet = image::open(spritesheet_path)?.to_rgba8();
    let (sheet_width, sheet_height) = spritesheet.dimensions();
    if sheet_width % COLUMNS != 0 || sheet_height % ROWS != 0 {
        return Err(format!("Invalid spritesheet size {sheet_width}x{sheet_height}.").into());
    }

    let frame_width = sheet_width / COLUMNS;
    let frame_height = sheet_height / ROWS;
    let frame = DynamicImage::ImageRgba8(spritesheet)
        .crop_imm(
            sprite.column * frame_width,
            sprite.row * frame_height,
            frame_width,
            frame_height,
        )
        .to_rgba8();

    let scale =
        (OUTPUT_SIZE as f32 / frame_width as f32).min(OUTPUT_SIZE as f32 / frame_height as f32);
    let draw_width = (frame_width as f32 * scale).floor().max(1.0) as u32;
    let draw_height = (frame_height as f32 * scale).floor().max(1.0) as u32;
    let resized = resize(&frame, draw_width, draw_height, FilterType::Nearest);

    let mut canvas = ImageBuffer::from_pixel(OUTPUT_SIZE, OUTPUT_SIZE, Rgba([0, 0, 0, 255]));
    let x = ((OUTPUT_SIZE - draw_width) / 2) as i64;
    let y = ((OUTPUT_SIZE - draw_height) / 2) as i64;
    overlay(&mut canvas, &resized, x, y);

    if let Some(count) = badge_count.filter(|count| *count > 0) {
        draw_badge(&mut canvas, count.min(99));
    }

    Ok(canvas)
}

fn encode_png(image: &RgbaImage) -> Result<Vec<u8>> {
    let mut output = Vec::new();
    let encoder = PngEncoder::new(Cursor::new(&mut output));
    encoder.write_image(
        image.as_raw(),
        image.width(),
        image.height(),
        ColorType::Rgba8.into(),
    )?;
    Ok(output)
}

fn timeline_frame(state: PetAnimationState, elapsed_ms: u64) -> TimelineFrame {
    let idle_slow = [
        TimelineFrame {
            row: 0,
            column: 0,
            duration_ms: 280 * 6,
        },
        TimelineFrame {
            row: 0,
            column: 1,
            duration_ms: 110 * 6,
        },
        TimelineFrame {
            row: 0,
            column: 2,
            duration_ms: 110 * 6,
        },
        TimelineFrame {
            row: 0,
            column: 3,
            duration_ms: 140 * 6,
        },
        TimelineFrame {
            row: 0,
            column: 4,
            duration_ms: 140 * 6,
        },
        TimelineFrame {
            row: 0,
            column: 5,
            duration_ms: 320 * 6,
        },
    ];

    if state == PetAnimationState::Idle {
        return frame_in(&idle_slow, elapsed_ms);
    }

    let intro = match state {
        PetAnimationState::Failed => make_frames(5, 8, 140, 240),
        PetAnimationState::Waiting => make_frames(6, 6, 150, 260),
        PetAnimationState::Running => make_frames(7, 6, 120, 220),
        PetAnimationState::Review => make_frames(8, 6, 150, 280),
        PetAnimationState::Idle => unreachable!(),
    };
    let intro_duration = duration_of(&intro) * 3;
    if elapsed_ms < intro_duration {
        return frame_in_repeated(&intro, elapsed_ms, 3);
    }
    frame_in(&idle_slow, elapsed_ms - intro_duration)
}

fn make_frames(
    row: u32,
    count: u32,
    duration_ms: u64,
    last_duration_ms: u64,
) -> Vec<TimelineFrame> {
    (0..count)
        .map(|column| TimelineFrame {
            row,
            column,
            duration_ms: if column == count - 1 {
                last_duration_ms
            } else {
                duration_ms
            },
        })
        .collect()
}

fn frame_in_repeated(frames: &[TimelineFrame], elapsed_ms: u64, repeat: u64) -> TimelineFrame {
    let total = duration_of(frames) * repeat;
    frame_in(frames, elapsed_ms % total)
}

fn frame_in(frames: &[TimelineFrame], elapsed_ms: u64) -> TimelineFrame {
    let total = duration_of(frames);
    let mut remaining = if total > 0 { elapsed_ms % total } else { 0 };
    for frame in frames {
        if remaining < frame.duration_ms {
            return *frame;
        }
        remaining -= frame.duration_ms;
    }
    frames[0]
}

fn duration_of(frames: &[TimelineFrame]) -> u64 {
    frames.iter().map(|frame| frame.duration_ms).sum()
}

fn draw_badge(image: &mut RgbaImage, count: u32) {
    let center_x = 117_i32;
    let center_y = 25_i32;
    let radius = 17_i32;
    for y in -radius..=radius {
        for x in -radius..=radius {
            if x * x + y * y <= radius * radius {
                let px = center_x + x;
                let py = center_y + y;
                if (0..OUTPUT_SIZE as i32).contains(&px) && (0..OUTPUT_SIZE as i32).contains(&py) {
                    image.put_pixel(px as u32, py as u32, Rgba([232, 242, 255, 255]));
                }
            }
        }
    }
    draw_digits(image, count.to_string().as_str(), center_x, center_y);
}

fn draw_digits(image: &mut RgbaImage, text: &str, center_x: i32, center_y: i32) {
    let scale = 4_i32;
    let digit_width = 3 * scale;
    let gap = scale;
    let total_width = text.chars().count() as i32 * digit_width
        + (text.chars().count().saturating_sub(1) as i32 * gap);
    let mut x = center_x - total_width / 2;
    let y = center_y - (5 * scale) / 2;
    for ch in text.chars() {
        draw_digit(image, ch, x, y, scale);
        x += digit_width + gap;
    }
}

fn draw_digit(image: &mut RgbaImage, ch: char, origin_x: i32, origin_y: i32, scale: i32) {
    let pattern = match ch {
        '0' => ["111", "101", "101", "101", "111"],
        '1' => ["010", "110", "010", "010", "111"],
        '2' => ["111", "001", "111", "100", "111"],
        '3' => ["111", "001", "111", "001", "111"],
        '4' => ["101", "101", "111", "001", "001"],
        '5' => ["111", "100", "111", "001", "111"],
        '6' => ["111", "100", "111", "101", "111"],
        '7' => ["111", "001", "010", "010", "010"],
        '8' => ["111", "101", "111", "101", "111"],
        '9' => ["111", "101", "111", "001", "111"],
        _ => ["000", "000", "000", "000", "000"],
    };
    for (row, line) in pattern.iter().enumerate() {
        for (column, pixel) in line.chars().enumerate() {
            if pixel != '1' {
                continue;
            }
            for dy in 0..scale {
                for dx in 0..scale {
                    let px = origin_x + column as i32 * scale + dx;
                    let py = origin_y + row as i32 * scale + dy;
                    if (0..OUTPUT_SIZE as i32).contains(&px)
                        && (0..OUTPUT_SIZE as i32).contains(&py)
                    {
                        image.put_pixel(px as u32, py as u32, Rgba([15, 23, 42, 255]));
                    }
                }
            }
        }
    }
}

fn atomic_write(path: &Path, data: &[u8]) -> Result<()> {
    let tmp_path = path.with_extension(format!(
        "{}.tmp-{}",
        path.extension()
            .and_then(|ext| ext.to_str())
            .unwrap_or("tmp"),
        std::process::id()
    ));
    fs::write(&tmp_path, data)?;
    fs::rename(tmp_path, path)?;
    Ok(())
}

fn iso8601_now() -> String {
    OffsetDateTime::now_utc()
        .format(&Rfc3339)
        .unwrap_or_else(|_| "1970-01-01T00:00:00Z".to_string())
}

fn run_http_server(addr: &str, shared: Arc<Mutex<SharedFrame>>) -> Result<()> {
    let server = Server::http(addr)?;
    eprintln!("codex-pet-renderer http listening on http://{addr}");
    for request in server.incoming_requests() {
        let path = request.url().split('?').next().unwrap_or("/");
        let frame = shared.lock().expect("shared frame lock poisoned").clone();
        let response = match path {
            "/health" => text_response("ok\n", "text/plain"),
            "/status" => text_response(&frame.status_json, "application/json"),
            "/frame/latest-data-url" => text_response(&frame.data_url, "text/plain"),
            "/frame/latest.png" => binary_response(frame.png, "image/png"),
            _ => Response::from_string("not found\n").with_status_code(StatusCode(404)),
        };
        let _ = request.respond(response);
    }
    Ok(())
}

fn text_response(body: &str, content_type: &'static str) -> Response<Cursor<Vec<u8>>> {
    binary_response(body.as_bytes().to_vec(), content_type)
}

fn binary_response(body: Vec<u8>, content_type: &'static str) -> Response<Cursor<Vec<u8>>> {
    Response::from_data(body).with_header(
        Header::from_bytes(&b"Content-Type"[..], content_type.as_bytes())
            .expect("valid content type header"),
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn timeline_uses_codex_review_row_before_returning_to_idle() {
        let first = timeline_frame(PetAnimationState::Review, 0);
        assert_eq!(first.row, 8);
        assert_eq!(first.column, 0);

        let later = timeline_frame(PetAnimationState::Review, 500);
        assert_eq!(later.row, 8);

        let after_intro = timeline_frame(PetAnimationState::Review, 4_000);
        assert_eq!(after_intro.row, 0);
    }

    #[test]
    fn status_uses_existing_frame_contract_field_names() {
        let status = RenderStatus {
            version: 2,
            status: "ok".to_string(),
            source: "asset-renderer".to_string(),
            state_source: Some("codex-debug-overlay".to_string()),
            updated_at: "2026-01-01T00:00:00Z".to_string(),
            frame_path: Some("/tmp/frame-0.png".to_string()),
            frame_sequence: Some(1),
            frame_slot: Some(1),
            frame_data_path: Some("/tmp/latest-data-url.txt".to_string()),
            capture_mode: Some("render-assets".to_string()),
            capture_fps: Some(10.0),
            render_fps: Some(10.0),
            crop: None,
            target_window_id: None,
            pet_id: Some("custom:test".to_string()),
            pet_state: Some(PetAnimationState::Running),
            notification_badge_count: Some(1),
            message: None,
        };

        let value = serde_json::to_value(status).expect("status serializes");
        assert!(value.get("captureFPS").is_some());
        assert!(value.get("renderFPS").is_some());
        assert!(value.get("petID").is_some());
        assert!(value.get("petId").is_none());
        assert!(value.get("crop").is_none());
    }
}
