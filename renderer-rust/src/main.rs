use base64::Engine;
use image::codecs::png::PngEncoder;
use image::imageops::{FilterType, overlay, resize};
use image::{ColorType, DynamicImage, ImageBuffer, ImageEncoder, Rgba, RgbaImage};
use serde::{Deserialize, Serialize};
use std::env;
use std::fs;
use std::io::Cursor;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};
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
    state_source: Option<String>,
    updated_at: String,
    frame_path: Option<String>,
    frame_sequence: Option<u64>,
    frame_slot: Option<u64>,
    frame_data_path: Option<String>,
    capture_mode: Option<String>,
    #[serde(rename = "captureFPS")]
    capture_fps: Option<f64>,
    #[serde(rename = "renderFPS")]
    render_fps: Option<f64>,
    crop: Option<serde_json::Value>,
    #[serde(rename = "targetWindowID")]
    target_window_id: Option<u32>,
    pet_id: Option<String>,
    pet_state: Option<PetAnimationState>,
    notification_badge_count: Option<u32>,
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
    let pet = resolve_pet(config.pet_id.as_deref())?;
    let state = config.pet_state.unwrap_or(PetAnimationState::Idle);
    let key = format!("{}:{}", pet.id, state.as_str());
    if *animation_key != key {
        *animation_key = key;
        *animation_started_at = Instant::now();
    }

    let elapsed_ms = animation_started_at.elapsed().as_millis() as u64;
    let sprite = timeline_frame(state, elapsed_ms);
    let image = render_sprite_frame(&pet.spritesheet_path, sprite, None)?;
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
        state_source: Some("default".to_string()),
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
        notification_badge_count: None,
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
            "render frame {sequence} slot={slot} pet={} state={} row={} col={} -> {}",
            pet.id,
            state.as_str(),
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

fn resolve_pet(preferred_id: Option<&str>) -> Result<ResolvedPet> {
    let codex_home = env::var_os("CODEX_HOME")
        .map(PathBuf::from)
        .unwrap_or_else(|| home_dir().join(".codex"));
    let pets_dir = codex_home.join("pets");

    if let Some(id) = preferred_id {
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
