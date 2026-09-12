use crate::error::GeoError;

/// A geographic coordinate in WGS84 lon/lat degrees.
///
/// `Coordinate` is immutable and always valid: construction validates range
/// and finiteness, so downstream code can rely on the invariants.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Coordinate {
    latitude: f64,
    longitude: f64,
}

impl Coordinate {
    /// Constructs a coordinate, validating latitude and longitude ranges.
    ///
    /// Returns [`GeoError::NonFinite`] for NaN/∞ inputs, and
    /// [`GeoError::LatitudeOutOfRange`] / [`GeoError::LongitudeOutOfRange`]
    /// when out of range.
    pub fn new(latitude: f64, longitude: f64) -> Result<Self, GeoError> {
        if !latitude.is_finite() || !longitude.is_finite() {
            return Err(GeoError::NonFinite("coordinate"));
        }
        if !(-90.0..=90.0).contains(&latitude) {
            return Err(GeoError::LatitudeOutOfRange(latitude));
        }
        if !(-180.0..=180.0).contains(&longitude) {
            return Err(GeoError::LongitudeOutOfRange(longitude));
        }
        Ok(Coordinate {
            latitude,
            longitude,
        })
    }

    /// Latitude in degrees, in `[-90, 90]`.
    pub fn latitude(self) -> f64 {
        self.latitude
    }

    /// Longitude in degrees, in `[-180, 180]`.
    pub fn longitude(self) -> f64 {
        self.longitude
    }
}

impl Default for Coordinate {
    fn default() -> Self {
        Coordinate {
            latitude: 0.0,
            longitude: 0.0,
        }
    }
}
