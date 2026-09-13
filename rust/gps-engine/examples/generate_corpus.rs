//! Regenerates the deterministic synthetic corpus under `testdata/synthetic/`
//! (§33 of the crate plan).
//!
//! Every track is generated with a fixed seed and written as GPX, so the
//! corpus is reproducible:
//!
//! ```text
//! cargo run --example generate_corpus
//! ```
//!
//! A single 2.4 km loop route is recorded under many defect profiles
//! (clean / noisy / sparse / gapped / stopped / outliers / reversed / detour),
//! which lets `discover` and `compare` be exercised against realistic,
//! deliberately messy recordings without any downloaded data.

use std::path::Path;

use gps_engine::geo::Coordinate;
use gps_engine::synthetic::{SyntheticConfig, add_detour, reverse as reverse_track};
use gps_engine::units::Distance;
use gps_engine::{Route, Track, write_gpx_file};

const OUT_DIR: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/testdata/synthetic");

fn loop_route() -> Route {
    let raw = [
        Coordinate::new(52.500_000, 13.400_000).unwrap(),
        Coordinate::new(52.510_815, 13.400_000).unwrap(),
        Coordinate::new(52.515_315, 13.410_918).unwrap(),
        Coordinate::new(52.507_500, 13.418_836).unwrap(),
        Coordinate::new(52.500_000, 13.410_918).unwrap(),
        Coordinate::new(52.500_000, 13.400_000).unwrap(),
    ];
    Route::new(raw.to_vec()).expect("valid loop")
}

fn write(name: &str, track: &Track) {
    let path = Path::new(OUT_DIR).join(name);
    write_gpx_file(track, &path).expect("write corpus file");
    println!("wrote {}", path.display());
}

fn main() {
    let route = loop_route();
    let geometry = route.geometry();
    std::fs::create_dir_all(OUT_DIR).expect("create corpus dir");

    write(
        "clean.gpx",
        &gps_engine::synthetic::generate(geometry, &SyntheticConfig::clean(1)),
    );
    write(
        "noisy_5m.gpx",
        &gps_engine::synthetic::generate(geometry, &SyntheticConfig::noisy(2, 5.0)),
    );
    write(
        "noisy_12m.gpx",
        &gps_engine::synthetic::generate(geometry, &SyntheticConfig::noisy(3, 12.0)),
    );
    write(
        "sparse.gpx",
        &gps_engine::synthetic::generate(geometry, &SyntheticConfig::sparse(4)),
    );
    write(
        "gapped.gpx",
        &gps_engine::synthetic::generate(geometry, &SyntheticConfig::gapped(5)),
    );
    write(
        "stopped.gpx",
        &gps_engine::synthetic::generate(geometry, &SyntheticConfig::stopped(6)),
    );
    write(
        "outliers.gpx",
        &gps_engine::synthetic::generate(geometry, &SyntheticConfig::outliers(7)),
    );

    let reversed = reverse_track(&gps_engine::synthetic::generate(
        geometry,
        &SyntheticConfig::noisy(8, 5.0),
    ));
    write("reversed.gpx", &reversed);

    let detour = add_detour(
        &gps_engine::synthetic::generate(geometry, &SyntheticConfig::noisy(9, 5.0)),
        Distance::from_meters(60.0),
    );
    write("detour.gpx", &detour);

    println!(
        "corpus: {} tracks, {:.2} km loop",
        std::fs::read_dir(OUT_DIR).expect("read dir").count(),
        route.length().kilometers()
    );
    let _ = Distance::ZERO;
}
